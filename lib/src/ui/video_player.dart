import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/fullscreen_gesture_side_mapping.dart';
import '../data/enums/play_state.dart';
import '../data/enums/player_lock_button_position.dart';
import '../data/enums/skip_second_type.dart';
import '../player/video_player_controller.dart';
import 'player_gesture_hud_context.dart';
import 'style/video_player_theme.dart';
import 'video_player_slot_context.dart';
import 'widgets/player_body.dart';

export 'player_gesture_hud_context.dart';
export 'video_player_slot_context.dart';

/// 高性能的默认视频播放器组件。
///
/// Hosts visual fullscreen via [OverlayPortal]. Entering fullscreen reparents
/// the in-tree surface into the overlay host in the same frame (via [GlobalKey])
/// so Android PlatformViews are not disposed and immediately resized.
/// Controller-only fullscreen without this widget still applies orientation /
/// window / browser fullscreen, without Overlay chrome.
class VideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final double? aspectRatio;
  final bool fill;
  final Duration autoHideDelay;
  final Duration fadeDuration;
  final bool initiallyVisible;
  final VoidCallback? onClose;

  /// AppBar-style leading (defaults to close button).
  final Widget? leading;

  /// AppBar-style centered title.
  final Widget? title;

  /// AppBar-style trailing actions (aspect-ratio menu appended when enabled).
  final List<Widget> actions;

  /// Legacy extra actions merged into [actions].
  final List<Widget> topBarActions;

  /// Whether to show the wireless cast button in the top bar when supported.
  final bool showCastButton;

  final bool showAspectRatioMenu;
  final bool enableFullscreen;

  /// Enables vertical brightness/volume drag gestures in fullscreen landscape playback.
  final bool enableFullscreenVerticalGestures;

  /// Configures which side controls screen brightness vs. audio volume in fullscreen landscape.
  final FullscreenGestureSideMapping verticalGestureMapping;

  /// Width fraction (`0.0..1.0`) of the left vertical gesture area. Defaults to `0.3` (30%).
  ///
  /// Must satisfy `verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0`.
  final double verticalGestureLeftWidthRatio;

  /// Width fraction (`0.0..1.0`) of the right vertical gesture area. Defaults to `0.3` (30%).
  ///
  /// Must satisfy `verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0`.
  final double verticalGestureRightWidthRatio;

  /// Vertically centered height fraction (`0.0..1.0`) of the vertical gesture band. Defaults to `0.7` (70%).
  final double verticalGestureHeightRatio;

  /// Whether to display the screen lock/unlock button in fullscreen mode.
  final bool showLockButton;

  /// Horizontal edge (`left` or `right`) where the fullscreen lock/unlock button is positioned.
  final PlayerLockButtonPosition lockButtonPosition;

  /// Optional theme override for this player instance. Falls back to
  /// `VideoPlayerTheme.of(context)` when null.
  final VideoPlayerTheme? theme;

  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? castingOverlayBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;

  /// Fully customizable center real-time indicator shown during brightness,
  /// volume, and seek gestures. Defaults to [PlayerGestureHud].
  final Widget Function(BuildContext context, PlayerGestureHudContext hud)? gestureHudBuilder;

  /// Fully customizable fullscreen lock/unlock button widget. Defaults to [PlayerLockButton].
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot, bool isLocked)?
  lockButtonBuilder;

  /// Initial skip step; synced with [VideoPlayerController.skipSecondType].
  final SkipSecondType skipSecondType;

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
        overlayChildBuilder: (BuildContext context) => Theme(
          data: themedData,
          child: Material(
            color: slot.theme.backgroundColor,
            child: PlayerBody(
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
            ),
          ),
        ),
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
