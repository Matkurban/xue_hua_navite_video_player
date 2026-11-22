/// 根据运行平台条件导出 Flutter Asset 临时文件抽取器（IO 平台支持落盘抽取，Web 平台为桩实现）。
///
/// Conditionally exports the Flutter asset extractor for IO vs. non-IO platforms.
library;

export 'asset_extractor_stub.dart' if (dart.library.io) 'asset_extractor_io.dart';
