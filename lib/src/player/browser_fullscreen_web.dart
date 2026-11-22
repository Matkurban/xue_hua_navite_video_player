import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 基于浏览器 Fullscreen API 的 Web 全屏控制器（作用于 Flutter 文档根节点而非 `<video>`）。
///
/// Browser Fullscreen API helper targeting the Flutter document root (not `<video>`).
class BrowserFullscreen {
  BrowserFullscreen._();

  static final StreamController<bool> _changes = StreamController<bool>.broadcast();
  static bool _listening = false;

  /// 浏览器全屏状态变更事件流（`true` 表示已进入全屏，`false` 表示已退出）。
  ///
  /// Broadcast stream emitting `true` on entering browser fullscreen and `false` on exit.
  static Stream<bool> get changes {
    _ensureListening();
    return _changes.stream;
  }

  /// 请求将当前文档根节点切换为浏览器全屏。
  ///
  /// Requests browser fullscreen on `document.documentElement`.
  static Future<void> enter() {
    _ensureListening();
    final el = web.document.documentElement;
    if (el == null || web.document.fullscreenElement != null) {
      return Future<void>.value();
    }
    try {
      return el.requestFullscreen().toDart.then<void>((_) {});
    } catch (_) {
      return Future<void>.value();
    }
  }

  /// 退出当前浏览器全屏状态。
  ///
  /// Exits browser fullscreen if currently active.
  static Future<void> exit() {
    _ensureListening();
    if (web.document.fullscreenElement == null) {
      return Future<void>.value();
    }
    try {
      return web.document.exitFullscreen().toDart.then<void>((_) {});
    } catch (_) {
      return Future<void>.value();
    }
  }

  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    web.document.addEventListener(
      'fullscreenchange',
      (web.Event _) {
        if (!_changes.isClosed) {
          _changes.add(web.document.fullscreenElement != null);
        }
      }.toJS,
    );
  }
}
