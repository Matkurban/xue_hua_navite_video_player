import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/fullscreen_gesture_side_mapping.dart';
import '../data/enums/play_state.dart';
import '../data/enums/player_lock_button_position.dart';
import '../data/enums/skip_second_type.dart';
import '../orientation/player_orientation_controller.dart';
import '../player/video_player_controller.dart';
import 'player_gesture_hud_context.dart';
import 'style/video_player_theme.dart';
import 'video_player_slot_context.dart';
import 'widgets/player_body.dart';
import 'widgets/web_orientation_viewport.dart';

export 'player_gesture_hud_context.dart';
export 'video_player_slot_context.dart';

/// 高性能的开箱即用视频播放器组件（含顶栏、居中传输控制、双层缓冲进度条、全屏 Overlay、手势与锁屏）。
///
/// High-performance drop-in video player widget with top bar, center controls,
/// bottom buffered scrubber, visual fullscreen via [OverlayPortal], landscape
/// brightness/volume gestures, and screen lock.
class VideoPlayer extends StatefulWidget {
  /// 绑定的视频播放器控制器实例。
  ///
  /// Attached [VideoPlayerController] driving playback.
  final VideoPlayerController controller;

  /// 非全屏且 [fill] 为 `false` 时的固定宽高比；为 `null` 时按视频原始比例自适应（不低于 `16/9`）。
  ///
  /// Optional aspect ratio when inline and [fill] is `false`; defaults to the video's ratio (>= `16/9`).
  final double? aspectRatio;

  /// 是否直接铺满父容器尺寸（全屏 Overlay 中始终为 `true`）。
  ///
  /// Whether to expand to fill the parent constraints (always `true` in fullscreen Overlay).
  final bool fill;

  /// 播放中控件层自动隐藏的等待时长（设为 [Duration.zero] 禁用自动隐藏）。
  ///
  /// Delay before auto-hiding chrome while playing ([Duration.zero] disables auto-hide).
  final Duration autoHideDelay;

  /// 控件层显隐切换的淡入淡出动画时长。
  ///
  /// Fade duration for showing and hiding overlay chrome.
  final Duration fadeDuration;

  /// 初始渲染时控件层是否可见。
  ///
  /// Whether overlay controls are initially visible.
  final bool initiallyVisible;

  /// 非全屏模式下点击默认关闭按钮时的回调；为 `null` 时调用 `Navigator.maybePop()`。
  ///
  /// Callback invoked by the default close button when not fullscreen (defaults to `Navigator.maybePop`).
  final VoidCallback? onClose;

  /// 顶栏左侧自定义组件（默认显示关闭 / 退出全屏按钮）。
  ///
  /// AppBar-style leading widget (defaults to the close / exit-fullscreen button).
  final Widget? leading;

  /// 顶栏居中标题组件。
  ///
  /// AppBar-style centered title widget.
  final Widget? title;

  /// 顶栏右侧自定义操作组件列表（启用投屏与画面比例菜单时会自动追加在其后）。
  ///
  /// AppBar-style trailing actions (cast button and aspect-ratio menu append after when enabled).
  final List<Widget> actions;

  /// 兼容旧版的额外顶栏右侧操作组件，会合并在 [actions] 之后。
  ///
  /// Legacy extra trailing actions merged after [actions].
  final List<Widget> topBarActions;

  /// 当平台支持投屏时是否在默认顶栏展示无线投屏按钮。
  ///
  /// Whether to show the wireless cast button in the top bar when supported.
  final bool showCastButton;

  /// 是否在默认顶栏展示画面适应模式切换菜单（适应 / 铺满 / 拉伸）。
  ///
  /// Whether to display the aspect-ratio mode popup menu in the top bar.
  final bool showAspectRatioMenu;

  /// 是否在默认底栏展示全屏切换按钮。
  ///
  /// Whether to show the fullscreen toggle button in the bottom bar.
  final bool enableFullscreen;

  /// 全屏横屏播放时是否启用左右区域垂直滑动调节亮度与音量手势。
  ///
  /// Enables vertical brightness/volume drag gestures during fullscreen landscape playback.
  final bool enableFullscreenVerticalGestures;

  /// 控制全屏横屏播放时左右两侧分别调节亮度还是音量（默认左亮右音）。
  ///
  /// Configures which side controls screen brightness vs. audio volume in fullscreen landscape.
  final FullscreenGestureSideMapping verticalGestureMapping;

  /// 左侧垂直手势热区宽度占播放器总宽度的比例（`0.0..1.0`，默认 `0.3`，且左右宽度之和不可超过 `1.0`）。
  ///
  /// Width fraction (`0.0..1.0`) of the left vertical gesture area. Defaults to `0.3` (30%).
  /// Must satisfy `verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0`.
  final double verticalGestureLeftWidthRatio;

  /// 右侧垂直手势热区宽度占播放器总宽度的比例（`0.0..1.0`，默认 `0.3`，且左右宽度之和不可超过 `1.0`）。
  ///
  /// Width fraction (`0.0..1.0`) of the right vertical gesture area. Defaults to `0.3` (30%).
  /// Must satisfy `verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0`.
  final double verticalGestureRightWidthRatio;

  /// 垂直手势热区居中高度占播放器总高度的比例（`0.0..1.0`，默认 `0.7`）。
  ///
  /// Vertically centered height fraction (`0.0..1.0`) of the vertical gesture band. Defaults to `0.7` (70%).
  final double verticalGestureHeightRatio;

  /// 全屏模式下是否显示屏幕锁定/解锁按钮。
  ///
  /// Whether to display the screen lock/unlock button in fullscreen mode.
  final bool showLockButton;

  /// 全屏锁定/解锁按钮在屏幕左侧或右侧的摆放位置（默认左侧）。
  ///
  /// Horizontal edge (`left` or `right`) where the fullscreen lock/unlock button is positioned.
  final PlayerLockButtonPosition lockButtonPosition;

  /// 当前播放器实例的局部主题覆盖；为 `null` 时回退到 `VideoPlayerTheme.of(context)`。
  ///
  /// Optional theme override for this player instance. Falls back to `VideoPlayerTheme.of(context)`.
  final VideoPlayerTheme? theme;

  /// 播放出错时的自定义错误界面构建器（透传至 `CorePlayer`）。
  ///
  /// Custom error overlay builder forwarded to `CorePlayer`.
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;

  /// 加载或缓冲中的自定义指示器构建器（透传至 `CorePlayer`）。
  ///
  /// Custom loading/buffering indicator builder forwarded to `CorePlayer`.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// 完全替换默认顶栏的自定义构建器。
  ///
  /// Custom builder replacing the default top bar.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;

  /// 完全替换居中播放/快进/快退控制区的自定义构建器。
  ///
  /// Custom builder replacing the default center transport controls.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;

  /// 完全替换底部进度条与操作栏的自定义构建器。
  ///
  /// Custom builder replacing the default bottom scrubber bar.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;

  /// 完全替换投屏状态遮罩层的自定义构建器。
  ///
  /// Custom builder replacing the default casting status overlay.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? castingOverlayBuilder;

  /// 叠加在投屏遮罩之上的额外自定义浮层构建器（锁屏时自动隐藏）。
  ///
  /// Optional extra full-bleed overlay builder layered above the cast overlay (hidden while locked).
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;

  /// 全屏手势（亮度/音量/快进快退）实时中心指示器的完全自定义构建器；默认使用 `PlayerGestureHud`。
  ///
  /// Fully customizable center real-time indicator shown during brightness,
  /// volume, and seek gestures. Defaults to `PlayerGestureHud`.
  final Widget Function(BuildContext context, PlayerGestureHudContext hud)? gestureHudBuilder;

  /// 全屏锁定/解锁按钮的完全自定义构建器；默认使用 `PlayerLockButton`。
  ///
  /// Fully customizable fullscreen lock/unlock button widget. Defaults to `PlayerLockButton`.
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot, bool isLocked)?
  lockButtonBuilder;

  /// 初始快进/快退步进时长预设，会同步写入 `VideoPlayerController.skipSecondType`。
  ///
  /// Initial skip step preset synced with [VideoPlayerController.skipSecondType].
  final SkipSecondType skipSecondType;

  /// 创建完整功能的视频播放器组件。
  ///
  /// Creates a [VideoPlayer] widget with full chrome, gestures, and lock controls.
  const VideoPlayer({
    super.key,
    required this.controller,
    this.aspectRatio,
    this.fill = false,
    this.autoHideDelay = const Duration(seconds: 3),
    this.fadeDuration = const Duration(milliseconds: 250),
    this.initiallyVisible = true,
    this.onClose,
    this.leading,
    this.title,
    this.actions = const <Widget>[],
    this.topBarActions = const <Widget>[],
    this.showCastButton = true,
    this.showAspectRatioMenu = true,
    this.enableFullscreen = true,
    this.enableFullscreenVerticalGestures = true,
    this.verticalGestureMapping = FullscreenGestureSideMapping.leftBrightnessRightVolume,
    this.verticalGestureLeftWidthRatio = 0.3,
    this.verticalGestureRightWidthRatio = 0.3,
    this.verticalGestureHeightRatio = 0.7,
    this.showLockButton = true,
    this.lockButtonPosition = PlayerLockButtonPosition.left,
    this.theme,
    this.errorBuilder,
    this.loadingBuilder,
    this.topBarBuilder,
    this.centerControlsBuilder,
    this.bottomScrubberBuilder,
    this.castingOverlayBuilder,
    this.extraOverlayBuilder,
    this.gestureHudBuilder,
    this.lockButtonBuilder,
    this.skipSecondType = SkipSecondType.second10,
  }) : assert(
         verticalGestureLeftWidthRatio >= 0.0 && verticalGestureLeftWidthRatio <= 1.0,
         'verticalGestureLeftWidthRatio must be between 0.0 and 1.0.',
       ),
       assert(
         verticalGestureRightWidthRatio >= 0.0 && verticalGestureRightWidthRatio <= 1.0,
         'verticalGestureRightWidthRatio must be between 0.0 and 1.0.',
       ),
       assert(
         verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0,
         'verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio must not exceed 1.0.',
       ),
       assert(
         verticalGestureHeightRatio >= 0.0 && verticalGestureHeightRatio <= 1.0,
         'verticalGestureHeightRatio must be between 0.0 and 1.0.',
       );

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  late final FlutterSignal<bool> _visible = signal<bool>(widget.initiallyVisible);
  late final FlutterSignal<bool> _inlineSuppressed = signal<bool>(false);
  final FocusNode _focusNode = FocusNode();
  final OverlayPortalController _fullscreenPortal = OverlayPortalController();
  final GlobalKey _playerSurfaceKey = GlobalKey();

  Timer? _hideTimer;
  VoidCallback? _playingDisposer;
  VoidCallback? _bufferingDisposer;
  VoidCallback? _completedDisposer;
  VoidCallback? _castingDisposer;
  VoidCallback? _fullscreenDisposer;

  bool get _canAutoHide =>
      widget.controller.isPlaying.value &&
      !widget.controller.isBuffering.value &&
      !widget.controller.isCasting.value;

  bool get _isDesktop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.setSkipSecondType(widget.skipSecondType);
    _bindControllerEffects();
  }

  void _bindControllerEffects() {
    _disposeControllerEffects();

    _playingDisposer = effect(() {
      final bool playing = widget.controller.isPlaying.value;
      final bool buffering = widget.controller.isBuffering.value;
      if (playing && !buffering && _visible.value) {
        _scheduleAutoHide();
      } else if (!playing) {
        _hideTimer?.cancel();
      }
    });
    _bufferingDisposer = effect(() {
      final bool buffering = widget.controller.isBuffering.value;
      if (buffering) {
        _hideTimer?.cancel();
      } else if (widget.controller.isPlaying.value && _visible.value) {
        _scheduleAutoHide();
      }
    });
    _completedDisposer = effect(() {
      final PlayState state = widget.controller.playState.value;
      if (state == PlayState.completed) {
        _showControls(scheduleAutoHide: false);
      }
    });
    _castingDisposer = effect(() {
      final bool casting = widget.controller.isCasting.value;
      if (casting) {
        _showControls(scheduleAutoHide: false);
      } else if (widget.controller.isPlaying.value && _visible.value) {
        _scheduleAutoHide();
      }
    });
    _fullscreenDisposer = effect(() {
      final bool fs = widget.controller.isFullscreen.value;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) return;
        if (fs) {
          // Show overlay first so the GlobalKey'd surface moves in one build;
          // suppressing inline before show() would dispose the PlatformView.
          if (!_fullscreenPortal.isShowing) {
            final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
            if (overlay != null) {
              _fullscreenPortal.show();
            }
            if (_isDesktop) {
              _focusNode.requestFocus();
            }
          }
          if (_fullscreenPortal.isShowing && !_inlineSuppressed.value) {
            _inlineSuppressed.value = true;
          }
        } else {
          // Un-suppress before hide() so the surface stays mounted while moving.
          if (_inlineSuppressed.value) {
            _inlineSuppressed.value = false;
          }
          if (_fullscreenPortal.isShowing) {
            _fullscreenPortal.hide();
          }
        }
      });
    });
  }

  void _disposeControllerEffects() {
    _playingDisposer?.call();
    _playingDisposer = null;
    _bufferingDisposer?.call();
    _bufferingDisposer = null;
    _completedDisposer?.call();
    _completedDisposer = null;
    _castingDisposer?.call();
    _castingDisposer = null;
    _fullscreenDisposer?.call();
    _fullscreenDisposer = null;
  }

  @override
  void didUpdateWidget(covariant VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _hideTimer?.cancel();
      widget.controller.setSkipSecondType(widget.skipSecondType);
      _bindControllerEffects();
    } else if (oldWidget.skipSecondType != widget.skipSecondType) {
      widget.controller.setSkipSecondType(widget.skipSecondType);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _disposeControllerEffects();
    if (_fullscreenPortal.isShowing) {
      _fullscreenPortal.hide();
    }
    _visible.dispose();
    _inlineSuppressed.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showControls({bool scheduleAutoHide = true}) {
    _hideTimer?.cancel();
    if (!_visible.value) {
      _visible.value = true;
    }
    if (scheduleAutoHide) {
      _scheduleAutoHide();
    }
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (_visible.value) {
      _visible.value = false;
    }
    if (_isDesktop && _focusNode.hasFocus && !_focusNode.hasPrimaryFocus) {
      _focusNode.requestFocus();
    }
  }

  void _toggleControls() {
    if (_visible.value) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    if (widget.autoHideDelay == Duration.zero) return;
    if (!_canAutoHide) return;
    _hideTimer = Timer(widget.autoHideDelay, () {
      if (!mounted) return;
      if (_canAutoHide) {
        _hideControls();
      }
    });
  }

  void _handleClose() {
    if (widget.controller.isFullscreen.value) {
      if (widget.controller.isLocked.value) {
        return;
      }
      widget.controller.exitFullscreen();
      return;
    }
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerTheme effectiveTheme = widget.theme ?? VideoPlayerTheme.of(context);
    final VideoPlayerSlotContext slot = VideoPlayerSlotContext(
      controller: widget.controller,
      theme: effectiveTheme,
      showControls: _showControls,
      hideControls: _hideControls,
    );

    final ThemeData baseTheme = Theme.of(context);
    // Leave the list untyped. `<ThemeExtension<dynamic>>` normalizes to
    // `ThemeExtension<ThemeExtension<dynamic>>` because of the
    // `T extends ThemeExtension<T>` bound, so spreading
    // `baseTheme.extensions.values` fails to type-check.
    final ThemeData themedData = widget.theme != null
        ? baseTheme.copyWith(
            extensions: [
              ...baseTheme.extensions.values.where(
                (ThemeExtension<dynamic> ext) => ext is! VideoPlayerTheme,
              ),
              effectiveTheme,
            ],
          )
        : baseTheme;

    return Theme(
      data: themedData,
      child: OverlayPortal(
        controller: _fullscreenPortal,
        overlayChildBuilder: (BuildContext context) {
          final PlayerOrientationController? orientationCtrl =
              widget.controller.orientationController;
          final Widget fullscreenBody = PlayerBody(
            slot: slot,
            controller: widget.controller,
            surfaceKey: _playerSurfaceKey,
            aspectRatio: widget.aspectRatio,
            fill: true,
            fadeDuration: widget.fadeDuration,
            visible: _visible,
            isDesktop: _isDesktop,
            focusNode: _focusNode,
            leading: widget.leading,
            title: widget.title,
            actions: widget.actions,
            topBarActions: widget.topBarActions,
            showCastButton: widget.showCastButton,
            showAspectRatioMenu: widget.showAspectRatioMenu,
            enableFullscreen: widget.enableFullscreen,
            enableFullscreenVerticalGestures: widget.enableFullscreenVerticalGestures,
            verticalGestureMapping: widget.verticalGestureMapping,
            verticalGestureLeftWidthRatio: widget.verticalGestureLeftWidthRatio,
            verticalGestureRightWidthRatio: widget.verticalGestureRightWidthRatio,
            verticalGestureHeightRatio: widget.verticalGestureHeightRatio,
            showLockButton: widget.showLockButton,
            lockButtonPosition: widget.lockButtonPosition,
            errorBuilder: widget.errorBuilder,
            loadingBuilder: widget.loadingBuilder,
            topBarBuilder: widget.topBarBuilder,
            centerControlsBuilder: widget.centerControlsBuilder,
            bottomScrubberBuilder: widget.bottomScrubberBuilder,
            castingOverlayBuilder: widget.castingOverlayBuilder,
            extraOverlayBuilder: widget.extraOverlayBuilder,
            gestureHudBuilder: widget.gestureHudBuilder,
            lockButtonBuilder: widget.lockButtonBuilder,
            onClose: _handleClose,
            onToggleControls: _toggleControls,
            onShowControls: _showControls,
            onHideControls: _hideControls,
            onCancelHideTimer: () => _hideTimer?.cancel(),
            onScheduleAutoHide: _scheduleAutoHide,
          );
          return Theme(
            data: themedData,
            child: Material(
              color: slot.theme.backgroundColor,
              child: orientationCtrl != null
                  ? WebOrientationViewport(
                      controller: orientationCtrl,
                      child: fullscreenBody,
                    )
                  : fullscreenBody,
            ),
          );
        },
        child: SignalBuilder(
          builder: (BuildContext context) {
            final bool fs = widget.controller.isFullscreen.value;
            if (_inlineSuppressed.value || _fullscreenPortal.isShowing) {
              return const SizedBox.shrink();
            }
            return PlayerBody(
              slot: slot,
              controller: widget.controller,
              surfaceKey: _playerSurfaceKey,
              aspectRatio: widget.aspectRatio,
              fill: widget.fill || fs,
              fadeDuration: widget.fadeDuration,
              visible: _visible,
              isDesktop: _isDesktop,
              focusNode: _focusNode,
              leading: widget.leading,
              title: widget.title,
              actions: widget.actions,
              topBarActions: widget.topBarActions,
              showCastButton: widget.showCastButton,
              showAspectRatioMenu: widget.showAspectRatioMenu,
              enableFullscreen: widget.enableFullscreen,
              enableFullscreenVerticalGestures: widget.enableFullscreenVerticalGestures,
              verticalGestureMapping: widget.verticalGestureMapping,
              verticalGestureLeftWidthRatio: widget.verticalGestureLeftWidthRatio,
              verticalGestureRightWidthRatio: widget.verticalGestureRightWidthRatio,
              verticalGestureHeightRatio: widget.verticalGestureHeightRatio,
              showLockButton: widget.showLockButton,
              lockButtonPosition: widget.lockButtonPosition,
              errorBuilder: widget.errorBuilder,
              loadingBuilder: widget.loadingBuilder,
              topBarBuilder: widget.topBarBuilder,
              centerControlsBuilder: widget.centerControlsBuilder,
              bottomScrubberBuilder: widget.bottomScrubberBuilder,
              castingOverlayBuilder: widget.castingOverlayBuilder,
              extraOverlayBuilder: widget.extraOverlayBuilder,
              gestureHudBuilder: widget.gestureHudBuilder,
              lockButtonBuilder: widget.lockButtonBuilder,
              onClose: _handleClose,
              onToggleControls: _toggleControls,
              onShowControls: _showControls,
              onHideControls: _hideControls,
              onCancelHideTimer: () => _hideTimer?.cancel(),
              onScheduleAutoHide: _scheduleAutoHide,
            );
          },
        ),
      ),
    );
  }
}
