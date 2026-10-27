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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live photo demo: stay on page, play motion_*, fullscreen', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const ValueKey<String>('live_photo_mode_tap')));
    await tester.pump();
    await _sleep(tester, const Duration(milliseconds: 300));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ValueKey<String>('live_photo_item_$i')));
      await tester.pump();
      await _sleep(tester, const Duration(milliseconds: 500));

      expect(
        find.byType(LivePhotoPlayer),
        findsOneWidget,
        reason: 'item $i should keep a single LivePhotoPlayer on stage',
      );

      final badge = find.byKey(const ValueKey<String>('live_photo_badge'));
      expect(badge, findsOneWidget);
      await tester.tap(badge);
      await tester.pump();

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
      await tester.tap(
        find.byKey(const ValueKey<String>('live_photo_fullscreen_button')),
      );
      await tester.pump();
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
      final fsBadge = find.byKey(const ValueKey<String>('live_photo_badge'));
      if (fsBadge.evaluate().isNotEmpty) {
        await tester.tap(fsBadge.first);
        await tester.pump();
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

      await tester.tap(
        find.byKey(const ValueKey<String>('live_photo_fullscreen_close')),
      );
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
      );
      expect(find.byKey(const ValueKey<String>('home_page')), findsNothing);
    }
  });
}
