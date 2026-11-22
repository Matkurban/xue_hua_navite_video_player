/// 根据运行平台条件导出本地投屏 HTTP 代理服务（IO 平台提供局域网文件服务，其他平台使用桩实现）。
///
/// Conditionally exports the local cast HTTP server for IO vs. non-IO platforms.
library;

export 'local_cast_http_server_stub.dart' if (dart.library.io) 'local_cast_http_server_io.dart';
