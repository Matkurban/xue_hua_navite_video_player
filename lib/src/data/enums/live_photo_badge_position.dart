import 'package:material_ui/material_ui.dart';

/// 动态照片角标（`LIVE` / `实况`）的摆放位置。
///
/// Corner placement for the [LivePhotoBadge] overlay inside [LivePhotoPlayer].
enum LivePhotoBadgePosition {
  /// 左上角（iOS 相册默认位置）。
  topLeft,

  /// 右上角。
  topRight,

  /// 左下角。
  bottomLeft,

  /// 右下角。
  bottomRight;

  /// Converts this badge position into an [Alignment].
  Alignment get alignment => switch (this) {
    LivePhotoBadgePosition.topLeft => Alignment.topLeft,
    LivePhotoBadgePosition.topRight => Alignment.topRight,
    LivePhotoBadgePosition.bottomLeft => Alignment.bottomLeft,
    LivePhotoBadgePosition.bottomRight => Alignment.bottomRight,
  };
}
