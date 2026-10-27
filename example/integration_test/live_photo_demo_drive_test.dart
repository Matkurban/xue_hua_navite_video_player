import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/main.dart' as app;

/// flutter drive stays on [LivePhotoDemoPage] only (no home playlist).
///
/// Run (integration_test driver = modern flutter_driver replacement):
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/live_photo_demo_drive_test.dart \
///     -d macos
///   # or: -d linux / -d chrome / -d ios or android simulator
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

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live photo demo: stay on page, play motion_*, fullscreen', (
    tester,
  ) async {
    // Default IT surface (800x600) clips the 7:3 split + AppBar actions.
    const Size surface = Size(1400, 900);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await app.startLivePhotoDemoApp();
    await tester.pump();

    expect(
      await _waitFor(
        tester,
        () => find
            .byKey(const ValueKey<String>('live_photo_demo_page'))
            .evaluate()
            .isNotEmpty,
      ),
      isTrue,
      reason: 'LivePhotoDemoPage never appeared',
    );

    // Stay on this single page for the whole drive session.
    expect(find.byKey(const ValueKey<String>('home_page')), findsNothing);
    expect(find.text('Live Photo · 动态照片'), findsOneWidget);

    expect(
      await _waitFor(
        tester,
        () => find
            .byKey(const ValueKey<String>('live_photo_item_0'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 45),
      ),
      isTrue,
      reason: 'bundled motion photos never loaded',
    );

    expect(find.textContaining('motion_city_walk.jpg'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('live_photo_item_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('live_photo_item_2')),
      findsOneWidget,
    );

    // Switch to tap mode so one tap triggers motion playback.
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('live_photo_mode_tap')),
    );
    await _sleep(tester, const Duration(milliseconds: 300));

    for (var i = 0; i < 3; i++) {
      await _tapVisible(tester, find.byKey(ValueKey<String>('live_photo_item_$i')));
      await _sleep(tester, const Duration(milliseconds: 600));

      expect(
        find.byType(LivePhotoPlayer),
        findsOneWidget,
        reason: 'item $i should keep a single LivePhotoPlayer on stage',
      );

      // Tap the gesture layer (more reliable than badge corner hit-tests).
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('live_photo_gesture_detector')),
      );

      expect(
        await _waitFor(
          tester,
          () =>
              find
                  .byKey(const ValueKey<String>('live_photo_video_surface'))
                  .evaluate()
                  .isNotEmpty &&
              find.byType(LivePhotoPlayer).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 40),
        ),
        isTrue,
        reason: 'item $i: video surface never mounted after tap',
      );

      // Fullscreen must host LivePhotoPlayer + video surface (not empty black).
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('live_photo_fullscreen_button')),
      );
      expect(
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey<String>('live_photo_fullscreen_page'))
              .evaluate()
              .isNotEmpty,
        ),
        isTrue,
      );

      expect(find.byType(LivePhotoPlayer), findsWidgets);
      final fsGesture = find.byKey(
        const ValueKey<String>('live_photo_gesture_detector'),
      );
      if (fsGesture.evaluate().isNotEmpty) {
        await _tapVisible(tester, fsGesture);
      }
      expect(
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey<String>('live_photo_video_surface'))
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 40),
        ),
        isTrue,
        reason:
            'item $i fullscreen: video surface missing (possible black stage)',
      );

      // Prefer pageBack — AppBar close can sit outside the IT hit-test surface.
      await tester.pageBack();
      await tester.pump();
      expect(
        await _waitFor(
          tester,
          () =>
              find
                  .byKey(const ValueKey<String>('live_photo_demo_page'))
                  .evaluate()
                  .isNotEmpty &&
              find
                  .byKey(const ValueKey<String>('live_photo_fullscreen_page'))
                  .evaluate()
                  .isEmpty,
        ),
        isTrue,
      );
      expect(find.byKey(const ValueKey<String>('home_page')), findsNothing);
    }
  });
}
