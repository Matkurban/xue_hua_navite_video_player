import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/cache/local_video_cache_server_io.dart';
import 'package:xue_hua_navite_video_player/src/cache/video_cache_manager.dart';
import 'package:xue_hua_navite_video_player/src/cache/video_cache_types.dart';
import 'package:xue_hua_navite_video_player/src/player/brightness_controller.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_bottom_scrubber.dart';
import 'package:xue_hua_navite_video_player/src/utils/live_photo_extractor.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

/// Deterministic synthetic MP4 byte generator.
Uint8List _generateMp4Payload(int totalBytes) {
  final header = <int>[
    0x00, 0x00, 0x00, 0x18,
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x69, 0x73, 0x6F, 0x6D, // 'isom'
    0x00, 0x00, 0x02, 0x00,
    0x69, 0x73, 0x6F, 0x6D,
    0x6D, 0x70, 0x34, 0x32,
  ];
  final out = Uint8List(totalBytes);
  for (var i = 0; i < totalBytes; i++) {
    out[i] = i < header.length ? header[i] : ((i * 31 + 17) & 0xFF);
  }
  return out;
}

Uint8List _buildMinimalJpegBytes() {
  return Uint8List.fromList(<int>[
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x01,
    0x00,
    0x48,
    0x00,
    0x48,
    0x00,
    0x00,
    0xFF,
    0xD9,
  ]);
}

/// Counting local HTTP server supporting standard `200 OK` & `206 Partial Content` Range requests.
class _CountingUpstreamServer {
  final HttpServer _server;
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Map<String, String> _contentTypes = <String, String>{};
  int hitCount = 0;
  final List<String?> receivedRanges = <String?>[];
  final List<Map<String, String>> receivedHeaders = <Map<String, String>>[];

  _CountingUpstreamServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_CountingUpstreamServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _CountingUpstreamServer._(server);
  }

  String registerFile(String path, Uint8List bytes, {String contentType = 'video/mp4'}) {
    final normalized = path.startsWith('/') ? path : '/$path';
    _files[normalized] = bytes;
    _contentTypes[normalized] = contentType;
    return 'http://127.0.0.1:${_server.port}$normalized';
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    hitCount++;
    final hdrs = <String, String>{};
    req.headers.forEach((name, values) {
      hdrs[name.toLowerCase()] = values.join(', ');
    });
    receivedHeaders.add(hdrs);
    final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
    receivedRanges.add(rangeHeader);

    final bytes = _files[req.uri.path];
    if (bytes == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    final total = bytes.length;
    req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    req.response.headers.set(
      HttpHeaders.contentTypeHeader,
      _contentTypes[req.uri.path] ?? 'video/mp4',
    );

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring('bytes='.length).split(',').first.trim();
      final parts = spec.split('-');
      final start = parts[0].isEmpty ? 0 : int.parse(parts[0]);
      final end = (parts.length < 2 || parts[1].isEmpty)
          ? (total - 1)
          : int.parse(parts[1]).clamp(0, total - 1);

      if (start < 0 || start >= total || end < start) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await req.response.close();
        return;
      }

      final slice = Uint8List.sublistView(bytes, start, end + 1);
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      req.response.contentLength = slice.length;
      if (req.method != 'HEAD') {
        req.response.add(slice);
      }
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.ok;
    req.response.contentLength = total;
    if (req.method != 'HEAD') {
      req.response.add(bytes);
    }
    await req.response.close();
  }
}

Future<Uint8List> _httpGetBytes(String url, {int? rangeStart, int? rangeEnd}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    if (rangeStart != null) {
      final endPart = rangeEnd != null ? '$rangeEnd' : '';
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-$endPart');
    }
    final res = await req.close();
    expect(
      res.statusCode == HttpStatus.ok || res.statusCode == HttpStatus.partialContent,
      isTrue,
      reason: 'Expected HTTP 200 or 206, got ${res.statusCode}',
    );
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

class _FakePlayerBackend implements PlayerBackend {
  final StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();
  @override
  final FlutterSignal<int?> textureId = signal<int?>(null);

  String? lastOpenedUrl;
  String? lastCastUrl;
  String? lastCacheKey;
  Map<String, String>? lastHeaders;
  bool? lastEnableCache;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  void emit(PlayerEvent event) => _events.add(event);

  @override
  Future<int> create() async {
    textureId.value = 1;
    return 1;
  }

  @override
  Future<void> open(
    String mediaUrl, {
    String? castUrl,
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) async {
    lastOpenedUrl = mediaUrl;
    lastCastUrl = castUrl;
    lastCacheKey = cacheKey;
    lastHeaders = headers;
    lastEnableCache = enableCache;
  }

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
  Future<void> setAspectRatioMode(AspectRatioMode mode) async {}

  @override
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) async {}

  @override
  Future<void> showCastPicker() async {}

  @override
  Future<void> stopCasting() async {}

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) async => NaviteFile.fromBytes(Uint8List(0));

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _FakeFullscreen implements FullscreenCoordinator {
  final StreamController<bool> _ctrl = StreamController<bool>.broadcast();
  @override
  Stream<bool> get externalChanges => _ctrl.stream;
  @override
  Future<void> enter({required bool landscapeVideo}) async {}
  @override
  Future<void> exit() async {}
  @override
  void dispose() {
    _ctrl.close();
  }
}

class _FakeBrightness implements BrightnessController {
  @override
  Future<double> get current async => 0.5;
  @override
  Future<void> setBrightness(double value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides? savedHttpOverrides;
  late Directory tempRoot;

  setUpAll(() {
    savedHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
  });

  tearDownAll(() {
    HttpOverrides.global = savedHttpOverrides;
  });

  setUp(() async {
    HttpOverrides.global = null;
    tempRoot = await Directory.systemTemp.createTemp('xh_video_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempRoot.path,
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('ByteInterval & VideoCacheKeyUtils', () {
    test('merges overlapping and adjacent byte intervals and checks range coverage', () {
      final merged = ByteInterval.merge(const <ByteInterval>[
        ByteInterval(200, 300),
        ByteInterval(0, 120),
        ByteInterval(100, 200),
        ByteInterval(400, 500),
      ]);
      expect(merged, equals(const <ByteInterval>[ByteInterval(0, 300), ByteInterval(400, 500)]));
      expect(ByteInterval.coversRange(merged, 0, 300), isTrue);
      expect(ByteInterval.coversRange(merged, 50, 250), isTrue);
      expect(ByteInterval.coversRange(merged, 0, 500), isFalse);
    });

    test('resolves explicit cacheKey, global cacheKeyBuilder, and streaming manifest URLs', () {
      final cfg = VideoCacheConfig(cacheKeyBuilder: (Uri uri) => uri.replace(query: '').toString());
      final s1 = NetworkVideoSource('https://cdn.example.com/v.mp4?token=111');
      final s2 = NetworkVideoSource('https://cdn.example.com/v.mp4?token=222');
      final s3 = NetworkVideoSource(
        'https://cdn.example.com/other.mp4?token=999',
        cacheKey: 'custom-fixed-id',
      );

      final id1 = VideoCacheKeyUtils.resolveRawIdentity(s1, cfg);
      final id2 = VideoCacheKeyUtils.resolveRawIdentity(s2, cfg);
      final id3 = VideoCacheKeyUtils.resolveRawIdentity(s3, cfg);

      expect(id1, equals(id2));
      expect(
        VideoCacheKeyUtils.computeSha1Key(id1),
        equals(VideoCacheKeyUtils.computeSha1Key(id2)),
      );
      expect(id3, equals('custom-fixed-id'));
      expect(
        VideoCacheKeyUtils.isStreamingManifestUrl('https://a.com/live/index.m3u8?k=1'),
        isTrue,
      );
      expect(VideoCacheKeyUtils.isStreamingManifestUrl('https://a.com/dash/manifest.mpd'), isTrue);
      expect(VideoCacheKeyUtils.isStreamingManifestUrl('https://a.com/vod/clip.mp4'), isFalse);
    });
  });

  group('LocalVideoCacheEngine progressive & sparse Range caching', () {
    test(
      'streams and caches on first play, then serves file:// with zero network when offline',
      () async {
        final upstream = await _CountingUpstreamServer.start();
        final engine = LocalVideoCacheEngine();
        await engine.configure(VideoCacheConfig(cacheDirectory: '${tempRoot.path}/cache1'));

        try {
          final payload = _generateMp4Payload(64 * 1024);
          final url = upstream.registerFile('/videos/sample.mp4', payload);
          final source = NetworkVideoSource(url);

          expect(await engine.isCached(source), isFalse);

          // 1st playback: streams via 127.0.0.1 loopback proxy and caches to disk.
          final firstTarget = await engine.resolveForPlayback(source);
          expect(firstTarget.playUrl, startsWith('http://127.0.0.1:'));
          expect(firstTarget.castUrl, equals(url));
          expect(firstTarget.isCompleteFileHit, isFalse);

          final downloaded = await _httpGetBytes(firstTarget.playUrl);
          expect(downloaded, equals(payload));
          expect(upstream.hitCount, equals(1));
          expect(await engine.isCached(source), isTrue);
          expect(await engine.getCacheSize(), equals(payload.length));

          // Simulate complete network disconnection by shutting down upstream!
          await upstream.close();

          // 2nd playback: hits local file:// directly with 0 network requests!
          final secondTarget = await engine.resolveForPlayback(source);
          expect(secondTarget.playUrl, startsWith('file://'));
          expect(secondTarget.castUrl, equals(url));
          expect(secondTarget.isCompleteFileHit, isTrue);

          final localFile = File.fromUri(Uri.parse(secondTarget.playUrl));
          expect(await localFile.readAsBytes(), equals(payload));
          expect(upstream.hitCount, equals(1));
        } finally {
          await engine.dispose();
          await upstream.close();
        }
      },
    );

    test('assembles non-contiguous sparse Range requests (head + tail moov + gap) with zero duplicate downloads', () async {
      final upstream = await _CountingUpstreamServer.start();
      final engine = LocalVideoCacheEngine();
      await engine.configure(VideoCacheConfig(cacheDirectory: '${tempRoot.path}/cache_sparse'));

      try {
        final payload = _generateMp4Payload(50000);
        final expectedSha1 = sha1.convert(payload).toString();
        final url = upstream.registerFile('/videos/tail_moov.mp4', payload);
        final source = NetworkVideoSource(url);

        final target = await engine.resolveForPlayback(source);
        final proxyUrl = target.playUrl;

        // Step 1: Demuxer probes head [0..4095].
        final head = await _httpGetBytes(proxyUrl, rangeStart: 0, rangeEnd: 4095);
        expect(head, equals(payload.sublist(0, 4096)));
        expect(upstream.hitCount, equals(1));

        // Step 2: Demuxer seeks to tail [45000..49999] to read `moov` atom.
        final tail = await _httpGetBytes(proxyUrl, rangeStart: 45000, rangeEnd: 49999);
        expect(tail, equals(payload.sublist(45000, 50000)));
        expect(upstream.hitCount, equals(2));

        // Step 3: Re-reading already-cached slices causes 0 upstream requests!
        final cachedHeadSlice = await _httpGetBytes(proxyUrl, rangeStart: 512, rangeEnd: 2047);
        final cachedTailSlice = await _httpGetBytes(proxyUrl, rangeStart: 46000, rangeEnd: 48999);
        expect(cachedHeadSlice, equals(payload.sublist(512, 2048)));
        expect(cachedTailSlice, equals(payload.sublist(46000, 49000)));
        expect(upstream.hitCount, equals(2));

        // Step 4: Full read [0..49999] fetches ONLY the missing middle gap [4096..44999]!
        final fullBytes = await _httpGetBytes(proxyUrl, rangeStart: 0, rangeEnd: 49999);
        expect(sha1.convert(fullBytes).toString(), equals(expectedSha1));
        expect(upstream.hitCount, equals(3));
        expect(upstream.receivedRanges.last, equals('bytes=4096-44999'));

        // Sparse segments must now be promoted into a single complete MP4 file!
        expect(await engine.isCached(source), isTrue);
        final promotedTarget = await engine.resolveForPlayback(source);
        expect(promotedTarget.playUrl, startsWith('file://'));
        expect(
          sha1
              .convert(await File.fromUri(Uri.parse(promotedTarget.playUrl)).readAsBytes())
              .toString(),
          equals(expectedSha1),
        );
      } finally {
        await engine.dispose();
        await upstream.close();
      }
    });

    test(
      'deduplicates rotating signed URLs via cacheKey and forwards custom HTTP headers',
      () async {
        final upstream = await _CountingUpstreamServer.start();
        final engine = LocalVideoCacheEngine();
        await engine.configure(VideoCacheConfig(cacheDirectory: '${tempRoot.path}/cache_signed'));

        try {
          final payload = _generateMp4Payload(24 * 1024);
          final baseUrl = upstream.registerFile('/signed/clip.mp4', payload);

          final sourceV1 = NetworkVideoSource(
            '$baseUrl?expires=1000&sig=aaa',
            cacheKey: 'media-clip-99',
            headers: const <String, String>{'Authorization': 'Bearer token-v1'},
          );
          final target1 = await engine.resolveForPlayback(sourceV1);
          final data1 = await _httpGetBytes(target1.playUrl);
          expect(data1, equals(payload));
          expect(upstream.receivedHeaders.single['authorization'], equals('Bearer token-v1'));

          await upstream.close();

          // New signed token for the same logical video hits local file:// offline!
          final sourceV2 = NetworkVideoSource(
            '$baseUrl?expires=9999&sig=bbb',
            cacheKey: 'media-clip-99',
          );
          expect(await engine.isCached(sourceV2), isTrue);
          final target2 = await engine.resolveForPlayback(sourceV2);
          expect(target2.playUrl, startsWith('file://'));
          expect(target2.castUrl, equals('$baseUrl?expires=9999&sig=bbb'));
        } finally {
          await engine.dispose();
          await upstream.close();
        }
      },
    );

    test('bypasses disk write when exceeding maxSingleFileBytes and evicts unpinned LRU entries', () async {
      final upstream = await _CountingUpstreamServer.start();
      final engine = LocalVideoCacheEngine();

      try {
        // 1. maxSingleFileBytes bypass test: 32 KiB file with 10 KiB single-file limit.
        await engine.configure(
          VideoCacheConfig(
            cacheDirectory: '${tempRoot.path}/cache_limits',
            maxCacheBytes: 100 * 1024,
            maxSingleFileBytes: 10 * 1024,
          ),
        );
        final largePayload = _generateMp4Payload(32 * 1024);
        final largeUrl = upstream.registerFile('/large.mp4', largePayload);
        final largeSource = NetworkVideoSource(largeUrl);

        final largeTarget = await engine.resolveForPlayback(largeSource);
        final streamedLarge = await _httpGetBytes(largeTarget.playUrl);
        expect(streamedLarge, equals(largePayload));
        expect(await engine.isCached(largeSource), isFalse);
        expect(await engine.getCacheSize(), equals(0));

        // 2. LRU eviction + active pin protection test: maxCacheBytes = 50 KiB, three 20 KiB files.
        await engine.configure(
          VideoCacheConfig(
            cacheDirectory: '${tempRoot.path}/cache_limits',
            maxCacheBytes: 50 * 1024,
            maxSingleFileBytes: 50 * 1024,
          ),
        );

        final bytesA = _generateMp4Payload(20 * 1024);
        final bytesB = _generateMp4Payload(20 * 1024);
        final bytesC = _generateMp4Payload(20 * 1024);

        final srcA = NetworkVideoSource(upstream.registerFile('/a.mp4', bytesA), cacheKey: 'vid-a');
        final srcB = NetworkVideoSource(upstream.registerFile('/b.mp4', bytesB), cacheKey: 'vid-b');
        final srcC = NetworkVideoSource(upstream.registerFile('/c.mp4', bytesC), cacheKey: 'vid-c');

        await engine.precache(srcA);
        await engine.precache(srcB);
        expect(await engine.isCached(srcA), isTrue);
        expect(await engine.isCached(srcB), isTrue);

        // Make A look oldest on disk, BUT pin A as actively playing!
        final keyA = VideoCacheKeyUtils.computeSha1Key('vid-a');
        final keyB = VideoCacheKeyUtils.computeSha1Key('vid-b');
        final fileA = (await LocalVideoCacheEngine.findCompleteFileInDir(
          await engine.resolveCacheDir(),
          keyA,
        ))!;
        final fileB = (await LocalVideoCacheEngine.findCompleteFileInDir(
          await engine.resolveCacheDir(),
          keyB,
        ))!;
        fileA.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 10)));
        fileB.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 5)));

        engine.pin(keyA);

        // Precaching C pushes total to 60 KiB > 50 KiB -> must skip pinned A and evict B!
        await engine.precache(srcC);
        expect(
          await engine.isCached(srcA),
          isTrue,
          reason: 'Pinned active video A must not be evicted',
        );
        expect(
          await engine.isCached(srcB),
          isFalse,
          reason: 'Unpinned older video B must be evicted',
        );
        expect(await engine.isCached(srcC), isTrue);
        expect(await engine.getCacheSize(), lessThanOrEqualTo(50 * 1024));

        // Unpin A and clearCache: now everything can be cleaned.
        engine.unpin(keyA);
        await engine.clearCache();
        expect(await engine.getCacheSize(), equals(0));
      } finally {
        await engine.dispose();
        await upstream.close();
      }
    });

    test(
      'supports partial head precache(preloadBytes) followed by full precache and removeCache',
      () async {
        final upstream = await _CountingUpstreamServer.start();
        final engine = LocalVideoCacheEngine();
        await engine.configure(VideoCacheConfig(cacheDirectory: '${tempRoot.path}/cache_precache'));

        try {
          final payload = _generateMp4Payload(40 * 1024);
          final url = upstream.registerFile('/feed/item1.mp4', payload);
          final source = NetworkVideoSource(url);

          await engine.precache(source, preloadBytes: 8192);
          expect(upstream.receivedRanges.last, equals('bytes=0-8191'));
          expect(await engine.isCached(source), isFalse);
          expect(await engine.getCacheSize(), greaterThanOrEqualTo(8192));

          // Complete remaining bytes via full precache: resumes from 8192!
          await engine.precache(source);
          expect(upstream.receivedRanges.last, equals('bytes=8192-'));
          expect(await engine.isCached(source), isTrue);

          await engine.removeCache(source);
          expect(await engine.isCached(source), isFalse);
          expect(await engine.getCacheSize(), equals(0));
        } finally {
          await engine.dispose();
          await upstream.close();
        }
      },
    );
  });

  group('VideoPlayerController cache + Cast isolation + buffered progress UI', () {
    test('preserves remote https castUrl when opening proxy or file:// cached video and updates bufferedPercent', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final upstream = await _CountingUpstreamServer.start();
      await VideoCacheManager.instance.configure(
        VideoCacheConfig(cacheDirectory: '${tempRoot.path}/controller_cache'),
      );

      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _FakeFullscreen(),
        brightness: _FakeBrightness(),
        cacheManager: VideoCacheManager.instance,
      );
      await controller.initialize();

      try {
        final payload = _generateMp4Payload(16 * 1024);
        final remoteUrl = upstream.registerFile('/castable.mp4', payload);

        // 1. Uncached network open on desktop: playUrl uses 127.0.0.1 proxy, castUrl stays remote!
        await controller.openNetwork(remoteUrl, cacheKey: 'cast-video-1');
        expect(backend.lastOpenedUrl, startsWith('http://127.0.0.1:'));
        expect(backend.lastCastUrl, equals(remoteUrl));

        backend.emit(const PlayerEvent.duration(Duration(seconds: 100)));
        backend.emit(const PlayerEvent.buffered(Duration(seconds: 35)));
        await Future<void>.delayed(Duration.zero);
        expect(controller.bufferedPosition.value, equals(const Duration(seconds: 35)));
        expect(controller.bufferedPercent.value, closeTo(0.35, 1e-6));

        // 2. Precache to 100% completion and re-open: playUrl uses file://, castUrl STILL stays remote,
        // and bufferedPercent immediately reflects 100% once duration arrives!
        await XueHuaNaviteVideoPlayer.instance.precache(
          VideoSource.network(remoteUrl, cacheKey: 'cast-video-1'),
        );
        await controller.openNetwork(remoteUrl, cacheKey: 'cast-video-1');
        expect(backend.lastOpenedUrl, startsWith('file://'));
        expect(backend.lastCastUrl, equals(remoteUrl));

        backend.emit(const PlayerEvent.duration(Duration(seconds: 80)));
        await Future<void>.delayed(Duration.zero);
        expect(controller.bufferedPosition.value, equals(const Duration(seconds: 80)));
        expect(controller.bufferedPercent.value, closeTo(1.0, 1e-6));
      } finally {
        await controller.dispose();
        await VideoCacheManager.instance.clearCache();
        await upstream.close();
      }
    });

    testWidgets('PlayerBottomScrubber renders dual-layer buffered track cleanly', (
      WidgetTester tester,
    ) async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _FakeFullscreen(),
        brightness: _FakeBrightness(),
      );
      await controller.initialize();
      await controller.openNetwork('https://example.com/demo.mp4');
      backend.emit(const PlayerEvent.duration(Duration(seconds: 120)));
      backend.emit(const PlayerEvent.position(Duration(seconds: 30)));
      backend.emit(const PlayerEvent.buffered(Duration(seconds: 90)));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 480,
                height: 270,
                child: VideoPlayer(
                  controller: controller,
                  initiallyVisible: true,
                  autoHideDelay: const Duration(minutes: 5),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(controller.bufferedPercent.value, closeTo(0.75, 1e-6));
      expect(find.byType(PlayerBottomScrubber), findsOneWidget);

      await controller.dispose();
    });
  });

  group('Network single-file Motion Photo cache reuse', () {
    test(
      'downloads single-file network Motion Photo only once across repeated resolutions',
      () async {
        final upstream = await _CountingUpstreamServer.start();
        try {
          final motionPhotoBytes = LivePhotoParser.createMotionPhotoBytes(
            imageBytes: _buildMinimalJpegBytes(),
            videoBytes: _generateMp4Payload(8192),
            presentationTimestamp: const Duration(milliseconds: 500),
          );
          final baseUrl = upstream.registerFile(
            '/moments/IMG_0001.JPG',
            motionPhotoBytes,
            contentType: 'image/jpeg',
          );

          final bundle1 = await LivePhotoExtractor.resolve(
            LivePhotoSource.network(imageUrl: '$baseUrl?token=first', cacheKey: 'moment-lp-001'),
          );
          expect(upstream.hitCount, equals(1));
          expect(await bundle1.imageFile!.length(), greaterThan(0));

          // Shut down upstream server completely: 2nd resolution with rotated token must hit disk cache!
          await upstream.close();

          final bundle2 = await LivePhotoExtractor.resolve(
            LivePhotoSource.network(imageUrl: '$baseUrl?token=second', cacheKey: 'moment-lp-001'),
          );
          expect(upstream.hitCount, equals(1));
          expect(bundle2.nativeVideoUrl, equals(bundle1.nativeVideoUrl));
          expect(await File(bundle2.imageFile!.path).exists(), isTrue);
        } finally {
          await upstream.close();
        }
      },
    );
  });
}
