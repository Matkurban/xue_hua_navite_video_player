import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelPlayerOrientation platform mapping', () {
    test('maps landscapeLeft/landscapeRight correctly for iOS vs Android', () {
      // iOS: landscapeLeft (top on left, home on right) -> UIInterfaceOrientationMask.landscapeRight
      //      -> Flutter DeviceOrientation.landscapeRight
      expect(
        MethodChannelPlayerOrientation.toPreferredSystemOrientations(
          DevicePhysicalOrientation.landscapeLeft,
          platform: TargetPlatform.iOS,
        ),
        <DeviceOrientation>[DeviceOrientation.landscapeRight],
      );
      expect(
        MethodChannelPlayerOrientation.toPreferredSystemOrientations(
          DevicePhysicalOrientation.landscapeRight,
          platform: TargetPlatform.iOS,
        ),
        <DeviceOrientation>[DeviceOrientation.landscapeLeft],
      );

      // Android: direct mapping
      expect(
        MethodChannelPlayerOrientation.toPreferredSystemOrientations(
          DevicePhysicalOrientation.landscapeLeft,
          platform: TargetPlatform.android,
        ),
        <DeviceOrientation>[DeviceOrientation.landscapeLeft],
      );
      expect(
        MethodChannelPlayerOrientation.toPreferredSystemOrientations(
          DevicePhysicalOrientation.landscapeRight,
          platform: TargetPlatform.android,
        ),
        <DeviceOrientation>[DeviceOrientation.landscapeRight],
      );
    });
  });

  group('PlayerOrientationController state machine', () {
    test('lock and unlock do NOT cause spurious 180-degree flip when already in landscapeRight', () async {
      final _FakeOrientationPlatform platform = _FakeOrientationPlatform(
        initialCurrent: DevicePhysicalOrientation.landscapeRight,
      );
      final PlayerOrientationController controller = PlayerOrientationController(
        platform: platform,
      );

      // Simulate physical grip already in landscapeRight before entering fullscreen.
      platform.emit(DevicePhysicalOrientation.landscapeRight);
      await Future<void>.delayed(Duration.zero);

      await controller.enterFullscreen(landscapeVideo: true);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeRight);
      expect(platform.targetCalls, <DevicePhysicalOrientation>[
        DevicePhysicalOrientation.landscapeRight,
      ]);

      // Lock without specifying explicit orientation -> queries actual current orientation
      // (landscapeRight) and does NOT emit a redundant or flipped setTargetOrientation call.
      await controller.lock();
      expect(controller.isLocked.value, isTrue);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeRight);
      expect(platform.targetCalls, <DevicePhysicalOrientation>[
        DevicePhysicalOrientation.landscapeRight,
      ]);

      // Unlock while phone is still held in landscapeRight -> zero extra rotation!
      await controller.unlock();
      expect(controller.isLocked.value, isFalse);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeRight);
      expect(platform.targetCalls, <DevicePhysicalOrientation>[
        DevicePhysicalOrientation.landscapeRight,
      ]);

      controller.dispose();
      platform.dispose();
    });

    test('auto-rotates 180 degrees in fullscreen when unlocked, pauses when locked, and resumes on unlock', () async {
      final _FakeOrientationPlatform platform = _FakeOrientationPlatform();
      final PlayerOrientationController controller = PlayerOrientationController(
        platform: platform,
      );

      await controller.enterFullscreen(landscapeVideo: true);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeLeft);

      // Flip phone 180 degrees while unlocked -> auto-switches to landscapeRight.
      platform.emit(DevicePhysicalOrientation.landscapeRight);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeRight);

      // Lock screen -> flipping back to landscapeLeft must be ignored.
      await controller.lock();
      platform.emit(DevicePhysicalOrientation.landscapeLeft);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeRight);

      // Unlock screen -> immediately catches up to physical landscapeLeft grip.
      await controller.unlock();
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.landscapeLeft);

      controller.dispose();
      platform.dispose();
    });

    test('auto-reset guard prevents bounce-back after exiting fullscreen while still holding horizontally', () async {
      final _FakeOrientationPlatform platform = _FakeOrientationPlatform();
      final List<DevicePhysicalOrientation> autoEnterCalls = <DevicePhysicalOrientation>[];
      final PlayerOrientationController controller = PlayerOrientationController(
        platform: platform,
        onAutoEnterFullscreen: autoEnterCalls.add,
      );

      // Enter fullscreen while holding landscapeLeft.
      platform.emit(DevicePhysicalOrientation.landscapeLeft);
      await Future<void>.delayed(Duration.zero);
      autoEnterCalls.clear();

      await controller.enterFullscreen(landscapeVideo: true);
      await controller.exitFullscreen();

      expect(controller.isFullscreen.value, isFalse);
      expect(controller.currentOrientation.value, DevicePhysicalOrientation.portraitUp);
      expect(controller.isAwaitingPortraitReset.value, isTrue);

      // Still holding phone horizontally -> must NOT bounce back to fullscreen!
      platform.emit(DevicePhysicalOrientation.landscapeRight);
      await Future<void>.delayed(Duration.zero);
      expect(autoEnterCalls, isEmpty);
      expect(controller.isAwaitingPortraitReset.value, isTrue);

      // User finally holds phone upright -> guard clears.
      platform.emit(DevicePhysicalOrientation.portraitUp);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isAwaitingPortraitReset.value, isFalse);

      // Subsequent horizontal rotation now triggers auto-enter fullscreen normally.
      platform.emit(DevicePhysicalOrientation.landscapeLeft);
      await Future<void>.delayed(Duration.zero);
      expect(autoEnterCalls, <DevicePhysicalOrientation>[
        DevicePhysicalOrientation.landscapeLeft,
      ]);

      controller.dispose();
      platform.dispose();
    });
  });

  group('WebOrientationViewport iOS Safari CSS fallback', () {
    testWidgets('rotates viewport 90/-90 degrees when usesCssFallbackRotation is true', (
      WidgetTester tester,
    ) async {
      final _FakeOrientationPlatform platform = _FakeOrientationPlatform(
        cssFallback: true,
      );
      final PlayerOrientationController controller = PlayerOrientationController(
        platform: platform,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390.0,
              height: 844.0,
              child: WebOrientationViewport(
                controller: controller,
                animationDuration: Duration.zero,
                child: const Text('PLAYER'),
              ),
            ),
          ),
        ),
      );

      // Not fullscreen -> no Transform.rotate wrapper.
      expect(find.byType(Transform), findsNothing);

      // Enter fullscreen -> rotates to landscapeLeft (+90 deg).
      await controller.enterFullscreen(landscapeVideo: true);
      await tester.pumpAndSettle();
      expect(find.byType(Transform), findsOneWidget);
      expect(controller.cssRotationRadians.value, greaterThan(0.0));

      // Flip to landscapeRight -> rotates to -90 deg.
      platform.emit(DevicePhysicalOrientation.landscapeRight);
      await tester.pumpAndSettle();
      expect(controller.cssRotationRadians.value, lessThan(0.0));

      // Exit fullscreen -> returns to normal unrotated viewport.
      await controller.exitFullscreen();
      await tester.pumpAndSettle();
      expect(find.byType(Transform), findsNothing);

      controller.dispose();
      platform.dispose();
    });
  });
}

class _FakeOrientationPlatform extends PlayerOrientationPlatform {
  _FakeOrientationPlatform({
    this.cssFallback = false,
    DevicePhysicalOrientation initialCurrent = DevicePhysicalOrientation.portraitUp,
  }) : _current = initialCurrent;

  final bool cssFallback;
  DevicePhysicalOrientation _current;
  final List<DevicePhysicalOrientation> targetCalls = <DevicePhysicalOrientation>[];
  final StreamController<OrientationSensorEvent> _controller =
      StreamController<OrientationSensorEvent>.broadcast();

  void emit(
    DevicePhysicalOrientation orientation, {
    double confidence = 0.95,
    double angleDegrees = 0.0,
  }) {
    _controller.add(
      OrientationSensorEvent(
        orientation: orientation,
        confidence: confidence,
        angleDegrees: angleDegrees,
      ),
    );
  }

  @override
  bool get usesCssFallbackRotation => cssFallback;

  @override
  Stream<OrientationSensorEvent> get physicalOrientationStream => _controller.stream;

  @override
  Future<void> setTargetOrientation(DevicePhysicalOrientation orientation) async {
    _current = orientation;
    targetCalls.add(orientation);
  }

  @override
  Future<DevicePhysicalOrientation> getCurrentOrientation() async => _current;

  @override
  Future<void> startSensorListening() async {}

  @override
  Future<void> stopSensorListening() async {}

  @override
  Future<void> setImmersiveFullscreen(bool enabled) async {}

  @override
  void dispose() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }
}
