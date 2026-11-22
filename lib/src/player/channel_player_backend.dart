import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../bridge/video_player_host_bridge.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/models/navite_file.dart';
import '../pigeon/player_api.g.dart';
import '../utils/temp_paths.dart';
import 'player_backend.dart';
import 'player_event.dart';
import 'player_event_decoder.dart';

/// 基于 [VideoPlayerHostBridge] 的 [PlayerBackend] 默认适配器，事件解码委托给 [PlayerEventDecoder]。
///
/// Default [PlayerBackend] adapter over [VideoPlayerHostBridge], delegating
/// Pigeon payload decoding to [PlayerEventDecoder].
class ChannelPlayerBackend implements PlayerBackend {
  /// 创建通道播放器后端，可选传入测试用 [bridge]。
  ///
  /// Creates a [ChannelPlayerBackend] with an optional [bridge] override.
  ChannelPlayerBackend({this._bridge});

  final VideoPlayerHostBridge? _bridge;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

  final FlutterSignal<int?> _textureId = signal<int?>(null);
  StreamSubscription<PlayerEventData>? _eventSubscription;
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

    // Subscribe before create() so native ready events are not dropped.
    _listenEvents();

    final id = await _resolvedBridge.create();
    _textureId.value = id;
    return id;
  }

  void _listenEvents() {
    if (_eventSubscription != null) {
      return;
    }
    _eventSubscription = _resolvedBridge.events.listen(
      (PlayerEventData raw) {
        try {
          final event = PlayerEventDecoder.fromPigeon(raw);
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
  static PlayerEvent? decodeEventForTest(PlayerEventData event) {
    return PlayerEventDecoder.fromPigeon(event);
  }

  @override
  Future<void> open(
    String url, {
    String? castUrl,
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) async {
    await _resolvedBridge.open(
      OpenMediaRequest(
        url: url,
        castUrl: castUrl,
        cacheKey: cacheKey,
        headers: headers,
        enableCache: enableCache,
      ),
    );
  }

  @override
  Future<void> play() async {
    await _resolvedBridge.play();
  }

  @override
  Future<void> pause() async {
    await _resolvedBridge.pause();
  }

  @override
  Future<void> seek(int positionMs) async {
    await _resolvedBridge.seek(positionMs);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _resolvedBridge.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _resolvedBridge.setSpeed(speed);
  }

  @override
  Future<void> setAspectRatioMode(AspectRatioMode mode) async {
    await _resolvedBridge.setAspectRatioMode(_toNativeAspectRatioMode(mode));
  }

  @override
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) async {
    await _resolvedBridge.setVideoViewSize(width, height, devicePixelRatio);
  }

  @override
  Future<void> showCastPicker() async {
    try {
      await _resolvedBridge.showCastPicker();
    } on MissingPluginException {
      // Safe no-op if platform does not implement casting.
    } on PlatformException {
      // Safe no-op if platform does not implement casting.
    }
  }

  @override
  Future<void> stopCasting() async {
    try {
      await _resolvedBridge.stopCasting();
    } on MissingPluginException {
      // Safe no-op if platform does not implement casting.
    } on PlatformException {
      // Safe no-op if platform does not implement casting.
    }
  }

  @override
  Future<void> dispose() async {
    final local = _eventSubscription;
    _eventSubscription = null;
    try {
      await local?.cancel();
    } catch (_) {
      // Local subscription cancel should not fail teardown or tests.
    }
    try {
      await _resolvedBridge.dispose();
    } catch (_) {}
    _textureId.value = null;
    // Do not close [_events] — [create] must be able to emit again.
  }

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) async {
    final data = await _resolvedBridge.takeSnapshot();
    if (data == null) {
      throw StateError('Native player returned no snapshot data.');
    }
    final dataUri = data.dataUri;
    final bytes = data.bytes;
    if (kIsWeb) {
      if (dataUri != null && dataUri.isNotEmpty) {
        return NaviteFile.fromLocation(dataUri, name: _defaultSnapshotName());
      }
      if (bytes != null) {
        return NaviteFile.fromBytes(bytes, name: _defaultSnapshotName());
      }
      throw StateError('Native player returned no snapshot data.');
    }
    if (bytes == null) {
      throw StateError('Native player returned no snapshot data.');
    }
    final outPath = savePath ?? await pluginSnapshotPath(_defaultSnapshotName());
    await writeFileBytes(outPath, bytes);
    return NaviteFile.fromLocation(outPath);
  }

  static NativeAspectRatioMode _toNativeAspectRatioMode(AspectRatioMode mode) {
    return switch (mode) {
      AspectRatioMode.fit => NativeAspectRatioMode.fit,
      AspectRatioMode.fill => NativeAspectRatioMode.fill,
      AspectRatioMode.stretch => NativeAspectRatioMode.stretch,
    };
  }

  static String _defaultSnapshotName() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'snapshot-$ts.png';
  }
}
