---
name: xue-hua-navite-video-player-ui
description: >-
  Build player UI with xue_hua_navite_video_player. Use when creating
  VideoPlayer, CorePlayer, VideoPlayerTheme, PlayerScrubberSlider,
  VideoPlayerSlotContext, fullscreen Overlay chrome, gestures, or keyboard
  shortcuts. Read references/ for exact widget fields — PlayerScrubberSlider
  has no controller parameter.
---

# UI — xue_hua_navite_video_player

Import the barrel only. `PlayerGestureLayer`, `PlayerMenuButton`, and `handlePlayerKeyEvent` are **not** exported; `VideoPlayer` already uses them.

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

References:

- [references/core-player.md](references/core-player.md)
- [references/video-player.md](references/video-player.md)
- [references/video-player-theme.md](references/video-player-theme.md)
- [references/player-scrubber-slider.md](references/player-scrubber-slider.md)

## Guidelines

- Register `VideoPlayerTheme` on `ThemeData.extensions`. `VideoPlayerTheme.of(context)` falls back to `const VideoPlayerTheme()` when omitted.
- `CorePlayer` is surface + loading/buffering/error only. It **fills the parent**. Its `aspectRatio` field does not wrap layout; when null, the widget watches `videoAspectRatio` so size/rotation rebuild. Wrap it yourself (`AspectRatio`, `Expanded`, …) for custom chrome.
- `VideoPlayer` adds top bar, center transport, bottom scrubber, Overlay fullscreen, gestures, and keyboard.
- Visual fullscreen (edge-to-edge Overlay) requires a mounted `VideoPlayer` under an `Overlay` (`MaterialApp` provides one). Call `controller.toggleFullscreen()` / `enterFullscreen()` while that widget is mounted.
- `CorePlayer` alone still applies platform fullscreen (orientation / window / browser) but has no Overlay chrome.
- `PlayerScrubberSlider` takes `required double value` (0.0–1.0). There is **no** `controller` argument. Commit seek in `onChangeEnd`. A press without drag does not seek.
- `VideoPlayer.topBarActions` is merged after `actions` (legacy extra actions). Prefer `actions`.
- `skipSecondType` on `VideoPlayer` is copied to the controller in `initState` and when the widget updates.
- Default chrome auto-hides after `autoHideDelay` (3s) only while playing and not buffering. `Duration.zero` disables auto-hide. Buffering and `completed` keep chrome visible.
- Close control: if fullscreen, `exitFullscreen()`; else `onClose` or `Navigator.maybePop()`.
- Gestures run when fullscreen and **not Web** (Android / iOS / macOS / Windows / Linux). Horizontal drag (past 48px) seeks; left 40% vertical = brightness; right 40% vertical = volume; tap toggles chrome.
- Keyboard runs when `VideoPlayer` is focused on Web or desktop (macOS / Windows / Linux), fullscreen or inline: Space play/pause, arrows seek / volume ±0.05, Escape exits fullscreen only if already fullscreen.
- Built-in speed menu values: `0.5, 1.0, 1.25, 1.5, 2.0`. That list is UI-only; `setSpeed` accepts any double.
- Slot builders receive `VideoPlayerSlotContext` (`controller`, `theme`, `showControls`, `hideControls`).
- Use `SignalBuilder` for custom chrome that reads controller signals.

## Example — full chrome

```dart
VideoPlayer(
  controller: controller,
  fill: true,
  onClose: () => Navigator.pop(context),
  title: const Text('Title'),
  skipSecondType: SkipSecondType.second10,
)
```

## Example — custom surface + scrubber

```dart
Column(
  children: [
    Expanded(child: CorePlayer(controller: controller)),
    SignalBuilder(
      builder: (context) {
        final d = controller.duration.value;
        final p = controller.position.value;
        final progress = d.inMilliseconds == 0
            ? 0.0
            : p.inMilliseconds / d.inMilliseconds;
        return PlayerScrubberSlider(
          value: progress.clamp(0.0, 1.0),
          onChangeEnd: (v) {
            controller.seek(
              Duration(milliseconds: (d.inMilliseconds * v).round()),
            );
          },
        );
      },
    ),
  ],
)
```
