import AVFoundation
import Flutter
import UIKit

let kPlayerPlatformViewType = "plugins.xuehua/navite_video_player"

/// Hosts [AVPlayerLayer] so videoGravity uses the official Apple property.
final class PlayerPlatformView: NSObject, FlutterPlatformView {
    private let container: PlayerContainerView

    init(frame: CGRect, player: NativeVideoPlayer) {
        container = PlayerContainerView(frame: frame)
        container.backgroundColor = .black
        super.init()
        player.attachPlayerLayer(container.playerLayer)
    }

    func view() -> UIView {
        container
    }
}

final class PlayerContainerView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

final class PlayerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let playerProvider: () -> NativeVideoPlayer?

    init(messenger: FlutterBinaryMessenger, playerProvider: @escaping () -> NativeVideoPlayer?) {
        self.messenger = messenger
        self.playerProvider = playerProvider
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier _: Int64, arguments _: Any?)
        -> FlutterPlatformView
    {
        guard let player = playerProvider() else {
            return EmptyPlatformView(frame: frame)
        }
        return PlayerPlatformView(frame: frame, player: player)
    }
}

private final class EmptyPlatformView: NSObject, FlutterPlatformView {
    private let v: UIView
    init(frame: CGRect) {
        v = UIView(frame: frame)
        v.backgroundColor = .black
        super.init()
    }

    func view() -> UIView {
        v
    }
}
