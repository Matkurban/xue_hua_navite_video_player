import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'video_player_design_style.dart';

/// 视频播放器外观主题扩展配置（注册到 `ThemeData.extensions` 或传入 `VideoPlayer.theme`）。
///
/// Theme extension configuring visual appearance for the video player.
@immutable
class VideoPlayerTheme extends ThemeExtension<VideoPlayerTheme> {
  /// 默认控件使用的设计语言（`material`、`cupertino` 或 `adaptive`）。
  ///
  /// Design language used by default player controls (`material`, `cupertino`, `adaptive`).
  final VideoPlayerDesignStyle designStyle;

  /// 浮层图标与文字的前景色。
  ///
  /// Foreground color for overlay glyphs and text.
  final Color foregroundColor;

  /// 视频画面背后的背景底色。
  ///
  /// Background color behind the video frame.
  final Color backgroundColor;

  /// 中央三个控制按钮（快退 / 播放 / 快进）之间的水平间距。
  ///
  /// Horizontal spacing between the three center transport buttons.
  final double centerControlsSpacing;

  /// 中央播放/暂停主按钮图标尺寸。
  ///
  /// Icon size of the central play/pause button.
  final double centerPlayButtonIconSize;

  /// 中央快进/快退按钮图标尺寸。
  ///
  /// Icon size of the skip forward/backward buttons.
  final double centerSkipButtonIconSize;

  /// 中央按钮与锁屏按钮的圆形背景色。
  ///
  /// Background color for center transport and lock buttons.
  final Color centerButtonBackgroundColor;

  /// 顶栏与底栏控制图标尺寸（静音、全屏、锁屏等）。
  ///
  /// Icon size for top/bottom chrome controls (mute, fullscreen, lock, etc.).
  final double chromeIconSize;

  /// 顶栏内边距。
  ///
  /// Inset padding of the top bar.
  final EdgeInsets topBarPadding;

  /// 底部进度条区域内边距。
  ///
  /// Inset padding of the bottom scrubber row.
  final EdgeInsets bottomBarPadding;

  /// 进度条两侧当前时间与总时长文本样式。
  ///
  /// Text style of the time labels flanking the scrubber.
  final TextStyle timeTextStyle;

  /// 进度条已播放段颜色。
  ///
  /// Active (played) segment color.
  final Color scrubberActiveColor;

  /// 进度条已缓冲段颜色。
  ///
  /// Buffered segment color.
  final Color scrubberBufferedColor;

  /// 进度条未播放轨道颜色。
  ///
  /// Inactive (unplayed) track color.
  final Color scrubberInactiveColor;

  /// 进度条拖动滑块颜色。
  ///
  /// Scrubber thumb color.
  final Color scrubberThumbColor;

  /// 进度条滑块底部柔和阴影颜色。
  ///
  /// Soft shadow drawn under the scrubber thumb.
  final Color scrubberThumbShadowColor;

  /// 进度条静息态轨道高度。
  ///
  /// Scrubber track thickness at rest.
  final double scrubberTrackHeight;

  /// 进度条拖动激活态轨道高度。
  ///
  /// Scrubber track thickness while scrubbing.
  final double scrubberActiveTrackHeight;

  /// 进度条静息态滑块半径。
  ///
  /// Scrubber thumb radius at rest.
  final double scrubberThumbRadius;

  /// 进度条按下或拖动时的滑块半径。
  ///
  /// Scrubber thumb radius while pressing or dragging.
  final double scrubberActiveThumbRadius;

  /// 弹出菜单面板背景色。
  ///
  /// Popup menu panel background color.
  final Color menuBackgroundColor;

  /// 弹出菜单面板圆角半径。
  ///
  /// Popup menu corner radius.
  final BorderRadius menuBorderRadius;

  /// 弹出菜单选项横向内边距。
  ///
  /// Horizontal padding inside menu list tiles.
  final EdgeInsets menuContentPadding;

  /// 弹出菜单选项最小纵向内边距。
  ///
  /// Minimum vertical padding inside menu list tiles.
  final double menuMinVerticalPadding;

  /// 弹出菜单项文字样式。
  ///
  /// Menu item title text style.
  final TextStyle menuItemTextStyle;

  /// 弹出菜单前置/尾随图标尺寸。
  ///
  /// Menu leading/trailing icon size.
  final double menuIconSize;

  /// 手势实时指示器 HUD 面板背景色。
  ///
  /// Gesture HUD panel background color.
  final Color hudBackgroundColor;

  /// 手势实时指示器 HUD 圆角半径。
  ///
  /// Gesture HUD corner radius.
  final BorderRadius hudBorderRadius;

  /// 手势实时指示器 HUD 内边距。
  ///
  /// Gesture HUD inner padding.
  final EdgeInsets hudPadding;

  /// 手势实时指示器 HUD 图标尺寸。
  ///
  /// Gesture HUD icon size.
  final double hudIconSize;

  /// 手势 HUD 图标与标签之间的间距。
  ///
  /// Gap between HUD icon and label.
  final double hudIconGap;

  /// 手势 HUD 文本标签样式。
  ///
  /// Gesture HUD label text style.
  final TextStyle hudTextStyle;

  /// Cupertino 毛玻璃浮层的高斯模糊半径。
  ///
  /// Gaussian blur sigma applied to Cupertino translucent chrome surfaces.
  final double backdropBlurSigma;

  /// Cupertino 半透明控制栏与胶囊的背景色。
  ///
  /// Background color for Cupertino translucent control bars and pills.
  final Color barBackgroundColor;

  /// Cupertino 半透明控制栏与胶囊的圆角半径。
  ///
  /// Corner radius for Cupertino translucent control bars and pills.
  final BorderRadius barBorderRadius;

  /// 创建自定义播放器主题配置。
  ///
  /// Creates a customizable [VideoPlayerTheme].
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

  /// 创建按平台自适应的预设主题：iOS/macOS 返回 [VideoPlayerTheme.cupertino]，其余平台返回 [VideoPlayerTheme.material]。
  ///
  /// Creates an adaptive theme resolving to [VideoPlayerTheme.cupertino] on
  /// iOS / macOS and [VideoPlayerTheme.material] on other platforms.
  factory VideoPlayerTheme.adaptive([TargetPlatform? platform]) {
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.iOS || target == TargetPlatform.macOS) {
      return const VideoPlayerTheme.cupertino();
    }
    return const VideoPlayerTheme.material();
  }

  /// 当前主题在 [defaultTargetPlatform] 下是否解析为 Cupertino 风格。
  ///
  /// Whether this theme resolves to Cupertino design on [defaultTargetPlatform].
  bool get isCupertino => designStyle.isCupertino();

  /// 结合 `Theme.of(context).platform` 判断当前子树是否应按 Cupertino 风格渲染。
  ///
  /// Whether this theme resolves to Cupertino design respecting `Theme.of(context).platform`.
  bool isCupertinoFor(BuildContext context) {
    return designStyle.isCupertino(Theme.of(context).platform);
  }

  /// 从 [context] 读取已注册的 [VideoPlayerTheme]；未注册时回退至平台自适应默认主题。
  ///
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
