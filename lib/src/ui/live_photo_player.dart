import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/live_photo_badge_position.dart';
import '../data/enums/live_photo_play_mode.dart';
import '../data/enums/play_state.dart';
import '../data/models/live_photo_bundle.dart';
import '../player/video_player_controller.dart';
import '../utils/live_photo_extractor.dart';
import '../xue_hua_navite_video_player.dart';
import 'core_player.dart';
import 'style/video_player_theme.dart';
import 'widgets/live_photo_badge.dart';
import 'widgets/live_photo_still_view.dart';

/// 专用于展示与交互式播放动态照片（Live Photo / Motion Photo）的跨平台组件（移动端 + 桌面端 + Web）。
///
/// 特性：
/// - **全端原生解码与渲染**：
///   - iOS / macOS：基于 `AVPlayer` PlatformView
///   - Android：基于 Media3 `ExoPlayer` PlatformView
///   - Windows / Linux：基于 `libmpv` 软件渲染 `Texture`（并在桌面端对不支持直接解码的 `.heic` 静态图提供视频首帧自动回退）
///   - Web：基于 HTML5 `<video>`
/// - **双格式全兼容**：同时支持双文件配对实况照片（[LivePhotoSource.paired] / `.network` / `.file` / `.asset`）
///   与单文件内嵌动态照片（Google/Android/Xiaomi/OPPO/Samsung Motion Photo 及 macOS `.pvt` 包）。
/// - **五种交互模式与桌面端原生体验**：
///   - [LivePhotoPlayMode.longPress]：长按画面播放，松手恢复静态图（且在桌面端默认支持鼠标悬停左上角 `LIVE` 徽标即刻播放，对齐 macOS 系统相册体验）
///   - [LivePhotoPlayMode.hover]：鼠标移入画面即播放，移出恢复静态图（桌面端/Web 推荐）
///   - [LivePhotoPlayMode.tap]：点击画面或 `LIVE` 徽标完整播放一次
///   - [LivePhotoPlayMode.autoPlayOnce]：组件加载完成后自动播放一次
///   - [LivePhotoPlayMode.loop]：持续无缝循环播放
/// - **单会话自动协调**：当未传入外部 [controller] 时，组件仅在触发动态播放时按需申请原生播放器会话，
///   并在多个 [LivePhotoPlayer] 之间自动移交原生单会话。
class LivePhotoPlayer extends StatefulWidget {
  const LivePhotoPlayer({
    super.key,
    required this.source,
    this.controller,
    this.playMode = LivePhotoPlayMode.longPress,
    this.enableBadgeHoverOnDesktop = true,
    this.badgePosition = LivePhotoBadgePosition.topLeft,
    this.badgePadding = const EdgeInsets.all(10),
    this.showBadge = true,
    this.badgeLabel = 'LIVE',
    this.showMuteButton = true,
    this.initiallyMuted = false,
    this.enableScaleEffect = true,
    this.activeScale = 1.035,
    this.enableHapticFeedback = true,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.borderRadius,
    this.backgroundColor,
    this.crossfadeDuration = const Duration(milliseconds: 220),
    this.theme,
    this.onPlaybackStart,
    this.onPlaybackComplete,
    this.badgeBuilder,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  /// 动态照片来源（支持配对图+视频、单文件 Motion Photo、内存字节或自动配对本地文件）。
  final LivePhotoSource source;

  /// 可选的外部 [VideoPlayerController]。
  /// 若为 `null`，组件将在触发播放时自动创建并协调内部控制器（遵循插件全局单会话约束）。
  final VideoPlayerController? controller;

  /// 动态照片触发与循环模式，默认 [LivePhotoPlayMode.longPress]。
  final LivePhotoPlayMode playMode;

  /// 在桌面端（macOS / Windows / Linux / Web）是否允许鼠标悬停在 `LIVE` 徽标上直接触发播放（仿 macOS Photos 行为），默认 `true`。
  final bool enableBadgeHoverOnDesktop;

  /// `LIVE` 徽标在画面四角的位置，默认 [LivePhotoBadgePosition.topLeft]。
  final LivePhotoBadgePosition badgePosition;

  /// `LIVE` 徽标距离边缘的内边距。
  final EdgeInsets badgePadding;

  /// 是否显示 `LIVE` 徽标，默认 `true`。
  final bool showBadge;

  /// 徽标文字，默认 `'LIVE'`（可设为 `'实况'` 等）。
  final String badgeLabel;

  /// 是否在徽标旁展示静音切换按钮，默认 `true`。
  final bool showMuteButton;

  /// 初始是否静音，默认 `false`。
  final bool initiallyMuted;

  /// 播放动态效果时是否启用 iOS / macOS 相册风格的微缩放动效，默认 `true`。
  final bool enableScaleEffect;

  /// 启用缩放动效时的目标缩放比例，默认 `1.035`。
  final double activeScale;

  /// 触发播放时是否产生轻触觉反馈（HapticFeedback），默认 `true`。
  final bool enableHapticFeedback;

  /// 画面填充方式，默认 [BoxFit.cover]。
  final BoxFit fit;

  /// 可选宽高比约束；若为 `null` 则填满父容器。
  final double? aspectRatio;

  /// 可选圆角裁剪。
  final BorderRadius? borderRadius;

  /// 背景底色，默认读取 [VideoPlayerTheme.backgroundColor]。
  final Color? backgroundColor;

  /// 静态图与动态视频之间的交叉淡入淡出时长，默认 `220ms`。
  final Duration crossfadeDuration;

  /// 可选的局部主题覆盖。
  final VideoPlayerTheme? theme;

  /// 动态视频开始播放时的回调。
  final VoidCallback? onPlaybackStart;

  /// 动态视频自然播放结束或停止时的回调。
  final VoidCallback? onPlaybackComplete;

  /// 自定义角标构建器。
  final Widget Function(BuildContext context, bool isPlaying, bool isMuted)? badgeBuilder;

  /// 静态封面加载前的占位构建器。
  final Widget Function(BuildContext context)? placeholderBuilder;

  /// 解析或播放出错时的错误构建器。
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;

  @override
  State<LivePhotoPlayer> createState() => _LivePhotoPlayerState();
}

class _LivePhotoPlayerState extends State<LivePhotoPlayer> {
  /// 全局跟踪当前持有自动创建原生会话的 [_LivePhotoPlayerState]，确保列表中切换实况照片时安全移交。
  static _LivePhotoPlayerState? _activeAutoSessionOwner;

  LivePhotoBundle? _bundle;
  String? _resolveError;
  bool _resolving = true;

  VideoPlayerController? _internalController;
  VoidCallback? _stateEffectDisposer;

  bool _wantsPlayback = false;
  bool _showingVideo = false;
  bool _isMuted = false;
  int _loadGeneration = 0;

  VideoPlayerController? get _activeController => widget.controller ?? _internalController;

  static bool get _isDesktopOrWeb {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  VideoSource? get _initialImageSource => switch (widget.source) {
    PairedLivePhotoSource(:final image) => image,
    SingleFileLivePhotoSource(:final source) => source,
    BytesLivePhotoSource() => null,
  };

  @override
  void initState() {
    super.initState();
    _isMuted = widget.initiallyMuted;
    if (widget.controller != null) {
      _bindController(widget.controller!);
    }
    _resolveSource();
  }

  @override
  void didUpdateWidget(covariant LivePhotoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _unbindControllerEffects();
      if (oldWidget.controller == null) {
        _releaseInternalController();
      }
      if (widget.controller != null) {
        _bindController(widget.controller!);
      }
    }
    if (oldWidget.source != widget.source) {
      _stopPlayback(resetToStill: true);
      _resolveSource();
    } else if (oldWidget.playMode != widget.playMode) {
      _activeController?.setLooping(widget.playMode == LivePhotoPlayMode.loop);
      if (widget.playMode == LivePhotoPlayMode.loop ||
          widget.playMode == LivePhotoPlayMode.autoPlayOnce) {
        _startPlayback();
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _unbindControllerEffects();
    _releaseInternalController();
    super.dispose();
  }

  Future<void> _resolveSource() async {
    final gen = ++_loadGeneration;
    setState(() {
      _resolving = true;
      _resolveError = null;
    });

    try {
      var bundle = await LivePhotoExtractor.resolve(widget.source);
      if (!mounted || gen != _loadGeneration) return;

      // On non-Apple platforms (Android / Windows / Linux / Web), Flutter's
      // built-in Skia/Impeller image codec does not decode .heic / .avif still
      // covers directly. Extract a PNG cover frame from the motion video stream
      // so the still cover displays on all 6 platforms!
      final isApplePlatform = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (!isApplePlatform &&
          _isUnsupportedNonAppleImageMime(bundle.imageFile?.mimeType)) {
        final covers = await XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
          bundle.videoSource,
          count: 1,
          minBrightness: 0.0,
        );
        if (!mounted || gen != _loadGeneration) return;
        if (covers.isNotEmpty) {
          bundle = LivePhotoBundle(
            imageFile: covers.first.image,
            imageSource: kIsWeb
                ? VideoSource.network(covers.first.image.uri)
                : VideoSource.file(covers.first.image.path),
            videoSource: bundle.videoSource,
            nativeVideoUrl: bundle.nativeVideoUrl,
            metadata: bundle.metadata,
          );
        }
      }

      setState(() {
        _bundle = bundle;
        _resolving = false;
      });

      if (widget.playMode == LivePhotoPlayMode.autoPlayOnce ||
          widget.playMode == LivePhotoPlayMode.loop) {
        await _startPlayback();
      }
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _resolveError = e.toString();
        _resolving = false;
      });
    }
  }

  static bool _isUnsupportedNonAppleImageMime(String? mime) {
    if (mime == null) return false;
    final lower = mime.toLowerCase();
    return lower.contains('heic') || lower.contains('heif') || lower.contains('avif');
  }

  void _bindController(VideoPlayerController controller) {
    _unbindControllerEffects();
    _stateEffectDisposer = effect(() {
      final state = controller.playState.value;
      final muted = controller.muted.value;
      if (!mounted) return;

      if (_isMuted != muted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isMuted != muted) {
            setState(() => _isMuted = muted);
          }
        });
      }

      if (state == PlayState.playing && _wantsPlayback) {
        if (!_showingVideo) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_wantsPlayback) return;
            setState(() => _showingVideo = true);
            widget.onPlaybackStart?.call();
          });
        }
      } else if (state == PlayState.completed && widget.playMode != LivePhotoPlayMode.loop) {
        if (_showingVideo || _wantsPlayback) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _wantsPlayback = false;
              _showingVideo = false;
            });
            widget.onPlaybackComplete?.call();
          });
        }
      } else if (state == PlayState.error) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _wantsPlayback = false;
            _showingVideo = false;
            _resolveError = controller.errorMessage.value;
          });
        });
      }
    });
  }

  void _unbindControllerEffects() {
    _stateEffectDisposer?.call();
    _stateEffectDisposer = null;
  }

  Future<VideoPlayerController> _ensureControllerReady() async {
    final externalCtrl = widget.controller;
    if (externalCtrl != null) {
      return externalCtrl;
    }

    if (_internalController != null) {
      return _internalController!;
    }

    // Release any other LivePhotoPlayer holding the process-wide native session.
    if (_activeAutoSessionOwner != null && !identical(_activeAutoSessionOwner, this)) {
      _activeAutoSessionOwner!._preemptAutoSession();
    }

    final ctrl = VideoPlayerController();
    _internalController = ctrl;
    _activeAutoSessionOwner = this;
    _bindController(ctrl);
    await ctrl.initialize();
    return ctrl;
  }

  void _preemptAutoSession() {
    _wantsPlayback = false;
    _showingVideo = false;
    _unbindControllerEffects();
    final ctrl = _internalController;
    _internalController = null;
    if (identical(_activeAutoSessionOwner, this)) {
      _activeAutoSessionOwner = null;
    }
    if (ctrl != null) {
      unawaited(ctrl.dispose());
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _releaseInternalController() {
    final ctrl = _internalController;
    _internalController = null;
    if (identical(_activeAutoSessionOwner, this)) {
      _activeAutoSessionOwner = null;
    }
    if (ctrl != null) {
      unawaited(ctrl.dispose());
    }
  }

  Future<void> _startPlayback() async {
    final bundle = _bundle;
    if (bundle == null || !mounted) return;

    if (widget.enableHapticFeedback &&
        !_isDesktopOrWeb &&
        (widget.playMode == LivePhotoPlayMode.longPress ||
            widget.playMode == LivePhotoPlayMode.tap)) {
      HapticFeedback.lightImpact();
    }

    setState(() {
      _wantsPlayback = true;
    });

    try {
      final ctrl = await _ensureControllerReady();
      if (!mounted || !_wantsPlayback) return;

      await ctrl.setAspectRatioMode(_mapBoxFitToAspectRatioMode(widget.fit));
      await ctrl.setMuted(_isMuted);
      ctrl.setLooping(widget.playMode == LivePhotoPlayMode.loop);

      if (ctrl.currentUrl.value == widget.source.identity &&
          ctrl.playState.value != PlayState.idle &&
          ctrl.playState.value != PlayState.error) {
        await ctrl.seek(Duration.zero);
        if (!mounted || !_wantsPlayback) return;
        await ctrl.play();
      } else {
        await ctrl.playLivePhoto(
          widget.source,
          loop: widget.playMode == LivePhotoPlayMode.loop,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wantsPlayback = false;
        _showingVideo = false;
        _resolveError = e.toString();
      });
    }
  }

  Future<void> _stopPlayback({bool resetToStill = true}) async {
    final wasShowing = _showingVideo || _wantsPlayback;
    if (resetToStill && mounted) {
      setState(() {
        _wantsPlayback = false;
        _showingVideo = false;
      });
    } else {
      _wantsPlayback = false;
      _showingVideo = false;
    }
    final ctrl = _activeController;
    if (ctrl != null) {
      try {
        await ctrl.pause();
      } catch (_) {}
    }
    if (wasShowing) {
      widget.onPlaybackComplete?.call();
    }
  }

  Future<void> _toggleMute() async {
    final next = !_isMuted;
    setState(() => _isMuted = next);
    final ctrl = _activeController;
    if (ctrl != null) {
      await ctrl.setMuted(next);
    }
  }

  void _handleBadgeOrTapTrigger() {
    if (_wantsPlayback || _showingVideo) {
      if (widget.playMode != LivePhotoPlayMode.loop) {
        _stopPlayback(resetToStill: true);
        return;
      }
    }
    _startPlayback();
  }

  static AspectRatioMode _mapBoxFitToAspectRatioMode(BoxFit fit) {
    return switch (fit) {
      BoxFit.cover => AspectRatioMode.fill,
      BoxFit.fill => AspectRatioMode.stretch,
      _ => AspectRatioMode.fit,
    };
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTheme = widget.theme ?? VideoPlayerTheme.of(context);
    final bg = widget.backgroundColor ?? effectiveTheme.backgroundColor;
    final ctrl = _activeController;
    final scale = (widget.enableScaleEffect && _showingVideo) ? widget.activeScale : 1.0;
    final enableBadgeHover =
        widget.enableBadgeHoverOnDesktop &&
        _isDesktopOrWeb &&
        widget.playMode != LivePhotoPlayMode.loop;

    Widget content;
    if (_resolveError != null && _bundle == null) {
      content = ColoredBox(
        color: bg,
        child: Center(
          child: widget.errorBuilder != null
              ? widget.errorBuilder!(context, _resolveError)
              : Text(
                  _resolveError!,
                  style: TextStyle(color: effectiveTheme.foregroundColor, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
        ),
      );
    } else {
      content = ColoredBox(
        color: bg,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Animated scale wrapper containing both the still photo and video surface
            AnimatedScale(
              scale: scale,
              duration: widget.crossfadeDuration,
              curve: Curves.easeOutCubic,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Positioned.fill(
                    child: LivePhotoStillView(
                      bundle: _bundle,
                      fallbackImageSource: _initialImageSource,
                      fit: widget.fit,
                      placeholderBuilder: widget.placeholderBuilder,
                    ),
                  ),
                  if (ctrl != null)
                    Positioned.fill(
                      child: AnimatedOpacity(
                        key: const ValueKey<String>('live_photo_video_opacity'),
                        opacity: _showingVideo ? 1.0 : 0.0,
                        duration: widget.crossfadeDuration,
                        curve: Curves.easeInOut,
                        child: IgnorePointer(
                          child: CorePlayer(
                            controller: ctrl,
                            backgroundColor: Colors.transparent,
                            loadingBuilder: (_) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 2. Interactive gesture & desktop mouse hover layer
            Positioned.fill(
              child: MouseRegion(
                key: const ValueKey<String>('live_photo_mouse_region'),
                cursor: widget.playMode == LivePhotoPlayMode.tap ||
                        widget.playMode == LivePhotoPlayMode.hover
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                onEnter: widget.playMode == LivePhotoPlayMode.hover
                    ? (_) => _startPlayback()
                    : null,
                onExit: widget.playMode == LivePhotoPlayMode.hover
                    ? (_) => _stopPlayback(resetToStill: true)
                    : null,
                child: GestureDetector(
                  key: const ValueKey<String>('live_photo_gesture_detector'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.playMode == LivePhotoPlayMode.tap ? _handleBadgeOrTapTrigger : null,
                  onLongPressStart: (_) {
                    if (widget.playMode == LivePhotoPlayMode.longPress ||
                        widget.playMode == LivePhotoPlayMode.autoPlayOnce) {
                      _startPlayback();
                    }
                  },
                  onLongPressEnd: (_) {
                    if (widget.playMode == LivePhotoPlayMode.longPress) {
                      _stopPlayback(resetToStill: true);
                    }
                  },
                  onLongPressCancel: () {
                    if (widget.playMode == LivePhotoPlayMode.longPress) {
                      _stopPlayback(resetToStill: true);
                    }
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),

            // 3. Corner LIVE badge & mute button
            if (widget.showBadge)
              Positioned.fill(
                child: SafeArea(
                  minimum: widget.badgePadding,
                  child: Align(
                    alignment: widget.badgePosition.alignment,
                    child: widget.badgeBuilder != null
                        ? widget.badgeBuilder!(context, _showingVideo, _isMuted)
                        : LivePhotoBadge(
                            label: widget.badgeLabel,
                            isPlaying: _showingVideo,
                            isLoading: _resolving || (_wantsPlayback && !_showingVideo),
                            showMuteButton: widget.showMuteButton,
                            isMuted: _isMuted,
                            onTap: _handleBadgeOrTapTrigger,
                            onHoverStart: enableBadgeHover ? _startPlayback : null,
                            onHoverEnd: enableBadgeHover
                                ? () => _stopPlayback(resetToStill: true)
                                : null,
                            onToggleMute: _toggleMute,
                          ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    if (widget.aspectRatio != null) {
      content = AspectRatio(
        aspectRatio: widget.aspectRatio!,
        child: content,
      );
    }

    if (widget.theme != null) {
      final baseTheme = Theme.of(context);
      content = Theme(
        data: baseTheme.copyWith(
          extensions: [
            ...baseTheme.extensions.values.where((ext) => ext is! VideoPlayerTheme),
            effectiveTheme,
          ],
        ),
        child: content,
      );
    }

    return content;
  }
}
