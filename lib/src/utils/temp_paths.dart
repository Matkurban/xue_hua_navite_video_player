/// 根据运行平台条件导出临时目录与本地文件读写辅助方法（IO 平台与 Web 桩实现）。
///
/// Conditionally exports temporary directory and file I/O helpers for IO vs. non-IO platforms.
library;

export 'temp_paths_stub.dart' if (dart.library.io) 'temp_paths_io.dart';
