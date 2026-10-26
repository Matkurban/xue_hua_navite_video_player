import 'dart:io';

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
  final List<String> presets = <String>[
    '/workspace/test.mp4',
    if (Platform.isWindows)
      r'E:\XueHuaPackages\xue_hua_navite_video_player\test.mp4',
    '${Directory.systemTemp.path}${Platform.pathSeparator}xh_it_test.mp4',
  ];
  for (final String preset in presets) {
    if (File(preset).existsSync()) return preset;
  }
  final String out = presets.last;
  final ProcessResult r = await Process.run('ffmpeg', <String>[
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'testsrc=size=320x240:rate=30',
    '-t',
    '10',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    out,
  ]);
  if (r.exitCode != 0) {
    throw StateError('ffmpeg failed (code ${r.exitCode}): ${r.stderr}');
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
}
