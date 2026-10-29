import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/player/brightness_controller.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/ui/style/player_icon_catalog.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_glass_surface.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('VideoPlayerDesignStyle & VideoPlayerTheme', () {
    test('adaptive resolves to cupertino on iOS/macOS and material on Android/Windows/Linux', () {
      expect(
        VideoPlayerDesignStyle.adaptive.resolve(TargetPlatform.iOS),
        VideoPlayerDesignStyle.cupertino,
      );
      expect(
        VideoPlayerDesignStyle.adaptive.resolve(TargetPlatform.macOS),
        VideoPlayerDesignStyle.cupertino,
      );
      expect(
        VideoPlayerDesignStyle.adaptive.resolve(TargetPlatform.android),
        VideoPlayerDesignStyle.material,
      );
      expect(
        VideoPlayerDesignStyle.adaptive.resolve(TargetPlatform.windows),
        VideoPlayerDesignStyle.material,
      );
      expect(
        VideoPlayerDesignStyle.adaptive.resolve(TargetPlatform.linux),
        VideoPlayerDesignStyle.material,
      );
    });

    test('VideoPlayerTheme presets set expected designStyle and properties', () {
      const mat = VideoPlayerTheme.material();
      expect(mat.designStyle, VideoPlayerDesignStyle.material);
      expect(mat.isCupertino, isFalse);
      expect(mat.backdropBlurSigma, 0.0);

      const cup = VideoPlayerTheme.cupertino();
      expect(cup.designStyle, VideoPlayerDesignStyle.cupertino);
      expect(cup.isCupertino, isTrue);
      expect(cup.backdropBlurSigma, greaterThan(0));

      final adaptiveIos = VideoPlayerTheme.adaptive(TargetPlatform.iOS);
      expect(adaptiveIos.designStyle, VideoPlayerDesignStyle.cupertino);

      final adaptiveAndroid = VideoPlayerTheme.adaptive(TargetPlatform.android);
      expect(adaptiveAndroid.designStyle, VideoPlayerDesignStyle.material);
    });

    test('copyWith and lerp preserve and interpolate theme properties', () {
      const mat = VideoPlayerTheme.material();
      const cup = VideoPlayerTheme.cupertino();

      final copied = mat.copyWith(designStyle: VideoPlayerDesignStyle.cupertino);
      expect(copied.designStyle, VideoPlayerDesignStyle.cupertino);

      final lerpedEarly = mat.lerp(cup, 0.2);
      expect(lerpedEarly.designStyle, VideoPlayerDesignStyle.material);

      final lerpedLate = mat.lerp(cup, 0.8);
      expect(lerpedLate.designStyle, VideoPlayerDesignStyle.cupertino);
      expect(lerpedLate.backdropBlurSigma, greaterThan(0));
    });
  });

  group('Material vs Cupertino UI rendering & bug regressions', () {
    testWidgets('renders Material controls when VideoPlayerTheme.material is configured', (
      WidgetTester tester,
    ) async {
      final backend = _FakeBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _NoopFullscreen(),
        brightness: _NoopBrightness(),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[VideoPlayerTheme.material()],
          ),
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: VideoPlayer(controller: controller, autoHideDelay: Duration.zero),
            ),
          ),
        ),
      );
      await tester.pump();

      // Material mode uses IconButton and Material icons (e.g. play_arrow_rounded, replay_10_rounded).
      expect(find.byType(IconButton), findsWidgets);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);

      // Buffering state uses CircularProgressIndicator in Material mode.
      await controller.openNetwork('https://example.com/sample.mp4');
      backend.emit(const PlayerEvent.duration(Duration(seconds: 30)));
      backend.emit(const PlayerEvent.buffering(true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);

      await controller.dispose();
    });

    testWidgets('renders Cupertino controls when VideoPlayerTheme.cupertino is configured', (
      WidgetTester tester,
    ) async {
      final backend = _FakeBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _NoopFullscreen(),
        brightness: _NoopBrightness(),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: VideoPlayer(
                controller: controller,
                theme: const VideoPlayerTheme.cupertino(),
                autoHideDelay: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Cupertino mode uses CupertinoButton, PlayerGlassSurface, and CupertinoIcons.
      expect(find.byType(CupertinoButton), findsWidgets);
      expect(find.byType(PlayerGlassSurface), findsWidgets);
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.gobackward_10), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.goforward_10), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      // Aspect ratio and fullscreen buttons use distinct icons in Cupertino mode.
      final aspectIcon = PlayerIconCatalog.aspectRatio(isCupertino: true);
      final fullscreenIcon = PlayerIconCatalog.fullscreen(isCupertino: true, isFullscreen: false);
      expect(aspectIcon, isNot(equals(fullscreenIcon)));
      expect(find.byIcon(CupertinoIcons.viewfinder), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.fullscreen), findsOneWidget);

      // Buffering state uses CupertinoActivityIndicator in Cupertino mode.
      await controller.openNetwork('https://example.com/sample.mp4');
      backend.emit(const PlayerEvent.duration(Duration(seconds: 30)));
      backend.emit(const PlayerEvent.buffering(true));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await controller.dispose();
    });

    test('seek while completed transitions state to paused so subsequent play resumes at seeked position', () async {
      final backend = _FakeBackend();
      final controller = VideoPlayerController(backend: backend, fullscreen: _NoopFullscreen());
      await controller.initialize();
      await controller.playNetwork('https://example.com/sample.mp4');

      backend.emit(const PlayerEvent.duration(Duration(seconds: 60)));
      backend.emit(const PlayerEvent.playing(true));
      backend.emit(const PlayerEvent.position(Duration(seconds: 60)));
      await Future<void>.delayed(Duration.zero);

      backend.emit(const PlayerEvent.playing(false));
      backend.emit(const PlayerEvent.completed());
      await Future<void>.delayed(Duration.zero);
      expect(controller.playState.value, PlayState.completed);

      // Seek back to 20s while in completed state.
      await controller.seek(const Duration(seconds: 20));
      expect(controller.position.value, const Duration(seconds: 20));
      expect(controller.playState.value, PlayState.paused);

      // Calling play() should resume from 20s instead of seeking back to 0.
      await controller.play();
      expect(backend.lastSeekMs, 20000);

      await controller.dispose();
    });
  });
}

class _FakeBackend implements PlayerBackend {
  final StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast(sync: true);
  final FlutterSignal<int?> _textureId = signal<int?>(1);
  int? lastSeekMs;

  void emit(PlayerEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  @override
  FlutterSignal<int?> get textureId => _textureId;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<int> create() async => 1;

  @override
  Future<void> open(
    String url, {
    String? castUrl,
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {
    lastSeekMs = positionMs;
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
  Future<void> dispose() async {}

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) async {
    throw UnsupportedError('not used');
  }
}

class _NoopFullscreen implements FullscreenCoordinator {
  @override
  Stream<bool> get externalChanges => const Stream<bool>.empty();

  @override
  Future<void> enter({required bool landscapeVideo}) async {}

  @override
  Future<void> exit() async {}

  @override
  void dispose() {}
}

class _NoopBrightness implements BrightnessController {
  @override
  Future<double> get current async => 1.0;

  @override
  Future<void> setBrightness(double value) async {}
}
