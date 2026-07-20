import AVFoundation
import Cocoa
import FlutterMacOS

/// macOS 插件主类，基于 AVPlayer 实现原生视频播放，通过 AVPlayerLayer（PlatformView）渲染。
/// macOS plugin: AVPlayer displayed via AVPlayerLayer PlatformView.
public class XueHuaNaviteVideoPlayerPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var registrar: FlutterPluginRegistrar?
    private var videoPlayer: NativeVideoPlayer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = XueHuaNaviteVideoPlayerPlugin()
        instance.registrar = registrar

        let methodChannel = FlutterMethodChannel(
            name: "xue_hua_navite_video_player/player",
            binaryMessenger: registrar.messenger
        )
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "xue_hua_navite_video_player/player/events",
            binaryMessenger: registrar.messenger
        )
        instance.eventChannel = eventChannel
        instance.videoPlayer = NativeVideoPlayer()
        eventChannel.setStreamHandler(instance.videoPlayer)

        registrar.register(
            PlayerPlatformViewFactory(
                playerProvider: { [weak instance] in instance?.videoPlayer }
            ),
            withId: kPlayerPlatformViewType
        )
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let player = videoPlayer else {
            result(
                FlutterError(
                    code: "NO_PLAYER",
                    message: "Player not initialized",
                    details: nil
                )
            )
            return
        }

        switch call.method {
        case "create":
            let textureId = player.create()
            result(textureId)
        case "open":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "url is required",
                        details: nil
                    )
                )
                return
            }
            player.open(url: url)
            result(nil)
        case "play":
            player.play()
            result(nil)
        case "pause":
            player.pause()
            result(nil)
        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Int
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "position is required",
                        details: nil
                    )
                )
                return
            }
            player.seek(positionMs: position)
            result(nil)
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "volume is required",
                        details: nil
                    )
                )
                return
            }
            player.setVolume(volume: Float(volume))
            result(nil)
        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "speed is required",
                        details: nil
                    )
                )
                return
            }
            player.setSpeed(speed: Float(speed))
            result(nil)
        case "setAspectRatioMode":
            guard let args = call.arguments as? [String: Any],
                  let mode = args["mode"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "mode is required",
                        details: nil
                    )
                )
                return
            }
            player.setAspectRatioMode(mode)
            result(nil)
        case "setVideoViewSize":
            result(nil)
        case "dispose":
            player.dispose()
            result(nil)
        case "takeSnapshot":
            player.takeSnapshot(result: result)
        case "extractCovers":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "url is required",
                        details: nil
                    )
                )
                return
            }
            let count = (args["count"] as? Int) ?? 5
            let candidates = (args["candidates"] as? Int) ?? (count * 3)
            let minBrightness = (args["minBrightness"] as? Double) ?? 0.08
            let outputDir =
                (args["outputDir"] as? String) ?? NSTemporaryDirectory()
            NativeVideoPlayer.extractCovers(
                url: url,
                count: count,
                candidates: candidates,
                minBrightness: minBrightness,
                outputDir: outputDir,
                result: result
            )
        case "getDuration":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "url is required",
                        details: nil
                    )
                )
                return
            }
            let timeoutMs = (args["timeoutMs"] as? Int) ?? 15000
            NativeVideoPlayer.getDuration(
                url: url,
                timeoutMs: timeoutMs,
                result: result
            )
        case "getPlatformVersion":
            result(
                "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
            )
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// AVPlayer 封装：画面由 PlatformView 上的 AVPlayerLayer 显示（videoGravity）。
/// AVPlayer wrapper: frames shown via AVPlayerLayer on a PlatformView.
class NativeVideoPlayer: NSObject, FlutterStreamHandler {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var eventSink: FlutterEventSink?
    private var timeObserver: Any?
    private var desiredRate: Float = 1.0
    private var waitingForRate = false
    private var playbackLikelyToKeepUp = true
    private var playbackBufferEmpty = false
    private var statusObservation: NSKeyValueObservation?
    private var presentationSizeObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var currentUrl: String?
    private var transientRetryCount = 0
    private let maxTransientRetries = 4
    private var wantsToPlay = false
    private weak var hostedPlayerLayer: AVPlayerLayer?
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    override init() {
        super.init()
    }

    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        hostedPlayerLayer = layer
        layer.videoGravity = videoGravity
        layer.player = player
    }

    func setAspectRatioMode(_ mode: String) {
        switch mode {
        case "fill":
            videoGravity = .resizeAspectFill
        case "stretch":
            videoGravity = .resize
        default:
            videoGravity = .resizeAspect
        }
        hostedPlayerLayer?.videoGravity = videoGravity
    }

    func onListen(
        withArguments _: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    /// Returns 0 — display uses PlatformView, not Flutter Texture.
    func create() -> Int64 {
        0
    }

    func open(url: String) {
        cleanupPlayer()
        currentUrl = url
        transientRetryCount = 0
        wantsToPlay = false
        openInternal(url: url)
    }

    private func openInternal(url: String) {
        guard let mediaUrl = URL(string: url) else {
            sendEvent(event: "error", value: "Invalid URL: \(url)")
            return
        }

        let asset = AVURLAsset(url: mediaUrl)
        playerItem = AVPlayerItem(asset: asset)

        statusObservation = playerItem!.observe(\.status, options: [.new]) {
            [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                self.transientRetryCount = 0
                let durationMs = Int(CMTimeGetSeconds(item.duration) * 1000)
                self.sendEvent(event: "duration", value: durationMs)
                self.publishBuffering()
            case .failed:
                if self.transientRetryCount < self.maxTransientRetries, let url = self.currentUrl {
                    self.transientRetryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if self.currentUrl == url {
                            self.cleanupPlayerKeepingUrl()
                            self.openInternal(url: url)
                            if self.wantsToPlay {
                                self.player?.playImmediately(atRate: self.desiredRate)
                            }
                        }
                    }
                } else {
                    self.sendEvent(
                        event: "error",
                        value: item.error?.localizedDescription ?? "Unknown error"
                    )
                }
            default:
                break
            }
        }

        let reportSize: (CGSize) -> Void = { [weak self] size in
            guard size.width > 0, size.height > 0 else { return }
            self?.sendEvent(
                event: "videoSize",
                value: [
                    "width": Int(size.width),
                    "height": Int(size.height),
                ]
            )
        }
        if playerItem!.presentationSize.width > 0,
           playerItem!.presentationSize.height > 0
        {
            reportSize(playerItem!.presentationSize)
        }
        presentationSizeObservation = playerItem!.observe(
            \.presentationSize,
            options: [.new, .initial]
        ) { item, _ in
            reportSize(item.presentationSize)
        }

        player = AVPlayer(playerItem: playerItem)
        hostedPlayerLayer?.player = player
        hostedPlayerLayer?.videoGravity = videoGravity

        let interval = CMTime(value: 1, timescale: 5)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            let ms = Int(CMTimeGetSeconds(time) * 1000)
            self?.sendEvent(event: "position", value: ms)
        }

        timeControlObservation = player?.observe(
            \.timeControlStatus,
            options: [.new, .initial]
        ) { [weak self] player, _ in
            self?.emitTimeControlStatus(player.timeControlStatus)
        }

        keepUpObservation = playerItem!.observe(
            \.isPlaybackLikelyToKeepUp,
            options: [.new, .initial]
        ) { [weak self] item, _ in
            self?.playbackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
            self?.publishBuffering()
        }
        bufferEmptyObservation = playerItem!.observe(
            \.isPlaybackBufferEmpty,
            options: [.new, .initial]
        ) { [weak self] item, _ in
            self?.playbackBufferEmpty = item.isPlaybackBufferEmpty
            self?.publishBuffering()
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.wantsToPlay = false
            self?.sendEvent(event: "playing", value: false)
            self?.sendEvent(event: "completed", value: nil)
        }

        sendEvent(event: "playing", value: false)
        sendEvent(event: "buffering", value: true)
    }

    func play() {
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

    func dispose() {
        cleanupPlayer()
        currentUrl = nil
    }

    private func emitTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            waitingForRate = false
            sendEvent(event: "playing", value: true)
            publishBuffering()
        case .waitingToPlayAtSpecifiedRate:
            waitingForRate = true
            if wantsToPlay {
                sendEvent(event: "playing", value: true)
            }
            publishBuffering()
        case .paused:
            waitingForRate = false
            sendEvent(event: "playing", value: false)
            publishBuffering()
        @unknown default:
            break
        }
    }

    private func publishBuffering() {
        let buffering =
            waitingForRate || !playbackLikelyToKeepUp || playbackBufferEmpty
        if !wantsToPlay, !waitingForRate {
            sendEvent(event: "buffering", value: false)
            return
        }
        sendEvent(event: "buffering", value: buffering)
    }

    private func cleanupPlayerKeepingUrl() {
        let url = currentUrl
        cleanupPlayer()
        currentUrl = url
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        presentationSizeObservation?.invalidate()
        presentationSizeObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        keepUpObservation?.invalidate()
        keepUpObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        waitingForRate = false
        playbackLikelyToKeepUp = true
        playbackBufferEmpty = false
        hostedPlayerLayer?.player = nil
        player?.pause()
        player = nil
        playerItem = nil
    }

    private func sendEvent(event: String, value: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": event, "value": value as Any])
        }
    }

    /// Snapshot via AVAssetImageGenerator at the current playhead.
    func takeSnapshot(result: @escaping FlutterResult) {
        guard let urlString = currentUrl, let mediaUrl = URL(string: urlString) else {
            result(
                FlutterError(
                    code: "NO_MEDIA",
                    message: "No media loaded",
                    details: nil
                )
            )
            return
        }
        let time = player?.currentTime() ?? .zero
        let asset = AVURLAsset(url: mediaUrl)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
            _, cgImage, _, status, error in
            DispatchQueue.main.async {
                guard status == .succeeded, let cgImage = cgImage else {
                    result(
                        FlutterError(
                            code: "NO_FRAME",
                            message: error?.localizedDescription ?? "Failed to capture frame",
                            details: nil
                        )
                    )
                    return
                }
                let rep = NSBitmapImageRep(cgImage: cgImage)
                guard let data = rep.representation(using: .png, properties: [:]) else {
                    result(
                        FlutterError(
                            code: "ENCODE_FAIL",
                            message: "Failed to encode PNG",
                            details: nil
                        )
                    )
                    return
                }
                result(FlutterStandardTypedData(bytes: data))
            }
        }
    }

    /// 从视频 URL 中抽取若干非黑的候选封面帧。
    /// Extract non-black cover candidates from a media URL.
    static func extractCovers(
        url: String,
        count: Int,
        candidates: Int,
        minBrightness: Double,
        outputDir: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let mediaURL = URL(string: url) else {
                DispatchQueue.main.async { result([]) }
                return
            }
            let asset = AVURLAsset(url: mediaURL)
            let durationSeconds = CMTimeGetSeconds(asset.duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                DispatchQueue.main.async { result([]) }
                return
            }

            let fm = FileManager.default
            try? fm.createDirectory(
                atPath: outputDir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(
                seconds: 0.5,
                preferredTimescale: 600
            )
            generator.requestedTimeToleranceAfter = CMTime(
                seconds: 0.5,
                preferredTimescale: 600
            )
            generator.maximumSize = CGSize(width: 1280, height: 720)

            let lower = durationSeconds * 0.05
            let upper = durationSeconds * 0.95
            let span = max(upper - lower, 0.1)
            let n = max(candidates, count)
            var times: [NSValue] = []
            for i in 0 ..< n {
                let t = lower + span * (Double(i) + 0.5) / Double(n)
                times.append(
                    NSValue(time: CMTime(seconds: t, preferredTimescale: 600))
                )
            }

            var frames: [[String: Any]] = []
            let group = DispatchGroup()
            let sync = DispatchQueue(label: "xue_hua_navite_video_player.covers")
            for _ in times {
                group.enter()
            }

            generator.generateCGImagesAsynchronously(forTimes: times) {
                requestedTime,
                cgImage,
                _,
                status,
                _ in
                defer { group.leave() }
                guard status == .succeeded, let cg = cgImage else { return }
                let brightness = Self.averageBrightness(cgImage: cg)
                if brightness < minBrightness {
                    return
                }
                let ms = Int(CMTimeGetSeconds(requestedTime) * 1000)
                let name = "cover-\(abs(url.hashValue))-\(ms).png"
                let outPath = (outputDir as NSString).appendingPathComponent(
                    name
                )
                if Self.writePNG(cgImage: cg, to: outPath) {
                    sync.sync {
                        frames.append([
                            "path": outPath,
                            "positionMs": ms,
                            "brightness": brightness,
                        ])
                    }
                }
            }

            group.notify(queue: .main) {
                let sorted = frames.sorted { a, b -> Bool in
                    let ab = (a["brightness"] as? Double) ?? 0
                    let bb = (b["brightness"] as? Double) ?? 0
                    return ab > bb
                }
                let trimmed = Array(sorted.prefix(count))
                result(trimmed)
            }
        }
    }

    /// 读取媒体总时长（毫秒）。失败 / 超时 / 非有限值返回 `nil`。
    /// Probe media total duration (ms). Returns `nil` on failure / timeout /
    /// non-finite duration (live / HLS).
    static func getDuration(
        url: String,
        timeoutMs: Int,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let mediaURL = URL(string: url) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let asset = AVURLAsset(url: mediaURL)
            let semaphore = DispatchSemaphore(value: 0)
            var finished = false
            asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                finished = true
                semaphore.signal()
            }
            let waitResult = semaphore.wait(
                timeout: .now() + .milliseconds(timeoutMs)
            )
            guard waitResult == .success, finished else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            guard status == .loaded else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let seconds = CMTimeGetSeconds(asset.duration)
            guard seconds.isFinite, seconds > 0 else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let ms = Int(seconds * 1000)
            DispatchQueue.main.async { result(ms) }
        }
    }

    // MARK: - Image helpers

    private static func pngData(from buffer: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    private static func writePNG(cgImage: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
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
