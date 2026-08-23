import 'dart:async';

/// VM / native stub — browser Fullscreen API is web-only.
class BrowserFullscreen {
  BrowserFullscreen._();

  static Stream<bool> get changes => const Stream<bool>.empty();

  static Future<void> enter() async {}

  static Future<void> exit() async {}
}
