import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

const String _networkUrl =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

/// Pumps until [condition] holds or [timeout] elapses; returns the final result.
Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) return false;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  return true;
}

Future<void> _sleep(WidgetTester tester, Duration d) async {
  await tester.runAsync(() => Future<void>.delayed(d));
  await tester.pump();
}

Future<String> _localVideoPath() async {
  // Prefer extracting the bundled asset into the app container temp directory.
  // That works under macOS App Sandbox and on iOS (where Process.run/ffmpeg is
  // unavailable). Absolute host paths may exist but AVPlayer often cannot open them.
  final String out =
      '${Directory.systemTemp.path}${Platform.pathSeparator}xh_it_test.mp4';
  final File outFile = File(out);
  if (!outFile.existsSync()) {
    final ByteData data = await rootBundle.load('assets/test.mp4');
    await outFile.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  if (!outFile.existsSync()) {
    throw StateError('failed to materialize local IT fixture at $out');
  }
  return out;
}

Future<VideoPlayerController> _mount(WidgetTester tester) async {
  await XueHuaNaviteVideoPlayer.instance.initialize();
  final VideoPlayerController c = VideoPlayerController();
  addTearDown(() => tester.runAsync(c.dispose));
  await tester.runAsync(c.initialize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 640,
          height: 360,
          child: CorePlayer(controller: c),
        ),
      ),
    ),
  );
  return c;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes without error', (WidgetTester tester) async {
    final VideoPlayerController c = await _mount(tester);
    expect(c.errorMessage.value, isNull);
    expect(c.playState.value, isNot(PlayState.error));
    expect(c.currentUrl.value, isNull);
  });

  testWidgets('fresh controller stays idle before any source is opened', (
    WidgetTester tester,
  ) async {
    final VideoPlayerController c = await _mount(tester);
    await _sleep(tester, const Duration(milliseconds: 500));
    expect(c.playState.value, PlayState.idle);
  });

  testWidgets('local file: plays, pauses, resumes, seeks', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);

    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
      reason: 'state=${c.playState.value} err=${c.errorMessage.value}',
    );
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );
    expect(c.duration.value.inSeconds, inInclusiveRange(9, 11));

    // Position advances.
    final Duration p0 = c.position.value;
    expect(
      await _waitFor(
        tester,
        () => c.position.value > p0 + const Duration(milliseconds: 500),
      ),
      isTrue,
      reason: 'position stuck at ${c.position.value}',
    );

    // Pause: position stops advancing.
    await tester.runAsync(c.pause);
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.paused),
      isTrue,
    );
    await _sleep(tester, const Duration(milliseconds: 500));
    final Duration paused = c.position.value;
    await _sleep(tester, const Duration(seconds: 1));
    expect((c.position.value - paused).inMilliseconds.abs(), lessThan(300));

    // Seek while paused.
    await tester.runAsync(() => c.seek(const Duration(seconds: 6)));
    expect(
      await _waitFor(
        tester,
        () =>
            (c.position.value - const Duration(seconds: 6)).inMilliseconds
                .abs() <
            700,
      ),
      isTrue,
      reason: 'position after seek: ${c.position.value}',
    );

    // Resume.
    await tester.runAsync(c.play);
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
    );
    final Duration p1 = c.position.value;
    expect(
      await _waitFor(
        tester,
        () => c.position.value > p1 + const Duration(milliseconds: 500),
      ),
      isTrue,
    );
  });

  testWidgets('local file reaches completed at end of stream', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );
    await tester.runAsync(
      () => c.seek(c.duration.value - const Duration(seconds: 1)),
    );
    expect(
      await _waitFor(
        tester,
        () => c.playState.value == PlayState.completed,
        timeout: const Duration(seconds: 10),
      ),
      isTrue,
      reason: 'state=${c.playState.value}',
    );
  });

  testWidgets('network source starts and advances', (
    WidgetTester tester,
  ) async {
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playNetwork(_networkUrl));
    expect(
      await _waitFor(
        tester,
        () => c.position.value > const Duration(seconds: 1),
        timeout: const Duration(seconds: 40),
      ),
      isTrue,
      reason: 'state=${c.playState.value} err=${c.errorMessage.value}',
    );
    expect(c.currentUrl.value, isNotNull);
  });

  testWidgets('volume, mute, unmute and toggleMuted', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
      reason: 'state=${c.playState.value} err=${c.errorMessage.value}',
    );

    await tester.runAsync(() => c.setVolume(0.35));
    expect(c.volume.value, closeTo(0.35, 0.001));

    await tester.runAsync(() => c.setMuted(true));
    expect(c.muted.value, isTrue);

    await tester.runAsync(() => c.setMuted(false));
    expect(c.muted.value, isFalse);

    await tester.runAsync(c.toggleMuted);
    expect(c.muted.value, isTrue);
    await tester.runAsync(c.toggleMuted);
    expect(c.muted.value, isFalse);
  });

  testWidgets('playback speed and brightness', (WidgetTester tester) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
    );

    await tester.runAsync(() => c.setSpeed(1.5));
    expect(c.speed.value, closeTo(1.5, 0.001));
    await tester.runAsync(() => c.setSpeed(1.0));
    expect(c.speed.value, closeTo(1.0, 0.001));

    final double before = c.brightness.value;
    await tester.runAsync(() => c.setBrightness(0.42));
    expect(c.brightness.value, closeTo(0.42, 0.001));
    await tester.runAsync(() => c.setBrightness(before.clamp(0.0, 1.0)));
  });

  testWidgets('looping flag toggles without error', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );

    expect(c.isLooping.value, isFalse);
    c.setLooping(true);
    expect(c.isLooping.value, isTrue);
    c.toggleLooping();
    expect(c.isLooping.value, isFalse);
    c.setLooping(true);
    expect(c.isLooping.value, isTrue);
  });

  testWidgets('skip forward and backward honor SkipSecondType', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );
    await tester.runAsync(c.pause);
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.paused),
      isTrue,
    );

    c.setSkipSecondType(SkipSecondType.second5);
    expect(c.skipSecondType.value, SkipSecondType.second5);

    // Forward from a settled 2s baseline.
    await tester.runAsync(() => c.seek(const Duration(seconds: 2)));
    expect(
      await _waitFor(
        tester,
        () =>
            (c.position.value - const Duration(seconds: 2)).inMilliseconds
                .abs() <
            700,
      ),
      isTrue,
    );
    await _sleep(tester, const Duration(milliseconds: 300));
    final Duration beforeFwd = c.position.value;
    await tester.runAsync(c.seekForward);
    expect(
      await _waitFor(
        tester,
        () =>
            (c.position.value - (beforeFwd + const Duration(seconds: 5)))
                .inMilliseconds
                .abs() <
            1200,
      ),
      isTrue,
      reason: 'forward pos=${c.position.value} before=$beforeFwd',
    );

    // Backward from a settled 7s baseline so each direction is isolated.
    await tester.runAsync(() => c.seek(const Duration(seconds: 7)));
    expect(
      await _waitFor(
        tester,
        () =>
            (c.position.value - const Duration(seconds: 7)).inMilliseconds
                .abs() <
            700,
      ),
      isTrue,
    );
    await _sleep(tester, const Duration(milliseconds: 300));
    final Duration beforeBack = c.position.value;
    await tester.runAsync(c.seekBackward);
    expect(
      await _waitFor(
        tester,
        () =>
            (c.position.value - (beforeBack - const Duration(seconds: 5)))
                .inMilliseconds
                .abs() <
            1200,
      ),
      isTrue,
      reason: 'backward pos=${c.position.value} before=$beforeBack',
    );
  });

  testWidgets('aspect ratio modes cycle', (WidgetTester tester) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
    );

    for (final AspectRatioMode mode in AspectRatioMode.values) {
      await tester.runAsync(() => c.setAspectRatioMode(mode));
      expect(c.aspectRatioMode.value, mode);
    }
    await tester.runAsync(() => c.setAspectRatioMode(AspectRatioMode.fit));
  });

  testWidgets('fullscreen enter and exit update signal', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );

    expect(c.isFullscreen.value, isFalse);
    await tester.runAsync(c.enterFullscreen);
    expect(c.isFullscreen.value, isTrue);
    await tester.runAsync(c.exitFullscreen);
    expect(c.isFullscreen.value, isFalse);
    await tester.runAsync(c.toggleFullscreen);
    expect(c.isFullscreen.value, isTrue);
    await tester.runAsync(c.toggleFullscreen);
    expect(c.isFullscreen.value, isFalse);
  });

  testWidgets('takeSnapshot returns a non-empty image file', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
    );
    await _sleep(tester, const Duration(milliseconds: 800));

    final NaviteFile shot =
        await tester.runAsync(() => c.takeSnapshot()) as NaviteFile;
    expect(shot.path, isNotEmpty);
    expect(shot.name, isNotEmpty);
    if (!shot.path.startsWith('data:') && !shot.path.startsWith('blob:')) {
      expect(File(shot.path).existsSync(), isTrue);
      expect(File(shot.path).lengthSync(), greaterThan(0));
    }
  });

  testWidgets('playAsset and VideoSource.asset / openSource', (
    WidgetTester tester,
  ) async {
    final VideoPlayerController c = await _mount(tester);

    await tester.runAsync(() => c.playAsset('assets/test.mp4'));
    expect(
      await _waitFor(
        tester,
        () => c.playState.value == PlayState.playing,
        timeout: const Duration(seconds: 30),
      ),
      isTrue,
      reason:
          'asset play state=${c.playState.value} err=${c.errorMessage.value}',
    );
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );
    await tester.runAsync(c.stop);

    await tester.runAsync(
      () => c.openSource(const VideoSource.asset('assets/test.mp4')),
    );
    expect(
      await _waitFor(
        tester,
        () =>
            c.playState.value == PlayState.paused ||
            c.playState.value == PlayState.loading ||
            c.duration.value > Duration.zero,
        timeout: const Duration(seconds: 30),
      ),
      isTrue,
      reason:
          'openSource state=${c.playState.value} err=${c.errorMessage.value}',
    );
    await tester.runAsync(c.play);
    expect(
      await _waitFor(tester, () => c.playState.value == PlayState.playing),
      isTrue,
    );
  });

  testWidgets('probe APIs: getDuration and extractCoverCandidates', (
    WidgetTester tester,
  ) async {
    await XueHuaNaviteVideoPlayer.instance.initialize();
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoSource source = VideoSource.file(path);

    final Duration? dur = await tester.runAsync<Duration?>(
      () => XueHuaNaviteVideoPlayer.instance.getDuration(source),
    );
    expect(dur, isNotNull);
    expect(dur!.inSeconds, inInclusiveRange(9, 11));

    final List<VideoCoverFrame>? covers = await tester
        .runAsync<List<VideoCoverFrame>>(
          () => XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
            source,
            count: 2,
          ),
        );
    expect(covers, isNotNull);
    // Some hosts may return empty if native cover extract is limited; allow
    // empty but when present frames must be valid.
    for (final VideoCoverFrame frame in covers!) {
      expect(frame.image.path, isNotEmpty);
      expect(frame.brightness, inInclusiveRange(0.0, 1.0));
    }
  });

  testWidgets('Live Photo probe and playback from Motion Photo asset', (
    WidgetTester tester,
  ) async {
    await XueHuaNaviteVideoPlayer.instance.initialize();
    const VideoSource motion = VideoSource.asset(
      'assets/live_photo/motion_city_walk.jpg',
    );

    final bool? isLive = await tester.runAsync<bool>(
      () => XueHuaNaviteVideoPlayer.instance.isLivePhoto(motion),
    );
    expect(isLive, isTrue);

    final LivePhotoBundle? bundle = await tester.runAsync<LivePhotoBundle?>(
      () => XueHuaNaviteVideoPlayer.instance.extractLivePhoto(motion),
    );
    expect(bundle, isNotNull);
    expect(bundle!.nativeVideoUrl, isNotEmpty);
    expect(bundle.metadata.videoLength, isNotNull);
    expect(bundle.metadata.videoLength!, greaterThan(1000));

    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(
      () => c.playLivePhoto(
        LivePhotoSource.asset(
          imageAsset: 'assets/live_photo/motion_city_walk.jpg',
        ),
      ),
    );
    expect(
      await _waitFor(
        tester,
        () =>
            c.isLivePhoto.value == true ||
            c.playState.value == PlayState.playing ||
            c.duration.value > Duration.zero,
        timeout: const Duration(seconds: 40),
      ),
      isTrue,
      reason:
          'livePhoto=${c.isLivePhoto.value} state=${c.playState.value} '
          'err=${c.errorMessage.value}',
    );
  });

  testWidgets('cast support signal; picker only when supported', (
    WidgetTester tester,
  ) async {
    final String path = await tester.runAsync(_localVideoPath) as String;
    final VideoPlayerController c = await _mount(tester);
    await tester.runAsync(() => c.playFile(path));
    expect(
      await _waitFor(tester, () => c.duration.value > Duration.zero),
      isTrue,
    );

    // Reading the computed flag must not throw.
    final bool supported = c.isCastSupported.value;
    expect(c.castState.value, isA<CastState>());
    expect(c.isCasting.value, isFalse);

    if (!supported) {
      expect(
        c.castState.value == CastState.unavailable ||
            c.castState.value == CastState.notConnected,
        isTrue,
      );
      return;
    }

    // Supported: presenting the system picker should not crash; dismiss is OS-owned.
    await tester.runAsync(c.showCastPicker);
    await _sleep(tester, const Duration(milliseconds: 500));
    await tester.runAsync(c.stopCasting);
    expect(c.isCasting.value, isFalse);
  });
}
