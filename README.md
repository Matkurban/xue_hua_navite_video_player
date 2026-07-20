# xue_hua_navite_video_player

[中文文档](README_ZH.md)

A cross-platform Flutter audio/video player plugin. Dart exposes a unified controller and optional UI; each platform decodes and renders with a native engine (ExoPlayer / AVPlayer / libmpv / HTML5).

| | |
|---|---|
| Version | `1.0.1` |
| Flutter | `>= 3.44.0` |
| Dart SDK | `^3.12.0` |
| Repository | [GitHub](https://github.com/MatkurbanWeiXin/xue_hua_navite_video_player) |
| Homepage | [jsontodart.cn](https://jsontodart.cn) |
| License | Apache 2.0 |

---

## Table of contents

- [Features](#features)
- [Platform engines & rendering](#platform-engines--rendering)
- [Architecture](#architecture)
- [Installation](#installation)
- [Platform setup](#platform-setup)
- [Quick start](#quick-start)
- [Important: single active session](#important-single-active-session)
- [VideoSource](#videosource)
- [VideoPlayerController](#videoplayercontroller)
- [PlayState](#playstate)
- [Widgets](#widgets)
- [VideoPlayerTheme](#videoplayertheme)
- [Fullscreen contract](#fullscreen-contract)
- [Gestures & keyboard](#gestures--keyboard)
- [Snapshots & media probe](#snapshots--media-probe)
- [Custom UI with Signals](#custom-ui-with-signals)
- [Example](#example)
- [FAQ](#faq)
- [License](#license)

---

## Features

- **6 platforms** — Android, iOS, macOS, Linux, Windows, Web
- **Native rendering** — PlatformView on Android / iOS / macOS; Texture (libmpv) on Linux / Windows; HTML5 `<video>` on Web
- **Sources** — network URL, local file, Flutter asset (assets are extracted to a temp directory)
- **Controls** — play / pause / seek / volume / mute / speed / brightness / aspect mode / snapshot
- **Built-in UI** — drop-in `VideoPlayer` and bare `CorePlayer`
- **Theming** — `VideoPlayerTheme` via `ThemeData.extensions`
- **Fullscreen** — controller owns orientation / immersive system UI; visual Overlay fullscreen requires a mounted `VideoPlayer`
- **Utilities** — duration probing and cover-frame extraction without starting playback
- **Reactive state** — playback state exposed with [`signals_flutter`](https://pub.dev/packages/signals_flutter)

---

## Platform engines & rendering

| Platform | Native engine | Surface |
|----------|---------------|---------|
| Android | ExoPlayer (Media3) | `AndroidView` PlatformView |
| iOS | AVPlayer | `UiKitView` PlatformView |
| macOS | AVPlayer | `AppKitView` PlatformView |
| Linux | libmpv (software) | Flutter `Texture` |
| Windows | libmpv (software) | Flutter `Texture` |
| Web | HTML5 `<video>` | `HtmlElementView` |

`AspectRatioMode` (`fit` / `fill` / `stretch`) maps to each platform’s native fit property (videoGravity, resizeMode, object-fit, mpv keepaspect/panscan, etc.).

---

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│  App UI                                                  │
│  VideoPlayer / CorePlayer / custom widgets               │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  VideoPlayerController (public facade)                   │
│  └── PlaybackSession (state machine + Signals)           │
│       └── PlayerBackend / ChannelPlayerBackend           │
└───────────────────────────┬─────────────────────────────┘
                            │ MethodChannel / EventChannel
┌───────────────────────────▼─────────────────────────────┐
│  Native: ExoPlayer / AVPlayer / libmpv / HTML5           │
└─────────────────────────────────────────────────────────┘

XueHuaNaviteVideoPlayer.instance
  └── MediaProbe (duration / covers; does not own the play session)
```

| Term | Meaning |
|------|---------|
| **VideoSource** | Sealed source model (network / file / asset) resolved to a native URL |
| **PlayState** | High-level playback state owned by `PlaybackSession` |
| **PlayerBackend** | Session transport: create / open / play / pause / seek / volume / speed / snapshot |
| **PlaybackSession** | Owns open → ready → playing / paused / stopped / completed / error |
| **VideoPlayerController** | Stable public API for apps and UI |
| **MediaProbe** | Probe APIs that do not create a live play session |

See [CONTEXT.md](CONTEXT.md) for domain notes.

---

## Installation

```yaml
dependencies:
  xue_hua_navite_video_player: ^1.0.1
```

```bash
flutter pub get
```

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

Public exports include: `VideoSource`, `VideoPlayerController`, `VideoPlayer`, `CorePlayer`, `VideoPlayerTheme`, `PlayState`, `AspectRatioMode`, `SkipSecondType`, `VideoCoverFrame`, `XueHuaNaviteVideoPlayer`, and `XFile` (re-exported from `cross_file`).

---

## Platform setup

### Android

Ensure network permission for remote media:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS

HTTPS playback usually needs no extra setup. For cleartext HTTP, configure App Transport Security in `Info.plist` as needed (avoid wide-open ATS in production). Local files must be readable inside the sandbox.

### macOS

Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

File access outside the sandbox may require additional entitlements.

### Linux

Install libmpv development packages:

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev

# Fedora
sudo dnf install mpv-libs-devel

# Arch
sudo pacman -S mpv
```

### Windows

Playback uses libmpv software rendering. Ensure the mpv runtime can be loaded with your build. If playback fails, check missing mpv native dependencies first.

### Web

Uses HTML5 `<video>`:

- Cross-origin media needs correct CORS headers (playback and/or snapshots may fail otherwise)
- Browsers may block unmuted autoplay until a user gesture

---

## Quick start

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
      theme: ThemeData(
        extensions: const [
          VideoPlayerTheme(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
        ],
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayer(
          controller: _controller,
          fill: true,
          onClose: () {},
        ),
      ),
    );
  }
}
```

`XueHuaNaviteVideoPlayer.instance.initialize()` is an idempotent binding helper. The native player session is created by `VideoPlayerController.initialize()`.

---

## Important: single active session

The plugin hosts **one** native player behind process-wide channels.

- Do not treat multiple `VideoPlayerController` instances as independent parallel players
- A later `open` / `play*` takes over the same native session
- Dispose the controller when leaving a page, then create + `initialize()` on the next page

Multi-instance concurrent players (e.g. PiP + list preview) are **not** supported.

---

## VideoSource

Sealed source types:

| Type | Factory | Notes |
|------|---------|-------|
| `NetworkVideoSource` | `VideoSource.network(url)` | HTTP(S); opened directly by the native player |
| `FileVideoSource` | `VideoSource.file(path)` | Absolute path or `file://` URI |
| `AssetVideoSource` | `VideoSource.asset(path)` | Flutter asset; extracted to temp on first use |

```dart
final network = VideoSource.network('https://example.com/a.mp4');
final file = VideoSource.file('/absolute/path/to/movie.mp4');
final asset = VideoSource.asset('assets/videos/intro.mp4');

final nativeUrl = await network.resolveToNativeUrl();
```

Declare assets in your app `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/videos/intro.mp4
```

Network media is opened directly by the native player via the original URL.

---

## VideoPlayerController

### Lifecycle

```dart
final controller = VideoPlayerController();
await controller.initialize(); // create native session + subscribe events
// ... control playback ...
await controller.dispose();    // release native resources; instance unusable after
controller.reset();            // reset Dart-side state without disposing the session
```

Optional constructor deps (mainly for tests):

```dart
VideoPlayerController({
  PlayerBackend? backend,
  FullscreenCoordinator? fullscreen,
  BrightnessController? brightness,
});
```

### Open & play

| API | Behavior |
|-----|----------|
| `playNetwork(url)` | Open network source and start |
| `openNetwork(url)` | Open only; call `play()` later |
| `playFile` / `openFile` | Local file |
| `playAsset` / `openAsset` | Flutter asset |
| `playSource` / `openSource` | Generic entry |
| `play` / `pause` / `playOrPause` | Transport |
| `stop` | Explicit stop (vs natural completion) |
| `seek` | Absolute seek |
| `seekForward` / `seekBackward` | Step by `skipSecondType` |

```dart
await controller.openNetwork('https://example.com/video.mp4');
await controller.play();

await controller.playSource(VideoSource.file('/tmp/a.mp4'));
```

### Volume, mute, speed, brightness

```dart
await controller.setVolume(0.8);      // 0.0 – 1.0
await controller.setMuted(true);
await controller.toggleMuted();
await controller.setSpeed(1.5);       // built-in menu: 0.5 / 1.0 / 1.25 / 1.5 / 2.0
await controller.setBrightness(0.6);  // 0.0 – 1.0 (screen brightness)
```

### Skip step & aspect mode

```dart
controller.setSkipSecondType(SkipSecondType.second15);
// second5 / second10 / second15 / second30 / second45 / second60

await controller.setAspectRatioMode(AspectRatioMode.fill);
// fit | fill | stretch
```

### Fullscreen

```dart
await controller.enterFullscreen();
await controller.exitFullscreen();
await controller.toggleFullscreen();
```

See [Fullscreen contract](#fullscreen-contract).

### Snapshot

```dart
final XFile png = await controller.takeSnapshot();
final XFile saved = await controller.takeSnapshot(savePath: '/tmp/frame.png');
```

### Reactive signals

| Signal / computed | Type | Meaning |
|-------------------|------|---------|
| `playState` | `PlayState` | Playback state |
| `position` / `duration` | `Duration` | Progress / total |
| `volume` / `speed` | `double` | Volume / rate |
| `isBuffering` | `bool` | Buffering |
| `errorMessage` | `String?` | Error text |
| `currentUrl` | `String?` | Current native URL |
| `mimeType` | `String?` | MIME type |
| `videoSize` | `Size` | Video size |
| `rotationDegrees` | `int` | Rotation |
| `videoAspectRatio` | `double` | Ratio after rotation |
| `isVideo` / `isAudio` | `bool` | From mime |
| `isPlaying` | `bool` | Playing |
| `progressPercent` | `double` | 0.0 – 1.0 |
| `muted` | `bool` | Muted |
| `skipSecondType` | `SkipSecondType` | Skip step |
| `aspectRatioMode` | `AspectRatioMode` | Fit mode |
| `isFullscreen` | `bool` | Fullscreen |
| `brightness` | `double` | Screen brightness |
| `textureId` | `int?` | Texture id (desktop) |

```dart
SignalBuilder(
  builder: (context) {
    final state = controller.playState.value;
    final pos = controller.position.value;
    return Text('${state.name}  ${pos.inSeconds}s');
  },
);
```

---

## PlayState

```dart
enum PlayState { idle, loading, playing, paused, stopped, completed, error }
```

| State | Meaning |
|-------|---------|
| `idle` | Initial / after reset |
| `loading` | Opening / preparing |
| `playing` | Playing |
| `paused` | Paused |
| `stopped` | Explicit `stop()` |
| `completed` | Natural end-of-stream (UI may show replay) |
| `error` | Failure; see `errorMessage` |

`isBuffering` can overlap other states (e.g. playing + buffering).

---

## Widgets

### `CorePlayer` — surface only

Renders the native frame plus loading / buffering / error. Use for fully custom chrome.

```dart
CorePlayer(
  controller: controller,
  aspectRatio: 16 / 9,
  backgroundColor: Colors.black,
  loadingBuilder: (context) => const CircularProgressIndicator(),
  errorBuilder: (context, message) => Text(message ?? 'Error'),
);
```

> With `CorePlayer` only, `enterFullscreen()` still changes orientation / immersive UI, but **does not** host a visual edge-to-edge Overlay.

### `VideoPlayer` — full chrome

Top bar, center transport, bottom scrubber. Tap toggles chrome; auto-hides after ~3s while playing.

```dart
VideoPlayer(
  controller: controller,
  fill: true,
  aspectRatio: null,
  autoHideDelay: const Duration(seconds: 3),
  fadeDuration: const Duration(milliseconds: 250),
  initiallyVisible: true,
  onClose: () => Navigator.pop(context),
  leading: null,
  title: const Text('Title'),
  actions: const [],
  showAspectRatioMenu: true,
  enableFullscreen: true,
  skipSecondType: SkipSecondType.second10,
  // topBarBuilder / centerControlsBuilder /
  // bottomScrubberBuilder / extraOverlayBuilder
  // errorBuilder / loadingBuilder
);
```

Slot builders receive `VideoPlayerSlotContext`:

```dart
class VideoPlayerSlotContext {
  final VideoPlayerController controller;
  final VideoPlayerTheme theme;
  final VoidCallback showControls;
  final VoidCallback hideControls;
}
```

**Visual fullscreen:** `VideoPlayer` reparents the surface into a root `Overlay` via `OverlayPortal`. Prefer `controller.toggleFullscreen()` while this widget is mounted under an `Overlay` ancestor (`MaterialApp` provides one).

---

## VideoPlayerTheme

Register on `ThemeData.extensions`. Defaults apply when omitted.

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const [
      VideoPlayerTheme(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        chromeIconSize: 22,
        scrubberActiveColor: Colors.white,
        menuBackgroundColor: Color(0xF01A1A1A),
      ),
    ],
  ),
);
```

| Group | Examples |
|-------|----------|
| Base | `foregroundColor`, `backgroundColor` |
| Center | `centerControlsSpacing`, `centerPlayButtonIconSize`, `centerSkipButtonIconSize` |
| Bars | `chromeIconSize`, `topBarPadding`, `bottomBarPadding`, `timeTextStyle` |
| Scrubber | active / buffered / inactive / thumb colors and sizes |
| Menu | `menuBackgroundColor`, `menuBorderRadius`, `menuItemTextStyle` |
| Gesture HUD | `hudBackgroundColor`, `hudPadding`, `hudTextStyle` |

```dart
final theme = VideoPlayerTheme.of(context);
```

---

## Fullscreen contract

```dart
await controller.enterFullscreen(); // isFullscreen + system chrome / orientation
await controller.exitFullscreen();
```

| Call site | Effect |
|-----------|--------|
| Mounted `VideoPlayer` under an `Overlay` | Immersive UI **and** edge-to-edge Overlay host |
| Controller / `CorePlayer` only | Immersive UI only — no visual Overlay host |

Orientation prefers landscape/portrait based on `videoAspectRatio`.

Gestures (mobile) are active only while fullscreen **and** a `VideoPlayer` is mounted. Keyboard shortcuts (desktop / web) work in fullscreen or inline when the player is focused.

---

## Gestures & keyboard

### Mobile (fullscreen)

| Gesture | Zone | Action |
|---------|------|--------|
| Horizontal drag | Anywhere (past threshold) | Seek (scaled by `skipSecondType`) |
| Vertical drag | Left ~40% | Brightness |
| Vertical drag | Right ~40% | Volume |
| Tap | — | Toggle chrome |

### Desktop / Web (focused — fullscreen or inline)

| Key | Action |
|-----|--------|
| `Space` | Play / pause |
| `←` / `→` | Seek backward / forward |
| `↑` / `↓` | Volume ±0.05 |

---

## Snapshots & media probe

### Current-frame snapshot

```dart
final XFile png = await controller.takeSnapshot();
```

- **iOS / macOS:** `AVAssetImageGenerator` at the current time (PlatformView display; no Texture frame buffer required)
- **Other platforms:** native snapshot paths
- Returns a PNG `XFile` (re-exported; no need to depend on `cross_file` yourself)

### Cover candidates (no playback session)

```dart
final frames = await XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,
  minBrightness: 0.08,
);

for (final frame in frames) {
  // frame.image, frame.position, frame.brightness
}
```

On native platforms `XFile.path` is a real file path; on web it may be a blob / data URL.

### Duration probe (no playback session)

```dart
final duration = await XueHuaNaviteVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
  timeout: const Duration(seconds: 15),
);
// null on failure, timeout, or non-finite duration (e.g. live)
```

---

## Custom UI with Signals

```dart
class MyPlayer extends StatelessWidget {
  const MyPlayer({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: CorePlayer(controller: controller)),
        SignalBuilder(
          builder: (context) {
            final playing = controller.isPlaying.value;
            return IconButton(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: controller.playOrPause,
            );
          },
        ),
      ],
    );
  }
}
```

Exported scrubber:

```dart
PlayerScrubberSlider(controller: controller);
```

---

## Example

See [`example/`](example/) for a full demo: playlist, themed `VideoPlayer`, fullscreen, snapshots, cover extraction, and state chips.

```bash
cd example
flutter run
```

---

## FAQ

**Why does a second controller interrupt the first?**  
Process-wide single native session. Reuse serially and `dispose()` on leave.

**Fullscreen does not go edge-to-edge?**  
Use mounted `VideoPlayer` under an `Overlay`, then `toggleFullscreen()` / `enterFullscreen()`.

**Asset playback fails?**  
Declare the asset in `pubspec.yaml` with a matching path. First play extracts to temp storage.

**Linux build cannot find mpv?**  
Install `libmpv-dev` (or distro equivalent).

**Web snapshot / black frame?**  
Check CORS and whether the browser allows reading cross-origin media pixels.

**How many `initialize()` calls?**  
- Plugin `initialize()`: optional, once in `main`  
- Controller `initialize()`: once per controller lifetime; do not reuse after `dispose()`

---

## License

Licensed under the [Apache License 2.0](LICENSE).
