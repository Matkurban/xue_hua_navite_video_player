import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'video_player_design_style.dart';

/// The theme configuration for the video player.
@immutable
class VideoPlayerTheme extends ThemeExtension<VideoPlayerTheme> {
  /// Design language used by default player controls (`material`, `cupertino`, `adaptive`).
  final VideoPlayerDesignStyle designStyle;

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

  /// Gaussian blur sigma applied to Cupertino translucent chrome surfaces.
  final double backdropBlurSigma;

  /// Background color for Cupertino translucent control bars / pills.
  final Color barBackgroundColor;

  /// Corner radius for Cupertino translucent control bars / pills.
  final BorderRadius barBorderRadius;

  const VideoPlayerTheme({
    this.designStyle = VideoPlayerDesignStyle.adaptive,
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.centerControlsSpacing = 48,
    this.centerPlayButtonIconSize = 24,
    this.centerSkipButtonIconSize = 22,
    this.centerButtonBackgroundColor = const Color(0x4D000000), // Colors.black38
    this.chromeIconSize = 20,
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
    this.menuIconSize = 20,
    this.hudBackgroundColor = const Color(0xB3000000), // black 0.7
    this.hudBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.hudPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.hudIconSize = 20,
    this.hudIconGap = 8,
    this.hudTextStyle = const TextStyle(color: Colors.white, fontSize: 16),
    this.backdropBlurSigma = 18.0,
    this.barBackgroundColor = const Color(0x591C1C1E),
    this.barBorderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  /// Material Design 3 preset theme.
  const VideoPlayerTheme.material({
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.centerControlsSpacing = 48,
    this.centerPlayButtonIconSize = 28,
    this.centerSkipButtonIconSize = 24,
    this.centerButtonBackgroundColor = const Color(0x59000000),
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
    this.scrubberBufferedColor = const Color(0x99FFFFFF),
    this.scrubberInactiveColor = const Color(0x38FFFFFF),
    this.scrubberThumbColor = Colors.white,
    this.scrubberThumbShadowColor = const Color(0x40000000),
    this.scrubberTrackHeight = 3.0,
    this.scrubberActiveTrackHeight = 6.0,
    this.scrubberThumbRadius = 6.0,
    this.scrubberActiveThumbRadius = 9.0,
    this.menuBackgroundColor = const Color(0xF21E1E1E),
    this.menuBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.menuContentPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.menuMinVerticalPadding = 6,
    this.menuItemTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    this.menuIconSize = 20,
    this.hudBackgroundColor = const Color(0xCC121212),
    this.hudBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.hudPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.hudIconSize = 22,
    this.hudIconGap = 8,
    this.hudTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    this.backdropBlurSigma = 0.0,
    this.barBackgroundColor = const Color(0x00000000),
    this.barBorderRadius = BorderRadius.zero,
  }) : designStyle = VideoPlayerDesignStyle.material;

  /// Apple Cupertino (iOS / macOS AVPlayerKit-inspired) preset theme.
  const VideoPlayerTheme.cupertino({
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.centerControlsSpacing = 52,
    this.centerPlayButtonIconSize = 28,
    this.centerSkipButtonIconSize = 24,
    this.centerButtonBackgroundColor = const Color(0x591C1C1E),
    this.chromeIconSize = 19,
    this.topBarPadding = const EdgeInsets.fromLTRB(14, 12, 14, 10),
    this.bottomBarPadding = const EdgeInsets.fromLTRB(14, 6, 14, 14),
    this.timeTextStyle = const TextStyle(
      color: Color(0xEBFFFFFF),
      fontSize: 12,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.0,
    ),
    this.scrubberActiveColor = Colors.white,
    this.scrubberBufferedColor = const Color(0x80FFFFFF),
    this.scrubberInactiveColor = const Color(0x33FFFFFF),
    this.scrubberThumbColor = Colors.white,
    this.scrubberThumbShadowColor = const Color(0x59000000),
    this.scrubberTrackHeight = 3.5,
    this.scrubberActiveTrackHeight = 7.0,
    this.scrubberThumbRadius = 5.5,
    this.scrubberActiveThumbRadius = 9.5,
    this.menuBackgroundColor = const Color(0xD9252528),
    this.menuBorderRadius = const BorderRadius.all(Radius.circular(13)),
    this.menuContentPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.menuMinVerticalPadding = 6,
    this.menuItemTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.2,
    ),
    this.menuIconSize = 18,
    this.hudBackgroundColor = const Color(0xB3252528),
    this.hudBorderRadius = const BorderRadius.all(Radius.circular(14)),
    this.hudPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.hudIconSize = 20,
    this.hudIconGap = 8,
    this.hudTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    this.backdropBlurSigma = 20.0,
    this.barBackgroundColor = const Color(0x591C1C1E),
    this.barBorderRadius = const BorderRadius.all(Radius.circular(14)),
  }) : designStyle = VideoPlayerDesignStyle.cupertino;

  /// Creates an adaptive theme that resolves to [VideoPlayerTheme.cupertino] on
  /// iOS / macOS and [VideoPlayerTheme.material] on other platforms.
  factory VideoPlayerTheme.adaptive([TargetPlatform? platform]) {
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.iOS || target == TargetPlatform.macOS) {
      return const VideoPlayerTheme.cupertino();
    }
    return const VideoPlayerTheme.material();
  }

  /// Whether this theme resolves to Cupertino design on the active platform.
  bool get isCupertino => designStyle.isCupertino();

  /// Resolves [VideoPlayerTheme] from [context], falling back to platform-adaptive defaults.
  static VideoPlayerTheme of(BuildContext context) {
    final ext = Theme.of(context).extension<VideoPlayerTheme>();
    if (ext != null) {
      return ext;
    }
    return VideoPlayerTheme.adaptive(Theme.of(context).platform);
  }

  @override
  VideoPlayerTheme copyWith({
    VideoPlayerDesignStyle? designStyle,
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
    double? backdropBlurSigma,
    Color? barBackgroundColor,
    BorderRadius? barBorderRadius,
  }) {
    return VideoPlayerTheme(
      designStyle: designStyle ?? this.designStyle,
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
      backdropBlurSigma: backdropBlurSigma ?? this.backdropBlurSigma,
      barBackgroundColor: barBackgroundColor ?? this.barBackgroundColor,
      barBorderRadius: barBorderRadius ?? this.barBorderRadius,
    );
  }

  @override
  VideoPlayerTheme lerp(ThemeExtension<VideoPlayerTheme>? other, double t) {
    if (other is! VideoPlayerTheme) {
      return this;
    }
    return VideoPlayerTheme(
      designStyle: t < 0.5 ? designStyle : other.designStyle,
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
      backdropBlurSigma:
          lerpDouble(backdropBlurSigma, other.backdropBlurSigma, t) ?? backdropBlurSigma,
      barBackgroundColor:
          Color.lerp(barBackgroundColor, other.barBackgroundColor, t) ?? barBackgroundColor,
      barBorderRadius:
          BorderRadius.lerp(barBorderRadius, other.barBorderRadius, t) ?? barBorderRadius,
    );
  }
}
