import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../style/player_icon_catalog.dart';
import '../video_player_slot_context.dart';
import 'player_glass_surface.dart';
import 'player_icon_button.dart';
import 'player_menu_button.dart';
import 'player_scrubber_slider.dart';

/// Default bottom scrubber bar of [VideoPlayer], adapting to Material and Cupertino styles.
class PlayerBottomScrubber extends StatefulWidget {
  const PlayerBottomScrubber({
    super.key,
    required this.slot,
    required this.onInteractStart,
    required this.onInteractEnd,
    required this.onInteract,
    required this.enableFullscreen,
  });

  final VideoPlayerSlotContext slot;
  final VoidCallback onInteractStart;
  final VoidCallback onInteractEnd;
  final VoidCallback onInteract;
  final bool enableFullscreen;

  @override
  State<PlayerBottomScrubber> createState() => _PlayerBottomScrubberState();
}

class _PlayerBottomScrubberState extends State<PlayerBottomScrubber> {
  final FlutterSignal<double?> _dragValue = signal(null);

  static const List<double> _speeds = <double>[0.5, 1.0, 1.25, 1.5, 2.0];

  static String _formatDuration(Duration duration, {bool negative = false}) {
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
    final isCupertino = style.isCupertino;

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

          final row = Row(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              PlayerIconButton(
                compact: true,
                onPressed: () {
                  controller.toggleMuted();
                  widget.onInteract();
                },
                color: style.foregroundColor,
                icon: Icon(
                  PlayerIconCatalog.volume(isCupertino: isCupertino, muted: muted),
                  size: style.chromeIconSize,
                ),
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
                compact: isCupertino,
                icon: PlayerIconCatalog.speed(isCupertino: isCupertino),
                color: style.foregroundColor,
                tooltip: '倍速',
                menuBuilder: (context, hideMenu) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < _speeds.length; i++)
                        PlayerMenuOptionTile(
                          label: '${_speeds[i]}x',
                          selected: (_speeds[i] - speed).abs() < 0.01,
                          showDivider: i < _speeds.length - 1,
                          onTap: () {
                            controller.setSpeed(_speeds[i]);
                            hideMenu();
                            widget.onInteract();
                          },
                        ),
                    ],
                  );
                },
              ),
              if (widget.enableFullscreen)
                PlayerIconButton(
                  compact: true,
                  onPressed: () {
                    controller.toggleFullscreen();
                    widget.onInteract();
                  },
                  color: style.foregroundColor,
                  icon: Icon(
                    PlayerIconCatalog.fullscreen(
                      isCupertino: isCupertino,
                      isFullscreen: fullscreen,
                    ),
                    size: style.chromeIconSize,
                  ),
                ),
            ],
          );

          if (isCupertino) {
            return PlayerGlassSurface(
              backgroundColor: style.barBackgroundColor,
              borderRadius: style.barBorderRadius,
              blurSigma: style.backdropBlurSigma,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: row,
            );
          }

          return row;
        },
      ),
    );
  }
}
