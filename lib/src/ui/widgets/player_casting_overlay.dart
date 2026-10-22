import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/enums/cast_state.dart';
import '../style/player_icon_catalog.dart';
import '../video_player_slot_context.dart';
import 'player_glass_surface.dart';
import 'player_icon_button.dart';

/// Default wireless casting status overlay and quick action buttons ("切换设备" / "退出投屏").
class PlayerCastingOverlay extends StatelessWidget {
  const PlayerCastingOverlay({
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
        final state = controller.castState.value;
        final deviceName = controller.castDeviceName.value;
        final isConnecting = state == CastState.connecting;
        final statusLabel = isConnecting
            ? (deviceName != null && deviceName.isNotEmpty ? '正在连接「$deviceName」...' : '正在连接投屏设备...')
            : (deviceName != null && deviceName.isNotEmpty ? '正在投屏至「$deviceName」' : '正在投屏播放');

        return SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Status badge positioned above the center playback controls.
              Align(
                alignment: const Alignment(0, -0.56),
                child: IgnorePointer(
                  child: PlayerGlassSurface(
                    backgroundColor: style.hudBackgroundColor,
                    borderRadius: style.hudBorderRadius,
                    blurSigma: isCupertino ? style.backdropBlurSigma : 0.0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          PlayerIconCatalog.cast(
                            isCupertino: isCupertino,
                            state: CastState.connected,
                          ),
                          size: style.hudIconSize,
                          color: style.foregroundColor,
                        ),
                        SizedBox(width: style.hudIconGap),
                        Flexible(
                          child: Text(
                            statusLabel,
                            style: style.menuItemTextStyle,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Quick action buttons positioned below the center playback controls.
              Align(
                alignment: const Alignment(0, 0.56),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PlayerActionPillButton(
                      key: const ValueKey<String>('video_player_cast_switch_button'),
                      icon: PlayerIconCatalog.cast(
                        isCupertino: isCupertino,
                        state: CastState.notConnected,
                      ),
                      label: '切换设备',
                      onPressed: () {
                        controller.showCastPicker();
                        onInteract();
                      },
                    ),
                    const SizedBox(width: 12),
                    PlayerActionPillButton(
                      key: const ValueKey<String>('video_player_cast_stop_button'),
                      icon: PlayerIconCatalog.stopCast(isCupertino: isCupertino),
                      label: '退出投屏',
                      onPressed: () {
                        controller.stopCasting();
                        onInteract();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
