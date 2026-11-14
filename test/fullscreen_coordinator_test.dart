import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_video_player/src/bridge/video_player_host_bridge.dart';
import 'package:xue_hua_navite_video_player/src/player/fullscreen_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('desktop enter / exit invokes setWindowFullscreen', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final bridge = _FakeHostBridge();

    final coord = SystemChromeFullscreenCoordinator(bridge: bridge, isWeb: false);
    await coord.enter(landscapeVideo: true);
    await coord.exit();

    expect(bridge.fullscreenCalls, [true, false]);
    coord.dispose();
    await bridge.close();
  });

  test('web enter / exit uses browser applier', () async {
    final bridge = _FakeHostBridge();
    final browser = _FakeBrowser();
    final coord = SystemChromeFullscreenCoordinator(
      bridge: bridge,
      browser: browser,
      isWeb: true,
    );

    await coord.enter(landscapeVideo: true);
    expect(browser.entered, isTrue);
    await coord.exit();
    expect(browser.entered, isFalse);
    coord.dispose();
    await bridge.close();
  });

  test('bridge fullscreenEvents is forwarded as externalChanges', () async {
    final bridge = _FakeHostBridge();
    final coord = SystemChromeFullscreenCoordinator(bridge: bridge, isWeb: false);
    final events = <bool>[];
    final sub = coord.externalChanges.listen(events.add);

    bridge.fullscreenController.add(false);
    await Future<void>.delayed(Duration.zero);

    expect(events, [false]);
    await sub.cancel();
    coord.dispose();
    await bridge.close();
  });

  test('web browser changes are forwarded as externalChanges', () async {
    final bridge = _FakeHostBridge();
    final browser = _FakeBrowser();
    final coord = SystemChromeFullscreenCoordinator(
      bridge: bridge,
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
    await bridge.close();
  });
}

class _FakeHostBridge implements VideoPlayerHostBridge {
  final StreamController<bool> fullscreenController = StreamController<bool>.broadcast();
  final List<bool> fullscreenCalls = <bool>[];

  @override
  Stream<bool> get fullscreenEvents => fullscreenController.stream;

  @override
  Future<void> setWindowFullscreen(bool value) async {
    fullscreenCalls.add(value);
  }

  Future<void> close() async {
    await fullscreenController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
