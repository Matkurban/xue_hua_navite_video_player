import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../style/video_player_theme.dart';
import 'player_glass_surface.dart';

/// Theme-adaptive icon button for player chrome and center transport controls.
///
/// - In Material mode: renders [IconButton] with Material ink ripple.
/// - In Cupertino mode: renders [CupertinoButton] with spring opacity fade
///   and optional frosted glass circular backing.
class PlayerIconButton extends StatelessWidget {
  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.tooltip,
    this.compact = false,
    this.circularGlassInCupertino = false,
    this.padding,
    this.minSize = 36.0,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? backgroundColor;
  final String? tooltip;
  final bool compact;
  final bool circularGlassInCupertino;
  final EdgeInsetsGeometry? padding;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    final foreground = color ?? style.foregroundColor;

    if (style.isCupertinoFor(context)) {
      final buttonPadding =
          padding ??
          (circularGlassInCupertino
              ? const EdgeInsets.all(12)
              : (compact ? const EdgeInsets.all(6) : const EdgeInsets.all(8)));

      Widget button = CupertinoButton(
        padding: buttonPadding,
        minimumSize: Size(minSize, minSize),
        pressedOpacity: 0.55,
        onPressed: onPressed,
        child: IconTheme(
          data: IconThemeData(color: foreground),
          child: icon,
        ),
      );

      if (backgroundColor != null) {
        button = PlayerGlassSurface(
          backgroundColor: backgroundColor!,
          borderRadius: BorderRadius.circular(999),
          blurSigma: circularGlassInCupertino ? style.backdropBlurSigma : 0.0,
          child: button,
        );
      }

      if (tooltip != null && tooltip!.isNotEmpty) {
        return Tooltip(message: tooltip!, child: button);
      }
      return button;
    }

    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      padding: padding ?? (compact ? EdgeInsets.zero : null),
      constraints: compact ? BoxConstraints(minWidth: minSize, minHeight: minSize) : null,
      tooltip: tooltip,
      color: foreground,
      style: backgroundColor != null
          ? IconButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foreground,
              disabledBackgroundColor: backgroundColor!.withValues(alpha: 0.25),
              disabledForegroundColor: foreground.withValues(alpha: 0.45),
            )
          : null,
      onPressed: onPressed,
      icon: icon,
    );
  }
}

/// Theme-adaptive labeled action pill button (e.g. casting quick actions).
class PlayerActionPillButton extends StatelessWidget {
  const PlayerActionPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);

    if (style.isCupertinoFor(context)) {
      return PlayerGlassSurface(
        backgroundColor: style.barBackgroundColor,
        borderRadius: BorderRadius.circular(999),
        blurSigma: style.backdropBlurSigma,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: Size.zero,
          pressedOpacity: 0.55,
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: style.menuIconSize, color: style.foregroundColor),
              const SizedBox(width: 6),
              Text(label, style: style.menuItemTextStyle),
            ],
          ),
        ),
      );
    }

    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: style.foregroundColor,
        backgroundColor: style.centerButtonBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: style.menuIconSize, color: style.foregroundColor),
      label: Text(label, style: style.menuItemTextStyle),
    );
  }
}
