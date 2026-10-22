import 'package:flutter/foundation.dart';

/// 播放器 UI 主题设计风格枚举。
///
/// The design style of the video player UI chrome.
enum VideoPlayerDesignStyle {
  /// Google Material Design 3 风格（水波纹反馈、圆形加载器、Material 图标体系）。
  material,

  /// Apple iOS / macOS Cupertino 风格（按压透明度渐变、菊花指示器、毛玻璃胶囊浮层、SF 风格图标）。
  cupertino,

  /// 根据当前运行平台自动适配（iOS / macOS 使用 [cupertino]，其余平台使用 [material]）。
  adaptive;

  /// 根据给定的 [platform]（默认读取 [defaultTargetPlatform]）解析实际生效的风格。
  ///
  /// Resolves [adaptive] into either [material] or [cupertino] based on [platform].
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

  /// 当前风格解析后是否为 Cupertino 样式。
  ///
  /// Whether this style resolves to [VideoPlayerDesignStyle.cupertino].
  bool isCupertino([TargetPlatform? platform]) {
    return resolve(platform) == VideoPlayerDesignStyle.cupertino;
  }
}
