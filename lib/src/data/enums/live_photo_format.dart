/// 动态照片（Live Photo / Motion Photo）的容器与编码格式类型。
///
/// Container and encoding format of a Live Photo / Motion Photo.
enum LivePhotoFormat {
  /// 双文件配对格式（静态图片 + 独立短视频，如 Apple iOS/macOS Live Photo、`.pvt` 包或云端配对 URL）。
  ///
  /// Paired still image + companion video file/URL (e.g. Apple Live Photo or `.pvt` bundle).
  paired,

  /// Google Camera MicroVideo XMP 单文件动态照片（`GCamera:MicroVideoOffset`）。
  ///
  /// Single-file JPEG/HEIC using Google Camera `GCamera:MicroVideoOffset` XMP metadata.
  gcameraMicroVideo,

  /// Android / Google Motion Photo 1.0 XMP Container 单文件动态照片（`Container:Item` `MotionPhoto`）。
  ///
  /// Single-file JPEG/HEIC/AVIF using Android Motion Photo 1.0 `Container:Directory` XMP metadata.
  androidMotionPhoto,

  /// Samsung Motion Photo 单文件动态照片（包含 `MotionPhoto_Data` 标记与内嵌 MP4）。
  ///
  /// Single-file Samsung Motion Photo containing the `MotionPhoto_Data` marker.
  samsungMotionPhoto,

  /// 通用单文件内嵌 MP4/QuickTime 视频流动态照片（图像流尾部拼接 ISO BMFF `ftyp` 视频流）。
  ///
  /// Generic single-file image with an appended ISO BMFF (`ftyp`) MP4/MOV video stream.
  embeddedMp4,

  /// Apple Live Photo 静帧容器（HEIC `MiPr`）或 vivo 导出的 Live Photo 静帧。
  ///
  /// 文件本身通常不含可抽取的 motion 视频轨（配对 `.MOV` 可能缺失）；插件会尝试
  /// 从静帧合成短视频，或走 Flutter Ken Burns 动效，避免把 HEIC 当视频硬开导致黑屏。
  ///
  /// Apple Live Photo still container (`MiPr`) / vivo-exported Live Photo still.
  appleLivePhoto,

  /// 未知或非动态照片。
  ///
  /// Unknown or not a Live Photo / Motion Photo.
  unknown;

  /// Wire name used for serialization.
  String get wireName => name;

  /// Whether this format represents a single-file embedded Motion Photo.
  bool get isSingleFile => switch (this) {
    LivePhotoFormat.gcameraMicroVideo ||
    LivePhotoFormat.androidMotionPhoto ||
    LivePhotoFormat.samsungMotionPhoto ||
    LivePhotoFormat.embeddedMp4 => true,
    LivePhotoFormat.paired || LivePhotoFormat.appleLivePhoto || LivePhotoFormat.unknown => false,
  };

  /// Parses [LivePhotoFormat] from a serialized wire string.
  static LivePhotoFormat fromWire(String? raw) {
    return switch (raw) {
      'paired' => LivePhotoFormat.paired,
      'gcameraMicroVideo' => LivePhotoFormat.gcameraMicroVideo,
      'androidMotionPhoto' => LivePhotoFormat.androidMotionPhoto,
      'samsungMotionPhoto' => LivePhotoFormat.samsungMotionPhoto,
      'embeddedMp4' => LivePhotoFormat.embeddedMp4,
      'appleLivePhoto' => LivePhotoFormat.appleLivePhoto,
      _ => LivePhotoFormat.unknown,
    };
  }
}
