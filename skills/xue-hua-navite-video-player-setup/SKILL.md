---
name: xue-hua-navite-video-player-setup
description: >-
  Install, initialize, and dispose xue_hua_navite_video_player. Use when adding
  the plugin, configuring Android/iOS/macOS/Linux/Windows/Web, calling
  initialize, or creating VideoPlayerController. Covers the process-wide single
  native session, asset vs network sources, and platform permissions.
---

# Setup — xue_hua_navite_video_player

Import only the barrel. Never import `package:xue_hua_navite_video_player/src/...`.

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

Playback APIs: [xue-hua-navite-video-player-playback](../xue-hua-navite-video-player-playback/SKILL.md).
Widgets and theme: [xue-hua-navite-video-player-ui](../xue-hua-navite-video-player-ui/SKILL.md).

## Guidelines

- Add `xue_hua_navite_video_player: ^2.0.3` and run `flutter pub get`.
- Call `WidgetsFlutterBinding.ensureInitialized()` before any plugin work.
- `XueHuaNaviteVideoPlayer.instance.initialize()` is optional, idempotent, and does **not** create the native player. It only ensures the binding and sets `isInitialized`.
- `VideoPlayerController.initialize()` creates the native session and subscribes to events. Call it once per controller lifetime, before `open*` / `play*`.
- After `VideoPlayerController.dispose()`, that instance is unusable. Create a new controller and `initialize()` again.
- The plugin hosts **one** native player behind process-wide channels. A second `VideoPlayerController.initialize()` while another native session is live throws `StateError`. Dispose the previous controller first.
- Do not treat multiple controllers as parallel independent players. A later `open` / `play*` takes over the same native session.
- Leave `VideoPlayerController` constructor `backend` / `fullscreen` / `brightness` at defaults. Those types are **not** barrel-exported (test injection only).
- `XueHuaNaviteVideoPlayer.dispose()` only clears the plugin binding flag. It does **not** release the playback session. Always `dispose()` the controller.
- Declare Flutter assets in the **app** `pubspec.yaml`. Native platforms extract assets to a temp file; Web/WASM uses the Flutter-hosted `assets/` URL.
- Probe APIs (`getDuration`, `extractCoverCandidates`) share the MethodChannel but do not call `create()`. Avoid heavy probe work while a playback session is active.

## Platform setup

### Android

Ensure `INTERNET` in `android/app/src/main/AndroidManifest.xml` for network media:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS

HTTPS needs no extra setup. For cleartext HTTP, configure ATS in `Info.plist` (avoid wide-open ATS in production). Local files must be readable in the sandbox.

### macOS

Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

File access outside the sandbox needs extra entitlements.

### Linux

Install libmpv development packages (`libmpv-dev` / `mpv-libs-devel` / `mpv`).

### Windows

First build downloads a prebuilt libmpv SDK into `windows/mpv-dev-<arch>/`. If that fails, extract `mpv-dev-*.7z` and set `MPV_DIR` or `-DMPV_DIR=` to the folder that contains `include/mpv/`.

### Web

HTML5 `<video>`. Cross-origin media needs CORS. Browsers may block unmuted autoplay until a user gesture. Screen brightness is a no-op (get returns `1.0`, set is ignored).

## Example

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final VideoPlayerController _controller = VideoPlayerController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _controller.initialize();
    await _controller.playNetwork('https://example.com/video.mp4');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: VideoPlayer(controller: _controller, fill: true),
      ),
    );
  }
}
```

## Install package skills for consumers

After depending on this package, install the bundled skills:

```bash
dart run skills@ get
# or
dart run skills@ get --all
```
