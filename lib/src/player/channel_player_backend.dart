import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/models/navite_file.dart';
import '../utils/temp_paths.dart';
import 'player_backend.dart';
import 'player_event.dart';
import 'player_event_decoder.dart';

/// Process-wide native [EventChannel] listener with ref-counting.
///
/// Native only allows one active listen on `player/events`. Live Photo (and any
/// recreate/dispose cycle) must share that single subscription instead of each
/// [ChannelPlayerBackend] calling [EventChannel.receiveBroadcastStream].
class _SharedNativeEventHub {
  static const EventChannel _eventChannel = EventChannel(
    'xue_hua_navite_video_player/player/events',
  );

  static final StreamController<dynamic> _raw = StreamController<dynamic>.broadcast();
  static StreamSubscription<dynamic>? _sub;
  static int _refs = 0;

  static Stream<dynamic> retain() {
    if (_refs == 0) {
      _sub = _eventChannel.receiveBroadcastStream().listen(_raw.add, onError: _raw.addError);
    }
    _refs += 1;
    return _raw.stream;
  }

  static Future<void> release() async {
    if (_refs <= 0) {
      return;
    }
    _refs -= 1;
    if (_refs > 0) {
      return;
    }
    final StreamSubscription<dynamic>? sub = _sub;
    _sub = null;
    if (sub == null) {
      return;
    }
    try {
      await sub.cancel();
    } on PlatformException catch (error) {
      // Concurrent dispose / already-cleared native handler.
      if (error.message != 'No active stream to cancel') {
        // Same class of cancel races — swallow to avoid failing widget tests.
      }
    } catch (_) {
      // Ignore cancel races on shared channel teardown.
    }
  }
}

/// [PlayerBackend] adapter over MethodChannel / EventChannel.
///
/// Wire protocol is unchanged; delegates event map decoding to [PlayerEventDecoder].
class ChannelPlayerBackend implements PlayerBackend {
  static const _methodChannel = MethodChannel('xue_hua_navite_video_player/player');

  final FlutterSignal<int?> _textureId = signal<int?>(null);
  StreamSubscription<dynamic>? _eventSubscription;
  StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();
  bool _holdingSharedEvents = false;

  @override
  FlutterSignal<int?> get textureId => _textureId;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<int> create() async {
    // Keep the broadcast stream usable across dispose → create cycles.
    if (_events.isClosed) {
      _events = StreamController<PlayerEvent>.broadcast();
    }

    // Subscribe before create() so native ready events are not dropped.
    _listenEvents();

    final id = await _methodChannel.invokeMethod<int>('create');
    if (id == null) {
      throw StateError('Native player create() returned a null texture id.');
    }
    _textureId.value = id;
    return id;
  }

  void _listenEvents() {
    if (_holdingSharedEvents) {
      return;
    }
    _holdingSharedEvents = true;
    _eventSubscription = _SharedNativeEventHub.retain().listen(
      (dynamic raw) {
        try {
          if (raw is! Map) return;
          final event = PlayerEventDecoder.decode(Map<String, dynamic>.from(raw));
          if (event != null && !_events.isClosed) {
            _events.add(event);
          }
        } catch (error) {
          if (!_events.isClosed) {
            _events.add(PlayerEvent.error('Invalid player event: $error'));
          }
        }
      },
      onError: (Object error) {
        if (!_events.isClosed) {
          _events.add(PlayerEvent.error(error.toString()));
        }
      },
    );
  }

  /// Visible for tests.
  @visibleForTesting
  static PlayerEvent? decodeEventForTest(Map<String, dynamic> event) {
    return PlayerEventDecoder.decode(event);
  }

  @override
  Future<void> open(String url, {String? castUrl}) async {
    await _methodChannel.invokeMethod('open', {'url': url, 'castUrl': ?castUrl});
  }

  @override
  Future<void> play() async {
    await _methodChannel.invokeMethod('play');
  }

  @override
  Future<void> pause() async {
    await _methodChannel.invokeMethod('pause');
  }

  @override
  Future<void> seek(int positionMs) async {
    await _methodChannel.invokeMethod('seek', {'position': positionMs});
  }

  @override
  Future<void> setVolume(double volume) async {
    await _methodChannel.invokeMethod('setVolume', {'volume': volume.clamp(0.0, 1.0)});
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _methodChannel.invokeMethod('setSpeed', {'speed': speed});
  }

  @override
  Future<void> setAspectRatioMode(AspectRatioMode mode) async {
    await _methodChannel.invokeMethod('setAspectRatioMode', {'mode': mode.wireName});
  }

  @override
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) async {
    await _methodChannel.invokeMethod('setVideoViewSize', {
      'width': width,
      'height': height,
      'devicePixelRatio': devicePixelRatio,
    });
  }

  @override
  Future<void> showCastPicker() async {
    try {
      await _methodChannel.invokeMethod('showCastPicker');
    } on MissingPluginException {
      // Safe no-op if platform does not implement casting.
    } on PlatformException {
      // Safe no-op if platform does not implement casting.
    }
  }

  @override
  Future<void> stopCasting() async {
    try {
      await _methodChannel.invokeMethod('stopCasting');
    } on MissingPluginException {
      // Safe no-op if platform does not implement casting.
    } on PlatformException {
      // Safe no-op if platform does not implement casting.
    }
  }

  @override
  Future<void> dispose() async {
    if (_holdingSharedEvents) {
      _holdingSharedEvents = false;
      final StreamSubscription<dynamic>? local = _eventSubscription;
      _eventSubscription = null;
      try {
        await local?.cancel();
      } catch (_) {
        // Local forwarder cancel should not fail tests.
      }
      await _SharedNativeEventHub.release();
    }
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
    _textureId.value = null;
    // Do not close [_events] — [create] must be able to emit again.
  }

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) async {
    final raw = await _methodChannel.invokeMethod<dynamic>('takeSnapshot');
    if (raw == null) {
      throw StateError('Native player returned no snapshot data.');
    }
    if (kIsWeb) {
      if (raw is String) {
        return NaviteFile.fromLocation(raw, name: _defaultSnapshotName());
      }
      return NaviteFile.fromBytes(_asUint8List(raw), name: _defaultSnapshotName());
    }
    final bytes = _asUint8List(raw);
    final outPath = savePath ?? await pluginSnapshotPath(_defaultSnapshotName());
    await writeFileBytes(outPath, bytes);
    return NaviteFile.fromLocation(outPath);
  }

  static Uint8List _asUint8List(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    throw StateError('Unsupported snapshot payload: ${raw.runtimeType}');
  }

  static String _defaultSnapshotName() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'snapshot-$ts.png';
  }
}
