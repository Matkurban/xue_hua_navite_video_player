import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';
import 'video_player_slot_context.dart';
import 'widgets/player_body.dart';

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
    this.theme,
    this.errorBuilder,
    this.loadingBuilder,
    this.topBarBuilder,
    this.centerControlsBuilder,
    this.bottomScrubberBuilder,
    this.castingOverlayBuilder,
    this.extraOverlayBuilder,
    this.skipSecondType = SkipSecondType.second10,
  });

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  late final FlutterSignal<bool> _visible = signal(widget.initiallyVisible);
  final FocusNode _focusNode = FocusNode();
  final OverlayPortalController _fullscreenPortal = OverlayPortalController();
  final GlobalKey _playerSurfaceKey = GlobalKey();

  /// When true, in-tree [PlayerBody] is omitted so overlay can host alone.
  bool _inlineSuppressed = false;

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

    _playingDisposer = effect(() {
      final playing = widget.controller.isPlaying.value;
      final buffering = widget.controller.isBuffering.value;
      if (playing && !buffering && _visible.value) {
        _scheduleAutoHide();
      } else if (!playing) {
        _hideTimer?.cancel();
      }
    });
    _bufferingDisposer = effect(() {
      final buffering = widget.controller.isBuffering.value;
      if (buffering) {
        _showControls(scheduleAutoHide: false);
      } else if (widget.controller.isPlaying.value && _visible.value) {
        _scheduleAutoHide();
      }
    });
    _completedDisposer = effect(() {
      final state = widget.controller.playState.value;
      if (state == PlayState.completed) {
        _showControls(scheduleAutoHide: false);
      }
    });
    _castingDisposer = effect(() {
      final casting = widget.controller.isCasting.value;
      if (casting) {
        _showControls(scheduleAutoHide: false);
      } else if (widget.controller.isPlaying.value && _visible.value) {
        _scheduleAutoHide();
      }
    });
    _fullscreenDisposer = effect(() {
      final fs = widget.controller.isFullscreen.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (fs) {
          // Show overlay first so the GlobalKey'd surface moves in one build;
          // suppressing inline before show() would dispose the PlatformView.
          if (!_fullscreenPortal.isShowing) {
            final overlay = Overlay.maybeOf(context, rootOverlay: true);
            if (overlay != null) {
              _fullscreenPortal.show();
            }
            if (_isDesktop) {
              _focusNode.requestFocus();
            }
          }
          if (_fullscreenPortal.isShowing && !_inlineSuppressed) {
            setState(() => _inlineSuppressed = true);
          }
        } else {
          // Un-suppress before hide() so the surface stays mounted while moving.
          if (_inlineSuppressed) {
            setState(() => _inlineSuppressed = false);
          }
          if (_fullscreenPortal.isShowing) {
            _fullscreenPortal.hide();
          }
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skipSecondType != widget.skipSecondType) {
      widget.controller.setSkipSecondType(widget.skipSecondType);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingDisposer?.call();
    _bufferingDisposer?.call();
    _completedDisposer?.call();
    _castingDisposer?.call();
    _fullscreenDisposer?.call();
    if (_fullscreenPortal.isShowing) {
      _fullscreenPortal.hide();
    }
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
    final effectiveTheme = widget.theme ?? VideoPlayerTheme.of(context);
    final slot = VideoPlayerSlotContext(
      controller: widget.controller,
      theme: effectiveTheme,
      showControls: _showControls,
      hideControls: _hideControls,
    );

    final baseTheme = Theme.of(context);
    final themedData = widget.theme != null
        ? baseTheme.copyWith(
            extensions: <ThemeExtension<dynamic>>[
              ...baseTheme.extensions.values.where((ext) => ext is! VideoPlayerTheme),
              effectiveTheme,
            ],
          )
        : baseTheme;

    return Theme(
      data: themedData,
      child: OverlayPortal(
        controller: _fullscreenPortal,
        overlayChildBuilder: (context) => Theme(
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
              errorBuilder: widget.errorBuilder,
              loadingBuilder: widget.loadingBuilder,
              topBarBuilder: widget.topBarBuilder,
              centerControlsBuilder: widget.centerControlsBuilder,
              bottomScrubberBuilder: widget.bottomScrubberBuilder,
              castingOverlayBuilder: widget.castingOverlayBuilder,
              extraOverlayBuilder: widget.extraOverlayBuilder,
              onClose: _handleClose,
              onToggleControls: _toggleControls,
              onShowControls: _showControls,
              onCancelHideTimer: () => _hideTimer?.cancel(),
              onScheduleAutoHide: _scheduleAutoHide,
            ),
          ),
        ),
        child: SignalBuilder(
          builder: (context) {
            widget.controller.isFullscreen.value;
            if (_inlineSuppressed || _fullscreenPortal.isShowing) {
              return const SizedBox.shrink();
            }
            final fs = widget.controller.isFullscreen.value;
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
              errorBuilder: widget.errorBuilder,
              loadingBuilder: widget.loadingBuilder,
              topBarBuilder: widget.topBarBuilder,
              centerControlsBuilder: widget.centerControlsBuilder,
              bottomScrubberBuilder: widget.bottomScrubberBuilder,
              castingOverlayBuilder: widget.castingOverlayBuilder,
              extraOverlayBuilder: widget.extraOverlayBuilder,
              onClose: _handleClose,
              onToggleControls: _toggleControls,
              onShowControls: _showControls,
              onCancelHideTimer: () => _hideTimer?.cancel(),
              onScheduleAutoHide: _scheduleAutoHide,
            );
          },
        ),
      ),
    );
  }
}
