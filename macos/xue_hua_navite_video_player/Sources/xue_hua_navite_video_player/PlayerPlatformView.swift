import AVFoundation
import Cocoa
import FlutterMacOS

let kPlayerPlatformViewType = "plugins.xuehua/navite_video_player"

final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

final class PlayerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let playerProvider: () -> NativeVideoPlayer?

    init(playerProvider: @escaping () -> NativeVideoPlayer?) {
        self.playerProvider = playerProvider
        super.init()
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let container = PlayerContainerView(frame: .zero)
        if let player = playerProvider() {
            player.attachPlayerLayer(container.playerLayer)
        }
        return container
    }
}
