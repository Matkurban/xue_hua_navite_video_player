import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import 'player_backend.dart';
import 'player_event.dart';

/// [PlayerBackend] adapter over MethodChannel / EventChannel.
///
/// Wire protocol is unchanged; this type only decodes maps into [PlayerEvent].
class ChannelPlayerBackend implements PlayerBackend {
  static const _methodChannel = MethodChannel('xue_hua_navite_video_player/player');
  static const _eventChannel = EventChannel('xue_hua_navite_video_player/player/events');

  final FlutterSignal<int?> _textureId = signal<int?>(null);
  StreamSubscription<dynamic>? _eventSubscription;
  StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();

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

    final id = await _methodChannel.invokeMethod<int>('create');
    if (id == null) {
      throw StateError('Native player create() returned a null texture id.');
    }
    _textureId.value = id;
    _listenEvents();
    return id;
  }

  void _listenEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic raw) {
        try {
          if (raw is! Map) return;
          final event = _decodeEvent(Map<String, dynamic>.from(raw));
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
    return _decodeEvent(event);
  }

  static PlayerEvent? _decodeEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    switch (type) {
      case 'position':
        final ms = _asInt(event['value']);
        if (ms == null) return null;
        return PlayerEvent.position(Duration(milliseconds: ms));
      case 'duration':
        final ms = _asInt(event['value']);
        if (ms == null) return null;
        return PlayerEvent.duration(Duration(milliseconds: ms));
      case 'playing':
        final playing = _asBool(event['value']);
        if (playing == null) return null;
        return PlayerEvent.playing(playing);
      case 'buffering':
        final buffering = _asBool(event['value']);
        if (buffering == null) return null;
        return PlayerEvent.buffering(buffering);
      case 'error':
        final message = event['value']?.toString();
        if (message == null) return null;
        return PlayerEvent.error(message);
      case 'completed':
        return const PlayerEvent.completed();
      case 'videoSize':
        final value = event['value'];
        if (value is! Map) return null;
        final w = (value['width'] as num?)?.toDouble() ?? 0;
        final h = (value['height'] as num?)?.toDouble() ?? 0;
        final rotation = (value['rotationDegrees'] as num?)?.toInt() ?? 0;
        final size = (w > 0 && h > 0) ? Size(w, h) : Size.zero;
        return PlayerEvent.videoSize(size, rotation % 360);
      default:
        return null;
    }
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    return null;
  }

  @override
  Future<void> open(String url) async {
    await _methodChannel.invokeMethod('open', {'url': url});
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
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
    _textureId.value = null;
    // Do not close [_events] — [create] must be able to emit again.
  }

  @override
  Future<XFile> takeSnapshot({String? savePath}) async {
    final raw = await _methodChannel.invokeMethod<dynamic>('takeSnapshot');
    if (raw == null) {
      throw StateError('Native player returned no snapshot data.');
    }
    if (kIsWeb) {
      if (raw is String) {
        return XFile(raw, mimeType: 'image/png');
      }
      final bytes = _asUint8List(raw);
      return XFile.fromData(bytes, mimeType: 'image/png', name: _defaultSnapshotName());
    }
    final bytes = _asUint8List(raw);
    final outPath = savePath ?? await _defaultSnapshotPath();
    final file = File(outPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return XFile(outPath, mimeType: 'image/png');
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

  static Future<String> _defaultSnapshotPath() async {
    final dir = await getTemporaryDirectory();
    final name = _defaultSnapshotName();
    return '${dir.path}/xue_hua_navite_video_player/snapshots/$name';
  }
}
