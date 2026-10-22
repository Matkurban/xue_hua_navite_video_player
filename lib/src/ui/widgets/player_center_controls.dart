import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/enums/play_state.dart';
import '../style/player_icon_catalog.dart';
import '../video_player_slot_context.dart';
import 'player_glass_surface.dart';
import 'player_icon_button.dart';
import 'player_loading_indicator.dart';

/// Default center playback transport controls (skip backward, play/pause/replay, skip forward).
class PlayerCenterControls extends StatelessWidget {
  const PlayerCenterControls({
    super.key,
    required this.slot,
    required this.onInteract,
  });

  final VideoPlayerSlotContext slot;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;
    final isCupertino = style.isCupertino;

    return SignalBuilder(
      builder: (context) {
        final state = controller.playState.value;
        final buffering = controller.isBuffering.value;
        final canInteract = state != PlayState.loading && state != PlayState.error;
        final skip = controller.skipSecondType.value;

        return Row(
          spacing: style.centerControlsSpacing,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            PlayerIconButton(
              circularGlassInCupertino: isCupertino,
              backgroundColor: style.centerButtonBackgroundColor,
              color: style.foregroundColor,
              onPressed: canInteract
                  ? () async {
                      await controller.seekBackward();
                      onInteract();
                    }
                  : null,
              icon: Icon(
                PlayerIconCatalog.skipBackward(
                  isCupertino: isCupertino,
                  seconds: skip,
                ),
                size: style.centerSkipButtonIconSize,
              ),
            ),
            _CenterPrimaryControlButton(
              slot: slot,
              state: state,
              buffering: buffering,
              canInteract: canInteract,
              onInteract: onInteract,
            ),
            PlayerIconButton(
              circularGlassInCupertino: isCupertino,
              backgroundColor: style.centerButtonBackgroundColor,
              color: style.foregroundColor,
              onPressed: canInteract
                  ? () async {
                      await controller.seekForward();
                      onInteract();
                    }
                  : null,
              icon: Icon(
                PlayerIconCatalog.skipForward(
                  isCupertino: isCupertino,
                  seconds: skip,
                ),
                size: style.centerSkipButtonIconSize,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CenterPrimaryControlButton extends StatelessWidget {
  const _CenterPrimaryControlButton({
    required this.slot,
    required this.state,
    required this.buffering,
    required this.canInteract,
    required this.onInteract,
  });

  final VideoPlayerSlotContext slot;
  final PlayState state;
  final bool buffering;
  final bool canInteract;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;
    final isCupertino = style.isCupertino;

    if (state == PlayState.loading || buffering) {
      final indicator = PlayerLoadingIndicator(
        size: style.centerPlayButtonIconSize,
        color: style.foregroundColor,
      );
      if (isCupertino) {
        return PlayerGlassSurface(
          backgroundColor: style.centerButtonBackgroundColor,
          borderRadius: BorderRadius.circular(999),
          blurSigma: style.backdropBlurSigma,
          padding: const EdgeInsets.all(14),
          child: indicator,
        );
      }
      return indicator;
    }

    if (state == PlayState.completed) {
      return PlayerIconButton(
        circularGlassInCupertino: isCupertino,
        backgroundColor: style.centerButtonBackgroundColor,
        color: style.foregroundColor,
        onPressed: () async {
          await controller.play();
          onInteract();
        },
        icon: Icon(
          PlayerIconCatalog.replay(isCupertino: isCupertino),
          size: style.centerPlayButtonIconSize,
        ),
      );
    }

    final isPlaying = state == PlayState.playing;
    return PlayerIconButton(
      circularGlassInCupertino: isCupertino,
      backgroundColor: style.centerButtonBackgroundColor,
      color: style.foregroundColor,
      onPressed: canInteract
          ? () {
              controller.playOrPause();
              onInteract();
            }
          : null,
      icon: Icon(
        isPlaying
            ? PlayerIconCatalog.pause(isCupertino: isCupertino)
            : PlayerIconCatalog.play(isCupertino: isCupertino),
        size: style.centerPlayButtonIconSize,
      ),
    );
  }
}
