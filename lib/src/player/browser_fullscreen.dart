/// 根据运行平台条件导出浏览器全屏协调实现（Web 平台使用 Fullscreen API，其他平台使用桩实现）。
///
/// Conditionally exports the browser fullscreen implementation for Web vs. non-Web platforms.
library;

export 'browser_fullscreen_stub.dart' if (dart.library.js_interop) 'browser_fullscreen_web.dart';
