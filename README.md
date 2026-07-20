# xue_hua_navite_video_player

[中文文档](README_ZH.md)

A cross-platform Flutter plugin for playing audio and video with native engines
(ExoPlayer, AVPlayer, libmpv, HTML5).

## Features

- **Native rendering** — PlatformView (Android / iOS / macOS) or Texture (Linux / Windows / Web HTML5)
- **6-platform support** — Android, iOS, macOS, Linux, Windows, and Web
- **Built-in UI** — ready-to-use `VideoPlayer` / `CorePlayer` widgets and theme support
- **Sources** — network URL, local file, and Flutter asset
- **Controls** — play, pause, seek, mute, aspect mode, volume, speed menu, brightness, snapshot
- **Fullscreen** — controller API for orientation / immersive UI; visual fullscreen Overlay requires a mounted `VideoPlayer`
- **Utilities** — cover frame extraction and duration probing without starting playback

## Platform Engines

| Platform | Native Engine               |
|----------|-----------------------------|
| Android  | ExoPlayer (Media3)          |
| iOS      | AVPlayer                    |
| macOS    | AVPlayer                    |
| Linux    | libmpv (software rendering) |
| Windows  | libmpv (software rendering) |
| Web      | HTML5 `<video>`             |

## Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  xue_hua_navite_video_player: ^lasted
```

### Platform Setup

#### Android

Ensure the INTERNET permission is present:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

#### macOS

Add to `macos/Runner/Release.entitlements` and `DebugProfile.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

#### Linux

Install libmpv development libraries:

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev
# Fedora
sudo dnf install mpv-libs-devel
# Arch
sudo pacman -S mpv
```

## Quick Start

```dart
await XueHuaNaviteVideoPlayer.instance.initialize();

final controller = VideoPlayerController();
await controller.initialize();
await controller.playNetwork('https://example.com/video.mp4');

// In your widget tree:
VideoPlayer(controller: controller);
```

> **Single active session:** the plugin hosts one native player behind shared channels. Do not treat multiple `VideoPlayerController` instances as independent parallel players.

## Widgets

### `CorePlayer` — bare video surface

Renders only the native video frame plus minimal loading / buffering / error state.
Use this when you want a fully custom UI.

### `VideoPlayer` — polished drop-in UI

An iOS-style player with top bar, center transport controls, and a bottom scrubber.
Tapping the frame fades the overlay; it auto-hides during playback.

`VideoPlayer` also owns **visual fullscreen**: it reparents the video surface into a
root `Overlay` (PlatformView is not disposed/recreated). Prefer
`controller.toggleFullscreen()` while this widget is mounted.

### Theme

Register `VideoPlayerTheme` on `ThemeData.extensions`. All chrome visuals
(colors, icon sizes, menu / HUD / scrubber appearance) resolve from this
extension — defaults match the built-in look when omitted.

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const [
      VideoPlayerTheme(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        // Optional: chromeIconSize, menuBackgroundColor, hudTextStyle, …
      ),
    ],
  ),
  home: …,
);
```

## Fullscreen contract

```dart
await controller.enterFullscreen(); // system chrome + isFullscreen signal
await controller.exitFullscreen();
```

| Call site | Effect |
|-----------|--------|
| `VideoPlayer` mounted under an `Overlay` | Orientation / immersive UI **and** edge-to-edge player Overlay |
| Controller / `CorePlayer` only | Orientation / immersive UI only — no visual Overlay host |

Gestures (mobile) and keyboard shortcuts (desktop) are active only while fullscreen
**and** a `VideoPlayer` is mounted.

## Sources & Playback

```dart
// Network — opened directly by the native player.
await controller.playNetwork('https://example.com/video.mp4');

// Network open-only — prepare, then start later.
await controller.openNetwork('https://example.com/video.mp4');
await controller.play();

// Local file — absolute path or file:// URI.
await controller.playFile('/absolute/path/to/movie.mp4');

// Flutter asset — first call extracts the asset to the temp directory.
await controller.playAsset('assets/videos/intro.mp4');

// Generic — use when you already have a VideoSource.
await controller.playSource(VideoSource.network('https://...'));
```

When using `playAsset`, declare the asset under your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/videos/intro.mp4
```

## Snapshots & Cover Candidates

### `takeSnapshot()` — capture the current frame

```dart
final XFile png = await controller.takeSnapshot();
```

On **iOS / macOS**, snapshots use `AVAssetImageGenerator` at the current playback
time (display uses `AVPlayerLayer` PlatformView; no Texture frame buffer is required).
Other platforms use their native snapshot path.

### `extractCoverCandidates()` — pick the best cover frames

```dart
final frames = await XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,
  minBrightness: 0.08,
);
```

## Getting Video Duration

```dart
final duration = await XueHuaNaviteVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
  timeout: const Duration(seconds: 10),
);
```

Returns `null` on failure, timeout, or non-finite durations (e.g. live streams).

## Example

See the [example](example/) directory for a complete demo app.

## License

See [LICENSE](LICENSE) for details.
