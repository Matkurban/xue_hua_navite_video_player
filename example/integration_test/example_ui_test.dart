import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_navite_video_player_example/main.dart' as app;

Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) return false;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  return true;
}

Future<void> _sleep(WidgetTester tester, Duration d) async {
  await tester.runAsync(() => Future<void>.delayed(d));
  await tester.pump();
}

Future<void> _shot(String name) async {
  final dir = Directory('/workspace/xvfb_shots');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final display = Platform.environment['DISPLAY'] ?? ':99';
  await Process.run('import', <String>[
    '-display',
    display,
    '-window',
    'root',
    '${dir.path}/$name.png',
  ]);
}

Future<void> _revealControls(WidgetTester tester) async {
  final player = find.byKey(const ValueKey<String>('player_page'));
  if (player.evaluate().isEmpty) return;
  await tester.tapAt(tester.getCenter(player));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<Finder> _waitForChrome(
  WidgetTester tester,
  Finder target, {
  int attempts = 20,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (target.evaluate().isNotEmpty) return target;
    await _revealControls(tester);
    await _sleep(tester, const Duration(milliseconds: 250));
  }
  return target;
}

Future<void> _scrubToFraction(WidgetTester tester, double fraction) async {
  final scrubber = find.byKey(const ValueKey<String>('video_player_scrubber'));
  await _waitForChrome(tester, scrubber);
  expect(scrubber, findsOneWidget, reason: 'scrubber never appeared');
  final rect = tester.getRect(scrubber);
  final start = Offset(rect.left + rect.width * 0.15, rect.center.dy);
  final end = Offset(
    rect.left + rect.width * fraction.clamp(0.0, 0.98),
    rect.center.dy,
  );
  await tester.timedDragFrom(
    start,
    end - start,
    const Duration(milliseconds: 500),
  );
  await tester.pump();
  await _sleep(tester, const Duration(milliseconds: 800));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const preset = '/workspace/test.mp4';
    if (!File(preset).existsSync()) {
      await Process.run('ffmpeg', [
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
        preset,
      ]);
    }
  });

  testWidgets('home list shows playlist items including local when present', (
    tester,
  ) async {
    await app.startExampleApp();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _shot('ui_01_home');

    expect(find.byKey(const ValueKey<String>('home_page')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('demo_item_0')), findsOneWidget);
    expect(find.text('Flutter · Butterfly'), findsOneWidget);
    expect(find.text('W3C · Sintel'), findsOneWidget);
    if (File('/workspace/test.mp4').existsSync()) {
      expect(find.text('Local · test.mp4'), findsOneWidget);
    }
  });

  testWidgets(
    'local file: play/pause, scrub near end, completed/replay, keyboard, open another',
    (tester) async {
      await app.startExampleApp();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final hasLocal = File('/workspace/test.mp4').existsSync();
      // Prefer local (index 0) for fast EOS; otherwise butterfly (network).
      final openKey = hasLocal
          ? const ValueKey<String>('demo_item_0')
          : const ValueKey<String>('demo_item_1');
      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey<String>('player_page')), findsOneWidget);

      expect(
        await _waitFor(tester, () {
          return find
              .byKey(const ValueKey<String>('player_title'))
              .evaluate()
              .isNotEmpty;
        }, timeout: const Duration(seconds: 40)),
        isTrue,
        reason: 'player title never appeared',
      );
      await _shot('ui_02_player_open');

      final playPause = find.byKey(
        const ValueKey<String>('video_player_play_pause_button'),
      );
      await _waitForChrome(tester, playPause);
      expect(
        playPause.evaluate().isNotEmpty ||
            find
                .byKey(const ValueKey<String>('video_player_replay_button'))
                .evaluate()
                .isNotEmpty,
        isTrue,
        reason: 'neither play/pause nor replay appeared',
      );

      // Play/pause via center button when available.
      if (playPause.evaluate().isNotEmpty) {
        await tester.tap(playPause);
        await _sleep(tester, const Duration(milliseconds: 600));
        await _revealControls(tester);
        if (playPause.evaluate().isNotEmpty) {
          await tester.tap(playPause);
          await _sleep(tester, const Duration(milliseconds: 600));
        }
      }

      // Keyboard: Space toggles after focusing the player surface.
      await _revealControls(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _sleep(tester, const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _sleep(tester, const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _sleep(tester, const Duration(milliseconds: 400));
      await _shot('ui_03_after_keyboard');

      // Scrub near end (~92%), then ensure playback continues into EOS.
      await _scrubToFraction(tester, 0.92);
      await _shot('ui_04_after_scrub');

      final replay = find.byKey(
        const ValueKey<String>('video_player_replay_button'),
      );

      // Wait for natural EOS; periodically re-reveal chrome. Do NOT toggle
      // Space here — that can pause playback and prevent eof-reached.
      var sawReplay = false;
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 25)) {
        if (replay.evaluate().isNotEmpty) {
          sawReplay = true;
          break;
        }
        await _revealControls(tester);
        await _sleep(tester, const Duration(milliseconds: 300));
      }
      // If still missing, try one resume via play button then wait again.
      if (!sawReplay && playPause.evaluate().isNotEmpty) {
        await tester.tap(playPause);
        await _sleep(tester, const Duration(milliseconds: 400));
        sw.reset();
        sw.start();
        while (sw.elapsed < const Duration(seconds: 15)) {
          if (replay.evaluate().isNotEmpty) {
            sawReplay = true;
            break;
          }
          await _revealControls(tester);
          await _sleep(tester, const Duration(milliseconds: 300));
        }
      }
      expect(
        sawReplay,
        isTrue,
        reason: 'expected completed/replay UI after scrubbing near end',
      );
      await _shot('ui_05_completed_replay');

      // Completed chrome stays visible — do NOT tap the surface first
      // (that toggles chrome off and removes the replay key).
      expect(replay, findsOneWidget);
      await tester.tap(replay);
      await _sleep(tester, const Duration(seconds: 1));
      await _shot('ui_06_after_replay');

      // Close via top-left chrome close; re-show only if chrome was hidden.
      final page = find.byKey(const ValueKey<String>('player_page'));
      if (find.byIcon(Icons.close).evaluate().isEmpty &&
          find.byIcon(Icons.close_rounded).evaluate().isEmpty) {
        await _revealControls(tester);
      }
      final topLeft = tester.getTopLeft(page);
      await tester.tapAt(topLeft + const Offset(28, 28));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey<String>('home_page')), findsOneWidget);
      await _shot('ui_07_back_home');

      // Open another (network) item — butterfly when local is index 0, else bunny.
      final otherKey = hasLocal
          ? const ValueKey<String>('demo_item_1')
          : const ValueKey<String>('demo_item_2');
      await tester.tap(find.byKey(otherKey));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey<String>('player_page')), findsOneWidget);
      expect(
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey<String>('player_title'))
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 30),
        ),
        isTrue,
      );
      await _shot('ui_08_second_item');
    },
  );
}
