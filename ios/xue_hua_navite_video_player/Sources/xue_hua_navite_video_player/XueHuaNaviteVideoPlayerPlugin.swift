import AVFoundation
import AVKit
import Flutter
import UIKit

/// iOS 插件主类，基于 AVPlayer + AVPlayerLayer（PlatformView）+ Pigeon Swift FFI。
/// iOS plugin: AVPlayer displayed via AVPlayerLayer PlatformView and Pigeon FFI.
public class XueHuaNaviteVideoPlayerPlugin: NSObject, FlutterPlugin, PlayerHostApi {
    private var registrar: FlutterPluginRegistrar?
    private var videoPlayer: NativeVideoPlayer?
    private let orientationPlugin = OrientationPlugin()
    private var savedBrightness: CGFloat?
    private var lastKnownBrightness: Double = 1.0
    private var interruptionObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var eventContinuation: AsyncStream<PlayerEventData>.Continuation?
    private var eventPumpTask: Task<Void, Never>?

    deinit {
        cleanupLifecycle()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = XueHuaNaviteVideoPlayerPlugin()
        instance.registrar = registrar
        registrar.publish(instance)
        instance.configureAudioSession()
        instance.observeAppLifecycle()
        instance.startEventPump()

        let player = NativeVideoPlayer { [weak instance] event in
            instance?.enqueueEvent(event)
        }
        instance.videoPlayer = player
        PlayerHostApiSetup.register(api: instance, registrar: registrar)
        instance.orientationPlugin.attach(binaryMessenger: registrar.messenger())

        registrar.register(
            PlayerPlatformViewFactory(
                messenger: registrar.messenger(),
                playerProvider: { [weak instance] in instance?.videoPlayer }
            ),
            withId: kPlayerPlatformViewType
        )
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        orientationPlugin.detach(binaryMessenger: registrar.messenger())
        PlayerHostApiSetup.unregister(api: self, registrar: registrar)
        cleanupLifecycle()
        self.registrar = nil
    }

    private func cleanupLifecycle() {
        restoreBrightness()
        videoPlayer?.dispose()
        eventContinuation?.finish()
        eventContinuation = nil
        eventPumpTask?.cancel()
        eventPumpTask = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
    }

    private func startEventPump() {
        var continuation: AsyncStream<PlayerEventData>.Continuation!
        let stream = AsyncStream<PlayerEventData>(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        eventContinuation = continuation
        eventPumpTask = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled {
                    break
                }
                guard let self, let registrar = self.registrar else {
                    break
                }
                if let flutterApi = PlayerFlutterApiRegistrar.getInstance(registrar: registrar) {
                    try? await flutterApi.onPlayerEvent(event: event)
                }
            }
        }
    }

    private func enqueueEvent(_ event: PlayerEventData) {
        eventContinuation?.yield(event)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    private func observeAppLifecycle() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw),
                  type == .began
            else { return }
            self?.videoPlayer?.pauseIfNotCasting()
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Do not pause playback when actively casting over AirPlay.
            self?.videoPlayer?.pauseIfNotCasting()
        }
    }

    private func requirePlayer() throws -> NativeVideoPlayer {
        guard let player = videoPlayer else {
            throw PigeonError(
                code: "NO_PLAYER",
                message: "Player not initialized",
                details: nil
            )
        }
        return player
    }

    // MARK: - PlayerHostApi

    func create() async throws -> Int64 {
        let player = try requirePlayer()
        return await MainActor.run {
            player.create()
        }
    }

    func open(request: OpenMediaRequest) async throws {
        let player = try requirePlayer()
        let normalizedHeaders = Self.normalizeHeaders(request.headers)
        let prep = await MainActor.run {
            player.beginOpen(
                url: request.url,
                castUrl: request.castUrl,
                cacheKey: request.cacheKey,
                headers: normalizedHeaders,
                enableCache: request.enableCache
            )
        }
        guard let prep else { return }

        let cachedFileURL: URL? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let resolved = NativeVideoPlayer.resolveCompleteCacheURL(
                    mediaUrl: prep.mediaUrl,
                    cacheKey: request.cacheKey,
                    enableCache: request.enableCache,
                    isAirPlayActive: prep.keepCastPlayer
                )
                continuation.resume(returning: resolved)
            }
        }

        await MainActor.run {
            player.finishOpen(
                generation: prep.generation,
                mediaUrl: prep.mediaUrl,
                keepCastPlayer: prep.keepCastPlayer,
                preResolvedCacheURL: cachedFileURL
            )
        }
    }

    func play() throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.play()
        }
    }

    func pause() throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.pause()
        }
    }

    func seek(positionMs: Int64) throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.seek(positionMs: Int(positionMs))
        }
    }

    func setVolume(volume: Double) throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.setVolume(volume: Float(volume))
        }
    }

    func setSpeed(speed: Double) throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.setSpeed(speed: Float(speed))
        }
    }

    func setAspectRatioMode(mode: NativeAspectRatioMode) throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.setAspectRatioMode(mode)
        }
    }

    func setVideoViewSize(width: Double, height: Double, devicePixelRatio: Double) throws {
        // AVPlayerLayer PlatformView auto-resizes via layoutSubviews.
    }

    func showCastPicker() throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.showCastPicker()
        }
    }

    func stopCasting() throws {
        let player = try requirePlayer()
        runOnMainThread {
            player.stopCasting()
        }
    }

    func dispose() throws {
        let player = try requirePlayer()
        runOnMainThread { [weak self] in
            self?.restoreBrightness()
            player.dispose()
        }
    }

    func getBrightness() throws -> Double {
        if Thread.isMainThread {
            let value = currentBrightness()
            lastKnownBrightness = value
            return value
        }
        return lastKnownBrightness
    }

    func setBrightness(value: Double) throws {
        runOnMainThread { [weak self] in
            self?.applyBrightness(value)
        }
    }

    func setWindowFullscreen(value: Bool) throws {
        // iOS window fullscreen is managed via SystemChrome on the Dart side.
    }

    func takeSnapshot() async throws -> SnapshotData? {
        let player = try requirePlayer()
        return try await player.takeSnapshot()
    }

    func getDuration(request: DurationProbeRequest) async throws -> Int64? {
        let headers = Self.normalizeHeaders(request.headers)
        return await NativeVideoPlayer.getDuration(
            url: request.url,
            timeoutMs: Int(request.timeoutMs),
            cacheKey: request.cacheKey,
            headers: headers
        )
    }

    func extractCovers(request: CoverExtractRequest) async throws -> [CoverFrameData] {
        let headers = Self.normalizeHeaders(request.headers)
        let outputDir = request.outputDir.isEmpty ? NSTemporaryDirectory() : request.outputDir
        return await NativeVideoPlayer.extractCovers(
            url: request.url,
            count: Int(request.count),
            candidates: Int(request.candidates),
            minBrightness: request.minBrightness,
            outputDir: outputDir,
            cacheKey: request.cacheKey,
            headers: headers
        )
    }

    func configureCache(request: CacheConfigRequest) async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                MediaCacheManager.shared.configure(
                    enabled: request.enabled,
                    maxCacheBytes: request.maxCacheBytes,
                    maxSingleFileBytes: request.maxSingleFileBytes,
                    cacheDir: request.cacheDir
                )
                continuation.resume()
            }
        }
    }

    func precache(request: PrecacheRequest) async throws {
        guard !request.url.isEmpty else { return }
        let cacheKey = (request.cacheKey?.isEmpty == false)
            ? request.cacheKey!
            : MediaCacheManager.sha1Hex(request.url)
        let headers = Self.normalizeHeaders(request.headers)
        await withCheckedContinuation { continuation in
            let gate = OneShotGate()
            MediaCacheManager.shared.precache(
                url: request.url,
                cacheKey: cacheKey,
                cacheDir: request.cacheDir,
                headers: headers,
                preloadBytes: request.preloadBytes
            ) {
                if gate.tryEnter() {
                    continuation.resume()
                }
            }
        }
    }

    func cancelPrecache(cacheKey: String) throws {
        if !cacheKey.isEmpty {
            MediaCacheManager.shared.cancelPrecache(cacheKey: cacheKey)
        }
    }

    func isCached(request: CacheEntryRequest) async throws -> Bool {
        let rawKey = (request.cacheKey?.isEmpty == false)
            ? request.cacheKey!
            : MediaCacheManager.sha1Hex(request.url)
        guard !rawKey.isEmpty else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let cached = MediaCacheManager.shared.isCached(
                    cacheKey: rawKey,
                    cacheDir: request.cacheDir
                )
                continuation.resume(returning: cached)
            }
        }
    }

    func getCacheSize(cacheDir: String?) async throws -> Int64 {
        await withCheckedContinuation { continuation in
            MediaCacheManager.shared.getCacheSizeAsync(cacheDir: cacheDir) { bytes in
                continuation.resume(returning: bytes)
            }
        }
    }

    func removeCache(request: CacheEntryRequest) async throws {
        let rawKey = (request.cacheKey?.isEmpty == false)
            ? request.cacheKey!
            : MediaCacheManager.sha1Hex(request.url)
        guard !rawKey.isEmpty else { return }
        await withCheckedContinuation { continuation in
            MediaCacheManager.shared.removeCacheAsync(
                cacheKey: rawKey,
                cacheDir: request.cacheDir
            ) {
                continuation.resume()
            }
        }
    }

    func clearCache(cacheDir: String?) async throws {
        await withCheckedContinuation { continuation in
            MediaCacheManager.shared.clearCacheAsync(cacheDir: cacheDir) {
                continuation.resume()
            }
        }
    }

    func pinCacheKey(cacheKey: String) throws {
        MediaCacheManager.shared.pin(cacheKey)
    }

    func unpinCacheKey(cacheKey: String) throws {
        MediaCacheManager.shared.unpin(cacheKey)
    }

    // MARK: - Helpers

    private static func normalizeHeaders(_ raw: [String: String]?) -> [String: String]? {
        guard let raw, !raw.isEmpty else { return nil }
        var out: [String: String] = [:]
        for (k, v) in raw {
            let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                out[key] = v
            }
        }
        return out.isEmpty ? nil : out
    }

    private func runOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func currentBrightness() -> Double {
        Double(UIScreen.main.brightness)
    }

    private func applyBrightness(_ value: Double) {
        if savedBrightness == nil {
            savedBrightness = UIScreen.main.brightness
        }
        let clamped = CGFloat(min(max(value, 0), 1))
        UIScreen.main.brightness = clamped
        lastKnownBrightness = Double(clamped)
    }

    private func restoreBrightness() {
        guard let original = savedBrightness else { return }
        savedBrightness = nil
        lastKnownBrightness = Double(original)
        runOnMainThread {
            UIScreen.main.brightness = original
        }
    }
}

private final class WeakBox<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false

    func tryEnter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if entered {
            return false
        }
        entered = true
        return true
    }
}

/// AVPlayer 封装：画面由 PlatformView 上的 AVPlayerLayer 显示（videoGravity）。
/// AVPlayer wrapper: frames shown via AVPlayerLayer on a PlatformView.
class NativeVideoPlayer: NSObject {
    private let eventEmitter: (PlayerEventData) -> Void
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var desiredRate: Float = 1.0
    private var wantsToPlay = false
    private var waitingForRate = false
    private var playbackLikelyToKeepUp = true
    private var playbackBufferEmpty = false
    private var statusObservation: NSKeyValueObservation?
    private var presentationSizeObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var externalPlaybackObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var loadedTimeRangesObservation: NSKeyValueObservation?
    private var resourceLoader: MediaCacheResourceLoader?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var failedToPlayToEndObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var routePickerView: AVRoutePickerView?
    private var wasExternalPlaybackActive = false
    private weak var hostedPlayerLayer: AVPlayerLayer?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var currentUrl: String?
    private var currentCastUrl: String?
    private var currentCacheKey: String?
    private var currentHeaders: [String: String]?
    private var currentEnableCache: Bool?
    private var lastReportedBufferedMs: Int = -1
    struct OpenPreparation {
        let generation: Int
        let mediaUrl: URL
        let keepCastPlayer: Bool
    }

    private var snapshotGeneration = 0
    private var openGeneration = 0
    private var activeSnapshotGenerator: AVAssetImageGenerator?
    private var activeSnapshotGeneratorId: ObjectIdentifier?
    private var securityScopedURLs = Set<URL>()

    init(eventEmitter: @escaping (PlayerEventData) -> Void) {
        self.eventEmitter = eventEmitter
        super.init()
    }

    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        hostedPlayerLayer = layer
        layer.videoGravity = videoGravity
        layer.player = player
    }

    func detachPlayerLayer(_ layer: AVPlayerLayer) {
        if hostedPlayerLayer === layer {
            hostedPlayerLayer = nil
        }
        if layer.player === player {
            layer.player = nil
        }
    }

    func setAspectRatioMode(_ mode: NativeAspectRatioMode) {
        switch mode {
        case .fill:
            videoGravity = .resizeAspectFill
        case .stretch:
            videoGravity = .resize
        case .fit:
            videoGravity = .resizeAspect
        }
        hostedPlayerLayer?.videoGravity = videoGravity
    }

    /// Returns 0 — display uses PlatformView, not Flutter Texture.
    func create() -> Int64 {
        ensureRouteChangeObserver()
        emitCastState()
        return 0
    }

    private static func mediaURL(from raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: raw)
    }

    private func stopSecurityScopedAccess() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    static func resolveCompleteCacheURL(
        mediaUrl: URL,
        cacheKey: String?,
        enableCache: Bool?,
        isAirPlayActive: Bool
    ) -> URL? {
        guard !isAirPlayActive,
              let scheme = mediaUrl.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        let mgr = MediaCacheManager.shared
        let resolvedKey = (cacheKey?.isEmpty == false)
            ? cacheKey!
            : MediaCacheManager.sha1Hex(mediaUrl.absoluteString)
        let useCache = (enableCache ?? mgr.enabled)
            && mgr.maxCacheBytes > 0
            && mgr.maxSingleFileBytes > 0
            && !MediaCacheManager.isStreamingManifest(url: mediaUrl.absoluteString)
        guard useCache else { return nil }
        return mgr.completeFileURL(cacheKey: resolvedKey)
    }

    private static func buildPlaybackAsset(
        mediaUrl: URL,
        cacheKey: String?,
        headers: [String: String]?,
        enableCache: Bool?,
        isAirPlayActive: Bool,
        preResolvedCacheURL: URL? = nil,
        cacheLookupDone: Bool = false
    ) -> (AVURLAsset, MediaCacheResourceLoader?) {
        let scheme = mediaUrl.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            let mgr = MediaCacheManager.shared
            let resolvedKey = (cacheKey?.isEmpty == false)
                ? cacheKey!
                : MediaCacheManager.sha1Hex(mediaUrl.absoluteString)
            let useCache = (enableCache ?? mgr.enabled)
                && mgr.maxCacheBytes > 0
                && mgr.maxSingleFileBytes > 0
                && !MediaCacheManager.isStreamingManifest(url: mediaUrl.absoluteString)

            if !isAirPlayActive, useCache {
                if let localFileURL = preResolvedCacheURL
                    ?? (cacheLookupDone ? nil : mgr.completeFileURL(cacheKey: resolvedKey))
                {
                    return (AVURLAsset(url: localFileURL), nil)
                }
                if let customURL = MediaCacheResourceLoader.makeCustomSchemeURL(from: mediaUrl) {
                    let loader = MediaCacheResourceLoader(
                        originalURL: mediaUrl,
                        cacheKey: resolvedKey,
                        headers: headers
                    )
                    let asset = AVURLAsset(url: customURL)
                    asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
                    return (asset, loader)
                }
            }

            if let headers = headers, !headers.isEmpty {
                return (
                    AVURLAsset(url: mediaUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]),
                    nil
                )
            }
            return (AVURLAsset(url: mediaUrl), nil)
        }
        return (AVURLAsset(url: mediaUrl), nil)
    }

    func beginOpen(
        url: String,
        castUrl: String? = nil,
        cacheKey: String? = nil,
        headers: [String: String]? = nil,
        enableCache: Bool? = nil
    ) -> OpenPreparation? {
        openGeneration += 1
        let targetOpenGen = openGeneration

        let keepCastPlayer = (player?.isExternalPlaybackActive == true)
        if keepCastPlayer {
            cleanupPlayerItemObservers()
        } else {
            cleanupPlayer()
        }
        guard targetOpenGen == openGeneration else { return nil }

        wantsToPlay = false
        currentUrl = url
        currentCastUrl = castUrl
        currentCacheKey = cacheKey
        currentHeaders = headers
        currentEnableCache = enableCache

        let targetUrlString: String
        if keepCastPlayer,
           let remoteCast = castUrl,
           remoteCast.hasPrefix("http://") || remoteCast.hasPrefix("https://")
        {
            targetUrlString = remoteCast
        } else {
            targetUrlString = url
        }

        guard let mediaUrl = Self.mediaURL(from: targetUrlString) else {
            emitError("Invalid URL: \(url)")
            return nil
        }

        let accessing = mediaUrl.isFileURL && mediaUrl.startAccessingSecurityScopedResource()
        if accessing {
            securityScopedURLs.insert(mediaUrl)
        }
        return OpenPreparation(
            generation: targetOpenGen,
            mediaUrl: mediaUrl,
            keepCastPlayer: keepCastPlayer
        )
    }

    func finishOpen(
        generation: Int,
        mediaUrl: URL,
        keepCastPlayer: Bool,
        preResolvedCacheURL: URL?
    ) {
        guard generation == openGeneration else { return }

        let (asset, loader) = Self.buildPlaybackAsset(
            mediaUrl: mediaUrl,
            cacheKey: currentCacheKey,
            headers: currentHeaders,
            enableCache: currentEnableCache,
            isAirPlayActive: keepCastPlayer,
            preResolvedCacheURL: preResolvedCacheURL,
            cacheLookupDone: true
        )
        resourceLoader = loader
        let item = AVPlayerItem(asset: asset)
        playerItem = item

        attachItemObservers(item: item)

        if keepCastPlayer, let existingPlayer = player {
            existingPlayer.replaceCurrentItem(with: item)
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.allowsExternalPlayback = true
            newPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
            player = newPlayer
            hostedPlayerLayer?.player = newPlayer
            hostedPlayerLayer?.videoGravity = videoGravity

            let interval = CMTime(value: 1, timescale: 5)
            timeObserver = newPlayer.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self] time in
                if let ms = self?.milliseconds(from: time) {
                    self?.emitPosition(Int64(ms))
                }
            }

            timeControlObservation = newPlayer.observe(
                \.timeControlStatus,
                options: [.new, .initial]
            ) { [weak self] player, _ in
                self?.emitTimeControlStatus(player.timeControlStatus)
            }

            externalPlaybackObservation = newPlayer.observe(
                \.isExternalPlaybackActive,
                options: [.new, .initial]
            ) { [weak self] player, _ in
                guard let self = self else { return }
                let active = player.isExternalPlaybackActive
                if !self.wasExternalPlaybackActive, active {
                    // AirPlay receivers cannot resolve custom `xhcache-*` or app-private `file://` URLs;
                    // switch seamlessly to remote `castUrl` while preserving playhead.
                    if self.resourceLoader != nil || self.currentUrl?.hasPrefix("file://") == true,
                       let remoteCast = self.currentCastUrl,
                       remoteCast.hasPrefix("http://") || remoteCast.hasPrefix("https://")
                    {
                        let resumeTime = player.currentTime()
                        let shouldResume = self.wantsToPlay || player.rate > 0
                        self.switchItemForAirPlay(
                            remoteUrl: remoteCast,
                            resumeTime: resumeTime,
                            shouldResume: shouldResume
                        )
                    }
                } else if self.wasExternalPlaybackActive, !active {
                    // Disconnected from AirPlay: pause local playback.
                    self.wantsToPlay = false
                    player.pause()
                }
                self.wasExternalPlaybackActive = active
                self.emitCastState()
            }
        }

        ensureRouteChangeObserver()
        emitCastState()
        emitPlaying(false)
        emitBuffering(true)
    }

    private func switchItemForAirPlay(
        remoteUrl: String,
        resumeTime: CMTime,
        shouldResume: Bool
    ) {
        guard let existingPlayer = player, let url = URL(string: remoteUrl) else { return }
        cleanupPlayerItemObservers()
        let (asset, _) = Self.buildPlaybackAsset(
            mediaUrl: url,
            cacheKey: currentCacheKey,
            headers: currentHeaders,
            enableCache: false,
            isAirPlayActive: true
        )
        let item = AVPlayerItem(asset: asset)
        playerItem = item
        attachItemObservers(item: item)
        existingPlayer.replaceCurrentItem(with: item)
        let seconds = CMTimeGetSeconds(resumeTime)
        if seconds.isFinite, seconds > 0 {
            existingPlayer.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) {
                [weak self] _ in
                guard let self = self, shouldResume else { return }
                self.player?.playImmediately(atRate: self.desiredRate)
            }
        } else if shouldResume {
            existingPlayer.playImmediately(atRate: desiredRate)
        }
    }

    private func attachItemObservers(item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) {
            [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                if let durationMs = self.milliseconds(from: item.duration) {
                    self.emitDuration(Int64(durationMs))
                    if (item.asset as? AVURLAsset)?.url.isFileURL == true {
                        self.lastReportedBufferedMs = durationMs
                        self.emitBuffered(Int64(durationMs))
                    }
                }
                self.publishBufferedRanges(item: item)
                self.publishBuffering()
            case .failed:
                self.emitError(item.error?.localizedDescription ?? "Unknown error")
            default:
                break
            }
        }

        let reportSize: (CGSize) -> Void = { [weak self] size in
            guard size.width > 0, size.height > 0 else { return }
            self?.emitVideoSize(width: Double(size.width), height: Double(size.height))
        }
        if item.presentationSize.width > 0,
           item.presentationSize.height > 0
        {
            reportSize(item.presentationSize)
        }
        presentationSizeObservation = item.observe(
            \.presentationSize,
            options: [.new, .initial]
        ) { item, _ in
            reportSize(item.presentationSize)
        }

        loadedTimeRangesObservation = item.observe(
            \.loadedTimeRanges,
            options: [.new, .initial]
        ) { [weak self] item, _ in
            self?.publishBufferedRanges(item: item)
        }

        keepUpObservation = item.observe(
            \.isPlaybackLikelyToKeepUp,
            options: [.new, .initial]
        ) { [weak self] item, _ in
            self?.playbackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
            self?.publishBuffering()
        }
        bufferEmptyObservation = item.observe(
            \.isPlaybackBufferEmpty,
            options: [.new, .initial]
        ) { [weak self] item, _ in
            self?.playbackBufferEmpty = item.isPlaybackBufferEmpty
            self?.publishBuffering()
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.wantsToPlay = false
            self?.emitPlaying(false)
            self?.emitCompleted()
        }

        failedToPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.wantsToPlay = false
            self?.emitError(error?.localizedDescription ?? "Unknown error")
        }
    }

    private func publishBufferedRanges(item: AVPlayerItem) {
        var maxEndSeconds: Double = 0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
            if end.isFinite, end > maxEndSeconds {
                maxEndSeconds = end
            }
        }
        guard maxEndSeconds > 0 else { return }
        let ms = Int((maxEndSeconds * 1000).rounded())
        if ms != lastReportedBufferedMs {
            lastReportedBufferedMs = ms
            emitBuffered(Int64(ms))
        }
    }

    func play() {
        guard playerItem?.status != .failed else { return }
        wantsToPlay = true
        if let item = playerItem {
            let current = CMTimeGetSeconds(player?.currentTime() ?? .zero)
            let duration = CMTimeGetSeconds(item.duration)
            if duration.isFinite, duration > 0, current >= duration - 0.05 {
                player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        player?.playImmediately(atRate: desiredRate)
    }

    func pause() {
        wantsToPlay = false
        player?.pause()
    }

    func pauseIfNotCasting() {
        if player?.isExternalPlaybackActive == true {
            return
        }
        pause()
    }

    func seek(positionMs: Int) {
        let time = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] finished in
            guard let self = self, finished, self.wantsToPlay else { return }
            self.player?.playImmediately(atRate: self.desiredRate)
        }
    }

    func setVolume(volume: Float) {
        player?.volume = volume
    }

    func setSpeed(speed: Float) {
        desiredRate = speed
        guard let player = player else { return }
        if player.timeControlStatus == .playing || player.rate > 0 {
            player.rate = speed
        }
    }

    func showCastPicker() {
        ensureRouteChangeObserver()
        let picker = ensureRoutePickerView()
        if let button = Self.findButton(in: picker) {
            button.sendActions(for: .touchUpInside)
        }
    }

    func stopCasting() {
        guard let player else { return }
        let currentTime = player.currentTime()
        wantsToPlay = false
        player.pause()
        if player.isExternalPlaybackActive {
            player.allowsExternalPlayback = false
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let player = self.player else { return }
                player.allowsExternalPlayback = true
                player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                self.wasExternalPlaybackActive = false
                self.emitCastState()
            }
        } else {
            emitCastState()
        }
    }

    private func ensureRoutePickerView() -> AVRoutePickerView {
        if let existing = routePickerView, existing.window != nil {
            return existing
        }
        let picker = routePickerView ?? AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.alpha = 0.01
        picker.isUserInteractionEnabled = false
        if #available(iOS 13.0, *) {
            picker.prioritizesVideoDevices = true
        }
        if picker.superview == nil, let hostWindow = Self.activeWindow() {
            hostWindow.addSubview(picker)
        }
        routePickerView = picker
        return picker
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let ordered = scenes.sorted { lhs, rhs in
            let l = lhs.activationState == .foregroundActive ? 0 : 1
            let r = rhs.activationState == .foregroundActive ? 0 : 1
            return l < r
        }
        for windowScene in ordered {
            if let keyWin = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWin
            }
            if let firstWin = windowScene.windows.first {
                return firstWin
            }
        }
        return nil
    }

    private static func findButton(in view: UIView) -> UIButton? {
        if let btn = view as? UIButton {
            return btn
        }
        for sub in view.subviews {
            if let found = findButton(in: sub) {
                return found
            }
        }
        return nil
    }

    private func ensureRouteChangeObserver() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            self?.emitCastState()
        }
    }

    private func currentAirPlayDeviceName() -> String? {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if let airPlayPort = outputs.first(where: { $0.portType == .airPlay }) {
            let name = airPlayPort.portName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }
        return player?.isExternalPlaybackActive == true ? "AirPlay" : nil
    }

    private func emitCastState() {
        let isCasting = (player?.isExternalPlaybackActive == true)
        if isCasting {
            eventEmitter(
                PlayerEventData(
                    kind: .castState,
                    castState: .connected,
                    castDeviceName: currentAirPlayDeviceName() ?? "AirPlay"
                )
            )
        } else {
            eventEmitter(
                PlayerEventData(
                    kind: .castState,
                    castState: .notConnected
                )
            )
        }
    }

    private func emitPosition(_ positionMs: Int64) {
        eventEmitter(PlayerEventData(kind: .position, intValue: positionMs))
    }

    private func emitBuffered(_ bufferedMs: Int64) {
        eventEmitter(PlayerEventData(kind: .buffered, intValue: bufferedMs))
    }

    private func emitDuration(_ durationMs: Int64) {
        eventEmitter(PlayerEventData(kind: .duration, intValue: durationMs))
    }

    private func emitPlaying(_ isPlaying: Bool) {
        eventEmitter(PlayerEventData(kind: .playing, boolValue: isPlaying))
    }

    private func emitBuffering(_ isBuffering: Bool) {
        eventEmitter(PlayerEventData(kind: .buffering, boolValue: isBuffering))
    }

    private func emitError(_ message: String) {
        eventEmitter(PlayerEventData(kind: .error, message: message))
    }

    private func emitCompleted() {
        eventEmitter(PlayerEventData(kind: .completed))
    }

    private func emitVideoSize(width: Double, height: Double) {
        eventEmitter(PlayerEventData(kind: .videoSize, width: width, height: height))
    }

    func dispose() {
        openGeneration += 1
        snapshotGeneration += 1
        activeSnapshotGenerator?.cancelAllCGImageGeneration()
        activeSnapshotGenerator = nil
        activeSnapshotGeneratorId = nil
        cleanupPlayer()
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        routePickerView?.removeFromSuperview()
        routePickerView = nil
        currentUrl = nil
        currentCastUrl = nil
        currentCacheKey = nil
        currentHeaders = nil
        currentEnableCache = nil
    }

    private func milliseconds(from time: CMTime) -> Int? {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return Int((seconds * 1000).rounded())
    }

    private func emitTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            waitingForRate = false
            emitPlaying(true)
            publishBuffering()
        case .waitingToPlayAtSpecifiedRate:
            waitingForRate = true
            if wantsToPlay {
                emitPlaying(true)
            }
            publishBuffering()
        case .paused:
            waitingForRate = false
            emitPlaying(false)
            publishBuffering()
        @unknown default:
            break
        }
    }

    private func publishBuffering() {
        let buffering = waitingForRate || !playbackLikelyToKeepUp || playbackBufferEmpty
        if !wantsToPlay, !waitingForRate {
            emitBuffering(false)
            return
        }
        emitBuffering(buffering)
    }

    private func cleanupPlayerItemObservers() {
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
        if let observer = failedToPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            failedToPlayToEndObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        presentationSizeObservation?.invalidate()
        presentationSizeObservation = nil
        loadedTimeRangesObservation?.invalidate()
        loadedTimeRangesObservation = nil
        keepUpObservation?.invalidate()
        keepUpObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        resourceLoader?.invalidate()
        resourceLoader = nil
        lastReportedBufferedMs = -1
        waitingForRate = false
        playbackLikelyToKeepUp = true
        playbackBufferEmpty = false
        playerItem = nil
    }

    private func cleanupPlayer() {
        stopSecurityScopedAccess()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        cleanupPlayerItemObservers()
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        externalPlaybackObservation?.invalidate()
        externalPlaybackObservation = nil
        wasExternalPlaybackActive = false
        hostedPlayerLayer?.player = nil
        player?.pause()
        player = nil
    }

    /// Snapshot via AVAssetImageGenerator at the current playhead.
    func takeSnapshot() async throws -> SnapshotData? {
        let (generation, time, asset, generator): (Int, CMTime, AVAsset, AVAssetImageGenerator) =
            try await MainActor.run {
                guard currentUrl != nil else {
                    throw PigeonError(
                        code: "NO_MEDIA",
                        message: "No media loaded",
                        details: nil
                    )
                }
                snapshotGeneration += 1
                let gen = snapshotGeneration
                let playhead = player?.currentTime() ?? .zero
                let resolvedAsset: AVAsset
                if let cachedFileURL = MediaCacheManager.shared.completeFileURL(cacheKey: currentCacheKey) {
                    resolvedAsset = AVURLAsset(url: cachedFileURL)
                } else if let itemAsset = playerItem?.asset {
                    resolvedAsset = itemAsset
                } else if let urlString = currentUrl, let mediaUrl = URL(string: urlString) {
                    resolvedAsset = Self.makeProbeAsset(
                        mediaURL: mediaUrl,
                        cacheKey: currentCacheKey,
                        headers: currentHeaders
                    )
                } else {
                    throw PigeonError(
                        code: "NO_MEDIA",
                        message: "No media loaded",
                        details: nil
                    )
                }
                let genInstance = AVAssetImageGenerator(asset: resolvedAsset)
                genInstance.appliesPreferredTrackTransform = true
                genInstance.requestedTimeToleranceBefore = .zero
                genInstance.requestedTimeToleranceAfter = .zero
                activeSnapshotGenerator = genInstance
                activeSnapshotGeneratorId = ObjectIdentifier(genInstance)
                return (gen, playhead, resolvedAsset, genInstance)
            }
        _ = asset

        return try await withCheckedThrowingContinuation { continuation in
            let gate = OneShotGate()
            let selfBox = WeakBox(self)
            let generatorId = ObjectIdentifier(generator)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
                _, cgImage, _, status, error in
                guard gate.tryEnter() else { return }
                let errorMessage = error?.localizedDescription
                Task { @MainActor in
                    guard let player = selfBox.value else {
                        continuation.resume(
                            throwing: PigeonError(
                                code: "CANCELLED",
                                message: "Player deallocated",
                                details: nil
                            )
                        )
                        return
                    }
                    if player.activeSnapshotGeneratorId == generatorId {
                        player.activeSnapshotGenerator = nil
                        player.activeSnapshotGeneratorId = nil
                    }
                    guard generation == player.snapshotGeneration else {
                        continuation.resume(
                            throwing: PigeonError(
                                code: "CANCELLED",
                                message: "Snapshot superseded by dispose",
                                details: nil
                            )
                        )
                        return
                    }
                    guard status == .succeeded, let cgImage else {
                        continuation.resume(
                            throwing: PigeonError(
                                code: "NO_FRAME",
                                message: errorMessage ?? "Failed to capture frame",
                                details: nil
                            )
                        )
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let uiImage = UIImage(cgImage: cgImage)
                        guard let data = uiImage.pngData() else {
                            continuation.resume(
                                throwing: PigeonError(
                                    code: "ENCODE_FAIL",
                                    message: "Failed to encode PNG",
                                    details: nil
                                )
                            )
                            return
                        }
                        continuation.resume(
                            returning: SnapshotData(bytes: Array(data), dataUri: nil)
                        )
                    }
                }
            }
        }
    }

    private static func makeProbeAsset(
        mediaURL: URL,
        cacheKey: String?,
        headers: [String: String]?
    ) -> AVURLAsset {
        if let key = cacheKey, !key.isEmpty,
           let cachedURL = MediaCacheManager.shared.completeFileURL(cacheKey: key)
        {
            return AVURLAsset(url: cachedURL)
        }
        if let headers = headers, !headers.isEmpty,
           let scheme = mediaURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return AVURLAsset(url: mediaURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        return AVURLAsset(url: mediaURL)
    }

    /// 从视频 URL 中抽取若干非黑的候选封面帧。
    /// Extract non-black cover candidates from a media URL.
    static func extractCovers(
        url: String,
        count: Int,
        candidates: Int,
        minBrightness: Double,
        outputDir: String,
        cacheKey: String? = nil,
        headers: [String: String]? = nil
    ) async -> [CoverFrameData] {
        guard count > 0, let mediaURL = Self.mediaURL(from: url) else {
            return []
        }
        let asset = Self.makeProbeAsset(mediaURL: mediaURL, cacheKey: cacheKey, headers: headers)
        guard let durationSeconds = await loadDurationSeconds(asset: asset, timeoutMs: 15000) else {
            return []
        }

        let fm = FileManager.default
        try? fm.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1280, height: 720)

        let lower = durationSeconds * 0.05
        let upper = durationSeconds * 0.95
        let span = max(upper - lower, 0.1)
        let n = max(candidates, count)
        var times: [NSValue] = []
        times.reserveCapacity(n)
        for i in 0 ..< n {
            let t = lower + span * (Double(i) + 0.5) / Double(n)
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
        }
        if times.isEmpty {
            return []
        }

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var remaining = times.count
            var frames: [CoverFrameData] = []
            generator.generateCGImagesAsynchronously(forTimes: times) {
                requestedTime,
                cgImage,
                _,
                status,
                _ in
                var captured: CoverFrameData?
                if status == .succeeded, let cg = cgImage {
                    let brightness = Self.averageBrightness(cgImage: cg)
                    if brightness >= minBrightness {
                        let ms = Int64(CMTimeGetSeconds(requestedTime) * 1000)
                        let name = "cover-\(abs(url.hashValue))-\(ms).png"
                        let outPath = (outputDir as NSString).appendingPathComponent(name)
                        if Self.writePNG(cgImage: cg, to: outPath) {
                            captured = CoverFrameData(
                                path: outPath,
                                positionMs: ms,
                                brightness: brightness
                            )
                        }
                    }
                }

                lock.lock()
                if let captured {
                    frames.append(captured)
                }
                remaining -= 1
                let done = (remaining == 0)
                let snapshot = done ? frames : []
                lock.unlock()

                if done {
                    Self.trimCoverCache(in: outputDir)
                    let sorted = snapshot.sorted { $0.brightness > $1.brightness }
                    continuation.resume(returning: Array(sorted.prefix(count)))
                }
            }
        }
    }

    /// 读取媒体总时长（毫秒）。失败 / 超时 / 非有限值返回 `nil`。
    static func getDuration(
        url: String,
        timeoutMs: Int,
        cacheKey: String? = nil,
        headers: [String: String]? = nil
    ) async -> Int64? {
        guard let mediaURL = Self.mediaURL(from: url) else {
            return nil
        }
        let asset = Self.makeProbeAsset(mediaURL: mediaURL, cacheKey: cacheKey, headers: headers)
        guard let seconds = await loadDurationSeconds(asset: asset, timeoutMs: timeoutMs) else {
            return nil
        }
        return Int64((seconds * 1000).rounded())
    }

    static func loadDurationSeconds(asset: AVURLAsset, timeoutMs: Int) async -> Double? {
        let timeoutNs = UInt64(max(timeoutMs, 1)) * 1_000_000
        return await withCheckedContinuation { continuation in
            let gate = OneShotGate()
            var timeoutTask: Task<Void, Never>?

            func finish(with value: Double?) {
                if gate.tryEnter() {
                    timeoutTask?.cancel()
                    continuation.resume(returning: value)
                }
            }

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNs)
                guard !Task.isCancelled else { return }
                asset.cancelLoading()
                finish(with: nil)
            }

            asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "duration", error: &error)
                guard status == .loaded else {
                    finish(with: nil)
                    return
                }
                let seconds = CMTimeGetSeconds(asset.duration)
                guard seconds.isFinite, seconds > 0 else {
                    finish(with: nil)
                    return
                }
                finish(with: seconds)
            }
        }
    }

    static func trimCoverCache(in outputDir: String, keep: Int = 40) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: outputDir) else { return }
        let covers = items.filter { $0.hasPrefix("cover-") && $0.hasSuffix(".png") }
        if covers.count <= keep {
            return
        }
        let urls = covers.map { (outputDir as NSString).appendingPathComponent($0) }
            .compactMap { path -> (String, Date)? in
                let attrs = try? fm.attributesOfItem(atPath: path)
                let date = attrs?[.modificationDate] as? Date ?? .distantPast
                return (path, date)
            }
            .sorted { $0.1 < $1.1 }
        let extra = urls.count - keep
        if extra <= 0 {
            return
        }
        for i in 0 ..< extra {
            try? fm.removeItem(atPath: urls[i].0)
        }
    }

    // MARK: - Image helpers

    private static func writePNG(cgImage: CGImage, to path: String) -> Bool {
        #if os(iOS) || os(tvOS) || os(visionOS)
            guard let data = UIImage(cgImage: cgImage).pngData() else {
                return false
            }
            return (try? data.write(to: URL(fileURLWithPath: path))) != nil
        #else
            return false
        #endif
    }

    private static func averageBrightness(cgImage: CGImage) -> Double {
        let w = 64
        let h = 64
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let ctx = CGContext(
                data: &data,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else { return 0 }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total: Double = 0
        let pixelCount = w * h
        for i in 0 ..< pixelCount {
            let r = Double(data[i * 4]) / 255.0
            let g = Double(data[i * 4 + 1]) / 255.0
            let b = Double(data[i * 4 + 2]) / 255.0
            total += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return total / Double(pixelCount)
    }
}
