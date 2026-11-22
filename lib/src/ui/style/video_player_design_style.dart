import 'package:flutter/foundation.dart';

/// 播放器 UI 主题设计风格枚举。
///
/// The design language used by the default video player UI chrome.
enum VideoPlayerDesignStyle {
  /// Google Material Design 3 风格（水波纹反馈、圆形加载器、Material 图标体系）。
  ///
  /// Google Material Design 3 style (ink ripples, circular indicators, Material icons).
  material,

  /// Apple iOS / macOS Cupertino 风格（按压透明度渐变、菊花指示器、毛玻璃胶囊浮层、SF 风格图标）。
  ///
  /// Apple iOS / macOS Cupertino style (opacity fade feedback, frosted glass pills, SF-style icons).
  cupertino,

  /// 根据当前运行平台自动适配（iOS / macOS 使用 [cupertino]，其余平台使用 [material]）。
  ///
  /// Automatically adapts to the host platform ([cupertino] on iOS/macOS, [material] elsewhere).
  adaptive;

  /// 根据给定的 [platform]（默认读取 [defaultTargetPlatform]）解析实际生效的风格。
  ///
  /// Resolves [adaptive] into either [material] or [cupertino] based on [platform].
  ///
  /// - [platform]：目标平台，省略时使用 [defaultTargetPlatform]。Target platform (defaults to [defaultTargetPlatform]).
  ///
  /// 返回值 / Returns：解析后的具体设计风格（[material] 或 [cupertino]）。Resolved concrete style.
  VideoPlayerDesignStyle resolve([TargetPlatform? platform]) {
    if (this != VideoPlayerDesignStyle.adaptive) {
      return this;
    }
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.iOS || target == TargetPlatform.macOS) {
      return VideoPlayerDesignStyle.cupertino;
    }
    return VideoPlayerDesignStyle.material;
  }

  /// 当前风格在指定 [platform] 下解析后是否为 Cupertino 样式。
  ///
  /// Whether this style resolves to [VideoPlayerDesignStyle.cupertino] on [platform].
  ///
  /// - [platform]：目标平台，省略时使用 [defaultTargetPlatform]。Target platform.
  ///
  /// 返回值 / Returns：若解析为 Cupertino 风格则返回 `true`，否则返回 `false`。
  bool isCupertino([TargetPlatform? platform]) {
    return resolve(platform) == VideoPlayerDesignStyle.cupertino;
  }
}
