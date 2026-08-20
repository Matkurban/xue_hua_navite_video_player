import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_video_player/src/core/video_source.dart';
import 'package:xue_hua_navite_video_player/src/player/media_probe.dart';
import 'package:xue_hua_navite_video_player/src/player/video_player_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('xue_hua_navite_video_player/player');
  const eventChannel = EventChannel('xue_hua_navite_video_player/player/events');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (call) async {
        if (call.method == 'create') return 0;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (Object? arguments, MockStreamHandlerEventSink events) {}),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      eventChannel,
      null,
    );
  });

  test('second native PlaybackSession initialize throws', () async {
    final first = VideoPlayerController();
    final second = VideoPlayerController();
    await first.initialize();
    await expectLater(second.initialize(), throwsA(isA<StateError>()));
    await first.dispose();
    await second.initialize();
    await second.dispose();
  });

  test('MediaProbe.probeDuration returns null when the channel hangs past timeout', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (call) async {
        if (call.method == 'getDuration') {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return 9000;
        }
        return null;
      },
    );

    final probe = MediaProbe();
    final duration = await probe.probeDuration(
      VideoSource.network('https://example.com/live.m3u8'),
      timeout: const Duration(milliseconds: 10),
    );
    expect(duration, isNull);
  });

  test('MediaProbe.probeDuration maps native milliseconds', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (call) async {
        if (call.method == 'getDuration') return 1500;
        return null;
      },
    );

    final probe = MediaProbe();
    final duration = await probe.probeDuration(VideoSource.network('https://example.com/a.mp4'));
    expect(duration, const Duration(milliseconds: 1500));
  });
}
