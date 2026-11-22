/// 画面适应模式（原生侧直传各平台官方缩放属性）。
///
/// Video display fit mode mapped to each platform's native scaling property.
enum AspectRatioMode {
  /// 适应模式：保持原始宽高比完整显示画面，可能出现上下或左右黑边（letterbox / pillarbox）。
  ///
  /// Fit mode: preserves the aspect ratio and fits the entire frame inside the
  /// viewport, adding letterbox or pillarbox bars as needed.
  fit,

  /// 铺满模式：保持原始宽高比并居中裁切，使画面完全填满容器。
  ///
  /// Fill mode: preserves the aspect ratio and center-crops to completely fill
  /// the viewport.
  fill,

  /// 拉伸模式：忽略原始宽高比，强制将画面拉伸至铺满整个容器。
  ///
  /// Stretch mode: ignores the aspect ratio and stretches the frame to fill
  /// the entire viewport.
  stretch;

  /// 用于原生桥接通信的协议字符串名称（`'fit'`、`'fill'` 或 `'stretch'`）。
  ///
  /// Wire string name used across the native bridge (`'fit'`, `'fill'`, or `'stretch'`).
  String get wireName => name;

  /// 从原生端传回的协议字符串解析对应的 [AspectRatioMode]。
  ///
  /// Parses an [AspectRatioMode] from a serialized wire string.
  ///
  /// - [value]：协议字符串（`'fit'`、`'fill'`、`'stretch'` 或 `null`）。
  ///   Serialized wire string (`'fit'`, `'fill'`, `'stretch'`, or `null`).
  ///
  /// 返回值 / Returns：匹配到的 [AspectRatioMode]；未知值或 `null` 默认回退为 [AspectRatioMode.fit]。
  /// The matching [AspectRatioMode], falling back to [AspectRatioMode.fit] for
  /// unknown values or `null`.
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
