/// Controls which horizontal side adjusts screen brightness vs. audio volume
/// during fullscreen landscape vertical swipe gestures.
enum FullscreenGestureSideMapping {
  /// Left edge adjusts screen brightness; right edge adjusts audio volume.
  leftBrightnessRightVolume,

  /// Left edge adjusts audio volume; right edge adjusts screen brightness.
  leftVolumeRightBrightness;

  /// Whether the left vertical swipe zone controls screen brightness.
  bool get isLeftBrightness => this == FullscreenGestureSideMapping.leftBrightnessRightVolume;

  /// Whether the left vertical swipe zone controls audio volume.
  bool get isLeftVolume => this == FullscreenGestureSideMapping.leftVolumeRightBrightness;

  /// Whether the right vertical swipe zone controls screen brightness.
  bool get isRightBrightness => this == FullscreenGestureSideMapping.leftVolumeRightBrightness;

  /// Whether the right vertical swipe zone controls audio volume.
  bool get isRightVolume => this == FullscreenGestureSideMapping.leftBrightnessRightVolume;
}
