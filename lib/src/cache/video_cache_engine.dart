/// 根据运行平台条件导出媒体缓存引擎（IO 平台、Web 平台与兜底桩实现）。
///
/// Conditionally exports the platform video cache engine for IO, Web, and stub targets.
library;

export 'video_cache_engine_stub.dart'
    if (dart.library.io) 'video_cache_engine_io.dart'
    if (dart.library.js_interop) 'video_cache_engine_web.dart';
