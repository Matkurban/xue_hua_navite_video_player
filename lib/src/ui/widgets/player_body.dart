import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../player/video_player_controller.dart';
import '../core_player.dart';
import '../video_player_slot_context.dart';
import 'player_bottom_scrubber.dart';
import 'player_casting_overlay.dart';
import 'player_center_controls.dart';
import 'player_gesture_layer.dart';
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
    required this.errorBuilder,
    required this.loadingBuilder,
    required this.topBarBuilder,
    required this.centerControlsBuilder,
    required this.bottomScrubberBuilder,
    required this.castingOverlayBuilder,
    required this.extraOverlayBuilder,
    required this.onClose,
    required this.onToggleControls,
    required this.onShowControls,
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
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? castingOverlayBuilder;
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;
  final VoidCallback onClose;
  final VoidCallback onToggleControls;
  final VoidCallback onShowControls;
  final VoidCallback onCancelHideTimer;
  final VoidCallback onScheduleAutoHide;

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;

    return SignalBuilder(
      builder: (context) {
        final isFullscreen = controller.isFullscreen.value;

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
                  builder: (context) {
                    if (!controller.isCasting.value) {
                      return const SizedBox.shrink();
                    }
                    return ColoredBox(color: style.backgroundColor);
                  },
                ),
              ),
              Positioned.fill(
                child: isFullscreen && !kIsWeb
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
                  child: SignalBuilder(
                    builder: (context) {
                      final isVisible = visible.value;
                      return AnimatedSwitcher(
                        duration: fadeDuration,
                        child: !isVisible
                            ? const SizedBox.shrink(key: ValueKey<bool>(false))
                            : Column(
                                key: const ValueKey<bool>(true),
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
                      );
                    },
                  ),
                ),
              ),
              // Interactive casting status & quick actions ("切换设备" / "退出投屏").
              Positioned.fill(
                child: SignalBuilder(
                  builder: (context) {
                    if (!controller.isCasting.value) {
                      return const SizedBox.shrink();
                    }
                    return castingOverlayBuilder?.call(context, slot) ??
                        PlayerCastingOverlay(slot: slot, onInteract: onShowControls);
                  },
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
