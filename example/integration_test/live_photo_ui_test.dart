import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/main.dart' as app;

const List<String> _assets = <String>[
  'assets/live_photo/motion_city_walk.jpg',
  'assets/live_photo/motion_park_pan.jpg',
  'assets/live_photo/motion_street_clip.jpg',
];

Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 35),
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) return false;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return true;
}

Future<void> _sleep(WidgetTester tester, Duration d) async {
  await tester.runAsync(() => Future<void>.delayed(d));
  await tester.pump(const Duration(milliseconds: 16));
}

Finder get _videoSurface =>
    find.byKey(const ValueKey<String>('live_photo_video_surface'));

bool _hasVideoSurface() => _videoSurface.evaluate().isNotEmpty;

void _setWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _expectMotionAndFullscreen(
  WidgetTester tester, {
  required String asset,
}) async {
  debugPrint('IT: mount player $asset');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 900,
            height: 700,
            child: LivePhotoPlayer(
              key: ValueKey<String>('it_player_$asset'),
              source: LivePhotoSource.asset(imageAsset: asset),
              playMode: LivePhotoPlayMode.loop,
              aspectRatio: 16 / 9,
              fit: BoxFit.cover,
              badgeLabel: '实况',
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          key: const ValueKey<String>('it_open_fullscreen'),
          onPressed: () {
            // filled by Builder below — replaced
          },
          child: const Icon(Icons.fullscreen),
        ),
      ),
    ),
  );

  // Rebuild with a Navigator-capable fullscreen opener.
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                height: 700,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    LivePhotoPlayer(
                      key: ValueKey<String>('it_player_$asset'),
                      source: LivePhotoSource.asset(imageAsset: asset),
                      playMode: LivePhotoPlayMode.loop,
                      aspectRatio: 16 / 9,
                      fit: BoxFit.cover,
                      badgeLabel: '实况',
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: IconButton(
                        key: const ValueKey<String>('it_open_fullscreen'),
                        icon: const Icon(Icons.fullscreen),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => app.LivePhotoFullscreenPage(
                                source: LivePhotoSource.asset(imageAsset: asset),
                                playMode: LivePhotoPlayMode.loop,
                                title: asset.split('/').last,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await _pumpFrames(tester, frames: 10);

  final playing = await _waitFor(tester, _hasVideoSurface);
  expect(
    playing,
    isTrue,
    reason: '$asset: motion video surface not mounted',
  );
  await _sleep(tester, const Duration(milliseconds: 700));
  expect(_hasVideoSurface(), isTrue, reason: '$asset: surface lost while playing');

  debugPrint('IT: open fullscreen $asset');
  await tester.tap(find.byKey(const ValueKey<String>('it_open_fullscreen')));
  await _pumpFrames(tester, frames: 25);

  final fsShown = await _waitFor(
    tester,
    () => find
        .byKey(const ValueKey<String>('live_photo_fullscreen_close'))
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 12),
  );
  expect(fsShown, isTrue, reason: '$asset: fullscreen not shown');

  final fsPlaying = await _waitFor(tester, _hasVideoSurface);
  expect(
    fsPlaying,
    isTrue,
    reason: '$asset fullscreen: no video surface (black?)',
  );
  await _sleep(tester, const Duration(milliseconds: 500));
  expect(
    _hasVideoSurface(),
    isTrue,
    reason: '$asset fullscreen: surface lost (black stage)',
  );

  await tester.tap(
    find.byKey(const ValueKey<String>('live_photo_fullscreen_close')),
  );
  await _pumpFrames(tester, frames: 20);
  debugPrint('IT: ok $asset');
}


void _drainKnownNoise(WidgetTester tester) {
  for (var i = 0; i < 8; i++) {
    final Object? ex = tester.takeException();
    if (ex == null) break;
    final msg = ex.toString();
    if (!msg.contains('No active stream to cancel')) {
      throw ex;
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native player EventChannel cancel is racy on rebuild/dispose; ignore known noise.
  binding.platformDispatcher.onError = (Object error, StackTrace stack) {
    final msg = error.toString();
    if (msg.contains('No active stream to cancel')) {
      return true;
    }
    return false;
  };


  testWidgets('demo page opens and stays on Live Photo', (tester) async {
    _setWideSurface(tester);
    await XueHuaNaviteVideoPlayer.instance.initialize();
    await app.startExampleApp();
    await _pumpFrames(tester, frames: 40);
    expect(find.byKey(const ValueKey<String>('home_page')), findsOneWidget);

    final entry = find.byKey(const ValueKey<String>('demo_live_photo_entry'));
    if (entry.evaluate().isNotEmpty) {
      await tester.ensureVisible(entry);
      await tester.tap(entry);
    } else {
      await tester.tap(find.byKey(const ValueKey<String>('live_photo_demo_button')));
    }

    final opened = await _waitFor(
      tester,
      () => find.byKey(const ValueKey<String>('live_photo_demo_page')).evaluate().isNotEmpty,
    );
    expect(opened, isTrue);
    // Stay on page: items should load.
    final items = await _waitFor(
      tester,
      () => find.byKey(const ValueKey<String>('live_photo_item_0')).evaluate().isNotEmpty,
    );
    expect(items, isTrue);
    expect(find.textContaining('motion_city_walk'), findsWidgets);
  });

  testWidgets('motion play + fullscreen not black for 3 assets', (tester) async {
    _setWideSurface(tester);
    await XueHuaNaviteVideoPlayer.instance.initialize();
    for (final asset in _assets) {
      await _expectMotionAndFullscreen(tester, asset: asset);
      _drainKnownNoise(tester);
    }
  });
}
