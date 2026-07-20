import 'dart:ui';
import 'package:flutter/material.dart';

/// The theme configuration for the video player.
@immutable
class VideoPlayerTheme extends ThemeExtension<VideoPlayerTheme> {
  /// Foreground color for overlay glyphs and text.
  final Color foregroundColor;

  /// Background color behind the video frame.
  final Color backgroundColor;

  /// Horizontal spacing between the three center buttons.
  final double centerControlsSpacing;

  /// The size of the central play/pause button icon.
  final double centerPlayButtonIconSize;

  /// The size of the skip forward/backward button icons.
  final double centerSkipButtonIconSize;

  /// The background color for the center buttons.
  final Color centerButtonBackgroundColor;

  /// Icon size for top/bottom chrome controls (mute, fullscreen, etc.).
  final double chromeIconSize;

  /// Inset of the top bar.
  final EdgeInsets topBarPadding;

  /// Inset of the bottom scrubber row.
  final EdgeInsets bottomBarPadding;

  /// Text style of the time labels flanking the scrubber.
  final TextStyle timeTextStyle;

  /// Active (played) segment color.
  final Color scrubberActiveColor;

  /// Buffered segment color.
  final Color scrubberBufferedColor;

  /// Inactive (unplayed) segment color.
  final Color scrubberInactiveColor;

  /// Scrubber thumb color.
  final Color scrubberThumbColor;

  /// Soft shadow drawn under the scrubber thumb.
  final Color scrubberThumbShadowColor;

  /// Scrubber track thickness at rest.
  final double scrubberTrackHeight;

  /// Scrubber track thickness while scrubbing.
  final double scrubberActiveTrackHeight;

  /// Scrubber thumb radius at rest.
  final double scrubberThumbRadius;

  /// Scrubber thumb radius while the user is pressing or dragging.
  final double scrubberActiveThumbRadius;

  /// Popup menu panel background.
  final Color menuBackgroundColor;

  /// Popup menu corner radius.
  final BorderRadius menuBorderRadius;

  /// Horizontal padding inside menu list tiles.
  final EdgeInsets menuContentPadding;

  /// Vertical padding inside menu list tiles.
  final double menuMinVerticalPadding;

  /// Menu item title text style.
  final TextStyle menuItemTextStyle;

  /// Menu leading/trailing icon size.
  final double menuIconSize;

  /// Gesture HUD panel background.
  final Color hudBackgroundColor;

  /// Gesture HUD corner radius.
  final BorderRadius hudBorderRadius;

  /// Gesture HUD inner padding.
  final EdgeInsets hudPadding;

  /// Gesture HUD icon size.
  final double hudIconSize;

  /// Gap between HUD icon and label.
  final double hudIconGap;

  /// Gesture HUD label text style.
  final TextStyle hudTextStyle;

  const VideoPlayerTheme({
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.centerControlsSpacing = 56,
    this.centerPlayButtonIconSize = 48,
    this.centerSkipButtonIconSize = 32,
    this.centerButtonBackgroundColor = const Color(0x4D000000), // Colors.black38
    this.chromeIconSize = 22,
    this.topBarPadding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
    this.bottomBarPadding = const EdgeInsets.fromLTRB(16, 6, 16, 14),
    this.timeTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      fontWeight: FontWeight.w500,
      height: 1.0,
    ),
    this.scrubberActiveColor = Colors.white,
    this.scrubberBufferedColor = const Color(0xB3FFFFFF),
    this.scrubberInactiveColor = const Color(0x40FFFFFF),
    this.scrubberThumbColor = Colors.white,
    this.scrubberThumbShadowColor = const Color(0x40000000), // black 0.25
    this.scrubberTrackHeight = 2.0,
    this.scrubberActiveTrackHeight = 6.0,
    this.scrubberThumbRadius = 5.0,
    this.scrubberActiveThumbRadius = 9.0,
    this.menuBackgroundColor = const Color(0xF01A1A1A),
    this.menuBorderRadius = const BorderRadius.all(Radius.circular(10)),
    this.menuContentPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.menuMinVerticalPadding = 4,
    this.menuItemTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    this.menuIconSize = 18,
    this.hudBackgroundColor = const Color(0xB3000000), // black 0.7
    this.hudBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.hudPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.hudIconSize = 24,
    this.hudIconGap = 8,
    this.hudTextStyle = const TextStyle(color: Colors.white, fontSize: 16),
  });

  /// Resolves [VideoPlayerTheme] from [context], falling back to defaults.
  static VideoPlayerTheme of(BuildContext context) {
    return Theme.of(context).extension<VideoPlayerTheme>() ?? const VideoPlayerTheme();
  }

  @override
  VideoPlayerTheme copyWith({
    Color? foregroundColor,
    Color? backgroundColor,
    double? centerControlsSpacing,
    double? centerPlayButtonIconSize,
    double? centerSkipButtonIconSize,
    Color? centerButtonBackgroundColor,
    double? chromeIconSize,
    EdgeInsets? topBarPadding,
    EdgeInsets? bottomBarPadding,
    TextStyle? timeTextStyle,
    Color? scrubberActiveColor,
    Color? scrubberBufferedColor,
    Color? scrubberInactiveColor,
    Color? scrubberThumbColor,
    Color? scrubberThumbShadowColor,
    double? scrubberTrackHeight,
    double? scrubberActiveTrackHeight,
    double? scrubberThumbRadius,
    double? scrubberActiveThumbRadius,
    Color? menuBackgroundColor,
    BorderRadius? menuBorderRadius,
    EdgeInsets? menuContentPadding,
    double? menuMinVerticalPadding,
    TextStyle? menuItemTextStyle,
    double? menuIconSize,
    Color? hudBackgroundColor,
    BorderRadius? hudBorderRadius,
    EdgeInsets? hudPadding,
    double? hudIconSize,
    double? hudIconGap,
    TextStyle? hudTextStyle,
  }) {
    return VideoPlayerTheme(
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      centerControlsSpacing: centerControlsSpacing ?? this.centerControlsSpacing,
      centerPlayButtonIconSize: centerPlayButtonIconSize ?? this.centerPlayButtonIconSize,
      centerSkipButtonIconSize: centerSkipButtonIconSize ?? this.centerSkipButtonIconSize,
      centerButtonBackgroundColor: centerButtonBackgroundColor ?? this.centerButtonBackgroundColor,
      chromeIconSize: chromeIconSize ?? this.chromeIconSize,
      topBarPadding: topBarPadding ?? this.topBarPadding,
      bottomBarPadding: bottomBarPadding ?? this.bottomBarPadding,
      timeTextStyle: timeTextStyle ?? this.timeTextStyle,
      scrubberActiveColor: scrubberActiveColor ?? this.scrubberActiveColor,
      scrubberBufferedColor: scrubberBufferedColor ?? this.scrubberBufferedColor,
      scrubberInactiveColor: scrubberInactiveColor ?? this.scrubberInactiveColor,
      scrubberThumbColor: scrubberThumbColor ?? this.scrubberThumbColor,
      scrubberThumbShadowColor: scrubberThumbShadowColor ?? this.scrubberThumbShadowColor,
      scrubberTrackHeight: scrubberTrackHeight ?? this.scrubberTrackHeight,
      scrubberActiveTrackHeight: scrubberActiveTrackHeight ?? this.scrubberActiveTrackHeight,
      scrubberThumbRadius: scrubberThumbRadius ?? this.scrubberThumbRadius,
      scrubberActiveThumbRadius: scrubberActiveThumbRadius ?? this.scrubberActiveThumbRadius,
      menuBackgroundColor: menuBackgroundColor ?? this.menuBackgroundColor,
      menuBorderRadius: menuBorderRadius ?? this.menuBorderRadius,
      menuContentPadding: menuContentPadding ?? this.menuContentPadding,
      menuMinVerticalPadding: menuMinVerticalPadding ?? this.menuMinVerticalPadding,
      menuItemTextStyle: menuItemTextStyle ?? this.menuItemTextStyle,
      menuIconSize: menuIconSize ?? this.menuIconSize,
      hudBackgroundColor: hudBackgroundColor ?? this.hudBackgroundColor,
      hudBorderRadius: hudBorderRadius ?? this.hudBorderRadius,
      hudPadding: hudPadding ?? this.hudPadding,
      hudIconSize: hudIconSize ?? this.hudIconSize,
      hudIconGap: hudIconGap ?? this.hudIconGap,
      hudTextStyle: hudTextStyle ?? this.hudTextStyle,
    );
  }

  @override
  VideoPlayerTheme lerp(ThemeExtension<VideoPlayerTheme>? other, double t) {
    if (other is! VideoPlayerTheme) {
      return this;
    }
    return VideoPlayerTheme(
      foregroundColor: Color.lerp(foregroundColor, other.foregroundColor, t) ?? foregroundColor,
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t) ?? backgroundColor,
      centerControlsSpacing:
          lerpDouble(centerControlsSpacing, other.centerControlsSpacing, t) ??
          centerControlsSpacing,
      centerPlayButtonIconSize:
          lerpDouble(centerPlayButtonIconSize, other.centerPlayButtonIconSize, t) ??
          centerPlayButtonIconSize,
      centerSkipButtonIconSize:
          lerpDouble(centerSkipButtonIconSize, other.centerSkipButtonIconSize, t) ??
          centerSkipButtonIconSize,
      centerButtonBackgroundColor:
          Color.lerp(centerButtonBackgroundColor, other.centerButtonBackgroundColor, t) ??
          centerButtonBackgroundColor,
      chromeIconSize: lerpDouble(chromeIconSize, other.chromeIconSize, t) ?? chromeIconSize,
      topBarPadding: EdgeInsets.lerp(topBarPadding, other.topBarPadding, t) ?? topBarPadding,
      bottomBarPadding:
          EdgeInsets.lerp(bottomBarPadding, other.bottomBarPadding, t) ?? bottomBarPadding,
      timeTextStyle: TextStyle.lerp(timeTextStyle, other.timeTextStyle, t) ?? timeTextStyle,
      scrubberActiveColor:
          Color.lerp(scrubberActiveColor, other.scrubberActiveColor, t) ?? scrubberActiveColor,
      scrubberBufferedColor:
          Color.lerp(scrubberBufferedColor, other.scrubberBufferedColor, t) ??
          scrubberBufferedColor,
      scrubberInactiveColor:
          Color.lerp(scrubberInactiveColor, other.scrubberInactiveColor, t) ??
          scrubberInactiveColor,
      scrubberThumbColor:
          Color.lerp(scrubberThumbColor, other.scrubberThumbColor, t) ?? scrubberThumbColor,
      scrubberThumbShadowColor:
          Color.lerp(scrubberThumbShadowColor, other.scrubberThumbShadowColor, t) ??
          scrubberThumbShadowColor,
      scrubberTrackHeight:
          lerpDouble(scrubberTrackHeight, other.scrubberTrackHeight, t) ?? scrubberTrackHeight,
      scrubberActiveTrackHeight:
          lerpDouble(scrubberActiveTrackHeight, other.scrubberActiveTrackHeight, t) ??
          scrubberActiveTrackHeight,
      scrubberThumbRadius:
          lerpDouble(scrubberThumbRadius, other.scrubberThumbRadius, t) ?? scrubberThumbRadius,
      scrubberActiveThumbRadius:
          lerpDouble(scrubberActiveThumbRadius, other.scrubberActiveThumbRadius, t) ??
          scrubberActiveThumbRadius,
      menuBackgroundColor:
          Color.lerp(menuBackgroundColor, other.menuBackgroundColor, t) ?? menuBackgroundColor,
      menuBorderRadius:
          BorderRadius.lerp(menuBorderRadius, other.menuBorderRadius, t) ?? menuBorderRadius,
      menuContentPadding:
          EdgeInsets.lerp(menuContentPadding, other.menuContentPadding, t) ?? menuContentPadding,
      menuMinVerticalPadding:
          lerpDouble(menuMinVerticalPadding, other.menuMinVerticalPadding, t) ??
          menuMinVerticalPadding,
      menuItemTextStyle:
          TextStyle.lerp(menuItemTextStyle, other.menuItemTextStyle, t) ?? menuItemTextStyle,
      menuIconSize: lerpDouble(menuIconSize, other.menuIconSize, t) ?? menuIconSize,
      hudBackgroundColor:
          Color.lerp(hudBackgroundColor, other.hudBackgroundColor, t) ?? hudBackgroundColor,
      hudBorderRadius:
          BorderRadius.lerp(hudBorderRadius, other.hudBorderRadius, t) ?? hudBorderRadius,
      hudPadding: EdgeInsets.lerp(hudPadding, other.hudPadding, t) ?? hudPadding,
      hudIconSize: lerpDouble(hudIconSize, other.hudIconSize, t) ?? hudIconSize,
      hudIconGap: lerpDouble(hudIconGap, other.hudIconGap, t) ?? hudIconGap,
      hudTextStyle: TextStyle.lerp(hudTextStyle, other.hudTextStyle, t) ?? hudTextStyle,
    );
  }
}
