/// 控制全屏横屏播放时左右两侧垂直滑动手势分别调节亮度还是音量。
///
/// Controls which horizontal side adjusts screen brightness vs. audio volume
/// during fullscreen landscape vertical swipe gestures.
enum FullscreenGestureSideMapping {
  /// 左侧区域调节屏幕亮度，右侧区域调节播放音量（默认）。
  ///
  /// Left edge adjusts screen brightness; right edge adjusts audio volume (default).
  leftBrightnessRightVolume,

  /// 左侧区域调节播放音量，右侧区域调节屏幕亮度。
  ///
  /// Left edge adjusts audio volume; right edge adjusts screen brightness.
  leftVolumeRightBrightness;

  /// 左侧垂直滑动热区是否用于调节屏幕亮度。
  ///
  /// Whether the left vertical swipe zone controls screen brightness.
  bool get isLeftBrightness => this == FullscreenGestureSideMapping.leftBrightnessRightVolume;

  /// 左侧垂直滑动热区是否用于调节播放音量。
  ///
  /// Whether the left vertical swipe zone controls audio volume.
  bool get isLeftVolume => this == FullscreenGestureSideMapping.leftVolumeRightBrightness;

  /// 右侧垂直滑动热区是否用于调节屏幕亮度。
  ///
  /// Whether the right vertical swipe zone controls screen brightness.
  bool get isRightBrightness => this == FullscreenGestureSideMapping.leftVolumeRightBrightness;

  /// 右侧垂直滑动热区是否用于调节播放音量。
  ///
  /// Whether the right vertical swipe zone controls audio volume.
  bool get isRightVolume => this == FullscreenGestureSideMapping.leftBrightnessRightVolume;
}
