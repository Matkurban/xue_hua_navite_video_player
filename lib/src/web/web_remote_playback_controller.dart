import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as html;

import 'web_remote_playback_interop.dart';

/// Callback signature for reporting cast state changes from the browser.
typedef WebCastStateCallback = void Function(String state, {String? deviceName});

/// Coordinates W3C Remote Playback API and Safari WebKit AirPlay target picking
/// for an [html.HTMLVideoElement].
class WebRemotePlaybackController {
  WebRemotePlaybackController({required this._onStateChanged});

  final WebCastStateCallback _onStateChanged;
  String _state = 'unavailable';
  String? _deviceName;

  String get state => _state;
  String? get deviceName => _deviceName;

  void emitCurrentState() {
    _emit(_state, deviceName: _deviceName);
  }

  void _emit(String state, {String? deviceName}) {
    _state = state;
    _deviceName = deviceName;
    _onStateChanged(state, deviceName: deviceName);
  }

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
