import AVFoundation
import AVKit
import Flutter
import UIKit

/// iOS 插件主类，基于 AVPlayer + AVPlayerLayer（PlatformView）渲染。
/// iOS plugin: AVPlayer displayed via AVPlayerLayer PlatformView.
public class XueHuaNaviteVideoPlayerPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var registrar: FlutterPluginRegistrar?
    private var videoPlayer: NativeVideoPlayer?
    private var savedBrightness: CGFloat?
    private var interruptionObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = XueHuaNaviteVideoPlayerPlugin()
        instance.registrar = registrar
        instance.configureAudioSession()
        instance.observeAppLifecycle()

        let methodChannel = FlutterMethodChannel(
            name: "xue_hua_navite_video_player/player",
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = methodChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "xue_hua_navite_video_player/player/events",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel = eventChannel
        instance.videoPlayer = NativeVideoPlayer()
        eventChannel.setStreamHandler(instance.videoPlayer)

        registrar.register(
            PlayerPlatformViewFactory(
                messenger: registrar.messenger(),
                playerProvider: { [weak instance] in instance?.videoPlayer }
            ),
            withId: kPlayerPlatformViewType
        )
    }

    public func detachFromEngine(for _: FlutterPluginRegistrar) {
        restoreBrightness()
        videoPlayer?.dispose()
        methodChannel?.setMethodCallHandler(nil)
        eventChannel?.setStreamHandler(nil)
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        interruptionObserver = nil
        backgroundObserver = nil
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
            let castUrl = args["castUrl"] as? String
            let cacheKey = args["cacheKey"] as? String
            let headers = Self.extractHeaders(args)
            let enableCache = args["enableCache"] as? Bool
            player.open(
                url: url,
                castUrl: castUrl,
                cacheKey: cacheKey,
                headers: headers,
                enableCache: enableCache
            )
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
        case "showCastPicker":
            player.showCastPicker()
            result(nil)
        case "stopCasting":
            player.stopCasting()
            result(nil)
        case "dispose":
            restoreBrightness()
            player.dispose()
            result(nil)
        case "getBrightness":
            result(currentBrightness())
        case "setBrightness":
            guard let args = call.arguments as? [String: Any],
                  let value = args["value"] as? Double
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARG",
                        message: "value is required",
                        details: nil
                    )
                )
                return
            }
            applyBrightness(value)
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
            let cacheKey = args["cacheKey"] as? String
            let headers = Self.extractHeaders(args)
            NativeVideoPlayer.extractCovers(
                url: url,
                count: count,
                candidates: candidates,
                minBrightness: minBrightness,
                outputDir: outputDir,
                cacheKey: cacheKey,
                headers: headers,
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
            let cacheKey = args["cacheKey"] as? String
            let headers = Self.extractHeaders(args)
            NativeVideoPlayer.getDuration(
                url: url,
                timeoutMs: timeoutMs,
                cacheKey: cacheKey,
                headers: headers,
                result: result
            )
        case "configureCache":
            let args = call.arguments as? [String: Any]
            let enabled = (args?["enabled"] as? Bool) ?? true
            let maxCacheBytes = (args?["maxCacheBytes"] as? NSNumber)?.int64Value ?? (512 * 1024 * 1024)
            let maxSingleFileBytes = (args?["maxSingleFileBytes"] as? NSNumber)?.int64Value ?? (256 * 1024 * 1024)
            let cacheDir = args?["cacheDir"] as? String
            MediaCacheManager.shared.configure(
                enabled: enabled,
                maxCacheBytes: maxCacheBytes,
                maxSingleFileBytes: maxSingleFileBytes,
                cacheDir: cacheDir
            )
            result(nil)
        case "precache":
            let args = call.arguments as? [String: Any]
            guard let url = args?["url"] as? String, !url.isEmpty else {
                result(nil)
                return
            }
            let cacheKey = (args?["cacheKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? MediaCacheManager.sha1Hex(url)
            let cacheDir = args?["cacheDir"] as? String
            let headers = Self.extractHeaders(args)
            let preloadBytes = (args?["preloadBytes"] as? NSNumber)?.int64Value
            MediaCacheManager.shared.precache(
                url: url,
                cacheKey: cacheKey,
                cacheDir: cacheDir,
                headers: headers,
                preloadBytes: preloadBytes
            ) {
                DispatchQueue.main.async { result(nil) }
            }
        case "cancelPrecache":
            if let args = call.arguments as? [String: Any],
               let cacheKey = args["cacheKey"] as? String,
               !cacheKey.isEmpty
            {
                MediaCacheManager.shared.cancelPrecache(cacheKey: cacheKey)
            }
            result(nil)
        case "isCached":
            let args = call.arguments as? [String: Any]
            let rawKey = (args?["cacheKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (args?["url"] as? String).map { MediaCacheManager.sha1Hex($0) }
            guard let key = rawKey, !key.isEmpty else {
                result(false)
                return
            }
            let cacheDir = args?["cacheDir"] as? String
            result(MediaCacheManager.shared.isCached(cacheKey: key, cacheDir: cacheDir))
        case "getCacheSize":
            let args = call.arguments as? [String: Any]
            let cacheDir = args?["cacheDir"] as? String
            MediaCacheManager.shared.getCacheSizeAsync(cacheDir: cacheDir) { bytes in
                DispatchQueue.main.async { result(bytes) }
            }
        case "removeCache":
            let args = call.arguments as? [String: Any]
            let rawKey = (args?["cacheKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (args?["url"] as? String).map { MediaCacheManager.sha1Hex($0) }
            guard let key = rawKey, !key.isEmpty else {
                result(nil)
                return
            }
            let cacheDir = args?["cacheDir"] as? String
            MediaCacheManager.shared.removeCacheAsync(cacheKey: key, cacheDir: cacheDir) {
                DispatchQueue.main.async { result(nil) }
            }
        case "clearCache":
            let args = call.arguments as? [String: Any]
            let cacheDir = args?["cacheDir"] as? String
            MediaCacheManager.shared.clearCacheAsync(cacheDir: cacheDir) {
                DispatchQueue.main.async { result(nil) }
            }
        case "pinCacheKey":
            let args = call.arguments as? [String: Any]
            MediaCacheManager.shared.pin(args?["cacheKey"] as? String)
            result(nil)
        case "unpinCacheKey":
            let args = call.arguments as? [String: Any]
            MediaCacheManager.shared.unpin(args?["cacheKey"] as? String)
            result(nil)
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func extractHeaders(_ args: [String: Any]?) -> [String: String]? {
        guard let raw = args?["headers"] as? [AnyHashable: Any] else { return nil }
        var out: [String: String] = [:]
        for (k, v) in raw {
            let key = String(describing: k).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                out[key] = String(describing: v)
            }
        }
        return out.isEmpty ? nil : out
    }

    private func currentBrightness() -> Double {
        Double(UIScreen.main.brightness)
    }

    private func applyBrightness(_ value: Double) {
        let apply = {
            if self.savedBrightness == nil {
                self.savedBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = CGFloat(min(max(value, 0), 1))
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    private func restoreBrightness() {
        guard let original = savedBrightness else { return }
        savedBrightness = nil
        let restore = {
            UIScreen.main.brightness = original
        }
        if Thread.isMainThread {
            restore()
        } else {
            DispatchQueue.main.sync(execute: restore)
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
    private var snapshotGeneration = 0

    override init() {
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
        emitCastState()
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    /// Returns 0 — display uses PlatformView, not Flutter Texture.
    func create() -> Int64 {
        ensureRouteChangeObserver()
        emitCastState()
        return 0
    }

    private var securityScopedURLs = Set<URL>()

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

    private static func buildPlaybackAsset(
        mediaUrl: URL,
        cacheKey: String?,
        headers: [String: String]?,
        enableCache: Bool?,
        isAirPlayActive: Bool
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
                if let localFileURL = mgr.completeFileURL(cacheKey: resolvedKey) {
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

    func open(
        url: String,
        castUrl: String? = nil,
        cacheKey: String? = nil,
        headers: [String: String]? = nil,
        enableCache: Bool? = nil
    ) {
        let keepCastPlayer = (player?.isExternalPlaybackActive == true)
        if keepCastPlayer {
            cleanupPlayerItemObservers()
        } else {
            cleanupPlayer()
        }
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
            sendEvent(event: "error", value: "Invalid URL: \(url)")
            return
        }

        let accessing = mediaUrl.isFileURL && mediaUrl.startAccessingSecurityScopedResource()
        if accessing {
            securityScopedURLs.insert(mediaUrl)
        }

        let (asset, loader) = Self.buildPlaybackAsset(
            mediaUrl: mediaUrl,
            cacheKey: cacheKey,
            headers: headers,
            enableCache: enableCache,
            isAirPlayActive: keepCastPlayer
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
                    self?.sendEvent(event: "position", value: ms)
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
                    // switch seamlessly to the remote `castUrl` while preserving playhead!
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
                    // Disconnected from AirPlay: pause local playback so audio
                    // does not unexpectedly blast from the device speaker.
                    self.wantsToPlay = false
                    player.pause()
                }
                self.wasExternalPlaybackActive = active
                self.emitCastState()
            }
        }

        ensureRouteChangeObserver()
        emitCastState()
        sendEvent(event: "playing", value: false)
        sendEvent(event: "buffering", value: true)
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
                    self.sendEvent(event: "duration", value: durationMs)
                    if (item.asset as? AVURLAsset)?.url.isFileURL == true {
                        self.lastReportedBufferedMs = durationMs
                        self.sendEvent(event: "buffered", value: durationMs)
                    }
                }
                self.publishBufferedRanges(item: item)
                self.publishBuffering()
            case .failed:
                self.sendEvent(
                    event: "error",
                    value: item.error?.localizedDescription ?? "Unknown error"
                )
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
            self?.sendEvent(event: "playing", value: false)
            self?.sendEvent(event: "completed", value: nil)
        }

        failedToPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.wantsToPlay = false
            self?.sendEvent(
                event: "error",
                value: error?.localizedDescription ?? "Unknown error"
            )
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
            sendEvent(event: "buffered", value: ms)
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensureRouteChangeObserver()
            let picker = self.ensureRoutePickerView()
            if let button = Self.findButton(in: picker) {
                button.sendActions(for: .touchUpInside)
            }
        }
    }

    func stopCasting() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let player = self.player else { return }
            let currentTime = player.currentTime()
            self.wantsToPlay = false
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
                self.emitCastState()
            }
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
        if picker.superview == nil {
            if let hostWindow = Self.activeWindow() {
                hostWindow.addSubview(picker)
            }
        }
        routePickerView = picker
        return picker
    }

    private static func activeWindow() -> UIWindow? {
        // Min deployment is iOS 13; prefer the foreground active scene's key window.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let ordered = scenes.sorted { lhs, rhs in
            // Prefer foreground active scenes when available.
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
            sendEvent(
                event: "castState",
                value: [
                    "state": "connected",
                    "deviceName": currentAirPlayDeviceName() ?? "AirPlay",
                ]
            )
        } else {
            sendEvent(
                event: "castState",
                value: [
                    "state": "notConnected",
                ]
            )
        }
    }

    func dispose() {
        snapshotGeneration += 1
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

    private func sendEvent(event: String, value: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["event": event, "value": value as Any])
        }
    }

    /// Snapshot via AVAssetImageGenerator at the current playhead.
    func takeSnapshot(result: @escaping FlutterResult) {
        guard currentUrl != nil else {
            result(
                FlutterError(
                    code: "NO_MEDIA",
                    message: "No media loaded",
                    details: nil
                )
            )
            return
        }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        let time = player?.currentTime() ?? .zero
        let asset: AVAsset
        if let cachedFileURL = MediaCacheManager.shared.completeFileURL(cacheKey: currentCacheKey) {
            asset = AVURLAsset(url: cachedFileURL)
        } else if let itemAsset = playerItem?.asset {
            asset = itemAsset
        } else if let urlString = currentUrl, let mediaUrl = URL(string: urlString) {
            asset = Self.makeProbeAsset(mediaURL: mediaUrl, cacheKey: currentCacheKey, headers: currentHeaders)
        } else {
            result(
                FlutterError(
                    code: "NO_MEDIA",
                    message: "No media loaded",
                    details: nil
                )
            )
            return
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
            [weak self] _, cgImage, _, status, error in
            DispatchQueue.main.async {
                guard let self, generation == self.snapshotGeneration else { return }
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
                let uiImage = UIImage(cgImage: cgImage)
                guard let data = uiImage.pngData() else {
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
        headers: [String: String]? = nil,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let mediaURL = Self.mediaURL(from: url) else {
                DispatchQueue.main.async { result([]) }
                return
            }
            let asset = Self.makeProbeAsset(mediaURL: mediaURL, cacheKey: cacheKey, headers: headers)
            guard let durationSeconds = loadDurationSeconds(asset: asset, timeoutMs: 15000)
            else {
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

            // Sample times: skip first/last 5%, evenly distribute `candidates` in between.
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
            for value in times {
                _ = value
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
                Self.trimCoverCache(in: outputDir)
                // Sort by brightness descending and trim to count.
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
        cacheKey: String? = nil,
        headers: [String: String]? = nil,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let mediaURL = Self.mediaURL(from: url) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let asset = Self.makeProbeAsset(mediaURL: mediaURL, cacheKey: cacheKey, headers: headers)
            guard let seconds = loadDurationSeconds(asset: asset, timeoutMs: timeoutMs) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let ms = Int((seconds * 1000).rounded())
            DispatchQueue.main.async { result(ms) }
        }
    }

    static func loadDurationSeconds(asset: AVURLAsset, timeoutMs: Int) -> Double? {
        let semaphore = DispatchSemaphore(value: 0)
        var finished = false
        asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            finished = true
            semaphore.signal()
        }
        let waitResult = semaphore.wait(timeout: .now() + .milliseconds(timeoutMs))
        guard waitResult == .success, finished else { return nil }
        var error: NSError?
        let status = asset.statusOfValue(forKey: "duration", error: &error)
        guard status == .loaded else { return nil }
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
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

    private static func pngData(from buffer: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else {
            return nil
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
            return UIImage(cgImage: cg).pngData()
        #else
            return nil
        #endif
    }

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
