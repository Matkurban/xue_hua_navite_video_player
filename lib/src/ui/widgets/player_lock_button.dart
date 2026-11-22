import 'package:material_ui/material_ui.dart';

import '../style/player_icon_catalog.dart';
import '../style/video_player_theme.dart';
import '../video_player_slot_context.dart';
import 'player_icon_button.dart';

/// Default fullscreen lock/unlock button adapting to Material and Cupertino themes.
class PlayerLockButton extends StatelessWidget {
  const PlayerLockButton({
    super.key,
    required this.slot,
    required this.isLocked,
    required this.onToggle,
  });

  final VideoPlayerSlotContext slot;
  final bool isLocked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerTheme style = slot.theme;
    final bool isCupertino = style.isCupertinoFor(context);

    return PlayerIconButton(
      key: const ValueKey<String>('player_lock_button'),
      icon: Icon(
        PlayerIconCatalog.lock(isCupertino: isCupertino, isLocked: isLocked),
        size: style.chromeIconSize,
      ),
      color: style.foregroundColor,
      backgroundColor: style.centerButtonBackgroundColor,
      circularGlassInCupertino: true,
      tooltip: isLocked ? '解锁屏幕' : '锁定屏幕',
      onPressed: onToggle,
    );
  }
}
