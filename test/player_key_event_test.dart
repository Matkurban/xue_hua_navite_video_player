import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/aspect_ratio_mode.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/player/video_player_controller.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_gesture_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}

class _FakePlayerBackend implements PlayerBackend {
  final StreamController<PlayerEvent> _controller = StreamController<PlayerEvent>.broadcast();
  final FlutterSignal<int?> _textureId = signal<int?>(1);

  @override
  FlutterSignal<int?> get textureId => _textureId;

  @override
  Stream<PlayerEvent> get events => _controller.stream;

  @override
  Future<int> create() async => 1;

  @override
  Future<void> open(String url) async {}

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
  Future<void> dispose() async {}

  @override
  Future<XFile> takeSnapshot({String? savePath}) async {
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
