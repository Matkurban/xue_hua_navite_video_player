import 'package:material_ui/material_ui.dart';

/// 动态照片角标（`LIVE` / `实况`）的摆放位置。
///
/// Corner placement for the Live Photo badge overlay inside the player.
enum LivePhotoBadgePosition {
  /// 左上角（iOS 系统相册默认位置）。
  ///
  /// Top-left corner (default placement in Apple Photos).
  topLeft,

  /// 右上角。
  ///
  /// Top-right corner.
  topRight,

  /// 左下角。
  ///
  /// Bottom-left corner.
  bottomLeft,

  /// 右下角。
  ///
  /// Bottom-right corner.
  bottomRight;

  /// 将当前角标位置转换为 Flutter [Alignment] 对齐方式。
  ///
  /// Converts this badge position into a Flutter [Alignment].
  Alignment get alignment => switch (this) {
    LivePhotoBadgePosition.topLeft => Alignment.topLeft,
    LivePhotoBadgePosition.topRight => Alignment.topRight,
    LivePhotoBadgePosition.bottomLeft => Alignment.bottomLeft,
    LivePhotoBadgePosition.bottomRight => Alignment.bottomRight,
  };
}
