import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player_example/main.dart' as app;

String _fixtureVideoPath() {
  // Always materialize under systemTemp so AVPlayer can read the file inside
  // the app container (macOS sandbox / iOS) and so iOS does not need ffmpeg.
  return '${Directory.systemTemp.path}${Platform.pathSeparator}xh_it_test.mp4';
}

String _shotsDir() {
  if (Platform.isWindows) {
    return r'E:\XueHuaPackages\xue_hua_navite_video_player\win_shots';
  }
  if (Platform.isMacOS) {
    return r'/Users/admin/XueHuaPackages/xue_hua_navite_video_player/mac_shots';
  }
  // Android / iOS screenshots go through takeScreenshot — device FS may be
  // sandboxed and host paths like /workspace are not writable.
  if (Platform.isAndroid || Platform.isIOS) {
    return Directory.systemTemp.path;
  }
  return '/workspace/xvfb_shots';
}

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
  // On Android/iOS the test runs inside the device/simulator: host Mac paths
  // are not writable. Prefer the integration_test screenshot channel.
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await IntegrationTestWidgetsFlutterBinding.instance.takeScreenshot(name);
    } catch (_) {}
    return;
  }
  final dir = Directory(_shotsDir());
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final out = '${dir.path}${Platform.pathSeparator}$name.png';
  if (Platform.isWindows) {
    // Best-effort Win32 screenshot via PowerShell; ignore failures.
    await Process.run('powershell', <String>[
      '-NoProfile',
      '-Command',
      "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; "
          "\$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; "
          "\$bmp=New-Object System.Drawing.Bitmap \$b.Width,\$b.Height; "
          "\$g=[System.Drawing.Graphics]::FromImage(\$bmp); "
          "\$g.CopyFromScreen(\$b.Location,[System.Drawing.Point]::Empty,\$b.Size); "
          "\$bmp.Save('$out'); \$g.Dispose(); \$bmp.Dispose();",
    ]);
    return;
  }
  if (Platform.isMacOS) {
    await Process.run('screencapture', <String>['-x', out]);
    return;
  }
  final display = Platform.environment['DISPLAY'] ?? ':99';
  await Process.run('import', <String>[
    '-display',
    display,
    '-window',
    'root',
    out,
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

Future<void> _ensureFixture() async {
  final path = _fixtureVideoPath();
  if (File(path).existsSync()) return;
  final ByteData data = await rootBundle.load('assets/test.mp4');
  await File(path).writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _ensureFixture();
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
    if (File(_fixtureVideoPath()).existsSync()) {
      expect(find.text('Local · test.mp4'), findsOneWidget);
    }
  });

  testWidgets(
    'local file: play/pause, scrub near end, completed/replay, keyboard, open another',
    (tester) async {
      await app.startExampleApp();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final hasLocal = File(_fixtureVideoPath()).existsSync();
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

      if (playPause.evaluate().isNotEmpty) {
        await tester.tap(playPause);
        await _sleep(tester, const Duration(milliseconds: 600));
        await _revealControls(tester);
        if (playPause.evaluate().isNotEmpty) {
          await tester.tap(playPause);
          await _sleep(tester, const Duration(milliseconds: 600));
        }
      }

      await _revealControls(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _sleep(tester, const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _sleep(tester, const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _sleep(tester, const Duration(milliseconds: 400));
      await _shot('ui_03_after_keyboard');

      await _scrubToFraction(tester, 0.92);
      await _shot('ui_04_after_scrub');

      final replay = find.byKey(
        const ValueKey<String>('video_player_replay_button'),
      );

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

      expect(replay, findsOneWidget);
      await tester.tap(replay);
      await _sleep(tester, const Duration(seconds: 1));
      await _shot('ui_06_after_replay');

      // Prefer the stable close key — coordinate taps miss under Android SafeArea.
      final closeBtn = find.byKey(
        const ValueKey<String>('video_player_close_button'),
      );
      await _waitForChrome(tester, closeBtn);
      expect(
        closeBtn,
        findsOneWidget,
        reason: 'close button never appeared after revealing chrome',
      );
      await tester.tap(closeBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey<String>('home_page')), findsOneWidget);
      // Allow async controller.dispose() to finish releasing the native slot.
      await _sleep(tester, const Duration(milliseconds: 500));
      await _shot('ui_07_back_home');

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
