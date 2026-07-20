import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../data/enums/play_state.dart';
import '../player/video_player_controller.dart';
import 'platform_view_types.dart';
import 'style/video_player_theme.dart';

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

  static bool get _usesPlatformView {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS || Platform.isAndroid;
  }

  @override
  Widget build(BuildContext context) {
    final FlutterSignal<PlayState> state = controller.playState;
    final buffering = controller.isBuffering;
    final bg = backgroundColor ?? VideoPlayerTheme.of(context).backgroundColor;

    final double effectiveAspectRatio;
    if (aspectRatio != null) {
      effectiveAspectRatio = aspectRatio!;
    } else {
      final reported = controller.videoAspectRatio;
      effectiveAspectRatio = ((reported.value > 0) ? reported.value : 16 / 9);
    }

    if (state.value == PlayState.error) {
      final err = controller.errorMessage;
      return Container(
        color: bg,
        alignment: Alignment.center,
        child: errorBuilder != null ? errorBuilder!(context, err.value) : const SizedBox(),
      );
    }

    final media = _buildMediaSurface(context, effectiveAspectRatio);
    final showLoading = state.value == PlayState.loading || buffering.value;

    return ColoredBox(
      color: bg,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: media),
          if (showLoading) loadingBuilder?.call(context) ?? const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildMediaSurface(BuildContext context, double effectiveAspectRatio) {
    if (kIsWeb) {
      return const HtmlElementView(viewType: kWebPlayerViewType);
    }

    if (_usesPlatformView) {
      return _PlatformPlayerView(controller: controller);
    }

    // Linux / Windows — Texture + report view size for mpv panscan.
    return _TexturePlayerView(controller: controller, effectiveAspectRatio: effectiveAspectRatio);
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
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: kNativePlayerViewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }
    if (Platform.isIOS) {
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
  const _TexturePlayerView({required this.controller, required this.effectiveAspectRatio});

  final VideoPlayerController controller;
  final double effectiveAspectRatio;

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

        final textureId = widget.controller.textureId.value;
        final rotation = widget.controller.rotationDegrees.value % 360;
        if (textureId == null) {
          return const SizedBox.expand();
        }
        return _VideoTexture(textureId: textureId, rotationDegrees: rotation);
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
