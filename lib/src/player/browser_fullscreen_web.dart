import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser Fullscreen API over the Flutter document root (not the `<video>`).
class BrowserFullscreen {
  BrowserFullscreen._();

  static final StreamController<bool> _changes = StreamController<bool>.broadcast();
  static bool _listening = false;

  static Stream<bool> get changes {
    _ensureListening();
    return _changes.stream;
  }

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
