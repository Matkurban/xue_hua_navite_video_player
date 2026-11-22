import 'dart:js_interop';

import 'package:web/web.dart' as html;

/// HTML5 `<video>` 远端投屏相关的 JS 互操作扩展（W3C Remote Playback API 与 Safari AirPlay）。
///
/// JS interop extensions for HTML5 `<video>` remote playback (W3C Remote Playback API & Safari AirPlay).
extension HTMLVideoRemotePlaybackExt on html.HTMLVideoElement {
  /// W3C `video.remote` 接口句柄（浏览器不支持时为 `null`）。
  ///
  /// W3C `video.remote` handle (`null` when unsupported by the browser).
  @JS('remote')
  external JSRemotePlayback? get remotePlayback;

  /// Safari 专有的 AirPlay 设备选择器唤起函数。
  ///
  /// Safari-specific function to present the AirPlay playback target picker.
  @JS('webkitShowPlaybackTargetPicker')
  external JSFunction? get webkitShowPlaybackTargetPicker;

  /// Safari 专有的无线投屏激活状态标志。
  ///
  /// Safari-specific flag indicating whether wireless playback is active.
  @JS('webkitCurrentPlaybackTargetIsWireless')
  external bool? get webkitCurrentPlaybackTargetIsWireless;
}

/// 浏览器 `RemotePlayback` 接口的强类型 JS 包装。
///
/// Typed JS interop wrapper over the browser's `RemotePlayback` interface.
extension type JSRemotePlayback._(JSObject _) implements JSObject {
  /// 当前远端连接状态字符串（`'disconnected'`、`'connecting'`、`'connected'`）。
  ///
  /// Current remote connection state (`'disconnected'`, `'connecting'`, `'connected'`).
  external String get state;

  /// 监听局域网可用远端投屏设备的可用性变化。
  ///
  /// Watches availability of remote playback devices and invokes [callback].
  external JSPromise<JSNumber> watchAvailability(JSFunction callback);

  /// 弹出浏览器原生的投屏设备选择器。
  ///
  /// Prompts the user to select or manage a remote playback device.
  external JSPromise<JSAny?> prompt();

  /// 注册远端投屏生命周期事件监听器（如 `connecting`、`connect`、`disconnect`）。
  ///
  /// Registers an event [listener] for the specified event [type].
  external void addEventListener(String type, JSFunction listener);
}
