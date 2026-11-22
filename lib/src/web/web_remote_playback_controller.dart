import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as html;

import 'web_remote_playback_interop.dart';

/// 浏览器投屏状态变更回调函数签名。
///
/// Callback signature for reporting cast state changes from the browser.
typedef WebCastStateCallback = void Function(String state, {String? deviceName});

/// 负责在 Web 平台协调 W3C Remote Playback API 与 Safari WebKit AirPlay 投屏选择器。
///
/// Coordinates W3C Remote Playback API and Safari WebKit AirPlay target picking
/// for an [html.HTMLVideoElement].
class WebRemotePlaybackController {
  /// 创建 Web 远端投屏控制器。
  ///
  /// Creates a [WebRemotePlaybackController] that reports updates via [onStateChanged].
  WebRemotePlaybackController({required this._onStateChanged});

  final WebCastStateCallback _onStateChanged;
  String _state = 'unavailable';
  String? _deviceName;

  /// 当前投屏协议状态字符串（如 `'unavailable'`、`'notConnected'`、`'connecting'`、`'connected'`）。
  ///
  /// Current cast state string (`'unavailable'`, `'notConnected'`, `'connecting'`, `'connected'`).
  String get state => _state;

  /// 当前连接或连接中的远端设备友好名称（若有）。
  ///
  /// Friendly name of the connected or connecting remote device, if any.
  String? get deviceName => _deviceName;

  /// 重新对外发送一次当前缓存的投屏状态。
  ///
  /// Re-emits the current cached cast state and device name.
  void emitCurrentState() {
    _emit(_state, deviceName: _deviceName);
  }

  void _emit(String state, {String? deviceName}) {
    _state = state;
    _deviceName = deviceName;
    _onStateChanged(state, deviceName: deviceName);
  }

  /// 将浏览器远端投屏事件监听器绑定到指定的 `<video>` 元素（[video]）。
  ///
  /// Attaches W3C Remote Playback or Safari WebKit AirPlay event listeners to [video].
  void attach(html.HTMLVideoElement video) {
    try {
      final remote = video.remotePlayback;
      if (remote != null) {
        _emit('notConnected');

        remote.addEventListener(
          'connecting',
          ((html.Event _) {
            _emit('connecting', deviceName: 'Web Cast');
          }).toJS,
        );

        remote.addEventListener(
          'connect',
          ((html.Event _) {
            _emit('connected', deviceName: 'Web Cast');
          }).toJS,
        );

        remote.addEventListener(
          'disconnect',
          ((html.Event _) {
            // Pause local playback when disconnecting from remote screen.
            video.pause();
            _emit('notConnected');
          }).toJS,
        );

        try {
          remote
              .watchAvailability(
                ((JSBoolean available) {
                  if (_state == 'connected' || _state == 'connecting') {
                    return;
                  }
                  _emit(available.toDart ? 'notConnected' : 'unavailable');
                }).toJS,
              )
              .toDart
              .catchError((Object _) {
                // If watchAvailability is unsupported or disabled, keep 'notConnected'
                // so prompt() can still be invoked by user gesture.
                if (_state == 'unavailable') {
                  _emit('notConnected');
                }
                return 0.toJS;
              });
        } catch (_) {}
        return;
      }

      if (video.webkitShowPlaybackTargetPicker != null) {
        _emit('notConnected');
        video.addEventListener(
          'webkitcurrentplaybacktargetiswirelesschanged',
          ((html.Event _) {
            final wireless = video.webkitCurrentPlaybackTargetIsWireless ?? false;
            if (wireless) {
              _emit('connected', deviceName: 'AirPlay');
            } else {
              video.pause();
              _emit('notConnected');
            }
          }).toJS,
        );
        return;
      }
    } catch (_) {}

    _emit('unavailable');
  }

  /// 唤起浏览器原生的远端投屏或 Safari AirPlay 设备选择器。
  ///
  /// Prompts the browser's native remote playback or Safari AirPlay target picker for [video].
  Future<void> showPicker(html.HTMLVideoElement? video) async {
    if (video == null) return;
    try {
      final remote = video.remotePlayback;
      if (remote != null) {
        await remote.prompt().toDart;
        return;
      }
      final webkitPicker = video.webkitShowPlaybackTargetPicker;
      if (webkitPicker != null) {
        webkitPicker.callAsFunction(video);
      }
    } catch (_) {
      // User cancelled picker or no devices found; keep existing cast state.
    }
  }

  /// 断开当前浏览器远端投屏会话并暂停本地播放。
  ///
  /// Disconnects active remote playback on [video] and pauses local playback.
  Future<void> stopCasting(html.HTMLVideoElement? video) async {
    if (video == null) return;
    try {
      video.pause();
      // Toggling disableRemotePlayback forces W3C RemotePlayback disconnection;
      // if browser ignores it, fall back to prompt() so user can disconnect.
      video.disableRemotePlayback = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      video.disableRemotePlayback = false;
      _emit('notConnected');
    } catch (_) {
      await showPicker(video);
    }
  }
}
