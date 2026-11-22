import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/enums/fullscreen_gesture_side_mapping.dart';
import '../../data/enums/player_lock_button_position.dart';
import '../../player/video_player_controller.dart';
import '../core_player.dart';
import '../style/video_player_theme.dart';
import '../video_player_slot_context.dart';
import 'player_bottom_scrubber.dart';
import 'player_casting_overlay.dart';
import 'player_center_controls.dart';
import 'player_gesture_layer.dart';
import 'player_lock_button.dart';
import 'player_top_bar.dart';

/// Shared player body used both inline and inside the fullscreen [OverlayPortal].
class PlayerBody extends StatelessWidget {
  const PlayerBody({
    super.key,
    required this.slot,
    required this.controller,
    required this.surfaceKey,
    required this.aspectRatio,
    required this.fill,
    required this.fadeDuration,
    required this.visible,
    required this.isDesktop,
    required this.focusNode,
    required this.leading,
    required this.title,
    required this.actions,
    required this.topBarActions,
    required this.showCastButton,
    required this.showAspectRatioMenu,
    required this.enableFullscreen,
    required this.enableFullscreenVerticalGestures,
    required this.verticalGestureMapping,
    required this.verticalGestureLeftWidthRatio,
    required this.verticalGestureRightWidthRatio,
    required this.verticalGestureHeightRatio,
    required this.showLockButton,
    required this.lockButtonPosition,
    required this.errorBuilder,
    required this.loadingBuilder,
    required this.topBarBuilder,
    required this.centerControlsBuilder,
    required this.bottomScrubberBuilder,
    required this.castingOverlayBuilder,
    required this.extraOverlayBuilder,
    required this.gestureHudBuilder,
    required this.lockButtonBuilder,
    required this.onClose,
    required this.onToggleControls,
    required this.onShowControls,
    required this.onHideControls,
    required this.onCancelHideTimer,
    required this.onScheduleAutoHide,
  });

  final VideoPlayerSlotContext slot;
  final VideoPlayerController controller;
  final Key surfaceKey;
  final double? aspectRatio;
  final bool fill;
  final Duration fadeDuration;
  final FlutterSignal<bool> visible;
  final bool isDesktop;
  final FocusNode focusNode;
  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final List<Widget> topBarActions;
  final bool showCastButton;
  final bool showAspectRatioMenu;
  final bool enableFullscreen;
  final bool enableFullscreenVerticalGestures;
  final FullscreenGestureSideMapping verticalGestureMapping;
  final double verticalGestureLeftWidthRatio;
  final double verticalGestureRightWidthRatio;
  final double verticalGestureHeightRatio;
  final bool showLockButton;
  final PlayerLockButtonPosition lockButtonPosition;
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? castingOverlayBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;
  final Widget Function(BuildContext context, PlayerGestureHudContext hud)? gestureHudBuilder;
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot, bool isLocked)?
  lockButtonBuilder;
  final VoidCallback onClose;
  final VoidCallback onToggleControls;
  final VoidCallback onShowControls;
  final VoidCallback onHideControls;
  final VoidCallback onCancelHideTimer;
  final VoidCallback onScheduleAutoHide;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerTheme style = slot.theme;

    return SignalBuilder(
      builder: (BuildContext context) {
        final bool isFullscreen = controller.isFullscreen.value;
        final bool isLocked = controller.isLocked.value;

        Widget stack = ColoredBox(
          color: style.backgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fill(
                child: CorePlayer(
                  key: surfaceKey,
                  controller: controller,
                  aspectRatio: aspectRatio,
                  backgroundColor: style.backgroundColor,
                  errorBuilder: errorBuilder,
                  loadingBuilder: loadingBuilder,
                ),
              ),
              // Hide frozen local video frames while casting to a remote device.
              Positioned.fill(
                child: SignalBuilder(
                  builder: (BuildContext context) {
                    if (!controller.isCasting.value) {
                      return const SizedBox.shrink();
                    }
                    return ColoredBox(color: style.backgroundColor);
                  },
                ),
              ),
              Positioned.fill(
                child: isFullscreen
                    ? PlayerGestureLayer(
                        controller: controller,
                        isLocked: isLocked,
                        enableVerticalGestures: enableFullscreenVerticalGestures,
                        verticalGestureMapping: verticalGestureMapping,
                        verticalGestureLeftWidthRatio: verticalGestureLeftWidthRatio,
                        verticalGestureRightWidthRatio: verticalGestureRightWidthRatio,
                        verticalGestureHeightRatio: verticalGestureHeightRatio,
                        gestureHudBuilder: gestureHudBuilder,
                        onTap: () {
                          if (isDesktop) {
                            focusNode.requestFocus();
                          }
                          onToggleControls();
                        },
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
                  child: SignalBuilder(
                    builder: (BuildContext context) {
                      final bool isVisible = visible.value;
                      return AnimatedSwitcher(
                        duration: fadeDuration,
                        child: !isVisible
                            ? const SizedBox.shrink(key: ValueKey<String>('controls_hidden'))
                            : (isFullscreen && isLocked)
                            ? (showLockButton
                                  ? _PositionedLockButton(
                                      key: const ValueKey<String>('controls_locked'),
                                      slot: slot,
                                      position: lockButtonPosition,
                                      isLocked: true,
                                      lockButtonBuilder: lockButtonBuilder,
                                      onToggle: () {
                                        controller.toggleLocked();
                                        onShowControls();
                                      },
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey<String>('controls_locked_empty'),
                                    ))
                            : Stack(
                                key: const ValueKey<String>('controls_visible'),
                                fit: StackFit.expand,
                                children: <Widget>[
                                  Column(
                                    mainAxisSize: MainAxisSize.max,
                                    children: <Widget>[
                                      topBarBuilder?.call(context, slot) ??
                                          PlayerTopBar(
                                            slot: slot,
                                            leading: leading,
                                            title: title,
                                            actions: actions,
                                            topBarActions: topBarActions,
                                            showCastButton: showCastButton,
                                            showAspectRatioMenu: showAspectRatioMenu,
                                            onClose: onClose,
                                            onShowControls: onShowControls,
                                          ),
                                      Expanded(
                                        child: Center(
                                          child:
                                              centerControlsBuilder?.call(context, slot) ??
                                              PlayerCenterControls(
                                                slot: slot,
                                                onInteract: onShowControls,
                                              ),
                                        ),
                                      ),
                                      bottomScrubberBuilder?.call(context, slot) ??
                                          PlayerBottomScrubber(
                                            slot: slot,
                                            enableFullscreen: enableFullscreen,
                                            onInteractStart: onCancelHideTimer,
                                            onInteractEnd: onScheduleAutoHide,
                                            onInteract: onShowControls,
                                          ),
                                    ],
                                  ),
                                  if (isFullscreen && showLockButton)
                                    _PositionedLockButton(
                                      slot: slot,
                                      position: lockButtonPosition,
                                      isLocked: false,
                                      lockButtonBuilder: lockButtonBuilder,
                                      onToggle: () {
                                        controller.toggleLocked();
                                        onShowControls();
                                      },
                                    ),
                                ],
                              ),
                      );
                    },
                  ),
                ),
              ),
              // Interactive casting status & quick actions ("切换设备" / "退出投屏").
              Positioned.fill(
                child: SignalBuilder(
                  builder: (BuildContext context) {
                    if (!controller.isCasting.value || isLocked) {
                      return const SizedBox.shrink();
                    }
                    return castingOverlayBuilder?.call(context, slot) ??
                        PlayerCastingOverlay(slot: slot, onInteract: onShowControls);
                  },
                ),
              ),
              if (extraOverlayBuilder != null && !isLocked)
                Positioned.fill(child: extraOverlayBuilder!(context, slot)),
            ],
          ),
        );

        if (isDesktop) {
          stack = Focus(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              final KeyEventResult result = handlePlayerKeyEvent(controller, event);
              if (result == KeyEventResult.handled) {
                onHideControls();
              }
              return result;
            },
            child: stack,
          );
        }

        if (fill || isFullscreen) {
          return stack;
        }

        final double effectiveAspectRatio;
        if (aspectRatio != null) {
          effectiveAspectRatio = aspectRatio!;
        } else {
          final double reported = controller.videoAspectRatio.value;
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

class _PositionedLockButton extends StatelessWidget {
  const _PositionedLockButton({
    super.key,
    required this.slot,
    required this.position,
    required this.isLocked,
    required this.lockButtonBuilder,
    required this.onToggle,
  });

  final VideoPlayerSlotContext slot;
  final PlayerLockButtonPosition position;
  final bool isLocked;
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot, bool isLocked)?
  lockButtonBuilder;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Alignment alignment = position == PlayerLockButtonPosition.left
        ? Alignment.centerLeft
        : Alignment.centerRight;

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child:
            lockButtonBuilder?.call(context, slot, isLocked) ??
            PlayerLockButton(slot: slot, isLocked: isLocked, onToggle: onToggle),
      ),
    );
  }
}
