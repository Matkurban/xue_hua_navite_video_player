/// 根据运行平台条件导出实况照片 / 动态照片提取器（IO 平台、Web 平台与兜底桩实现）。
///
/// Conditionally exports the Live Photo / Motion Photo extractor for IO, Web, and stub targets.
library;

export 'live_photo_extractor_stub.dart'
    if (dart.library.io) 'live_photo_extractor_io.dart'
    if (dart.library.js_interop) 'live_photo_extractor_web.dart';
