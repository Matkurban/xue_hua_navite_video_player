/// 根据运行平台条件导出桥接环境检测工具（IO 平台使用 `bridge_env_io.dart`，其他平台使用桩实现）。
///
/// Conditionally exports the bridge environment helpers for IO vs. non-IO platforms.
library;

export 'bridge_env_stub.dart' if (dart.library.io) 'bridge_env_io.dart';
