---
name: xue-hua-navite-video-player-playback
description: >-
  Play, seek, and control media with xue_hua_navite_video_player. Use when
  calling VideoPlayerController, VideoSource, PlayState, SkipSecondType,
  AspectRatioMode, XueHuaNaviteVideoPlayer probe APIs, takeSnapshot,
  extractCoverCandidates, or getDuration. Read references/ before inventing
  signatures.
---

# Playback — xue_hua_navite_video_player

Import the barrel only:

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

Setup and single-session rules: [xue-hua-navite-video-player-setup](../xue-hua-navite-video-player-setup/SKILL.md).
Widgets: [xue-hua-navite-video-player-ui](../xue-hua-navite-video-player-ui/SKILL.md).

Before calling an API, read the matching reference:

- [references/video-source.md](references/video-source.md)
- [references/video-player-controller.md](references/video-player-controller.md)
- [references/play-state-and-enums.md](references/play-state-and-enums.md)
- [references/plugin-and-probe.md](references/plugin-and-probe.md)

Do not import `PlaybackSession`, `PlayerBackend`, `MediaProbe`, or `MimeDetector`. They are not barrel-exported.

## Guidelines

- Call `controller.initialize()` before `open*` / `play*`. Calling it after `dispose()` throws `StateError`.
- `playNetwork` / `playFile` / `playAsset` / `playSource` open and start playback. `open*` variants load without auto-play; call `play()` later.
- `playAsset` / `openAsset` accept optional `AssetBundle? bundle` (defaults to `rootBundle` inside the extractor).
- On `openSource`, Dart state is `reset()` first, then `playState` becomes `loading`. Native volume, speed, and aspect mode are re-applied after open.
- `currentUrl` stores the **source identity** (`url`, `file://…`, or `asset://…`), not the extracted native file path.
- `mimeType` is inferred from the identity path extension. Unknown extensions become `application/octet-stream`, so `isVideo` / `isAudio` stay false.
- `play()` on `PlayState.completed` seeks to 0 then plays (replay). `playOrPause()` pauses when `isPlaying`, otherwise calls `play()`.
- `stop()` pauses native playback and sets `PlayState.stopped`. It is distinct from natural `completed`.
- `seek(Duration)` sends milliseconds to native. `seekForward` / `seekBackward` step by `skipSecondType.duration`, clamped to `[0, duration]` when duration is positive.
- `setVolume` clamps to `0.0–1.0`. Value `0` sets `muted` true; value `> 0` sets `muted` false.
- `setMuted(true)` stores the previous volume (or `1.0` if it was 0), sets volume to 0. `setMuted(false)` restores that volume.
- `setSpeed` does **not** clamp. Built-in UI offers `0.5 / 1.0 / 1.25 / 1.5 / 2.0` only.
- `setBrightness` clamps to `0.0–1.0`. Web is a no-op (get `1.0`, set ignored).
- `setSkipSecondType` is synchronous Dart state. `setAspectRatioMode` updates the signal and the native fit property.
- `setVideoViewSize` is a no-op when width or height `<= 0`. `CorePlayer` already reports size on Linux/Windows Texture. Custom Texture surfaces must call it for mpv panscan.
- `enterFullscreen` sets `isFullscreen` first, then the platform host. Visual Overlay chrome requires a mounted `VideoPlayer` under an `Overlay`. `CorePlayer` alone still changes window / browser / orientation.
- `takeSnapshot` throws `StateError` if disposed or if `currentUrl` is null. Returns a PNG `XFile`. Optional `savePath` writes to that path.
- `reset()` clears play/position/duration/buffering/error/url/mime/size/rotation. It does **not** reset volume, speed, muted, skip, aspect, fullscreen, or brightness, and does not dispose the native session.
- Watch signals with `SignalBuilder` / `effect` from `signals_flutter`. Read `.value` inside the builder.
- `isBuffering` can overlap other states (for example playing + buffering).
- Probe with `XueHuaNaviteVideoPlayer.instance`, not a new player. `extractCoverCandidates` requires `count > 0` (assert), times out at 60s (empty list), sorts by brightness descending. `getDuration` defaults to 15s and returns `null` on failure, timeout, or non-positive duration.

## Example — open then play

```dart
final controller = VideoPlayerController();
await controller.initialize();
await controller.openNetwork('https://example.com/video.mp4');
await controller.setVolume(0.8);
await controller.setSpeed(1.25);
await controller.play();
```

## Example — generic source + replay-safe play

```dart
final source = VideoSource.asset('assets/videos/intro.mp4');
await controller.playSource(source);
// Later, after completed:
await controller.play(); // seeks to 0 then plays
```

## Example — snapshot and duration probe

```dart
final png = await controller.takeSnapshot();
final duration = await XueHuaNaviteVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
);
```
