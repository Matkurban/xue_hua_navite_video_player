import AVFoundation
import CryptoKit
import Foundation
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

private let kDefaultCacheUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

private let kKnownMediaExtensions: [String] = [
    ".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi",
    ".mp3", ".m4a", ".aac", ".wav", ".ogg", ".flv", ".ts",
]

// MARK: - FileHandle iOS 13.0 / macOS 10.15 Safe Helpers

private extension FileHandle {
    func safeSeekToEnd() -> UInt64 {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            return (try? seekToEnd()) ?? 0
        } else {
            return seekToEndOfFile()
        }
    }

    func safeSeek(to offset: UInt64) throws {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try seek(toOffset: offset)
        } else {
            seek(toFileOffset: offset)
        }
    }

    func safeRead(upTo count: Int) -> Data? {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            return try? read(upToCount: count)
        } else {
            return readData(ofLength: count)
        }
    }

    func safeWrite(_ data: Data) throws {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try write(contentsOf: data)
        } else {
            write(data)
        }
    }

    func safeClose() {
        if #available(iOS 13.0, macOS 10.15, *) {
            try? close()
        } else {
            closeFile()
        }
    }
}

// MARK: - Disk Metadata & Segment Models

struct MediaCacheEntryMeta: Codable {
    var url: String
    var totalLength: Int64
    var contentType: String
    var ext: String
    var updatedAtMs: Int64
}

struct MediaCacheSegment {
    let start: Int64
    let length: Int64
    let fileURL: URL

    var end: Int64 {
        start + length
    }
}

// MARK: - Process-Wide Apple Media Cache Manager

/// 管理 iOS / macOS 本地视频缓存目录、稀疏 `.part/*.seg` 分片合并、LRU 容量治理与后台 `precache` 预热。
///
/// 目录协议与 Dart `LocalVideoCacheEngine` 完全对齐：
/// - 完整文件：`<cacheDir>/<cacheKey><ext>`
/// - 未完成分片目录：`<cacheDir>/<cacheKey>.part/`（内含 `meta.json` 与 `<startOffset>.seg`）
final class MediaCacheManager {
    static let shared = MediaCacheManager()

    private let stateLock = NSLock()
    private var _enabled: Bool = true
    private var _maxCacheBytes: Int64 = 512 * 1024 * 1024
    private var _maxSingleFileBytes: Int64 = 256 * 1024 * 1024
    private var _configuredCacheDir: String?
    private var pinnedKeys = Set<String>()
    private var activeWriterSegmentPaths = Set<String>()
    private var precacheTasks: [String: URLSessionDataTask] = [:]

    private let ioQueue = DispatchQueue(
        label: "com.kurban.xue_hua_navite_video_player.cache.io",
        qos: .utility
    )

    private lazy var precacheSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    private init() {}

    var enabled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _enabled
    }

    var maxCacheBytes: Int64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _maxCacheBytes
    }

    var maxSingleFileBytes: Int64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _maxSingleFileBytes
    }

    func resolveCacheDir(_ overrideDir: String? = nil) -> String {
        stateLock.lock()
        let configured = _configuredCacheDir
        stateLock.unlock()

        let path: String
        if let o = overrideDir?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty {
            path = o
        } else if let c = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            path = c
        } else {
            let base = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
                ?? NSTemporaryDirectory()
            path = ((base as NSString).appendingPathComponent("xue_hua_navite_video_player") as NSString)
                .appendingPathComponent("media_cache")
        }
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return path
    }

    func configure(
        enabled: Bool,
        maxCacheBytes: Int64,
        maxSingleFileBytes: Int64,
        cacheDir: String?
    ) {
        stateLock.lock()
        _enabled = enabled
        _maxCacheBytes = max(0, maxCacheBytes)
        _maxSingleFileBytes = max(0, maxSingleFileBytes)
        if let dir = cacheDir?.trimmingCharacters(in: .whitespacesAndNewlines), !dir.isEmpty {
            _configuredCacheDir = dir
        }
        let targetMax = _maxCacheBytes
        stateLock.unlock()

        let resolvedDir = resolveCacheDir(cacheDir)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            if targetMax == 0 {
                self.clearCacheSync(cacheDir: resolvedDir)
            } else if enabled {
                self.evictIfNeededSync(cacheDir: resolvedDir)
            }
        }
    }

    func pin(_ cacheKey: String?) {
        guard let key = cacheKey, !key.isEmpty else { return }
        stateLock.lock()
        pinnedKeys.insert(key)
        stateLock.unlock()
    }

    func unpin(_ cacheKey: String?) {
        guard let key = cacheKey, !key.isEmpty else { return }
        stateLock.lock()
        pinnedKeys.remove(key)
        stateLock.unlock()
    }

    func isPinned(_ cacheKey: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pinnedKeys.contains(cacheKey)
    }

    func tryLockSegment(_ path: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if activeWriterSegmentPaths.contains(path) {
            return false
        }
        activeWriterSegmentPaths.insert(path)
        return true
    }

    func unlockSegment(_ path: String?) {
        guard let p = path else { return }
        stateLock.lock()
        activeWriterSegmentPaths.remove(p)
        stateLock.unlock()
    }

    func hasActiveWriter(in partDirPath: String) -> Bool {
        let prefix = partDirPath.hasSuffix("/") ? partDirPath : (partDirPath + "/")
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeWriterSegmentPaths.contains { $0.hasPrefix(prefix) }
    }

    static func sha1Hex(_ raw: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func inferExtension(url: String, contentType: String? = nil) -> String {
        if let comps = URLComponents(string: url) {
            let p = comps.path.lowercased()
            for ext in kKnownMediaExtensions where p.hasSuffix(ext) {
                return ext
            }
        }
        if let ct = contentType?.lowercased() {
            if ct.contains("quicktime") {
                return ".mov"
            }
            if ct.contains("webm") {
                return ".webm"
            }
            if ct.contains("matroska") || ct.contains("mkv") {
                return ".mkv"
            }
            if ct.contains("mpeg") && ct.contains("audio") {
                return ".mp3"
            }
            if ct.contains("mp4") && ct.contains("audio") {
                return ".m4a"
            }
            if ct.contains("aac") {
                return ".aac"
            }
            if ct.contains("wav") {
                return ".wav"
            }
            if ct.contains("ogg") {
                return ".ogg"
            }
        }
        return ".mp4"
    }

    static func isStreamingManifest(url: String) -> Bool {
        let path = (URLComponents(string: url)?.path ?? url).lowercased()
        return path.hasSuffix(".m3u8") || path.hasSuffix(".mpd")
    }

    static func uti(forMimeType mime: String, fallbackExt: String) -> String {
        let clean = mime.split(separator: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "video/mp4"

        if #available(iOS 14.0, macOS 11.0, *) {
            #if canImport(UniformTypeIdentifiers)
                if let ut = UTType(mimeType: clean) {
                    return ut.identifier
                }
                let trimExt = fallbackExt.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !trimExt.isEmpty, let ut = UTType(filenameExtension: trimExt) {
                    return ut.identifier
                }
            #endif
        }

        switch clean {
        case "video/mp4":
            return AVFileType.mp4.rawValue
        case "video/quicktime":
            return AVFileType.mov.rawValue
        case "video/x-m4v":
            return AVFileType.m4v.rawValue
        case "audio/mpeg", "audio/mp3":
            return AVFileType.mp3.rawValue
        case "audio/mp4", "audio/x-m4a", "audio/aac":
            return AVFileType.m4a.rawValue
        case "audio/wav", "audio/x-wav":
            return AVFileType.wav.rawValue
        default:
            return AVFileType.mp4.rawValue
        }
    }

    func completeFileURL(cacheKey: String?, cacheDir: String? = nil) -> URL? {
        guard let key = cacheKey, !key.isEmpty else { return nil }
        let dir = resolveCacheDir(cacheDir)
        let fm = FileManager.default
        for ext in kKnownMediaExtensions {
            let full = (dir as NSString).appendingPathComponent("\(key)\(ext)")
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let size = attrs[.size] as? NSNumber,
               size.int64Value > 0
            {
                try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: full)
                return URL(fileURLWithPath: full)
            }
        }
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let prefix = "\(key)."
        for name in items where name.hasPrefix(prefix) {
            if name.hasSuffix(".part") || name.hasSuffix(".tmp") || name.hasSuffix(".json") {
                continue
            }
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue,
               let attrs = try? fm.attributesOfItem(atPath: full),
               let size = attrs[.size] as? NSNumber,
               size.int64Value > 0
            {
                try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: full)
                return URL(fileURLWithPath: full)
            }
        }
        return nil
    }

    func isCached(cacheKey: String, cacheDir: String? = nil) -> Bool {
        return completeFileURL(cacheKey: cacheKey, cacheDir: cacheDir) != nil
    }

    func readMeta(partDir: URL) -> MediaCacheEntryMeta? {
        let metaURL = partDir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(MediaCacheEntryMeta.self, from: data)
    }

    func writeMeta(_ meta: MediaCacheEntryMeta, partDir: URL) {
        try? FileManager.default.createDirectory(at: partDir, withIntermediateDirectories: true)
        let metaURL = partDir.appendingPathComponent("meta.json")
        let tmpURL = partDir.appendingPathComponent("meta.json.tmp.\(UUID().uuidString)")
        guard let data = try? JSONEncoder().encode(meta) else { return }
        do {
            try data.write(to: tmpURL, options: .atomic)
            if FileManager.default.fileExists(atPath: metaURL.path) {
                _ = try? FileManager.default.replaceItemAt(metaURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: metaURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    func listSegments(partDir: URL) -> [MediaCacheSegment] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: partDir.path) else { return [] }
        var segments: [MediaCacheSegment] = []
        for name in names where name.hasSuffix(".seg") {
            let numPart = String(name.dropLast(4))
            guard let start = Int64(numPart), start >= 0 else { continue }
            let segURL = partDir.appendingPathComponent(name)
            if let attrs = try? fm.attributesOfItem(atPath: segURL.path),
               let size = attrs[.size] as? NSNumber
            {
                let len = size.int64Value
                if len > 0 {
                    segments.append(MediaCacheSegment(start: start, length: len, fileURL: segURL))
                }
            }
        }
        segments.sort { lhs, rhs in
            if lhs.start != rhs.start {
                return lhs.start < rhs.start
            }
            return lhs.length > rhs.length
        }
        return segments
    }

    /// 若 `[0, totalLength)` 已由分片 100% 覆盖且无活跃写入句柄，则合并提升为 `<cacheKey><ext>`。
    @discardableResult
    func tryPromotePartIfComplete(cacheDir: String, cacheKey: String) -> URL? {
        if let existing = completeFileURL(cacheKey: cacheKey, cacheDir: cacheDir) {
            return existing
        }
        let partPath = (cacheDir as NSString).appendingPathComponent("\(cacheKey).part")
        if hasActiveWriter(in: partPath) {
            return nil
        }
        let partURL = URL(fileURLWithPath: partPath)
        guard let meta = readMeta(partDir: partURL), meta.totalLength > 0 else {
            return nil
        }
        let totalLength = meta.totalLength
        let segments = listSegments(partDir: partURL)
        guard !segments.isEmpty else { return nil }

        // Check full coverage [0, totalLength)
        var coveredUntil: Int64 = 0
        for seg in segments {
            if seg.start > coveredUntil {
                return nil
            }
            if seg.end > coveredUntil {
                coveredUntil = seg.end
            }
            if coveredUntil >= totalLength {
                break
            }
        }
        guard coveredUntil >= totalLength else { return nil }

        let ext = meta.ext.isEmpty ? ".mp4" : meta.ext
        let finalPath = (cacheDir as NSString).appendingPathComponent("\(cacheKey)\(ext)")
        let finalURL = URL(fileURLWithPath: finalPath)
        let fm = FileManager.default

        // Fast-path: single 0.seg with exact length -> O(1) atomic rename!
        if segments.count == 1,
           segments[0].start == 0,
           segments[0].length == totalLength
        {
            do {
                if fm.fileExists(atPath: finalPath) {
                    try? fm.removeItem(atPath: finalPath)
                }
                try fm.moveItem(at: segments[0].fileURL, to: finalURL)
                try? fm.removeItem(at: partURL)
                evictIfNeededSync(cacheDir: cacheDir)
                return finalURL
            } catch {
                // Fall through to stream assembly.
            }
        }

        let tempPath = (cacheDir as NSString).appendingPathComponent("\(cacheKey)\(ext).tmp.\(UUID().uuidString)")
        let tempURL = URL(fileURLWithPath: tempPath)
        fm.createFile(atPath: tempPath, contents: nil)
        guard let outHandle = FileHandle(forWritingAtPath: tempPath) else {
            try? fm.removeItem(at: tempURL)
            return nil
        }

        var cursor: Int64 = 0
        let chunkSize = 256 * 1024
        var ok = true

        while cursor < totalLength {
            guard let seg = segments.first(where: { $0.start <= cursor && $0.end > cursor }),
                  let inHandle = FileHandle(forReadingAtPath: seg.fileURL.path)
            else {
                ok = false
                break
            }
            let offsetInSeg = UInt64(cursor - seg.start)
            var remaining = Int64(min(seg.end, totalLength) - cursor)
            do {
                try inHandle.safeSeek(to: offsetInSeg)
                while remaining > 0 {
                    let toRead = Int(min(Int64(chunkSize), remaining))
                    guard let data = inHandle.safeRead(upTo: toRead), !data.isEmpty else {
                        ok = false
                        break
                    }
                    try outHandle.safeWrite(data)
                    cursor += Int64(data.count)
                    remaining -= Int64(data.count)
                }
            } catch {
                ok = false
            }
            inHandle.safeClose()
            if !ok {
                break
            }
        }
        outHandle.safeClose()

        guard ok, cursor == totalLength else {
            try? fm.removeItem(at: tempURL)
            return nil
        }

        do {
            if fm.fileExists(atPath: finalPath) {
                try? fm.removeItem(atPath: finalPath)
            }
            try fm.moveItem(at: tempURL, to: finalURL)
            try? fm.removeItem(at: partURL)
            evictIfNeededSync(cacheDir: cacheDir)
            return finalURL
        } catch {
            try? fm.removeItem(at: tempURL)
            return nil
        }
    }

    // MARK: - Precache / Size / Eviction / Cleanup

    func precache(
        url: String,
        cacheKey: String,
        cacheDir: String?,
        headers: [String: String]?,
        preloadBytes: Int64?,
        completion: @escaping () -> Void
    ) {
        if !enabled || maxCacheBytes <= 0 || maxSingleFileBytes <= 0 || Self.isStreamingManifest(url: url) {
            completion()
            return
        }
        let resolvedDir = resolveCacheDir(cacheDir)
        if completeFileURL(cacheKey: cacheKey, cacheDir: resolvedDir) != nil {
            completion()
            return
        }
        guard let targetURL = URL(string: url) else {
            completion()
            return
        }

        stateLock.lock()
        if precacheTasks[cacheKey] != nil {
            stateLock.unlock()
            completion()
            return
        }
        stateLock.unlock()

        ioQueue.async { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            let partURL = URL(fileURLWithPath: (resolvedDir as NSString).appendingPathComponent("\(cacheKey).part"))
            try? FileManager.default.createDirectory(at: partURL, withIntermediateDirectories: true)

            let existingSegs = self.listSegments(partDir: partURL)
            var startOffset: Int64 = 0
            for seg in existingSegs where seg.start == 0 {
                startOffset = max(startOffset, seg.end)
            }
            if let preload = preloadBytes, preload > 0, startOffset >= preload {
                completion()
                return
            }

            var request = URLRequest(url: targetURL)
            request.setValue(kDefaultCacheUserAgent, forHTTPHeaderField: "User-Agent")
            headers?.forEach { k, v in
                request.setValue(v, forHTTPHeaderField: k)
            }
            let singleLimit = self.maxSingleFileBytes
            if let preload = preloadBytes, preload > 0 {
                let cappedEnd = min(preload, singleLimit) - 1
                if cappedEnd < startOffset {
                    completion()
                    return
                }
                request.setValue("bytes=\(startOffset)-\(cappedEnd)", forHTTPHeaderField: "Range")
            } else if startOffset > 0 {
                request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
            }

            let task = self.precacheSession.dataTask(with: request) { [weak self] data, response, error in
                defer {
                    self?.stateLock.lock()
                    self?.precacheTasks.removeValue(forKey: cacheKey)
                    self?.stateLock.unlock()
                    completion()
                }
                guard let self = self, error == nil,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200 || http.statusCode == 206,
                      let body = data, !body.isEmpty
                else {
                    return
                }

                let existingMeta = self.readMeta(partDir: partURL)
                let totalLen = Self.parseTotalLength(http: http, fallback: existingMeta?.totalLength ?? -1)
                if totalLen > singleLimit || Int64(body.count) > singleLimit {
                    return
                }

                let mime = http.mimeType ?? existingMeta?.contentType ?? "video/mp4"
                let ext = Self.inferExtension(url: url, contentType: mime)
                let meta = MediaCacheEntryMeta(
                    url: url,
                    totalLength: totalLen,
                    contentType: mime,
                    ext: ext,
                    updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
                )
                self.writeMeta(meta, partDir: partURL)

                let writeStart: Int64 = (http.statusCode == 206) ? startOffset : 0
                let segName = (writeStart == startOffset && startOffset > 0) ? "0.seg" : "\(writeStart).seg"
                let segURL = partURL.appendingPathComponent(segName)
                guard self.tryLockSegment(segURL.path) else { return }
                defer { self.unlockSegment(segURL.path) }

                if writeStart == 0 {
                    // Replace 0.seg cleanly when server responds with 200 OK full body
                    try? FileManager.default.removeItem(at: segURL)
                }
                if !FileManager.default.fileExists(atPath: segURL.path) {
                    FileManager.default.createFile(atPath: segURL.path, contents: nil)
                }
                if let fh = FileHandle(forWritingAtPath: segURL.path) {
                    _ = fh.safeSeekToEnd()
                    try? fh.safeWrite(body)
                    fh.safeClose()
                }

                _ = self.tryPromotePartIfComplete(cacheDir: resolvedDir, cacheKey: cacheKey)
                self.evictIfNeededSync(cacheDir: resolvedDir)
            }

            self.stateLock.lock()
            self.precacheTasks[cacheKey] = task
            self.stateLock.unlock()
            task.resume()
        }
    }

    func cancelPrecache(cacheKey: String) {
        stateLock.lock()
        let task = precacheTasks.removeValue(forKey: cacheKey)
        stateLock.unlock()
        task?.cancel()
    }

    func getCacheSizeAsync(cacheDir: String?, completion: @escaping (Int64) -> Void) {
        let dir = resolveCacheDir(cacheDir)
        ioQueue.async {
            completion(Self.computeDirectoryBytes(atPath: dir))
        }
    }

    func removeCacheAsync(cacheKey: String, cacheDir: String?, completion: @escaping () -> Void) {
        cancelPrecache(cacheKey: cacheKey)
        let dir = resolveCacheDir(cacheDir)
        ioQueue.async {
            let fm = FileManager.default
            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                for name in items where name == cacheKey || name.hasPrefix("\(cacheKey).") {
                    let full = (dir as NSString).appendingPathComponent(name)
                    try? fm.removeItem(atPath: full)
                }
            }
            completion()
        }
    }

    func clearCacheAsync(cacheDir: String?, completion: @escaping () -> Void) {
        let dir = resolveCacheDir(cacheDir)
        ioQueue.async { [weak self] in
            self?.clearCacheSync(cacheDir: dir)
            completion()
        }
    }

    private func clearCacheSync(cacheDir: String) {
        stateLock.lock()
        let tasks = Array(precacheTasks.values)
        precacheTasks.removeAll()
        stateLock.unlock()
        tasks.forEach { $0.cancel() }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: cacheDir) else { return }
        for name in items {
            let key = Self.extractKey(fromItemName: name)
            if isPinned(key) {
                continue
            }
            let full = (cacheDir as NSString).appendingPathComponent(name)
            if name.hasSuffix(".part"), hasActiveWriter(in: full) {
                continue
            }
            try? fm.removeItem(atPath: full)
        }
    }

    func evictIfNeededSync(cacheDir: String) {
        let maxBytes = maxCacheBytes
        if maxBytes <= 0 {
            return
        }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: cacheDir) else { return }

        struct Candidate {
            let key: String
            let path: String
            let isPart: Bool
            let size: Int64
            let modified: Date
        }

        var candidates: [Candidate] = []
        var total: Int64 = 0

        for name in items {
            if name.contains(".tmp.") {
                continue
            }
            let full = (cacheDir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let key = Self.extractKey(fromItemName: name)
            let size: Int64
            let mod: Date
            if isDir.boolValue {
                size = Self.computeDirectoryBytes(atPath: full)
                let attrs = try? fm.attributesOfItem(atPath: full)
                mod = (attrs?[.modificationDate] as? Date) ?? .distantPast
            } else {
                let attrs = try? fm.attributesOfItem(atPath: full)
                size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                mod = (attrs?[.modificationDate] as? Date) ?? .distantPast
            }
            total += size
            candidates.append(Candidate(key: key, path: full, isPart: isDir.boolValue, size: size, modified: mod))
        }

        if total <= maxBytes {
            return
        }
        candidates.sort { $0.modified < $1.modified }

        for item in candidates {
            if total <= maxBytes {
                break
            }
            if isPinned(item.key) {
                continue
            }
            if item.isPart, hasActiveWriter(in: item.path) {
                continue
            }
            do {
                try fm.removeItem(atPath: item.path)
                total -= item.size
            } catch {}
        }
    }

    private static func extractKey(fromItemName name: String) -> String {
        if name.hasSuffix(".part") {
            return String(name.dropLast(5))
        }
        if let dot = name.firstIndex(of: ".") {
            return String(name[..<dot])
        }
        return name
    }

    private static func computeDirectoryBytes(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var sum: Int64 = 0
        for case let rel as String in enumerator {
            let subPath = (path as NSString).appendingPathComponent(rel)
            var subDir: ObjCBool = false
            if fm.fileExists(atPath: subPath, isDirectory: &subDir), !subDir.boolValue {
                let attrs = try? fm.attributesOfItem(atPath: subPath)
                sum += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        return sum
    }

    static func parseTotalLength(http: HTTPURLResponse, fallback: Int64) -> Int64 {
        let rangeHeader: String? = {
            if #available(iOS 13.0, macOS 10.15, *) {
                return http.value(forHTTPHeaderField: "Content-Range")
            } else {
                return http.allHeaderFields["Content-Range"] as? String
            }
        }()
        if let cr = rangeHeader,
           let slash = cr.lastIndex(of: "/")
        {
            let totalStr = cr[cr.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            if totalStr != "*", let parsed = Int64(totalStr), parsed > 0 {
                return parsed
            }
        }
        if http.statusCode == 200, http.expectedContentLength > 0 {
            return http.expectedContentLength
        }
        return fallback
    }
}

// MARK: - AVAssetResourceLoaderDelegate Streaming Sparse Cache

/// 为单个 `AVURLAsset` 提供 `xhcache-http(s)://` 边播边存代理的 Delegate。
final class MediaCacheResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    static let schemePrefix = "xhcache-"

    let originalURL: URL
    let cacheKey: String
    let cacheDir: String
    let headers: [String: String]?
    let loaderQueue: DispatchQueue

    private var urlSession: URLSession?
    private var activeTasks: [Int: ActiveRequestContext] = [:]
    private var invalidated = false

    private final class ActiveRequestContext {
        let loadingRequest: AVAssetResourceLoadingRequest
        var task: URLSessionDataTask?
        var cursor: Int64
        var reqEndExclusive: Int64 // Int64.max when requestsAllDataToEndOfResource and length unknown
        var fetchStart: Int64 = 0
        var fetchEndInclusive: Int64 = -1
        var upstreamLogicalOffset: Int64 = 0
        var upstreamIsFullBody200 = false
        var bypassDiskWrite = false
        var segFileHandle: FileHandle?
        var lockedSegmentPath: String?

        init(loadingRequest: AVAssetResourceLoadingRequest, cursor: Int64, reqEndExclusive: Int64) {
            self.loadingRequest = loadingRequest
            self.cursor = cursor
            self.reqEndExclusive = reqEndExclusive
        }
    }

    init(
        originalURL: URL,
        cacheKey: String,
        cacheDir: String? = nil,
        headers: [String: String]? = nil
    ) {
        self.originalURL = originalURL
        self.cacheKey = cacheKey
        self.cacheDir = MediaCacheManager.shared.resolveCacheDir(cacheDir)
        self.headers = headers
        loaderQueue = DispatchQueue(
            label: "com.kurban.xue_hua_navite_video_player.resourceloader.\(UUID().uuidString)",
            qos: .userInitiated
        )
        super.init()

        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = 1
        opQueue.underlyingQueue = loaderQueue

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 600
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: opQueue)
    }

    static func makeCustomSchemeURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "\(schemePrefix)\(scheme)"
        return comps?.url
    }

    func invalidate() {
        loaderQueue.async { [weak self] in
            guard let self = self, !self.invalidated else { return }
            self.invalidated = true
            for (_, ctx) in self.activeTasks {
                self.closeSegmentWriter(ctx)
                ctx.task?.cancel()
            }
            self.activeTasks.removeAll()
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            _ = MediaCacheManager.shared.tryPromotePartIfComplete(
                cacheDir: self.cacheDir,
                cacheKey: self.cacheKey
            )
        }
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard !invalidated else { return false }

        // 1. Complete file fast-path
        if let completeURL = MediaCacheManager.shared.completeFileURL(
            cacheKey: cacheKey,
            cacheDir: cacheDir
        ) {
            return fulfillFromCompleteFile(loadingRequest: loadingRequest, fileURL: completeURL)
        }

        let partURL = URL(fileURLWithPath: (cacheDir as NSString).appendingPathComponent("\(cacheKey).part"))
        try? FileManager.default.createDirectory(at: partURL, withIntermediateDirectories: true)
        let meta = MediaCacheManager.shared.readMeta(partDir: partURL)

        if let infoReq = loadingRequest.contentInformationRequest, let meta = meta, meta.totalLength > 0 {
            fillContentInformation(infoReq, meta: meta)
        }

        guard let dataReq = loadingRequest.dataRequest else {
            if loadingRequest.contentInformationRequest != nil, meta != nil {
                loadingRequest.finishLoading()
                return true
            }
            // Need upstream metadata probe (GET bytes=0-1; avoids HEAD 403 on S3/OSS presigned URLs).
            let ctx = ActiveRequestContext(loadingRequest: loadingRequest, cursor: 0, reqEndExclusive: 2)
            startNextUpstreamStep(ctx: ctx, partURL: partURL)
            return true
        }

        let startOffset: Int64 = dataReq.currentOffset > 0 ? dataReq.currentOffset : dataReq.requestedOffset
        let endExclusive: Int64
        if dataReq.requestsAllDataToEndOfResource {
            if let meta = meta, meta.totalLength > 0 {
                endExclusive = meta.totalLength
            } else {
                endExclusive = Int64.max
            }
        } else {
            endExclusive = startOffset + Int64(dataReq.requestedLength)
        }

        let ctx = ActiveRequestContext(
            loadingRequest: loadingRequest,
            cursor: startOffset,
            reqEndExclusive: endExclusive
        )
        advanceRequest(ctx: ctx, partURL: partURL)
        return true
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        if let entry = activeTasks.first(where: { $0.value.loadingRequest === loadingRequest }) {
            let ctx = entry.value
            activeTasks.removeValue(forKey: entry.key)
            closeSegmentWriter(ctx)
            ctx.task?.cancel()
            _ = MediaCacheManager.shared.tryPromotePartIfComplete(
                cacheDir: cacheDir,
                cacheKey: cacheKey
            )
        }
    }

    // MARK: Sparse State Machine

    private func advanceRequest(ctx: ActiveRequestContext, partURL: URL) {
        guard !invalidated, !ctx.loadingRequest.isCancelled else {
            closeSegmentWriter(ctx)
            return
        }

        // Serve as much contiguous cached data from `.seg` files as available at `ctx.cursor`.
        let meta = MediaCacheManager.shared.readMeta(partDir: partURL)
        if let infoReq = ctx.loadingRequest.contentInformationRequest,
           infoReq.contentType == nil,
           let meta = meta,
           meta.totalLength > 0
        {
            fillContentInformation(infoReq, meta: meta)
            if ctx.reqEndExclusive == Int64.max {
                ctx.reqEndExclusive = meta.totalLength
            }
        }

        if let dataReq = ctx.loadingRequest.dataRequest {
            let segments = MediaCacheManager.shared.listSegments(partDir: partURL)
            let chunkSize = 256 * 1024

            while ctx.cursor < ctx.reqEndExclusive {
                guard let seg = segments.first(where: { $0.start <= ctx.cursor && $0.end > ctx.cursor }),
                      let fh = FileHandle(forReadingAtPath: seg.fileURL.path)
                else {
                    break
                }
                let offsetInSeg = UInt64(ctx.cursor - seg.start)
                let targetStop = min(seg.end, ctx.reqEndExclusive)
                var remaining = targetStop - ctx.cursor
                var readFailed = false

                do {
                    try fh.safeSeek(to: offsetInSeg)
                    while remaining > 0 {
                        let toRead = Int(min(Int64(chunkSize), remaining))
                        guard let chunk = fh.safeRead(upTo: toRead), !chunk.isEmpty else {
                            readFailed = true
                            break
                        }
                        dataReq.respond(with: chunk)
                        ctx.cursor += Int64(chunk.count)
                        remaining -= Int64(chunk.count)
                    }
                } catch {
                    readFailed = true
                }
                fh.safeClose()
                if readFailed {
                    break
                }
            }
        }

        let needsInfo = (ctx.loadingRequest.contentInformationRequest != nil &&
            ctx.loadingRequest.contentInformationRequest?.contentType == nil)

        if !needsInfo, ctx.cursor >= ctx.reqEndExclusive {
            closeSegmentWriter(ctx)
            ctx.loadingRequest.finishLoading()
            _ = MediaCacheManager.shared.tryPromotePartIfComplete(
                cacheDir: cacheDir,
                cacheKey: cacheKey
            )
            return
        }

        startNextUpstreamStep(ctx: ctx, partURL: partURL)
    }

    private func startNextUpstreamStep(ctx: ActiveRequestContext, partURL: URL) {
        guard let session = urlSession, !invalidated else {
            ctx.loadingRequest.finishLoading(with: URLError(.cancelled))
            return
        }

        let segments = MediaCacheManager.shared.listSegments(partDir: partURL)
        let nextCachedSeg = segments.first(where: { $0.start > ctx.cursor && $0.start < ctx.reqEndExclusive })

        ctx.fetchStart = ctx.cursor
        if let nextSeg = nextCachedSeg {
            ctx.fetchEndInclusive = nextSeg.start - 1
        } else if ctx.reqEndExclusive < Int64.max {
            ctx.fetchEndInclusive = max(ctx.fetchStart, ctx.reqEndExclusive - 1)
        } else {
            ctx.fetchEndInclusive = -1
        }

        var urlReq = URLRequest(url: originalURL)
        urlReq.setValue(kDefaultCacheUserAgent, forHTTPHeaderField: "User-Agent")
        headers?.forEach { k, v in
            urlReq.setValue(v, forHTTPHeaderField: k)
        }
        if ctx.fetchEndInclusive >= ctx.fetchStart {
            urlReq.setValue("bytes=\(ctx.fetchStart)-\(ctx.fetchEndInclusive)", forHTTPHeaderField: "Range")
        } else {
            urlReq.setValue("bytes=\(ctx.fetchStart)-", forHTTPHeaderField: "Range")
        }

        let task = session.dataTask(with: urlReq)
        ctx.task = task
        activeTasks[task.taskIdentifier] = ctx
        task.resume()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let ctx = activeTasks[dataTask.taskIdentifier], !ctx.loadingRequest.isCancelled else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        if http.statusCode != 200 && http.statusCode != 206 {
            activeTasks.removeValue(forKey: dataTask.taskIdentifier)
            closeSegmentWriter(ctx)
            let err = NSError(
                domain: "XueHuaMediaCache",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP status \(http.statusCode)"]
            )
            ctx.loadingRequest.finishLoading(with: err)
            completionHandler(.cancel)
            return
        }

        let partURL = URL(fileURLWithPath: (cacheDir as NSString).appendingPathComponent("\(cacheKey).part"))
        let existingMeta = MediaCacheManager.shared.readMeta(partDir: partURL)
        let totalLength = MediaCacheManager.parseTotalLength(
            http: http,
            fallback: existingMeta?.totalLength ?? -1
        )
        let mime = http.mimeType ?? existingMeta?.contentType ?? "video/mp4"
        let ext = MediaCacheManager.inferExtension(url: originalURL.absoluteString, contentType: mime)

        let meta = MediaCacheEntryMeta(
            url: originalURL.absoluteString,
            totalLength: totalLength,
            contentType: mime,
            ext: ext,
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )

        let mgr = MediaCacheManager.shared
        let overSingleLimit = (totalLength > 0 && totalLength > mgr.maxSingleFileBytes)
        ctx.bypassDiskWrite = !mgr.enabled || mgr.maxCacheBytes <= 0 || mgr.maxSingleFileBytes <= 0 || overSingleLimit

        if !ctx.bypassDiskWrite {
            mgr.writeMeta(meta, partDir: partURL)
        }

        if let infoReq = ctx.loadingRequest.contentInformationRequest {
            fillContentInformation(infoReq, meta: meta)
        }
        if ctx.reqEndExclusive == Int64.max, totalLength > 0 {
            ctx.reqEndExclusive = totalLength
        }

        ctx.upstreamIsFullBody200 = (http.statusCode == 200 && ctx.fetchStart > 0)
        ctx.upstreamLogicalOffset = ctx.upstreamIsFullBody200 ? 0 : ctx.fetchStart

        // Open segment file writer (append to existing segment if `seg.end == writeStart`, else create `<writeStart>.seg`)
        if !ctx.bypassDiskWrite {
            let writeStart: Int64 = ctx.upstreamLogicalOffset
            let segments = mgr.listSegments(partDir: partURL)
            if let extendable = segments.first(where: { $0.end == writeStart }),
               mgr.tryLockSegment(extendable.fileURL.path),
               let fh = FileHandle(forWritingAtPath: extendable.fileURL.path)
            {
                _ = fh.safeSeekToEnd()
                ctx.segFileHandle = fh
                ctx.lockedSegmentPath = extendable.fileURL.path
            } else {
                let newSegURL = partURL.appendingPathComponent("\(writeStart).seg")
                if mgr.tryLockSegment(newSegURL.path) {
                    FileManager.default.createFile(atPath: newSegURL.path, contents: nil)
                    if let fh = FileHandle(forWritingAtPath: newSegURL.path) {
                        ctx.segFileHandle = fh
                        ctx.lockedSegmentPath = newSegURL.path
                    } else {
                        mgr.unlockSegment(newSegURL.path)
                    }
                }
            }
        }

        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let ctx = activeTasks[dataTask.taskIdentifier], !ctx.loadingRequest.isCancelled else {
            dataTask.cancel()
            return
        }
        guard !data.isEmpty else { return }

        let chunkStart = ctx.upstreamLogicalOffset
        let chunkEnd = chunkStart + Int64(data.count)
        ctx.upstreamLogicalOffset = chunkEnd

        // Persist to disk segment if within single-file limit
        if !ctx.bypassDiskWrite, let fh = ctx.segFileHandle {
            if chunkEnd <= MediaCacheManager.shared.maxSingleFileBytes {
                do {
                    try fh.safeWrite(data)
                } catch {
                    closeSegmentWriter(ctx)
                    ctx.bypassDiskWrite = true
                }
            } else {
                closeSegmentWriter(ctx)
                ctx.bypassDiskWrite = true
            }
        }

        // Feed requested slice into AVAssetResourceLoadingDataRequest
        if let dataReq = ctx.loadingRequest.dataRequest {
            let deliverStart = max(chunkStart, ctx.cursor)
            let deliverEnd = min(chunkEnd, ctx.reqEndExclusive)
            if deliverEnd > deliverStart {
                let sliceStart = data.index(data.startIndex, offsetBy: Int(deliverStart - chunkStart))
                let sliceEnd = data.index(data.startIndex, offsetBy: Int(deliverEnd - chunkStart))
                dataReq.respond(with: data[sliceStart ..< sliceEnd])
                ctx.cursor = deliverEnd
            }
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ctx = activeTasks.removeValue(forKey: task.taskIdentifier) else {
            return
        }
        closeSegmentWriter(ctx)

        if ctx.loadingRequest.isCancelled {
            return
        }

        if let error = error {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain, nsErr.code == NSURLErrorCancelled {
                return
            }
            ctx.loadingRequest.finishLoading(with: error)
            return
        }

        let partURL = URL(fileURLWithPath: (cacheDir as NSString).appendingPathComponent("\(cacheKey).part"))
        if ctx.cursor < ctx.reqEndExclusive, ctx.reqEndExclusive < Int64.max {
            // Continue serving next cached segment or next gap!
            advanceRequest(ctx: ctx, partURL: partURL)
        } else {
            ctx.loadingRequest.finishLoading()
            _ = MediaCacheManager.shared.tryPromotePartIfComplete(
                cacheDir: cacheDir,
                cacheKey: cacheKey
            )
            MediaCacheManager.shared.evictIfNeededSync(cacheDir: cacheDir)
        }
    }

    // MARK: Helpers

    private func fillContentInformation(
        _ infoReq: AVAssetResourceLoadingContentInformationRequest,
        meta: MediaCacheEntryMeta
    ) {
        infoReq.contentType = MediaCacheManager.uti(
            forMimeType: meta.contentType,
            fallbackExt: meta.ext
        )
        if meta.totalLength > 0 {
            infoReq.contentLength = meta.totalLength
        }
        infoReq.isByteRangeAccessSupported = true
    }

    private func fulfillFromCompleteFile(
        loadingRequest: AVAssetResourceLoadingRequest,
        fileURL: URL
    ) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let sizeNum = attrs[.size] as? NSNumber
        else {
            return false
        }
        let totalLength = sizeNum.int64Value
        let ext = "." + fileURL.pathExtension
        if let infoReq = loadingRequest.contentInformationRequest {
            infoReq.contentType = MediaCacheManager.uti(
                forMimeType: "video/mp4",
                fallbackExt: ext
            )
            infoReq.contentLength = totalLength
            infoReq.isByteRangeAccessSupported = true
        }
        if let dataReq = loadingRequest.dataRequest {
            let start = dataReq.currentOffset > 0 ? dataReq.currentOffset : dataReq.requestedOffset
            let endExclusive: Int64 = dataReq.requestsAllDataToEndOfResource
                ? totalLength
                : min(totalLength, start + Int64(dataReq.requestedLength))
            if start < endExclusive, let fh = FileHandle(forReadingAtPath: fileURL.path) {
                var remaining = endExclusive - start
                let chunkSize = 256 * 1024
                try? fh.safeSeek(to: UInt64(start))
                while remaining > 0 {
                    let toRead = Int(min(Int64(chunkSize), remaining))
                    guard let chunk = fh.safeRead(upTo: toRead), !chunk.isEmpty else { break }
                    dataReq.respond(with: chunk)
                    remaining -= Int64(chunk.count)
                }
                fh.safeClose()
            }
        }
        loadingRequest.finishLoading()
        return true
    }

    private func closeSegmentWriter(_ ctx: ActiveRequestContext) {
        ctx.segFileHandle?.safeClose()
        ctx.segFileHandle = nil
        if let locked = ctx.lockedSegmentPath {
            ctx.lockedSegmentPath = nil
            MediaCacheManager.shared.unlockSegment(locked)
        }
    }
}
