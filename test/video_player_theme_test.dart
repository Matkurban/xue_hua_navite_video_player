import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
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

  group('Material vs Cupertino UI rendering', () {
    testWidgets('renders Material controls when VideoPlayerTheme.material is configured', (
      WidgetTester tester,
    ) async {
      final backend = _FakeBackend();
      final controller = VideoPlayerController(
        backend: backend,
        fullscreen: _NoopFullscreen(),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[
              VideoPlayerTheme.material(),
            ],
          ),
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

      // Material mode uses IconButton and Material icons (e.g. play_arrow_rounded, replay_10_rounded).
      expect(find.byType(IconButton), findsWidgets);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);

      // Buffering state uses CircularProgressIndicator in Material mode.
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

      // Buffering state uses CupertinoActivityIndicator in Cupertino mode.
      backend.emit(const PlayerEvent.duration(Duration(seconds: 30)));
      backend.emit(const PlayerEvent.buffering(true));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await controller.dispose();
    });
  });
}

class _FakeBackend implements PlayerBackend {
  final StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();
  final FlutterSignal<int?> _textureId = signal<int?>(1);

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
  Future<void> open(String url, {String? castUrl}) async {}

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
  Future<void> dispose() async {
    await _events.close();
  }

  @override
  Future<XFile> takeSnapshot({String? savePath}) async {
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
