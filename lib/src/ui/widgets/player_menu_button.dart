import 'package:chat_context_menu/chat_context_menu.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../style/player_icon_catalog.dart';
import '../style/video_player_theme.dart';
import 'player_icon_button.dart';

/// 基于 [ChatContextMenuWrapper] 封装的播放器弹出菜单图标按钮（用于倍速、画面比例等菜单）。
///
/// Thin [ChatContextMenuWrapper] icon button used by player chrome for popup menus.
class PlayerMenuButton extends StatelessWidget {
  /// 创建弹出菜单触发按钮。
  ///
  /// Creates a [PlayerMenuButton].
  const PlayerMenuButton({
    super.key,
    required this.icon,
    required this.menuBuilder,
    this.color,
    this.tooltip,
    this.compact = false,
  });

  /// 触发按钮展示的图标。
  ///
  /// Icon displayed on the menu trigger button.
  final IconData icon;

  /// 弹出菜单内容构建器，接收 `hideMenu` 回调用于关闭菜单。
  ///
  /// Builder producing popup menu contents with a `hideMenu` callback.
  final Widget Function(BuildContext context, VoidCallback hideMenu) menuBuilder;

  /// 图标与菜单项前景色，默认读取 `VideoPlayerTheme.foregroundColor`。
  ///
  /// Foreground color for the icon and menu items.
  final Color? color;

  /// 按钮悬停或长按提示文本。
  ///
  /// Optional tooltip text for the trigger button.
  final String? tooltip;

  /// 是否启用紧凑内边距布局。
  ///
  /// Whether to use compact button padding.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    final foreground = color ?? style.foregroundColor;
    final menuTitleStyle = style.menuItemTextStyle.copyWith(color: foreground);
    final base = Theme.of(context);

    return ChatContextMenuWrapper(
      topPadding: 0,
      backgroundColor: style.menuBackgroundColor,
      borderRadius: style.menuBorderRadius,
      padding: EdgeInsets.zero,
      spacing: 0,
      horizontalMargin: 0,
      menuBuilder: (context, hideMenu) => Material(
        type: MaterialType.transparency,
        child: IntrinsicWidth(
          child: Theme(
            data: base.copyWith(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.dark(onSurface: foreground, primary: foreground),
              listTileTheme: ListTileThemeData(
                dense: true,
                visualDensity: VisualDensity.compact,
                textColor: foreground,
                iconColor: foreground,
                contentPadding: style.menuContentPadding,
                minVerticalPadding: style.menuMinVerticalPadding,
                horizontalTitleGap: 0,
                minLeadingWidth: 0,
                titleTextStyle: menuTitleStyle,
              ),
              iconTheme: IconThemeData(color: foreground, size: style.menuIconSize),
              textTheme: base.textTheme.apply(bodyColor: foreground, displayColor: foreground),
            ),
            child: DefaultTextStyle(
              style: menuTitleStyle,
              child: IconTheme(
                data: IconThemeData(color: foreground, size: style.menuIconSize),
                child: menuBuilder(context, hideMenu),
              ),
            ),
          ),
        ),
      ),
      widgetBuilder: (context, showMenu, _) {
        return PlayerIconButton(
          compact: compact,
          onPressed: showMenu,
          color: foreground,
          tooltip: tooltip,
          icon: Icon(icon, size: style.chromeIconSize),
        );
      },
    );
  }
}

/// 主题自适应的弹出菜单单行选项组件。
///
/// - Cupertino 模式：渲染带细分割线与 `CupertinoIcons.checkmark_alt` 勾选标志的按钮行；
/// - Material 模式：渲染紧凑型 [ListTile] 与 `Icons.check` 勾选标志。
///
/// Theme-adaptive popup menu option row for Material and Cupertino styles.
class PlayerMenuOptionTile extends StatelessWidget {
  /// 创建弹出菜单选项行。
  ///
  /// Creates a [PlayerMenuOptionTile].
  const PlayerMenuOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDivider = false,
  });

  /// 选项文本标签。
  ///
  /// Option display label.
  final String label;

  /// 当前项是否处于选中态。
  ///
  /// Whether this option is currently selected.
  final bool selected;

  /// 点击该选项时的回调。
  ///
  /// Callback invoked when the option is tapped.
  final VoidCallback onTap;

  /// Cupertino 模式下是否在底部绘制细分割线。
  ///
  /// Whether to draw a hairline bottom divider in Cupertino mode.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    final isCupertino = style.isCupertinoFor(context);
    final checkIcon = PlayerIconCatalog.check(isCupertino: isCupertino);

    if (isCupertino) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: style.foregroundColor.withValues(alpha: 0.14),
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: CupertinoButton(
          padding: EdgeInsets.symmetric(
            horizontal: style.menuContentPadding.horizontal / 2,
            vertical: style.menuMinVerticalPadding + 4,
          ),
          minimumSize: Size.zero,
          pressedOpacity: 0.55,
          onPressed: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label, style: style.menuItemTextStyle),
              const SizedBox(width: 14),
              SizedBox(
                width: style.menuIconSize,
                height: style.menuIconSize,
                child: selected
                    ? Icon(checkIcon, size: style.menuIconSize, color: style.foregroundColor)
                    : null,
              ),
            ],
          ),
        ),
      );
    }

    return ListTile(
      dense: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label),
          if (selected) ...<Widget>[
            const SizedBox(width: 8),
            Icon(checkIcon, size: style.menuIconSize, color: style.foregroundColor),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
