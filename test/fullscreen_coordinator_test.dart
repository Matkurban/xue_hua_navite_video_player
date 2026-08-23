import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('xue_hua_navite_video_player/player');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('desktop enter / exit invokes setWindowFullscreen', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    final coord = SystemChromeFullscreenCoordinator(channel: channel, isWeb: false);
    await coord.enter(landscapeVideo: true);
    await coord.exit();

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setWindowFullscreen');
    expect(calls[0].arguments, {'value': true});
    expect(calls[1].method, 'setWindowFullscreen');
    expect(calls[1].arguments, {'value': false});
    coord.dispose();
  });

  test('web enter / exit uses browser applier', () async {
    final browser = _FakeBrowser();
    final coord = SystemChromeFullscreenCoordinator(
      channel: channel,
      browser: browser,
      isWeb: true,
    );

    await coord.enter(landscapeVideo: true);
    expect(browser.entered, isTrue);
    await coord.exit();
    expect(browser.entered, isFalse);
    coord.dispose();
  });

  test('onWindowFullscreen method call is forwarded as externalChanges', () async {
    final coord = SystemChromeFullscreenCoordinator(channel: channel, isWeb: false);
    final events = <bool>[];
    final sub = coord.externalChanges.listen(events.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onWindowFullscreen', false),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, [false]);
    await sub.cancel();
    coord.dispose();
  });

  test('web browser changes are forwarded as externalChanges', () async {
    final browser = _FakeBrowser();
    final coord = SystemChromeFullscreenCoordinator(
      channel: channel,
      browser: browser,
      isWeb: true,
    );
    final events = <bool>[];
    final sub = coord.externalChanges.listen(events.add);

    browser.changesController.add(false);
    await Future<void>.delayed(Duration.zero);

    expect(events, [false]);
    await sub.cancel();
    coord.dispose();
  });
}

class _FakeBrowser implements BrowserFullscreenApplier {
  bool entered = false;
  final StreamController<bool> changesController = StreamController<bool>.broadcast();

  @override
  Future<void> enter() async {
    entered = true;
  }

  @override
  Future<void> exit() async {
    entered = false;
  }

  @override
  Stream<bool> get changes => changesController.stream;
}
