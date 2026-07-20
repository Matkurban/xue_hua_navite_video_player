import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/aspect_ratio_mode.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/skip_second_type.dart';
import 'package:xue_hua_navite_video_player/src/ui/core_player.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_gesture_layer.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_menu_button.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/play_state.dart';
import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';
import 'widgets/player_scrubber_slider.dart';

/// 传递给自定义槽位 builder 的上下文。
class VideoPlayerSlotContext {
  final VideoPlayerController controller;
  final VideoPlayerTheme theme;
  final VoidCallback showControls;
  final VoidCallback hideControls;

  const VideoPlayerSlotContext({
    required this.controller,
    required this.theme,
    required this.showControls,
    required this.hideControls,
  });
}

/// 高性能的默认视频播放器组件。
///
/// Hosts visual fullscreen via [OverlayPortal]. Entering fullscreen suppresses
/// the in-tree surface then shows the overlay host (PlatformView may remount).
/// Controller-only fullscreen without this widget still applies orientation /
/// immersive UI.
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

  final bool showAspectRatioMenu;
  final bool enableFullscreen;

  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;
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
    this.showAspectRatioMenu = true,
    this.enableFullscreen = true,
    this.errorBuilder,
    this.loadingBuilder,
    this.topBarBuilder,
    this.centerControlsBuilder,
    this.bottomScrubberBuilder,
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

  /// When true, in-tree [_PlayerBody] is omitted so overlay can host alone.
  bool _inlineSuppressed = false;

  Timer? _hideTimer;
  VoidCallback? _playingDisposer;
  VoidCallback? _bufferingDisposer;
  VoidCallback? _completedDisposer;
  VoidCallback? _fullscreenDisposer;

  bool get _canAutoHide =>
      widget.controller.isPlaying.value && !widget.controller.isBuffering.value;

  bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  bool get _isDesktop {
    if (kIsWeb) return true;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
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
    _fullscreenDisposer = effect(() {
      final fs = widget.controller.isFullscreen.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (fs) {
          if (!_inlineSuppressed) {
            setState(() => _inlineSuppressed = true);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !widget.controller.isFullscreen.value) return;
            if (!_fullscreenPortal.isShowing) {
              final overlay = Overlay.maybeOf(context, rootOverlay: true);
              if (overlay != null) {
                _fullscreenPortal.show();
              }
              if (_isDesktop) {
                _focusNode.requestFocus();
              }
              setState(() {});
            }
          });
        } else {
          if (_fullscreenPortal.isShowing) {
            _fullscreenPortal.hide();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || widget.controller.isFullscreen.value) return;
            if (_inlineSuppressed) {
              setState(() => _inlineSuppressed = false);
            }
          });
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

  VideoPlayerSlotContext _slotContext() {
    return VideoPlayerSlotContext(
      controller: widget.controller,
      theme: VideoPlayerTheme.of(context),
      showControls: _showControls,
      hideControls: _hideControls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slotContext();
    return OverlayPortal(
      controller: _fullscreenPortal,
      overlayChildBuilder: (context) => Material(
        color: slot.theme.backgroundColor,
        child: _PlayerBody(
          slot: slot,
          controller: widget.controller,
          aspectRatio: widget.aspectRatio,
          fill: true,
          fadeDuration: widget.fadeDuration,
          visible: _visible,
          isMobile: _isMobile,
          isDesktop: _isDesktop,
          focusNode: _focusNode,
          leading: widget.leading,
          title: widget.title,
          actions: widget.actions,
          topBarActions: widget.topBarActions,
          showAspectRatioMenu: widget.showAspectRatioMenu,
          enableFullscreen: widget.enableFullscreen,
          errorBuilder: widget.errorBuilder,
          loadingBuilder: widget.loadingBuilder,
          topBarBuilder: widget.topBarBuilder,
          centerControlsBuilder: widget.centerControlsBuilder,
          bottomScrubberBuilder: widget.bottomScrubberBuilder,
          extraOverlayBuilder: widget.extraOverlayBuilder,
          onClose: _handleClose,
          onToggleControls: _toggleControls,
          onShowControls: _showControls,
          onCancelHideTimer: () => _hideTimer?.cancel(),
          onScheduleAutoHide: _scheduleAutoHide,
        ),
      ),
      child: SignalBuilder(
        builder: (context) {
          widget.controller.isFullscreen.value;
          if (_inlineSuppressed || _fullscreenPortal.isShowing) {
            return const SizedBox.shrink();
          }
          final fs = widget.controller.isFullscreen.value;
          return _PlayerBody(
            slot: slot,
            controller: widget.controller,
            aspectRatio: widget.aspectRatio,
            fill: widget.fill || fs,
            fadeDuration: widget.fadeDuration,
            visible: _visible,
            isMobile: _isMobile,
            isDesktop: _isDesktop,
            focusNode: _focusNode,
            leading: widget.leading,
            title: widget.title,
            actions: widget.actions,
            topBarActions: widget.topBarActions,
            showAspectRatioMenu: widget.showAspectRatioMenu,
            enableFullscreen: widget.enableFullscreen,
            errorBuilder: widget.errorBuilder,
            loadingBuilder: widget.loadingBuilder,
            topBarBuilder: widget.topBarBuilder,
            centerControlsBuilder: widget.centerControlsBuilder,
            bottomScrubberBuilder: widget.bottomScrubberBuilder,
            extraOverlayBuilder: widget.extraOverlayBuilder,
            onClose: _handleClose,
            onToggleControls: _toggleControls,
            onShowControls: _showControls,
            onCancelHideTimer: () => _hideTimer?.cancel(),
            onScheduleAutoHide: _scheduleAutoHide,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player body (inline + fullscreen overlay)
// ---------------------------------------------------------------------------

class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    required this.slot,
    required this.controller,
    required this.aspectRatio,
    required this.fill,
    required this.fadeDuration,
    required this.visible,
    required this.isMobile,
    required this.isDesktop,
    required this.focusNode,
    required this.leading,
    required this.title,
    required this.actions,
    required this.topBarActions,
    required this.showAspectRatioMenu,
    required this.enableFullscreen,
    required this.errorBuilder,
    required this.loadingBuilder,
    required this.topBarBuilder,
    required this.centerControlsBuilder,
    required this.bottomScrubberBuilder,
    required this.extraOverlayBuilder,
    required this.onClose,
    required this.onToggleControls,
    required this.onShowControls,
    required this.onCancelHideTimer,
    required this.onScheduleAutoHide,
  });

  final VideoPlayerSlotContext slot;
  final VideoPlayerController controller;
  final double? aspectRatio;
  final bool fill;
  final Duration fadeDuration;
  final FlutterSignal<bool> visible;
  final bool isMobile;
  final bool isDesktop;
  final FocusNode focusNode;
  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final List<Widget> topBarActions;
  final bool showAspectRatioMenu;
  final bool enableFullscreen;
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;
  final VoidCallback onClose;
  final VoidCallback onToggleControls;
  final VoidCallback onShowControls;
  final VoidCallback onCancelHideTimer;
  final VoidCallback onScheduleAutoHide;

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final isFullscreen = controller.isFullscreen.value;

    Widget stack = ColoredBox(
      color: style.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: CorePlayer(
              controller: controller,
              aspectRatio: aspectRatio,
              backgroundColor: style.backgroundColor,
              errorBuilder: errorBuilder,
              loadingBuilder: loadingBuilder,
            ),
          ),
          Positioned.fill(
            child: isFullscreen && isMobile
                ? PlayerGestureLayer(
                    controller: controller,
                    onTap: onToggleControls,
                    child: const SizedBox.expand(),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (isDesktop) {
                        focusNode.requestFocus();
                      }
                      onToggleControls();
                    },
                    child: const SizedBox.expand(),
                  ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: fadeDuration,
                child: SignalBuilder(
                  builder: (context) {
                    if (!visible.value) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.max,
                      children: <Widget>[
                        topBarBuilder?.call(context, slot) ??
                            _DefaultTopBar(
                              slot: slot,
                              leading: leading,
                              title: title,
                              actions: actions,
                              topBarActions: topBarActions,
                              showAspectRatioMenu: showAspectRatioMenu,
                              onClose: onClose,
                              onShowControls: onShowControls,
                            ),
                        Expanded(
                          child: Center(
                            child:
                                centerControlsBuilder?.call(context, slot) ??
                                _DefaultCenterControls(slot: slot, onInteract: onShowControls),
                          ),
                        ),
                        bottomScrubberBuilder?.call(context, slot) ??
                            _DefaultBottomScrubber(
                              slot: slot,
                              enableFullscreen: enableFullscreen,
                              onInteractStart: onCancelHideTimer,
                              onInteractEnd: onScheduleAutoHide,
                              onInteract: onShowControls,
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (extraOverlayBuilder != null)
            Positioned.fill(child: extraOverlayBuilder!(context, slot)),
        ],
      ),
    );

    if (isDesktop) {
      stack = Focus(
        focusNode: focusNode,
        autofocus: isFullscreen,
        onKeyEvent: (node, event) => handlePlayerKeyEvent(controller, event),
        child: stack,
      );
    }

    if (fill || isFullscreen) {
      return stack;
    }

    return SignalBuilder(
      builder: (context) {
        final double effectiveAspectRatio;
        if (aspectRatio != null) {
          effectiveAspectRatio = aspectRatio!;
        } else {
          final reported = controller.videoAspectRatio.value;
          const double minInlineAspect = 16 / 9;
          if (reported > 0) {
            effectiveAspectRatio = reported >= minInlineAspect ? reported : minInlineAspect;
          } else {
            effectiveAspectRatio = minInlineAspect;
          }
        }
        return AspectRatio(aspectRatio: effectiveAspectRatio, child: stack);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Default top bar
// ---------------------------------------------------------------------------

class _DefaultTopBar extends StatelessWidget {
  const _DefaultTopBar({
    required this.slot,
    required this.leading,
    required this.title,
    required this.actions,
    required this.topBarActions,
    required this.showAspectRatioMenu,
    required this.onClose,
    required this.onShowControls,
  });

  final VideoPlayerSlotContext slot;
  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final List<Widget> topBarActions;
  final bool showAspectRatioMenu;
  final VoidCallback onClose;
  final VoidCallback onShowControls;

  static String _aspectLabel(AspectRatioMode mode) => switch (mode) {
    AspectRatioMode.fit => '适应',
    AspectRatioMode.fill => '铺满',
    AspectRatioMode.stretch => '拉伸',
  };

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;
    final trailing = <Widget>[
      ...actions,
      ...topBarActions,
      if (showAspectRatioMenu)
        PlayerMenuButton(
          icon: Icons.aspect_ratio,
          color: style.foregroundColor,
          tooltip: '画面模式',
          menuBuilder: (context, hideMenu) {
            return SignalBuilder(
              builder: (context) {
                final current = controller.aspectRatioMode.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final mode in AspectRatioMode.values)
                      ListTile(
                        dense: true,
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_aspectLabel(mode)),
                            if (current == mode) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check,
                                size: style.menuIconSize,
                                color: style.foregroundColor,
                              ),
                            ],
                          ],
                        ),
                        onTap: () {
                          controller.setAspectRatioMode(mode);
                          hideMenu();
                          onShowControls();
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
    ];

    return Padding(
      padding: style.topBarPadding,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  leading ??
                  IconButton(
                    onPressed: onClose,
                    color: style.foregroundColor,
                    icon: Icon(controller.isFullscreen.value ? Icons.fullscreen_exit : Icons.close),
                  ),
            ),
          ),
          Expanded(flex: 2, child: Center(child: title ?? const SizedBox.shrink())),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: trailing.isEmpty
                  ? const SizedBox.shrink()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Center controls
// ---------------------------------------------------------------------------

class _DefaultCenterControls extends StatelessWidget {
  final VideoPlayerSlotContext slot;
  final VoidCallback onInteract;

  const _DefaultCenterControls({required this.slot, required this.onInteract});

  IconData _skipBackwardIcon(SkipSecondType seconds) {
    switch (seconds) {
      case SkipSecondType.second5:
        return CupertinoIcons.gobackward;
      case SkipSecondType.second10:
        return CupertinoIcons.gobackward_10;
      case SkipSecondType.second15:
        return CupertinoIcons.gobackward_15;
      case SkipSecondType.second30:
        return CupertinoIcons.gobackward_30;
      case SkipSecondType.second45:
        return CupertinoIcons.gobackward_45;
      case SkipSecondType.second60:
        return CupertinoIcons.gobackward_60;
    }
  }

  IconData _skipForwardIcon(SkipSecondType seconds) {
    switch (seconds) {
      case SkipSecondType.second5:
        return CupertinoIcons.goforward;
      case SkipSecondType.second10:
        return CupertinoIcons.goforward_10;
      case SkipSecondType.second15:
        return CupertinoIcons.goforward_15;
      case SkipSecondType.second30:
        return CupertinoIcons.goforward_30;
      case SkipSecondType.second45:
        return CupertinoIcons.goforward_45;
      case SkipSecondType.second60:
        return CupertinoIcons.goforward_60;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;

    return SignalBuilder(
      builder: (context) {
        final state = controller.playState.value;
        final buffering = controller.isBuffering.value;
        final isPlaying = state == PlayState.playing;
        final isCompleted = state == PlayState.completed;
        final canInteract = state != PlayState.loading && state != PlayState.error;
        final skip = controller.skipSecondType.value;

        Widget centerButton;
        if (state == PlayState.loading || buffering) {
          centerButton = SizedBox(child: CupertinoActivityIndicator(color: style.foregroundColor));
        } else if (isCompleted) {
          centerButton = IconButton(
            icon: Icon(CupertinoIcons.arrow_counterclockwise, size: style.centerPlayButtonIconSize),
            color: style.foregroundColor,
            style: IconButton.styleFrom(backgroundColor: style.centerButtonBackgroundColor),
            onPressed: () async {
              await controller.play();
              onInteract();
            },
          );
        } else {
          centerButton = IconButton(
            icon: Icon(
              isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              size: style.centerPlayButtonIconSize,
            ),
            color: style.foregroundColor,
            style: IconButton.styleFrom(backgroundColor: style.centerButtonBackgroundColor),
            onPressed: canInteract
                ? () {
                    controller.playOrPause();
                    onInteract();
                  }
                : null,
          );
        }

        return Row(
          spacing: style.centerControlsSpacing,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            IconButton(
              icon: Icon(_skipBackwardIcon(skip), size: style.centerSkipButtonIconSize),
              color: style.foregroundColor,
              style: IconButton.styleFrom(backgroundColor: style.centerButtonBackgroundColor),
              onPressed: canInteract
                  ? () async {
                      await controller.seekBackward();
                      onInteract();
                    }
                  : null,
            ),
            centerButton,
            IconButton(
              icon: Icon(_skipForwardIcon(skip), size: style.centerSkipButtonIconSize),
              color: style.foregroundColor,
              style: IconButton.styleFrom(backgroundColor: style.centerButtonBackgroundColor),
              onPressed: canInteract
                  ? () async {
                      await controller.seekForward();
                      onInteract();
                    }
                  : null,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom scrubber
// ---------------------------------------------------------------------------

class _DefaultBottomScrubber extends StatefulWidget {
  final VideoPlayerSlotContext slot;
  final VoidCallback onInteractStart;
  final VoidCallback onInteractEnd;
  final VoidCallback onInteract;
  final bool enableFullscreen;

  const _DefaultBottomScrubber({
    required this.slot,
    required this.onInteractStart,
    required this.onInteractEnd,
    required this.onInteract,
    required this.enableFullscreen,
  });

  @override
  State<_DefaultBottomScrubber> createState() => _DefaultBottomScrubberState();
}

class _DefaultBottomScrubberState extends State<_DefaultBottomScrubber> {
  final FlutterSignal<double?> _dragValue = signal(null);

  String _formatDuration(Duration duration, {bool negative = false}) {
    if (duration.isNegative) duration = Duration.zero;
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    final body = hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
    return negative ? '-$body' : body;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.slot.theme;
    final controller = widget.slot.controller;

    return Padding(
      padding: style.bottomBarPadding,
      child: SignalBuilder(
        builder: (context) {
          final position = controller.position.value;
          final duration = controller.duration.value;
          final hasDuration = duration.inMilliseconds > 0;
          final progress = hasDuration
              ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
              : 0.0;
          final effectiveValue = _dragValue.value ?? progress;
          final previewDuration = Duration(
            milliseconds: (duration.inMilliseconds * effectiveValue).round(),
          );
          final remaining = hasDuration ? (duration - previewDuration) : Duration.zero;
          final muted = controller.muted.value || controller.volume.value == 0;
          final speed = controller.speed.value;
          final fullscreen = controller.isFullscreen.value;
          const speeds = <double>[0.5, 1.0, 1.25, 1.5, 2.0];

          return Row(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () {
                  controller.toggleMuted();
                  widget.onInteract();
                },
                color: style.foregroundColor,
                icon: Icon(muted ? Icons.volume_off : Icons.volume_up, size: style.chromeIconSize),
              ),
              Text(_formatDuration(previewDuration), style: style.timeTextStyle),
              Expanded(
                child: PlayerScrubberSlider(
                  value: effectiveValue,
                  activeColor: style.scrubberActiveColor,
                  bufferedColor: style.scrubberBufferedColor,
                  inactiveColor: style.scrubberInactiveColor,
                  thumbColor: style.scrubberThumbColor,
                  thumbShadowColor: style.scrubberThumbShadowColor,
                  trackHeight: style.scrubberTrackHeight,
                  activeTrackHeight: style.scrubberActiveTrackHeight,
                  thumbRadius: style.scrubberThumbRadius,
                  activeThumbRadius: style.scrubberActiveThumbRadius,
                  onChangeStart: hasDuration
                      ? (v) {
                          _dragValue.value = v;
                          widget.onInteractStart();
                        }
                      : null,
                  onChanged: hasDuration
                      ? (v) {
                          _dragValue.value = v;
                        }
                      : null,
                  onChangeEnd: hasDuration
                      ? (v) {
                          final target = Duration(
                            milliseconds: (duration.inMilliseconds * v).round(),
                          );
                          controller.seek(target);
                          _dragValue.value = null;
                          widget.onInteractEnd();
                        }
                      : null,
                ),
              ),
              Text(_formatDuration(remaining, negative: true), style: style.timeTextStyle),
              PlayerMenuButton(
                icon: Icons.speed,
                color: style.foregroundColor,
                tooltip: '倍速',
                menuBuilder: (context, hideMenu) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in speeds)
                        ListTile(
                          dense: true,
                          title: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${s}x'),
                              if ((s - speed).abs() < 0.01) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check,
                                  size: style.menuIconSize,
                                  color: style.foregroundColor,
                                ),
                              ],
                            ],
                          ),
                          onTap: () {
                            controller.setSpeed(s);
                            hideMenu();
                            widget.onInteract();
                          },
                        ),
                    ],
                  );
                },
              ),
              if (widget.enableFullscreen)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () {
                    controller.toggleFullscreen();
                    widget.onInteract();
                  },
                  color: style.foregroundColor,
                  icon: Icon(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    size: style.chromeIconSize,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
