import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/play_state.dart';
import '../player/video_player_controller.dart';
import 'platform_view_types.dart';
import 'style/video_player_theme.dart';
import 'widgets/live_photo_still_view.dart';

/// 视频渲染组件，只负责显示视频画面和基本状态（加载/缓冲/错误）。
///
/// - iOS / macOS / Android：PlatformView（原生 videoGravity / resizeMode）
/// - Web：HtmlElementView（object-fit）
/// - Linux / Windows：Flutter [Texture]（mpv keepaspect/panscan）
class CorePlayer extends SignalWidget {
  final VideoPlayerController controller;
  final double? aspectRatio;
  final Color? backgroundColor;
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;

  const CorePlayer({
    super.key,
    required this.controller,
    this.aspectRatio,
    this.backgroundColor,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final FlutterSignal<PlayState> state = controller.playState;
    final buffering = controller.isBuffering;
    final liveBundle = controller.livePhotoBundle.value;
    final aspectMode = controller.aspectRatioMode.value;
    final bg = backgroundColor ?? VideoPlayerTheme.of(context).backgroundColor;

    // Keep aspect tracking in this SignalWidget so size/rotation updates rebuild.
    if (aspectRatio == null) {
      controller.videoAspectRatio.value;
    }

    if (state.value == PlayState.error) {
      final err = controller.errorMessage;
      return Container(
        color: bg,
        alignment: Alignment.center,
        child: errorBuilder != null ? errorBuilder!(context, err.value) : const SizedBox(),
      );
    }

    final showLoading = state.value == PlayState.loading || buffering.value;
    final showLiveStillCover =
        liveBundle != null &&
        (state.value == PlayState.idle ||
            state.value == PlayState.loading ||
            state.value == PlayState.stopped ||
            state.value == PlayState.completed ||
            (state.value == PlayState.paused && controller.position.value == Duration.zero));

    final coverFit = switch (aspectMode) {
      AspectRatioMode.fill => BoxFit.cover,
      AspectRatioMode.stretch => BoxFit.fill,
      AspectRatioMode.fit => BoxFit.contain,
    };

    return ColoredBox(
      color: bg,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(child: _MediaSurface(controller: controller)),
          if (liveBundle != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showLiveStillCover ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: LivePhotoStillView(bundle: liveBundle, fit: coverFit),
                ),
              ),
            ),
          if (showLoading) loadingBuilder?.call(context) ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _MediaSurface extends StatelessWidget {
  const _MediaSurface({required this.controller});

  final VideoPlayerController controller;

  static bool get _usesPlatformView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const HtmlElementView(viewType: kWebPlayerViewType);
    }

    if (_usesPlatformView) {
      return _PlatformPlayerView(controller: controller);
    }

    // Linux / Windows — Texture + report view size for mpv panscan.
    return _TexturePlayerView(controller: controller);
  }
}

class _PlatformPlayerView extends StatefulWidget {
  const _PlatformPlayerView({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_PlatformPlayerView> createState() => _PlatformPlayerViewState();
}

class _PlatformPlayerViewState extends State<_PlatformPlayerView> {
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: kNativePlayerViewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: kNativePlayerViewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    // macOS
    return AppKitView(
      viewType: kNativePlayerViewType,
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}

class _TexturePlayerView extends StatefulWidget {
  const _TexturePlayerView({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_TexturePlayerView> createState() => _TexturePlayerViewState();
}

class _TexturePlayerViewState extends State<_TexturePlayerView> {
  Size? _lastSize;

  void _reportSize(Size size, double dpr) {
    if (size.width <= 0 || size.height <= 0) return;
    if (_lastSize == size) return;
    _lastSize = size;
    widget.controller.setVideoViewSize(
      width: size.width,
      height: size.height,
      devicePixelRatio: dpr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _reportSize(size, dpr);
        });

        return SignalBuilder(
          builder: (context) {
            final textureId = widget.controller.textureId.value;
            final rotation = widget.controller.rotationDegrees.value % 360;
            if (textureId == null) {
              return const SizedBox.expand();
            }
            return _VideoTexture(textureId: textureId, rotationDegrees: rotation);
          },
        );
      },
    );
  }
}

class _VideoTexture extends StatelessWidget {
  const _VideoTexture({required this.textureId, required this.rotationDegrees});

  final int textureId;
  final int rotationDegrees;

  @override
  Widget build(BuildContext context) {
    final child = Texture(textureId: textureId);
    if (rotationDegrees == 0) {
      return child;
    }
    assert(rotationDegrees % 90 == 0);
    return RotatedBox(quarterTurns: rotationDegrees ~/ 90, child: child);
  }
}
