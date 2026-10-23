import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/aspect_ratio_mode.dart';
import 'package:xue_hua_navite_video_player/src/data/models/navite_file.dart';
import 'package:xue_hua_navite_video_player/src/player/brightness_controller.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/player/video_player_controller.dart';
import 'package:xue_hua_navite_video_player/src/ui/video_player.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_bottom_scrubber.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_center_controls.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_gesture_layer.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_top_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Escape exits fullscreen when already fullscreen', () async {
    final backend = _FakePlayerBackend();
    final fs = _FakeFullscreen();
    final controller = VideoPlayerController(backend: backend, fullscreen: fs);
    await controller.initialize();
    await controller.enterFullscreen();

    final result = handlePlayerKeyEvent(
      controller,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );

    expect(result, KeyEventResult.handled);
    await Future<void>.delayed(Duration.zero);
    expect(controller.isFullscreen.value, isFalse);
    expect(fs.exitCount, 1);
    await controller.dispose();
  });

  test('Escape is ignored when not fullscreen', () async {
    final backend = _FakePlayerBackend();
    final fs = _FakeFullscreen();
    final controller = VideoPlayerController(backend: backend, fullscreen: fs);
    await controller.initialize();

    final result = handlePlayerKeyEvent(
      controller,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );

    expect(result, KeyEventResult.ignored);
    expect(fs.exitCount, 0);
    await controller.dispose();
  });

  testWidgets('Desktop keyboard control hides controls and does not show them on seek buffering', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final backend = _FakePlayerBackend(emitBufferingOnSeek: true);
    final fs = _FakeFullscreen();
    final controller = VideoPlayerController(
      backend: backend,
      fullscreen: fs,
      brightness: _FakeBrightness(),
    );
    await controller.initialize();
    await controller.playNetwork('https://example.com/video.mp4');
    backend.emit(const PlayerEvent.duration(Duration(seconds: 60)));
    backend.emit(const PlayerEvent.playing(true));
    backend.emit(const PlayerEvent.position(Duration(seconds: 10)));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: VideoPlayer(
              controller: controller,
              initiallyVisible: true,
              fadeDuration: Duration.zero,
              autoHideDelay: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PlayerTopBar), findsOneWidget);
    expect(find.byType(PlayerCenterControls), findsOneWidget);
    expect(find.byType(PlayerBottomScrubber), findsOneWidget);

    // Pressing ArrowRight seeks forward and hides the controls even if backend emits buffering=true.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(backend.lastSeekMs, 30000);
    expect(find.byType(PlayerTopBar), findsNothing);
    expect(find.byType(PlayerCenterControls), findsNothing);
    expect(find.byType(PlayerBottomScrubber), findsNothing);

    // Pressing Space toggles play/pause while keeping controls hidden.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(backend.pauseCount, 1);
    expect(find.byType(PlayerTopBar), findsNothing);
    expect(find.byType(PlayerCenterControls), findsNothing);
    expect(find.byType(PlayerBottomScrubber), findsNothing);

    await controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}

class _FakePlayerBackend implements PlayerBackend {
  _FakePlayerBackend({this.emitBufferingOnSeek = false});

  final bool emitBufferingOnSeek;
  final StreamController<PlayerEvent> _controller = StreamController<PlayerEvent>.broadcast(
    sync: true,
  );
  final FlutterSignal<int?> _textureId = signal<int?>(1);
  int? lastSeekMs;
  int pauseCount = 0;

  void emit(PlayerEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  FlutterSignal<int?> get textureId => _textureId;

  @override
  Stream<PlayerEvent> get events => _controller.stream;

  @override
  Future<int> create() async => 1;

  @override
  Future<void> open(String url, {String? castUrl}) async {}

  @override
  Future<void> play() async {
    emit(const PlayerEvent.playing(true));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emit(const PlayerEvent.playing(false));
  }

  @override
  Future<void> seek(int positionMs) async {
    lastSeekMs = positionMs;
    if (emitBufferingOnSeek) {
      emit(const PlayerEvent.buffering(true));
    }
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
  Future<void> dispose() async {}

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) async {
    throw UnsupportedError('not used');
  }
}

class _FakeFullscreen implements FullscreenCoordinator {
  int exitCount = 0;

  @override
  Stream<bool> get externalChanges => const Stream<bool>.empty();

  @override
  Future<void> enter({required bool landscapeVideo}) async {}

  @override
  Future<void> exit() async {
    exitCount++;
  }

  @override
  void dispose() {}
}

class _FakeBrightness implements BrightnessController {
  @override
  Future<double> get current async => 1.0;

  @override
  Future<void> setBrightness(double value) async {}
}
