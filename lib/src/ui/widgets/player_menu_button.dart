import 'package:chat_context_menu/chat_context_menu.dart';
import 'package:flutter/material.dart';

import '../style/video_player_theme.dart';

/// Thin [ChatContextMenuWrapper] icon button used by player chrome.
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    super.key,
    required this.icon,
    required this.menuBuilder,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final Widget Function(BuildContext context, VoidCallback hideMenu) menuBuilder;
  final Color? color;
  final String? tooltip;

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
      menuBuilder: (context, hideMenu) => IntrinsicWidth(
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
      widgetBuilder: (context, showMenu, _) {
        return IconButton(
          onPressed: showMenu,
          color: foreground,
          icon: Icon(icon, size: style.chromeIconSize),
          tooltip: tooltip,
        );
      },
    );
  }
}
