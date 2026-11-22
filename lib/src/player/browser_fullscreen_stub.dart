import 'dart:async';

/// 非 Web 平台浏览器全屏接口空实现占位（浏览器 Fullscreen API 仅在 Web 生效）。
///
/// VM / native stub — the browser Fullscreen API is Web-only.
class BrowserFullscreen {
  BrowserFullscreen._();

  /// 浏览器全屏状态变化事件流（非 Web 平台恒为空流）。
  ///
  /// Stream of browser fullscreen state changes (empty on non-Web platforms).
  static Stream<bool> get changes => const Stream<bool>.empty();

  /// 请求进入浏览器全屏（非 Web 平台为空操作）。
  ///
  /// Requests browser fullscreen (no-op on non-Web platforms).
  static Future<void> enter() async {}

  /// 退出浏览器全屏（非 Web 平台为空操作）。
  ///
  /// Exits browser fullscreen (no-op on non-Web platforms).
  static Future<void> exit() async {}
}
