import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/aspect_ratio_mode.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/play_state.dart';
import 'package:xue_hua_navite_video_player/src/data/enums/skip_second_type.dart';
import 'package:xue_hua_navite_video_player/src/player/brightness_controller.dart';
import 'package:xue_hua_navite_video_player/src/player/channel_player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/player/video_player_controller.dart';
import 'dart:async';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPlayerController', () {
    late Directory tempDir;
    late File mediaFile;
    late File mediaFileB;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fcvp-controller-test-');
      mediaFile = File('${tempDir.path}/sample.mp4');
      mediaFileB = File('${tempDir.path}/sample-b.mp4');
      await mediaFile.writeAsBytes(List<int>.filled(32, 7), flush: true);
      await mediaFileB.writeAsBytes(List<int>.filled(32, 9), flush: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('openFile leaves loading when duration arrives before playing', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.openFile(mediaFile.path);

      expect(controller.playState.value, PlayState.loading);

      backend.emit(const PlayerEvent.duration(Duration(seconds: 5)));
      await Future<void>.delayed(Duration.zero);

      expect(controller.playState.value, PlayState.paused);
      expect(controller.duration.value, const Duration(seconds: 5));
      expect(controller.isBuffering.value, isFalse);

      await controller.dispose();
    });

    test('openFile leaves loading when video size arrives before duration', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.openFile(mediaFile.path);

      expect(controller.playState.value, PlayState.loading);

      backend.emit(const PlayerEvent.videoSize(Size(640, 360), 0));
      await Future<void>.delayed(Duration.zero);

      expect(controller.playState.value, PlayState.paused);
      expect(controller.videoSize.value, const Size(640, 360));

      await controller.dispose();
    });

    test('playFile opens and starts playback', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.playFile(mediaFile.path);

      await Future<void>.delayed(Duration.zero);
      expect(controller.playState.value, PlayState.playing);

      backend.emit(const PlayerEvent.duration(Duration(seconds: 8)));
      backend.emit(const PlayerEvent.position(Duration(seconds: 2)));
      await Future<void>.delayed(Duration.zero);

      expect(controller.playState.value, PlayState.playing);
      expect(controller.duration.value, const Duration(seconds: 8));
      expect(controller.position.value, const Duration(seconds: 2));

      await controller.dispose();
    });

    test('keeps stopped state when the native player later reports paused', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.playFile(mediaFile.path);

      backend.emit(const PlayerEvent.duration(Duration(seconds: 6)));
      backend.emit(const PlayerEvent.playing(true));
      backend.emit(const PlayerEvent.position(Duration(seconds: 1)));
      await Future<void>.delayed(Duration.zero);

      await controller.stop();
      backend.emit(const PlayerEvent.playing(false));
      await Future<void>.delayed(Duration.zero);

      expect(controller.playState.value, PlayState.stopped);

      await controller.dispose();
    });

    test('keeps playing while buffering even if native reports playing=false', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.playFile(mediaFile.path);
      backend.emit(const PlayerEvent.duration(Duration(seconds: 10)));
      backend.emit(const PlayerEvent.playing(true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.playState.value, PlayState.playing);

      backend.emit(const PlayerEvent.buffering(true));
      backend.emit(const PlayerEvent.playing(false));
      await Future<void>.delayed(Duration.zero);

      expect(controller.playState.value, PlayState.playing);
      expect(controller.isBuffering.value, isTrue);

      await controller.dispose();
    });

    test('completed is distinct from stop and replay seeks to zero', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.playFile(mediaFile.path);
      backend.emit(const PlayerEvent.duration(Duration(seconds: 4)));
      backend.emit(const PlayerEvent.playing(true));
      backend.emit(const PlayerEvent.position(Duration(seconds: 4)));
      await Future<void>.delayed(Duration.zero);

      backend.emit(const PlayerEvent.completed());
      await Future<void>.delayed(Duration.zero);
      expect(controller.playState.value, PlayState.completed);

      await controller.play();
      expect(backend.lastSeekMs, 0);
      expect(controller.position.value, Duration.zero);

      await controller.dispose();
    });

    test('concurrent openSource keeps the later URL', () async {
      final backend = _FakePlayerBackend(openDelay: const Duration(milliseconds: 40));
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      final first = controller.openFile(mediaFile.path);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = controller.openFile(mediaFileB.path);
      await Future.wait([first, second]);

      expect(backend.lastOpenedUrl, contains('sample-b.mp4'));
      expect(controller.currentUrl.value, contains('sample-b.mp4'));

      await controller.dispose();
    });

    test('re-applies volume and speed after open', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.setVolume(0.25);
      await controller.setSpeed(1.5);
      await controller.openFile(mediaFile.path);

      expect(backend.lastVolume, closeTo(0.25, 0.001));
      expect(backend.lastSpeed, closeTo(1.5, 0.001));

      await controller.dispose();
    });

    test('dispose then recreate still receives events', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);

      await controller.initialize();
      await controller.dispose();

      final controller2 = VideoPlayerController(backend: backend);
      await controller2.initialize();
      await controller2.openFile(mediaFile.path);
      backend.emit(const PlayerEvent.duration(Duration(seconds: 3)));
      await Future<void>.delayed(Duration.zero);

      expect(controller2.playState.value, PlayState.paused);
      expect(controller2.duration.value, const Duration(seconds: 3));

      await controller2.dispose();
    });

    test('setMuted / toggleMuted restores prior volume', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);
      await controller.initialize();
      await controller.setVolume(0.4);
      await controller.setMuted(true);
      expect(controller.muted.value, isTrue);
      expect(backend.lastVolume, 0.0);
      await controller.toggleMuted();
      expect(controller.muted.value, isFalse);
      expect(controller.volume.value, 0.4);
      await controller.dispose();
    });

    test('setSkipSecondType and seekForward / seekBackward', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);
      await controller.initialize();
      await controller.playFile(mediaFile.path);
      backend.emit(const PlayerEvent.duration(Duration(seconds: 60)));
      backend.emit(const PlayerEvent.position(Duration(seconds: 20)));
      await Future<void>.delayed(Duration.zero);

      controller.setSkipSecondType(SkipSecondType.second5);
      expect(controller.skipSecondType.value, SkipSecondType.second5);
      await controller.seekForward();
      expect(backend.lastSeekMs, 25000);
      await controller.seekBackward();
      expect(backend.lastSeekMs, 20000);
      await controller.dispose();
    });

    test('setAspectRatioMode forwards to backend', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);
      await controller.initialize();
      expect(backend.lastAspectRatioMode, AspectRatioMode.fit);
      await controller.setAspectRatioMode(AspectRatioMode.fill);
      expect(controller.aspectRatioMode.value, AspectRatioMode.fill);
      expect(backend.lastAspectRatioMode, AspectRatioMode.fill);
      await controller.dispose();
    });

    test('setVideoViewSize forwards to backend', () async {
      final backend = _FakePlayerBackend();
      final controller = VideoPlayerController(backend: backend);
      await controller.initialize();
      await controller.setVideoViewSize(width: 320, height: 180, devicePixelRatio: 2);
      expect(backend.lastViewWidth, 320);
      expect(backend.lastViewHeight, 180);
      expect(backend.lastViewDpr, 2);
      await controller.dispose();
    });

    test('enterFullscreen / exitFullscreen / toggleFullscreen', () async {
      final backend = _FakePlayerBackend();
      final fs = _FakeFullscreen();
      final controller = VideoPlayerController(backend: backend, fullscreen: fs);
      await controller.initialize();
      backend.emit(const PlayerEvent.videoSize(Size(1920, 1080), 0));
      await Future<void>.delayed(Duration.zero);

      await controller.enterFullscreen();
      expect(controller.isFullscreen.value, isTrue);
      expect(fs.entered, isTrue);
      expect(fs.lastLandscape, isTrue);

      await controller.exitFullscreen();
      expect(controller.isFullscreen.value, isFalse);
      expect(fs.entered, isFalse);

      await controller.toggleFullscreen();
      expect(controller.isFullscreen.value, isTrue);
      await controller.dispose();
    });

    test('setBrightness updates signal via BrightnessController', () async {
      final backend = _FakePlayerBackend();
      final brightness = _FakeBrightness();
      final controller = VideoPlayerController(backend: backend, brightness: brightness);
      await controller.initialize();
      await controller.setBrightness(0.35);
      expect(controller.brightness.value, 0.35);
      expect(brightness.value, 0.35);
      await controller.dispose();
    });
  });

  group('ChannelPlayerBackend.decodeEventForTest', () {
    test('accepts num payloads for position and duration', () {
      final position = ChannelPlayerBackend.decodeEventForTest({
        'event': 'position',
        'value': 1500.0,
      });
      expect(position, isA<PlayerPositionEvent>());
      expect((position as PlayerPositionEvent).position, const Duration(milliseconds: 1500));

      final duration = ChannelPlayerBackend.decodeEventForTest({
        'event': 'duration',
        'value': 9000,
      });
      expect(duration, isA<PlayerDurationEvent>());
    });

    test('skips malformed payloads instead of throwing', () {
      expect(ChannelPlayerBackend.decodeEventForTest({'event': 'playing', 'value': 'yes'}), isNull);
      expect(
        ChannelPlayerBackend.decodeEventForTest({'event': 'position', 'value': 'bad'}),
        isNull,
      );
    });
  });
}

class _FakePlayerBackend implements PlayerBackend {
  _FakePlayerBackend({this.openDelay});

  final Duration? openDelay;
  final _controller = StreamController<PlayerEvent>.broadcast();
  final FlutterSignal<int?> _textureId = signal<int?>(null);

  String? lastOpenedUrl;
  double? lastVolume;
  double? lastSpeed;
  int? lastSeekMs;
  AspectRatioMode? lastAspectRatioMode;
  double? lastViewWidth;
  double? lastViewHeight;
  double? lastViewDpr;

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
  Future<void> open(String url) async {
    if (openDelay != null) {
      await Future<void>.delayed(openDelay!);
    }
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
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
  }

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> setAspectRatioMode(AspectRatioMode mode) async {
    lastAspectRatioMode = mode;
  }

  @override
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) async {
    lastViewWidth = width;
    lastViewHeight = height;
    lastViewDpr = devicePixelRatio;
  }

  @override
  Future<void> dispose() async {
    _textureId.value = null;
  }

  @override
  Future<XFile> takeSnapshot({String? savePath}) async {
    throw UnsupportedError('not used in tests');
  }

  void emit(PlayerEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }
}

class _FakeFullscreen implements FullscreenCoordinator {
  bool entered = false;
  bool? lastLandscape;

  @override
  Future<void> enter({required bool landscapeVideo}) async {
    entered = true;
    lastLandscape = landscapeVideo;
  }

  @override
  Future<void> exit() async {
    entered = false;
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
