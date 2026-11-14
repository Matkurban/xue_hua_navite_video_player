import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_video_player/src/bridge/video_player_host_bridge.dart';
import 'package:xue_hua_navite_video_player/src/cache/video_cache_engine.dart';
import 'package:xue_hua_navite_video_player/src/core/video_source.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/aspect_ratio_mode.dart';
import 'package:xue_hua_navite_video_player/src/data/models/navite_file.dart';
import 'package:xue_hua_navite_video_player/src/data/models/video_cache_config.dart';
import 'package:xue_hua_navite_video_player/src/pigeon/player_api.g.dart';
import 'package:xue_hua_navite_video_player/src/player/channel_player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/media_probe.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/player/video_player_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerHostBridge previousBridge;
  late _FakeRecordingHostBridge fakeBridge;

  setUp(() {
    previousBridge = VideoPlayerHostBridge.instance;
    fakeBridge = _FakeRecordingHostBridge();
    VideoPlayerHostBridge.instance = fakeBridge;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    VideoPlayerHostBridge.instance = previousBridge;
    await fakeBridge.close();
  });

  test('second native PlaybackSession initialize throws', () async {
    final first = VideoPlayerController();
    final second = VideoPlayerController();
    await first.initialize();
    await expectLater(second.initialize(), throwsA(isA<StateError>()));
    await first.dispose();
    await second.initialize();
    await second.dispose();
  });

  test('PigeonVideoPlayerHostBridge delegates host calls and dispatches FlutterApi events', () async {
    final fakeApi = _FakePlayerHostApi();
    final bridge = PigeonVideoPlayerHostBridge(hostApi: fakeApi);
    final backend = ChannelPlayerBackend(bridge: bridge);

    final receivedEvents = <PlayerEvent>[];
    final sub = backend.events.listen(receivedEvents.add);

    final textureId = await backend.create();
    expect(textureId, 7);
    expect(backend.textureId.value, 7);

    await backend.open(
      'https://example.com/video.mp4',
      castUrl: 'https://example.com/cast.mp4',
      cacheKey: 'k1',
      headers: const <String, String>{'Authorization': 'Bearer x'},
      enableCache: true,
    );
    expect(fakeApi.lastOpenRequest?.url, 'https://example.com/video.mp4');
    expect(fakeApi.lastOpenRequest?.castUrl, 'https://example.com/cast.mp4');
    expect(fakeApi.lastOpenRequest?.cacheKey, 'k1');
    expect(fakeApi.lastOpenRequest?.enableCache, isTrue);

    await backend.play();
    await backend.pause();
    await backend.seek(1234);
    await backend.setVolume(1.5);
    await backend.setSpeed(1.25);
    await backend.setAspectRatioMode(AspectRatioMode.fill);
    await backend.setVideoViewSize(width: 800, height: 600, devicePixelRatio: 2.0);
    await backend.showCastPicker();
    await backend.stopCasting();

    expect(fakeApi.playCount, 1);
    expect(fakeApi.pauseCount, 1);
    expect(fakeApi.lastSeekMs, 1234);
    expect(fakeApi.lastVolume, 1.0);
    expect(fakeApi.lastSpeed, 1.25);
    expect(fakeApi.lastAspectRatioMode, NativeAspectRatioMode.fill);
    expect(fakeApi.lastViewSize, (800.0, 600.0, 2.0));

    await bridge.onPlayerEvent(
      PlayerEventData(kind: NativePlayerEventType.duration, intValue: 5000),
    );
    await bridge.onPlayerEvent(
      PlayerEventData(kind: NativePlayerEventType.playing, boolValue: true),
    );
    await Future<void>.delayed(Duration.zero);

    expect(receivedEvents, hasLength(2));
    expect((receivedEvents[0] as PlayerDurationEvent).duration, const Duration(seconds: 5));
    expect((receivedEvents[1] as PlayerPlayingEvent).playing, isTrue);

    final tempDir = await Directory.systemTemp.createTemp('pigeon_snapshot_test_');
    try {
      final snapPath = '${tempDir.path}/snap.png';
      fakeApi.snapshotResult = SnapshotData(bytes: Uint8List.fromList(<int>[1, 2, 3, 4]));
      final snap = await backend.takeSnapshot(savePath: snapPath);
      expect(snap.path, snapPath);
      expect(await snap.readAsBytes(), <int>[1, 2, 3, 4]);
    } finally {
      await tempDir.delete(recursive: true);
    }

    await sub.cancel();
    await backend.dispose();
    expect(fakeApi.disposeCount, 1);
    expect(backend.textureId.value, isNull);
  });

  test('MediaProbe.probeDuration returns null when the bridge hangs past timeout', () async {
    fakeBridge.onGetDuration = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return 9000;
    };

    final probe = MediaProbe();
    final duration = await probe.probeDuration(
      VideoSource.network('https://example.com/live.m3u8'),
      timeout: const Duration(milliseconds: 10),
    );
    expect(duration, isNull);
  });

  test('MediaProbe.probeDuration maps native milliseconds', () async {
    fakeBridge.onGetDuration = (request) async => 1500;

    final probe = MediaProbe();
    final duration = await probe.probeDuration(VideoSource.network('https://example.com/a.mp4'));
    expect(duration, const Duration(milliseconds: 1500));
  });

  test('MediaProbe.extractCovers maps CoverFrameData and sorts descending by brightness', () async {
    fakeBridge.onExtractCovers = (request) async {
      return <CoverFrameData>[
        CoverFrameData(path: '/tmp/a.png', positionMs: 1000, brightness: 0.25),
        CoverFrameData(path: '', positionMs: 1500, brightness: 0.99),
        CoverFrameData(path: '/tmp/b.png', positionMs: 2500, brightness: 0.85),
      ];
    };

    final probe = MediaProbe();
    final frames = await probe.extractCovers(
      VideoSource.network('https://example.com/movie.mp4'),
      count: 2,
      minBrightness: 0.1,
      outputDir: '/tmp/covers',
    );
    expect(frames, hasLength(2));
    expect(frames[0].image.path, '/tmp/b.png');
    expect(frames[0].position, const Duration(milliseconds: 2500));
    expect(frames[0].brightness, closeTo(0.85, 1e-6));
    expect(frames[1].image.path, '/tmp/a.png');
    expect(fakeBridge.lastCoverRequest?.outputDir, '/tmp/covers');
    expect(fakeBridge.lastCoverRequest?.count, 2);
  });

  test('PlatformVideoCacheEngine routes non-desktop calls through VideoPlayerHostBridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final tempDir = await Directory.systemTemp.createTemp('xh_bridge_cache_test_');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (call) async => tempDir.path,
    );

    try {
      final engine = PlatformVideoCacheEngine(bridge: fakeBridge);
      final source = NetworkVideoSource(
        'https://cdn.example.com/sample.mp4',
        cacheKey: 'sample-key',
      );
      await engine.configure(
        VideoCacheConfig(
          enabled: true,
          maxCacheBytes: 8 * 1024 * 1024,
          maxSingleFileBytes: 2 * 1024 * 1024,
          cacheDirectory: tempDir.path,
        ),
      );
      expect(fakeBridge.lastCacheConfig?.cacheDir, tempDir.path);
      expect(fakeBridge.lastCacheConfig?.maxCacheBytes, 8 * 1024 * 1024);

      fakeBridge.cachedResult = true;
      fakeBridge.cacheSizeResult = 4096;

      await engine.precache(source, preloadBytes: 512);
      expect(fakeBridge.lastPrecache?.preloadBytes, 512);
      expect(await engine.isCached(source), isTrue);
      expect(await engine.getCacheSize(), 4096);

      engine.pin('k');
      engine.unpin('k');
      await Future<void>.delayed(Duration.zero);
      expect(fakeBridge.pinnedKeys, ['k']);
      expect(fakeBridge.unpinnedKeys, ['k']);

      await engine.cancelPrecache(source);
      await engine.removeCache(source);
      await engine.clearCache();
      expect(fakeBridge.clearedDirs, contains(tempDir.path));
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        null,
      );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('NaviteFile supports fromBytes, fromLocation, readAsBytes, length, and saveTo', () async {
    final rawBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final memoryFile = NaviteFile.fromBytes(rawBytes, name: 'test.png');

    expect(memoryFile.name, 'test.png');
    expect(memoryFile.mimeType, 'image/png');
    expect(memoryFile.uri, startsWith('data:image/png;base64,'));
    expect(await memoryFile.readAsBytes(), rawBytes);
    expect(await memoryFile.length(), rawBytes.length);

    final dataUrlFile = NaviteFile.fromLocation(memoryFile.uri);
    expect(await dataUrlFile.readAsBytes(), rawBytes);
    expect(await dataUrlFile.length(), rawBytes.length);

    final tempDir = await Directory.systemTemp.createTemp('navite_file_test_');
    try {
      final targetPath = '${tempDir.path}/saved_frame.png';
      await memoryFile.saveTo(targetPath);

      final localFile = NaviteFile.fromLocation(targetPath);
      expect(localFile.path, targetPath);
      expect(localFile.name, 'saved_frame.png');
      expect(localFile.uri, Uri.file(targetPath).toString());
      expect(await localFile.readAsBytes(), rawBytes);
      expect(await localFile.length(), rawBytes.length);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

class _FakeRecordingHostBridge implements VideoPlayerHostBridge {
  final StreamController<PlayerEventData> _events = StreamController<PlayerEventData>.broadcast();
  final StreamController<bool> _fullscreen = StreamController<bool>.broadcast();

  Future<int?> Function(DurationProbeRequest)? onGetDuration;
  Future<List<CoverFrameData>> Function(CoverExtractRequest)? onExtractCovers;

  CoverExtractRequest? lastCoverRequest;
  CacheConfigRequest? lastCacheConfig;
  PrecacheRequest? lastPrecache;
  final List<String> pinnedKeys = <String>[];
  final List<String> unpinnedKeys = <String>[];
  final List<String?> clearedDirs = <String?>[];
  bool cachedResult = false;
  int cacheSizeResult = 0;

  @override
  Stream<PlayerEventData> get events => _events.stream;

  @override
  Stream<bool> get fullscreenEvents => _fullscreen.stream;

  @override
  Future<int> create() async => 0;

  @override
  Future<void> open(OpenMediaRequest request) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setAspectRatioMode(NativeAspectRatioMode mode) async {}

  @override
  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio) async {}

  @override
  Future<void> showCastPicker() async {}

  @override
  Future<void> stopCasting() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<double> getBrightness() async => 1.0;

  @override
  Future<void> setBrightness(double value) async {}

  @override
  Future<void> setWindowFullscreen(bool value) async {}

  @override
  Future<SnapshotData?> takeSnapshot() async => null;

  @override
  Future<int?> getDuration(DurationProbeRequest request) async {
    final handler = onGetDuration;
    if (handler != null) {
      return handler(request);
    }
    return null;
  }

  @override
  Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request) async {
    lastCoverRequest = request;
    final handler = onExtractCovers;
    if (handler != null) {
      return handler(request);
    }
    return const <CoverFrameData>[];
  }

  @override
  Future<void> configureCache(CacheConfigRequest request) async {
    lastCacheConfig = request;
  }

  @override
  Future<void> precache(PrecacheRequest request) async {
    lastPrecache = request;
  }

  @override
  Future<void> cancelPrecache(String cacheKey) async {}

  @override
  Future<bool> isCached(CacheEntryRequest request) async => cachedResult;

  @override
  Future<int> getCacheSize(String? cacheDir) async => cacheSizeResult;

  @override
  Future<void> removeCache(CacheEntryRequest request) async {}

  @override
  Future<void> clearCache(String? cacheDir) async {
    clearedDirs.add(cacheDir);
  }

  @override
  Future<void> pinCacheKey(String cacheKey) async {
    pinnedKeys.add(cacheKey);
  }

  @override
  Future<void> unpinCacheKey(String cacheKey) async {
    unpinnedKeys.add(cacheKey);
  }

  Future<void> close() async {
    await _events.close();
    await _fullscreen.close();
  }
}

class _FakePlayerHostApi implements PlayerHostApi {
  OpenMediaRequest? lastOpenRequest;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  int? lastSeekMs;
  double? lastVolume;
  double? lastSpeed;
  NativeAspectRatioMode? lastAspectRatioMode;
  (double, double, double)? lastViewSize;
  SnapshotData? snapshotResult;

  @override
  Future<int> create() async => 7;

  @override
  Future<void> open(OpenMediaRequest request) async {
    lastOpenRequest = request;
  }

  @override
  Future<void> play() async {
    playCount += 1;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<void> seek(int positionMs) async {
    lastSeekMs = positionMs;
  }

  @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
  }

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> setAspectRatioMode(NativeAspectRatioMode mode) async {
    lastAspectRatioMode = mode;
  }

  @override
  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio) async {
    lastViewSize = (width, height, devicePixelRatio);
  }

  @override
  Future<void> showCastPicker() async {
    throw PlatformException(code: 'UNAVAILABLE');
  }

  @override
  Future<void> stopCasting() async {
    throw MissingPluginException();
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  Future<SnapshotData?> takeSnapshot() async => snapshotResult;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
