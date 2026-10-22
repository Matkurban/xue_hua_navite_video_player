import 'dart:js_interop';

import 'package:web/web.dart' as html;

/// JS interop extensions for HTML5 `<video>` remote playback (W3C Remote Playback API & Safari AirPlay).
extension HTMLVideoRemotePlaybackExt on html.HTMLVideoElement {
  @JS('remote')
  external JSRemotePlayback? get remotePlayback;

  @JS('webkitShowPlaybackTargetPicker')
  external JSFunction? get webkitShowPlaybackTargetPicker;

  @JS('webkitCurrentPlaybackTargetIsWireless')
  external bool? get webkitCurrentPlaybackTargetIsWireless;
}

/// Typed wrapper over the browser's `RemotePlayback` interface.
extension type JSRemotePlayback._(JSObject _) implements JSObject {
  external String get state;
  external JSPromise<JSNumber> watchAvailability(JSFunction callback);
  external JSPromise<JSAny?> prompt();
  external void addEventListener(String type, JSFunction listener);
}
