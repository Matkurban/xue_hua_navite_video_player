/// 画面适应模式（原生侧直传官方属性）。
/// Video display fit mode (mapped to each platform's native property).
enum AspectRatioMode {
  /// 适应 — letterbox / pillarbox，保持比例。
  /// Fit — letterbox while preserving aspect ratio.
  fit,

  /// 铺满 — 等比裁切填满。
  /// Fill — center-crop to fill the view.
  fill,

  /// 拉伸 — 不计比例填满。
  /// Stretch — ignore aspect ratio and fill.
  stretch;

  /// Method-channel wire value.
  String get wireName => name;

  static AspectRatioMode fromWire(String? value) {
    switch (value) {
      case 'fill':
        return AspectRatioMode.fill;
      case 'stretch':
        return AspectRatioMode.stretch;
      case 'fit':
      default:
        return AspectRatioMode.fit;
    }
  }
}
