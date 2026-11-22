import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/src/bridge/video_player_host_bridge.dart';
import 'package:xue_hua_navite_video_player/src/player/brightness_controller.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';
import 'package:xue_hua_navite_video_player/src/player/player_backend.dart';
import 'package:xue_hua_navite_video_player/src/player/player_event.dart';
import 'package:xue_hua_navite_video_player/src/ui/widgets/player_gesture_layer.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  group('SystemChromeFullscreenCoordinator orientation lock', () {
    test('locks to single orientation and unlocks to bidirectional landscape on mobile', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final List<List<String>> orientationCalls = <List<String>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientationCalls.add((call.arguments as List<Object?>).cast<String>());
          }
          return null;
        },
      );

      final _FakeHostBridge bridge = _FakeHostBridge();
      final SystemChromeFullscreenCoordinator coordinator = SystemChromeFullscreenCoordinator(
        bridge: bridge,
        isWeb: false,
      );

      await coordinator.enter(landscapeVideo: true);
      await coordinator.setOrientationLocked(locked: true, landscapeVideo: true);
      await coordinator.setOrientationLocked(
        locked: true,
        landscapeVideo: true,
        lockedOrientation: DeviceOrientation.landscapeRight,
      );
      await coordinator.setOrientationLocked(locked: false, landscapeVideo: true);
      await coordinator.exit();

      expect(orientationCalls, <List<String>>[
        <String>['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        <String>['DeviceOrientation.landscapeLeft'],
        <String>['DeviceOrientation.landscapeRight'],
        <String>['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        <String>[],
      ]);

      coordinator.dispose();
      await bridge.close();
    });
  });

  group('PlayerGestureLayer vertical brightness/volume controls', () {
    testWidgets('adjusts brightness on left 30%x70% and volume on right 30%x70% in landscape', (
      WidgetTester tester,
    ) async {
      final _FakeBackend backend = _FakeBackend();
      final _FakeBrightness brightness = _FakeBrightness(initial: 0.5);
      final _FakeFullscreen fullscreen = _FakeFullscreen();
      final VideoPlayerController controller = VideoPlayerController(
        backend: backend,
        brightness: brightness,
        fullscreen: fullscreen,
      );
      await controller.initialize();
      await controller.setVolume(0.5);
      await controller.enterFullscreen();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800.0,
                height: 400.0,
                child: PlayerGestureLayer(
                  controller: controller,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final Rect rect = tester.getRect(find.byType(PlayerGestureLayer));

      // Drag up in left 30% width, centered 70% height (x = 15%, y = 50% -> 25%).
      final TestGesture leftGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.15, rect.top + rect.height * 0.5),
      );
      await leftGesture.moveBy(const Offset(0.0, -70.0));
      await tester.pump();

      expect(controller.brightness.value, greaterThan(0.5));
      expect(find.byType(PlayerGestureHud), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await leftGesture.up();
      await tester.pump();
      expect(find.byType(PlayerGestureHud), findsNothing);

      // Drag down in right 30% width, centered 70% height (x = 85%, y = 50%).
      final TestGesture rightGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.85, rect.top + rect.height * 0.5),
      );
      await rightGesture.moveBy(const Offset(0.0, 70.0));
      await tester.pump();

      expect(controller.volume.value, lessThan(0.5));
      expect(find.byType(PlayerGestureHud), findsOneWidget);
      await rightGesture.up();
      await tester.pump();

      // Dragging outside vertical 70% band (top 5%) should NOT adjust brightness.
      final double brightnessBeforeEdge = controller.brightness.value;
      final TestGesture edgeGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.15, rect.top + rect.height * 0.05),
      );
      await edgeGesture.moveBy(const Offset(0.0, 60.0));
      await tester.pump();
      expect(controller.brightness.value, equals(brightnessBeforeEdge));
      expect(find.byType(PlayerGestureHud), findsNothing);
      await edgeGesture.up();
      await tester.pump();

      await controller.dispose();
    });

    testWidgets('supports swapping sides via FullscreenGestureSideMapping and custom HUD builder', (
      WidgetTester tester,
    ) async {
      final _FakeBackend backend = _FakeBackend();
      final _FakeBrightness brightness = _FakeBrightness(initial: 0.5);
      final _FakeFullscreen fullscreen = _FakeFullscreen();
      final VideoPlayerController controller = VideoPlayerController(
        backend: backend,
        brightness: brightness,
        fullscreen: fullscreen,
      );
      await controller.initialize();
      await controller.setVolume(0.5);
      await controller.enterFullscreen();

      PlayerGestureHudContext? capturedHud;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800.0,
                height: 400.0,
                child: PlayerGestureLayer(
                  controller: controller,
                  verticalGestureMapping: FullscreenGestureSideMapping.leftVolumeRightBrightness,
                  gestureHudBuilder: (BuildContext context, PlayerGestureHudContext hud) {
                    capturedHud = hud;
                    return Text(
                      'CUSTOM:${hud.kind.name}:${hud.percentage}',
                      key: const ValueKey<String>('custom_hud'),
                    );
                  },
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final Rect rect = tester.getRect(find.byType(PlayerGestureLayer));

      // Left edge now controls volume.
      final TestGesture leftGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.15, rect.top + rect.height * 0.5),
      );
      await leftGesture.moveBy(const Offset(0.0, -70.0));
      await tester.pump();

      expect(controller.volume.value, greaterThan(0.5));
      expect(controller.brightness.value, equals(0.5));
      expect(capturedHud?.kind, equals(PlayerHudKind.volume));
      expect(find.byKey(const ValueKey<String>('custom_hud')), findsOneWidget);
      await leftGesture.up();
      await tester.pump();

      // Right edge now controls brightness.
      final TestGesture rightGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.85, rect.top + rect.height * 0.5),
      );
      await rightGesture.moveBy(const Offset(0.0, 70.0));
      await tester.pump();

      expect(controller.brightness.value, lessThan(0.5));
      expect(capturedHud?.kind, equals(PlayerHudKind.brightness));
      await rightGesture.up();
      await tester.pump();

      await controller.dispose();
    });

    testWidgets('ignores vertical gestures in portrait layout and when locked', (
      WidgetTester tester,
    ) async {
      final _FakeBackend backend = _FakeBackend();
      final _FakeBrightness brightness = _FakeBrightness(initial: 0.5);
      final _FakeFullscreen fullscreen = _FakeFullscreen();
      final VideoPlayerController controller = VideoPlayerController(
        backend: backend,
        brightness: brightness,
        fullscreen: fullscreen,
      );
      await controller.initialize();
      await controller.setVolume(0.5);
      await controller.enterFullscreen();

      // Portrait box (height > width) should not trigger vertical brightness/volume drag.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360.0,
                height: 640.0,
                child: PlayerGestureLayer(
                  controller: controller,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final Rect portraitRect = tester.getRect(find.byType(PlayerGestureLayer));
      final TestGesture portraitGesture = await tester.startGesture(
        Offset(portraitRect.left + 40.0, portraitRect.top + portraitRect.height * 0.5),
      );
      await portraitGesture.moveBy(const Offset(0.0, -100.0));
      await tester.pump();
      expect(controller.brightness.value, equals(0.5));
      await portraitGesture.up();
      await tester.pump();

      // Locked landscape box should ignore vertical drags.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800.0,
                height: 400.0,
                child: PlayerGestureLayer(
                  controller: controller,
                  isLocked: true,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final Rect landscapeRect = tester.getRect(find.byType(PlayerGestureLayer));
      final TestGesture lockedGesture = await tester.startGesture(
        Offset(landscapeRect.left + 100.0, landscapeRect.top + 200.0),
      );
      await lockedGesture.moveBy(const Offset(0.0, -100.0));
      await tester.pump();
      expect(controller.brightness.value, equals(0.5));
      expect(find.byType(PlayerGestureHud), findsNothing);
      await lockedGesture.up();
      await tester.pump();

      await controller.dispose();
    });

    testWidgets('PlayerGestureHud adapts to Cupertino theme', (WidgetTester tester) async {
      final _FakeBackend backend = _FakeBackend();
      final VideoPlayerController controller = VideoPlayerController(
        backend: backend,
        brightness: _FakeBrightness(initial: 0.6),
        fullscreen: _FakeFullscreen(),
      );
      await controller.initialize();

      const VideoPlayerTheme cupertinoTheme = VideoPlayerTheme.cupertino();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[cupertinoTheme]),
          home: Scaffold(
            body: Center(
              child: PlayerGestureHud(
                hud: PlayerGestureHudContext(
                  controller: controller,
                  theme: cupertinoTheme,
                  kind: PlayerHudKind.brightness,
                  value: 0.65,
                  label: '65%',
                  seekForward: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.sun_max_fill), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await controller.dispose();
    });

    testWidgets('supports custom asymmetric left/right width ratios and validates 0..1 bounds', (
      WidgetTester tester,
    ) async {
      final _FakeBackend backend = _FakeBackend();
      final _FakeBrightness brightness = _FakeBrightness(initial: 0.5);
      final _FakeFullscreen fullscreen = _FakeFullscreen();
      final VideoPlayerController controller = VideoPlayerController(
        backend: backend,
        brightness: brightness,
        fullscreen: fullscreen,
      );
      await controller.initialize();
      await controller.setVolume(0.5);
      await controller.enterFullscreen();

      expect(
        () => VideoPlayer(controller: controller, verticalGestureLeftWidthRatio: -0.1),
        throwsAssertionError,
      );
      expect(
        () => VideoPlayer(controller: controller, verticalGestureRightWidthRatio: 1.1),
        throwsAssertionError,
      );
      expect(
        () => VideoPlayer(
          controller: controller,
          verticalGestureLeftWidthRatio: 0.6,
          verticalGestureRightWidthRatio: 0.5,
        ),
        throwsAssertionError,
      );
      expect(
        () => VideoPlayer(controller: controller, verticalGestureHeightRatio: 1.2),
        throwsAssertionError,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800.0,
                height: 400.0,
                child: PlayerGestureLayer(
                  controller: controller,
                  verticalGestureLeftWidthRatio: 0.6,
                  verticalGestureRightWidthRatio: 0.2,
                  verticalGestureHeightRatio: 0.5,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

      final Rect rect = tester.getRect(find.byType(PlayerGestureLayer));

      // x = 55% is inside the custom 60% left zone and centered 50% height band.
      final TestGesture leftGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.55, rect.top + rect.height * 0.5),
      );
      await leftGesture.moveBy(const Offset(0.0, -50.0));
      await tester.pump();
      expect(controller.brightness.value, greaterThan(0.5));
      await leftGesture.up();
      await tester.pump();

      // x = 70% is in the dead center gap (between 60% and 80%), so volume must not change.
      final TestGesture gapGesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.70, rect.top + rect.height * 0.5),
      );
      await gapGesture.moveBy(const Offset(0.0, -50.0));
      await tester.pump();
      expect(controller.volume.value, equals(0.5));
      await gapGesture.up();
      await tester.pump();

      await controller.dispose();
    });
  });

  group('VideoPlayer fullscreen lock button & positioning', () {
    testWidgets('positions lock button on right, supports custom builder, and toggles lock state', (
      WidgetTester tester,
    ) async {
      final _FakeBackend backend = _FakeBackend();
      final _FakeFullscreen fullscreen = _FakeFullscreen();
      final VideoPlayerController controller = VideoPlayerController(
        backend: backend,
        brightness: _FakeBrightness(initial: 0.5),
        fullscreen: fullscreen,
      );
      await controller.initialize();
      await controller.enterFullscreen();

      tester.view.physicalSize = const Size(800.0, 400.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPlayer(
              controller: controller,
              lockButtonPosition: PlayerLockButtonPosition.right,
              lockButtonBuilder: (BuildContext context, VideoPlayerSlotContext slot, bool locked) {
                return GestureDetector(
                  key: const ValueKey<String>('custom_lock_button'),
                  onTap: slot.controller.toggleLocked,
                  child: Text(locked ? 'UNLOCK' : 'LOCK'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder lockButtonFinder = find.byKey(const ValueKey<String>('custom_lock_button'));
      expect(lockButtonFinder, findsOneWidget);
      expect(find.text('LOCK'), findsOneWidget);

      final Offset lockCenter = tester.getCenter(lockButtonFinder);
      expect(lockCenter.dx, greaterThan(400.0));

      await tester.tap(lockButtonFinder);
      await tester.pumpAndSettle();

      expect(controller.isLocked.value, isTrue);
      expect(fullscreen.lockCalls, <bool>[true]);
      expect(find.text('UNLOCK'), findsOneWidget);

      await tester.tap(lockButtonFinder);
      await tester.pumpAndSettle();

      expect(controller.isLocked.value, isFalse);
      expect(fullscreen.lockCalls, <bool>[true, false]);

      await controller.dispose();
    });
  });
}

class _FakeBackend implements PlayerBackend {
  final StreamController<PlayerEvent> _events = StreamController<PlayerEvent>.broadcast();

  @override
  final FlutterSignal<int?> textureId = signal<int?>(null);

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<int> create() async => 0;

  @override
  Future<void> open(
    String url, {
    String? castUrl,
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) async {}

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
  Future<void> showCastPicker() async {}

  @override
  Future<void> stopCasting() async {}

  @override
  Future<NaviteFile> takeSnapshot({String? savePath}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _FakeBrightness implements BrightnessController {
  _FakeBrightness({double initial = 1.0}) : _value = initial;

  double _value;

  @override
  Future<double> get current async => _value;

  @override
  Future<void> setBrightness(double value) async {
    _value = value;
  }
}

class _FakeFullscreen implements FullscreenCoordinator {
  final List<bool> lockCalls = <bool>[];

  @override
  Stream<bool> get externalChanges => const Stream<bool>.empty();

  @override
  Future<void> enter({required bool landscapeVideo}) async {}

  @override
  Future<void> exit() async {}

  @override
  Future<void> setOrientationLocked({
    required bool locked,
    required bool landscapeVideo,
    DeviceOrientation? lockedOrientation,
  }) async {
    lockCalls.add(locked);
  }

  @override
  void dispose() {}
}

class _FakeHostBridge implements VideoPlayerHostBridge {
  final StreamController<bool> fullscreenController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get fullscreenEvents => fullscreenController.stream;

  Future<void> close() async {
    await fullscreenController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
