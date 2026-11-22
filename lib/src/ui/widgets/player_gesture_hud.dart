import 'package:material_ui/material_ui.dart';

import '../player_gesture_hud_context.dart';
import '../style/player_icon_catalog.dart';
import '../style/video_player_theme.dart';
import 'player_glass_surface.dart';

/// Default center HUD indicator shown during fullscreen gestures (brightness,
/// volume, and horizontal seek).
///
/// Automatically adapts to both Material and Cupertino themes via
/// [VideoPlayerTheme.isCupertinoFor].
class PlayerGestureHud extends StatelessWidget {
  const PlayerGestureHud({super.key, required this.hud});

  final PlayerGestureHudContext hud;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerTheme style = hud.theme;
    final bool isCupertino = style.isCupertinoFor(context);
    final IconData iconData = switch (hud.kind) {
      PlayerHudKind.seek => PlayerIconCatalog.hudSeek(
        isCupertino: isCupertino,
        forward: hud.seekForward,
      ),
      PlayerHudKind.brightness => PlayerIconCatalog.hudBrightness(isCupertino: isCupertino),
      PlayerHudKind.volume => PlayerIconCatalog.hudVolume(
        isCupertino: isCupertino,
        muted: hud.isMuted,
      ),
    };

    final BoxBorder? glassBorder = isCupertino
        ? Border.all(color: style.foregroundColor.withValues(alpha: 0.14), width: 0.5)
        : null;

    if (hud.kind == PlayerHudKind.seek) {
      return PlayerGlassSurface(
        backgroundColor: style.hudBackgroundColor,
        borderRadius: style.hudBorderRadius,
        blurSigma: isCupertino ? style.backdropBlurSigma : 0.0,
        padding: style.hudPadding,
        border: glassBorder,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(iconData, color: style.foregroundColor, size: style.hudIconSize),
            SizedBox(width: style.hudIconGap),
            Text(hud.label, style: style.hudTextStyle),
          ],
        ),
      );
    }

    final double clampedValue = hud.value.clamp(0.0, 1.0);
    final TextStyle percentTextStyle = style.hudTextStyle.copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return PlayerGlassSurface(
      backgroundColor: style.hudBackgroundColor,
      borderRadius: style.hudBorderRadius,
      blurSigma: isCupertino ? style.backdropBlurSigma : 0.0,
      padding: style.hudPadding,
      border: glassBorder,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(iconData, color: style.foregroundColor, size: style.hudIconSize),
          SizedBox(width: style.hudIconGap + 2.0),
          if (isCupertino)
            SizedBox(
              width: 112.0,
              height: 6.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(color: style.scrubberInactiveColor),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: clampedValue,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: style.scrubberActiveColor,
                          borderRadius: BorderRadius.circular(999.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              width: 112.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999.0),
                child: LinearProgressIndicator(
                  value: clampedValue,
                  minHeight: 4.0,
                  color: style.scrubberActiveColor,
                  backgroundColor: style.scrubberInactiveColor,
                ),
              ),
            ),
          SizedBox(width: style.hudIconGap + 2.0),
          SizedBox(
            width: 44.0,
            child: Text(
              hud.label,
              textAlign: TextAlign.end,
              style: percentTextStyle,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}
