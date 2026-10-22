import 'package:chat_context_menu/chat_context_menu.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../style/player_icon_catalog.dart';
import '../style/video_player_theme.dart';
import 'player_icon_button.dart';

/// Thin [ChatContextMenuWrapper] icon button used by player chrome.
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    super.key,
    required this.icon,
    required this.menuBuilder,
    this.color,
    this.tooltip,
    this.compact = false,
  });

  final IconData icon;
  final Widget Function(BuildContext context, VoidCallback hideMenu) menuBuilder;
  final Color? color;
  final String? tooltip;
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

/// Theme-adaptive popup menu item row.
///
/// - In Cupertino mode: renders a Cupertino-styled row with hairline divider
///   and [CupertinoIcons.checkmark_alt] selection indicator.
/// - In Material mode: renders a compact [ListTile] with [Icons.check]
///   selection indicator.
class PlayerMenuOptionTile extends StatelessWidget {
  const PlayerMenuOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDivider = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    final isCupertino = style.isCupertino;
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
                    ? Icon(
                        checkIcon,
                        size: style.menuIconSize,
                        color: style.foregroundColor,
                      )
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
            Icon(
              checkIcon,
              size: style.menuIconSize,
              color: style.foregroundColor,
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
