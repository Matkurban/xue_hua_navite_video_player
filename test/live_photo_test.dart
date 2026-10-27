import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/player/brightness_controller.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

/// Minimal valid 1x1 PNG image bytes for widget rendering tests.
final Uint8List _kSamplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Minimal valid JPEG SOI..EOI wrapper around sample payload.
Uint8List _buildMinimalJpegBytes() {
  return Uint8List.fromList(<int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, // APP0 JFIF
    0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00,
    0xFF, 0xD9, // EOI
  ]);
}

/// Minimal valid ISO BMFF MP4 header (`ftypisom` + `moov` box) with optional QuickTime content identifier.
Uint8List _buildMinimalMp4Bytes({String? contentIdentifier, String majorBrand = 'isom'}) {
  final brandBytes = ascii.encode(majorBrand.padRight(4).substring(0, 4));
  // 24-byte ftyp box: size=24, 'ftyp', majorBrand, minor_version=512, compat='isom','mp42'
  final ftyp = <int>[
    0x00, 0x00, 0x00, 0x18,
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    ...brandBytes,
    0x00, 0x00, 0x02, 0x00,
    0x69, 0x73, 0x6F, 0x6D, // 'isom'
    0x6D, 0x70, 0x34, 0x32, // 'mp42'
  ];

  final metaPayload = contentIdentifier != null
      ? ascii.encode('com.apple.quicktime.content.identifier:$contentIdentifier')
      : <int>[1, 2, 3, 4, 5, 6, 7, 8];
  final moovSize = 8 + metaPayload.length;
  final moov = <int>[
    (moovSize >> 24) & 0xFF,
    (moovSize >> 16) & 0xFF,
    (moovSize >> 8) & 0xFF,
    moovSize & 0xFF,
    0x6D, 0x6F, 0x6F, 0x76, // 'moov'
    ...metaPayload,
  ];

  return Uint8List.fromList(<int>[...ftyp, ...moov]);
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Materializing Motion Photo still/video files needs a temp directory.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  group('LivePhotoParser', () {
    test('createMotionPhotoBytes synthesizes valid XMP Motion Photo and round-trips via parseBytes', () {
      final jpeg = _buildMinimalJpegBytes();
      const uuid = '12345678-ABCD-4321-BCDE-112233445566';
      final mp4 = _buildMinimalMp4Bytes(contentIdentifier: uuid);
      const ts = Duration(milliseconds: 850);

      final motionPhotoBytes = LivePhotoParser.createMotionPhotoBytes(
        imageBytes: jpeg,
        videoBytes: mp4,
        presentationTimestamp: ts,
      );

      expect(LivePhotoParser.isMotionPhotoBytes(motionPhotoBytes), isTrue);

      final parsed = LivePhotoParser.parseBytes(motionPhotoBytes);
      expect(parsed, isNotNull);
      expect(parsed!.imageMimeType, 'image/jpeg');
      expect(parsed.videoMimeType, 'video/mp4');
      expect(parsed.videoBytes, equals(mp4));
      expect(parsed.metadata.format, LivePhotoFormat.gcameraMicroVideo);
      expect(parsed.metadata.videoLength, mp4.length);
      expect(parsed.metadata.presentationTimestamp, ts);
      expect(parsed.metadata.contentIdentifier, uuid);
      expect(parsed.metadata.isSingleFile, isTrue);
    });

    test('parses Android Motion Photo 1.0 Container:Item XMP format', () {
      final jpeg = _buildMinimalJpegBytes();
      final mp4 = _buildMinimalMp4Bytes(majorBrand: 'mp42');
      final xmp =
          '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
          '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
          '<rdf:Description '
          'GCamera:MotionPhoto="1" '
          'GCamera:MotionPhotoPresentationTimestampUs="420000">'
          '<Container:Directory><rdf:Seq>'
          '<rdf:li><Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary"/></rdf:li>'
          '<rdf:li><Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="${mp4.length}"/></rdf:li>'
          '</rdf:Seq></Container:Directory>'
          '</rdf:Description>'
          '</rdf:RDF></x:xmpmeta>';

      final combined = Uint8List.fromList(<int>[
        ...jpeg,
        ...utf8.encode(xmp),
        ...mp4,
      ]);

      final parsed = LivePhotoParser.parseBytes(combined);
      expect(parsed, isNotNull);
      expect(parsed!.metadata.format, LivePhotoFormat.androidMotionPhoto);
      expect(parsed.metadata.presentationTimestamp, const Duration(milliseconds: 420));
      expect(parsed.videoBytes, equals(mp4));
    });

    test('parses Samsung MotionPhoto_Data marker format', () {
      final jpeg = _buildMinimalJpegBytes();
      final mp4 = _buildMinimalMp4Bytes(majorBrand: 'qt  ');
      final marker = ascii.encode('MotionPhoto_Data');

      final combined = Uint8List.fromList(<int>[
        ...jpeg,
        ...marker,
        ...mp4,
      ]);

      final parsed = LivePhotoParser.parseBytes(combined);
      expect(parsed, isNotNull);
      expect(parsed!.metadata.format, LivePhotoFormat.samsungMotionPhoto);
      expect(parsed.imageBytes, equals(jpeg));
      expect(parsed.videoBytes, equals(mp4));
      expect(parsed.videoMimeType, 'video/quicktime');
    });

    test('parses generic embedded MP4 trailer when XMP is stripped', () {
      final jpeg = _buildMinimalJpegBytes();
      final mp4 = _buildMinimalMp4Bytes();
      final combined = Uint8List.fromList(<int>[...jpeg, ...mp4]);

      final parsed = LivePhotoParser.parseBytes(combined);
      expect(parsed, isNotNull);
      expect(parsed!.metadata.format, LivePhotoFormat.embeddedMp4);
      expect(parsed.imageBytes, equals(jpeg));
      expect(parsed.videoBytes, equals(mp4));
    });

    test('returns null for standalone MP4 or plain JPEG without embedded video', () {
      final jpeg = _buildMinimalJpegBytes();
      final mp4 = _buildMinimalMp4Bytes();

      expect(LivePhotoParser.parseBytes(jpeg), isNull);
      expect(LivePhotoParser.parseBytes(mp4), isNull);
    });
  });

  group('LivePhotoExtractor & XueHuaNaviteVideoPlayer probe APIs', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('xh_live_photo_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts single-file Motion Photo from disk and caches cover + video files', () async {
      final mp4 = _buildMinimalMp4Bytes();
      final motionBytes = LivePhotoParser.createMotionPhotoBytes(
        imageBytes: _kSamplePngBytes,
        videoBytes: mp4,
        presentationTimestamp: const Duration(milliseconds: 500),
      );
      final motionFile = File('${tempDir.path}/MVIMG_0001.jpg');
      await motionFile.writeAsBytes(motionBytes, flush: true);

      final isLive = await XueHuaNaviteVideoPlayer.instance.isLivePhoto(
        VideoSource.file(motionFile.path),
      );
      expect(isLive, isTrue);

      final bundle = await XueHuaNaviteVideoPlayer.instance.extractLivePhoto(
        VideoSource.file(motionFile.path),
      );
      expect(bundle, isNotNull);
      expect(bundle!.metadata.format, LivePhotoFormat.gcameraMicroVideo);
      expect(bundle.metadata.presentationTimestamp, const Duration(milliseconds: 500));
      expect(bundle.imageFile, isNotNull);
      expect(await bundle.imageFile!.readAsBytes(), isNotEmpty);
      expect(bundle.nativeVideoUrl, startsWith('file://'));
    });

    test('auto-discovers sibling .MOV companion file when given a local image path', () async {
      final imgFile = File('${tempDir.path}/IMG_2026.JPG');
      final movFile = File('${tempDir.path}/IMG_2026.MOV');
      await imgFile.writeAsBytes(_kSamplePngBytes, flush: true);
      await movFile.writeAsBytes(_buildMinimalMp4Bytes(majorBrand: 'qt  '), flush: true);

      final bundle = await XueHuaNaviteVideoPlayer.instance.extractLivePhoto(
        VideoSource.file(imgFile.path),
      );
      expect(bundle, isNotNull);
      expect(bundle!.metadata.format, LivePhotoFormat.paired);
      expect(bundle.imageFile?.path, imgFile.path);
      expect(bundle.nativeVideoUrl, Uri.file(movFile.path).toString());
    });

    test('extracts paired Live Photo from macOS .pvt bundle directory', () async {
      final pvtDir = Directory('${tempDir.path}/IMG_9999.pvt');
      await pvtDir.create(recursive: true);
      final imgFile = File('${pvtDir.path}/IMG_9999.HEIC');
      final movFile = File('${pvtDir.path}/IMG_9999.MOV');
      await imgFile.writeAsBytes(_kSamplePngBytes, flush: true);
      await movFile.writeAsBytes(_buildMinimalMp4Bytes(majorBrand: 'qt  '), flush: true);

      final bundle = await XueHuaNaviteVideoPlayer.instance.extractLivePhoto(
        VideoSource.file(pvtDir.path),
      );
      expect(bundle, isNotNull);
      expect(bundle!.metadata.format, LivePhotoFormat.paired);
      expect(bundle.imageFile?.path, imgFile.path);
      expect(bundle.nativeVideoUrl, Uri.file(movFile.path).toString());
    });
  });

  group('VideoPlayerController Live Photo & Looping', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('xh_ctrl_live_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('playLivePhoto and auto-detected Motion Photo file populate Live Photo signals', () async {
      final mp4 = _buildMinimalMp4Bytes();
      final motionBytes = LivePhotoParser.createMotionPhotoBytes(
        imageBytes: _kSamplePngBytes,
        videoBytes: mp4,
        presentationTimestamp: const Duration(milliseconds: 300),
      );
      final motionFile = File('${tempDir.path}/motion_sample.jpg');
      await motionFile.writeAsBytes(motionBytes, flush: true);

      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _FakeFullscreen(),
        brightness: _FakeBrightness(),
      );
      await controller.initialize();

      // 1. Auto-detects Motion Photo when opened via playFile(.jpg)
      await controller.playFile(motionFile.path);
      expect(controller.isLivePhoto.value, isTrue);
      expect(controller.isVideo.value, isTrue);
      expect(controller.livePhotoMetadata.value?.format, LivePhotoFormat.gcameraMicroVideo);
      expect(controller.livePhotoStillImage.value, isNotNull);
      expect(backend.lastOpenedUrl, endsWith('-motion.mp4'));

      // 2. Explicit playLivePhoto with loop: true
      final pairedSource = LivePhotoSource.paired(
        image: VideoSource.network('https://example.com/still.jpg'),
        video: VideoSource.network('https://example.com/motion.mov'),
      );
      await controller.playLivePhoto(pairedSource, loop: true);
      expect(controller.isLivePhoto.value, isTrue);
      expect(controller.isLooping.value, isTrue);
      expect(controller.livePhotoMetadata.value?.format, LivePhotoFormat.paired);
      expect(backend.lastOpenedUrl, 'https://example.com/motion.mov');

      // 3. When isLooping is true, PlayerCompletedEvent seeks to 0 and continues playing
      backend.emit(const PlayerEvent.duration(Duration(seconds: 2)));
      backend.emit(const PlayerEvent.playing(true));
      backend.emit(const PlayerEvent.position(Duration(seconds: 2)));
      await Future<void>.delayed(Duration.zero);

      backend.emit(const PlayerEvent.completed());
      await Future<void>.delayed(Duration.zero);

      expect(controller.playState.value, PlayState.playing);
      expect(controller.position.value, Duration.zero);
      expect(backend.lastSeekMs, 0);

      // 4. Disable looping -> completed transitions to PlayState.completed
      controller.setLooping(false);
      backend.emit(const PlayerEvent.completed());
      await Future<void>.delayed(Duration.zero);
      expect(controller.playState.value, PlayState.completed);

      await controller.dispose();
    });
  });

  

  test('opening bare Apple Live Photo HEIC does not open as video (avoids black stage)', () async {
    final fixture = File('example/assets/live_photo/IMG_0037.HEIC');
    expect(fixture.existsSync(), isTrue);
    final backend = _FakePlayerBackend();
    final controller = VideoPlayerController(
      backend: backend,
      fullscreen: _FakeFullscreen(),
      brightness: _FakeBrightness(),
    );
    await controller.initialize();
    await controller.playFile(fixture.path);
    await Future<void>.delayed(Duration.zero);
    expect(backend.lastOpenedUrl, isNull, reason: 'must not open HEIC as video URL');
    expect(controller.playState.value, PlayState.error);
    expect(controller.errorMessage.value, contains('Not a playable Motion Photo'));
    await controller.dispose();
  });

  test('Apple Live Photo HEIC stills (MiPr) are detected without embedded video', () async {
    final fixture = File('example/assets/live_photo/IMG_0262_4CDAA1F2.HEIC');
    expect(fixture.existsSync(), isTrue, reason: 'real HEIC fixture must exist');
    final bytes = Uint8List.fromList(fixture.readAsBytesSync());
    expect(LivePhotoParser.isAppleLivePhotoStillBytes(bytes), isTrue);
    expect(LivePhotoParser.isVivoLivePhotoMarkerBytes(bytes), isTrue);
    expect(LivePhotoParser.parseBytes(bytes), isNull,
        reason: 'MiPr still has no embedded motion stream; needs paired .MOV');
  });

  test('IMG_0037.HEIC is Apple Live Photo still without vivo trailer', () async {
    final fixture = File('example/assets/live_photo/IMG_0037.HEIC');
    expect(fixture.existsSync(), isTrue);
    final bytes = Uint8List.fromList(fixture.readAsBytesSync());
    expect(LivePhotoParser.isAppleLivePhotoStillBytes(bytes), isTrue);
    expect(LivePhotoParser.isVivoLivePhotoMarkerBytes(bytes), isFalse);
    expect(LivePhotoParser.parseBytes(bytes), isNull);
  });

  group('LivePhotoPlayer & LivePhotoBadge Widgets', () {
    testWidgets('LivePhotoPlayer supports tap and badge trigger, mute toggle, and completion reset', (
      WidgetTester tester,
    ) async {
      final source = LivePhotoSource.paired(
        image: VideoSource.network('https://example.com/still.jpg'),
        video: VideoSource.network('https://example.com/motion.mov'),
      );

      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _FakeFullscreen(),
        brightness: _FakeBrightness(),
      );
      await controller.initialize();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      var startCount = 0;
      var completeCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: LivePhotoPlayer(
                source: source,
                controller: controller,
                playMode: LivePhotoPlayMode.tap,
                enableHapticFeedback: false,
                onPlaybackStart: () => startCount++,
                onPlaybackComplete: () => completeCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();

      final badgeFinder = find.byKey(const ValueKey<String>('live_photo_badge'));
      final muteFinder = find.byKey(const ValueKey<String>('live_photo_mute_button'));
      expect(badgeFinder, findsOneWidget);
      expect(muteFinder, findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);

      await tester.tap(muteFinder);
      await tester.pump();
      expect(controller.muted.value, isTrue);

      await tester.tap(badgeFinder);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (backend.lastOpenedUrl != null) break;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      expect(backend.lastOpenedUrl, 'https://example.com/motion.mov');

      if (controller.playState.value != PlayState.playing) {
        backend.emit(const PlayerEvent.duration(Duration(milliseconds: 1500)));
        backend.emit(const PlayerEvent.playing(true));
      }
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(startCount, greaterThanOrEqualTo(1));
      final stillOpacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey<String>('live_photo_still_opacity')),
      );
      expect(stillOpacity.opacity, 0.0);
      expect(find.byKey(const ValueKey<String>('live_photo_video_surface')), findsOneWidget);

      final corePlayer = find.byType(CorePlayer);
      expect(corePlayer, findsWidgets);
      expect(
        find.ancestor(of: corePlayer.first, matching: find.byType(AnimatedOpacity)),
        findsNothing,
      );
      expect(
        find.ancestor(of: corePlayer.first, matching: find.byType(AnimatedScale)),
        findsNothing,
      );

      backend.emit(const PlayerEvent.completed());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(completeCount, greaterThanOrEqualTo(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final stillAfterComplete = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey<String>('live_photo_still_opacity')),
      );
      expect(stillAfterComplete.opacity, 1.0);

      debugDefaultTargetPlatformOverride = null;
      await controller.dispose();
    });

    testWidgets(
      'LivePhotoPlayer keeps CorePlayer free of ClipRRect when borderRadius is set',
      (WidgetTester tester) async {
      final source = LivePhotoSource.paired(
        image: VideoSource.network('https://example.com/still.jpg'),
        video: VideoSource.network('https://example.com/motion.mov'),
      );

      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _FakeFullscreen(),
        brightness: _FakeBrightness(),
      );
      await controller.initialize();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: LivePhotoPlayer(
                source: source,
                controller: controller,
                playMode: LivePhotoPlayMode.tap,
                enableHapticFeedback: false,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('live_photo_badge')));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (backend.lastOpenedUrl != null) break;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      if (controller.playState.value != PlayState.playing) {
        backend.emit(const PlayerEvent.duration(Duration(milliseconds: 800)));
        backend.emit(const PlayerEvent.playing(true));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final corePlayer = find.byType(CorePlayer);
      expect(corePlayer, findsWidgets);
      expect(
        find.ancestor(of: corePlayer.first, matching: find.byType(ClipRRect)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('live_photo_video_surface')), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
      await controller.dispose();
    });

    testWidgets('VideoPlayer displays LIVE badge in top bar when Live Photo source is opened', (
      WidgetTester tester,
    ) async {
      final source = LivePhotoSource.paired(
        image: VideoSource.network('https://example.com/still.jpg'),
        video: VideoSource.network('https://example.com/motion.mov'),
      );

      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _FakeFullscreen(),
        brightness: _FakeBrightness(),
      );
      await controller.initialize();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await controller.openLivePhoto(source);
      expect(controller.isLivePhoto.value, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: VideoPlayer(
                controller: controller,
                autoHideDelay: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(LivePhotoBadge), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
      await controller.dispose();
    });
  });

}


class _FakePlayerBackend implements PlayerBackend {
  final _controller = StreamController<PlayerEvent>.broadcast();
  final FlutterSignal<int?> _textureId = signal<int?>(null);

  String? lastOpenedUrl;
  int? lastSeekMs;

  @override
  FlutterSignal<int?> get textureId => _textureId;

  @override
  Stream<PlayerEvent> get events => _controller.stream;

  @override
  Future<int> create() async {
    _textureId.value = 1;
    return 1;
  }

  @override
  Future<void> open(String url, {String? castUrl}) async {
    lastOpenedUrl = url;
  }

  @override
  Future<void> play() async {
    emit(const PlayerEvent.playing(true));
  }

  @override
  Future<void> pause() async {
    emit(const PlayerEvent.playing(false));
  }

  @override
  Future<void> seek(int positionMs) async {
    lastSeekMs = positionMs;
    emit(PlayerEvent.position(Duration(milliseconds: positionMs)));
  }

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
  Future<void> dispose() async {
    _textureId.value = null;
  }

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) async {
    throw UnsupportedError('not used in tests');
  }

  void emit(PlayerEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }
}

class _FakeFullscreen implements FullscreenCoordinator {
  final StreamController<bool> external = StreamController<bool>.broadcast();

  @override
  Stream<bool> get externalChanges => external.stream;

  @override
  Future<void> enter({required bool landscapeVideo}) async {}

  @override
  Future<void> exit() async {}

  @override
  void dispose() {
    external.close();
  }
}

class _FakeBrightness implements BrightnessController {
  double value = 1.0;

  @override
  Future<double> get current async => value;

  @override
  Future<void> setBrightness(double v) async {
    value = v.clamp(0.0, 1.0);
  }
}
