import 'package:material_ui/material_ui.dart';

import '../style/player_icon_catalog.dart';
import '../style/video_player_theme.dart';
import '../video_player_slot_context.dart';
import 'player_icon_button.dart';

/// 全屏模式下的默认锁定/解锁按钮组件，自动适配 Material 与 Cupertino 主题。
///
/// Default fullscreen lock/unlock button adapting to Material and Cupertino themes.
class PlayerLockButton extends StatelessWidget {
  /// 创建默认全屏锁定/解锁按钮。
  ///
  /// Creates a [PlayerLockButton].
  const PlayerLockButton({
    super.key,
    required this.slot,
    required this.isLocked,
    required this.onToggle,
  });

  /// 当前播放器槽位上下文（提供主题与控制器）。
  ///
  /// Active player slot context providing theme and controller.
  final VideoPlayerSlotContext slot;

  /// 当前是否处于屏幕锁定状态。
  ///
  /// Whether fullscreen controls and orientation are currently locked.
  final bool isLocked;

  /// 点击锁定/解锁按钮时触发的切换回调。
  ///
  /// Callback invoked when the user taps to toggle lock state.
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
