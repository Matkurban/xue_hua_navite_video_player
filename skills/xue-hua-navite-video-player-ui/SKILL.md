---
name: xue-hua-navite-video-player-ui
description: >-
  Build player UI with xue_hua_navite_video_player. Use when creating
  VideoPlayer, CorePlayer, VideoPlayerTheme, PlayerScrubberSlider,
  VideoPlayerSlotContext, fullscreen Overlay chrome, gestures, keyboard
  shortcuts, showCastButton, or castingOverlayBuilder. Cast session behavior
  is xue-hua-navite-video-player-cast. Read references/ for exact widget
  fields — PlayerScrubberSlider has no controller parameter.
---

# UI — xue_hua_navite_video_player

Import the barrel only. `PlayerGestureLayer`, `PlayerMenuButton`, and `handlePlayerKeyEvent` are **not** exported; `VideoPlayer` already uses them.

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

Cast button and overlay behavior: [xue-hua-navite-video-player-cast](../xue-hua-navite-video-player-cast/SKILL.md).

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
- `VideoPlayer.showCastButton` defaults to `true`. The icon is still omitted when `isCastSupported` is false. `castingOverlayBuilder` replaces the default casting overlay. `CorePlayer` has neither.
- `VideoPlayer.topBarActions` is merged after `actions` (legacy extra actions). Prefer `actions`.
- `skipSecondType` on `VideoPlayer` is copied to the controller in `initState` and when the widget updates.
- Default chrome auto-hides after `autoHideDelay` (3s) only while playing, not buffering, and not casting. `Duration.zero` disables auto-hide. Buffering, `completed`, and `isCasting` keep chrome visible.
- Close control: if fullscreen, `exitFullscreen()` (ignored while `isLocked`); else `onClose` or `Navigator.maybePop()`.
- Gestures run when fullscreen and unlocked (`VideoPlayer` mounted). Horizontal drag (past 48px) seeks; in fullscreen landscape (`width > height`), vertical drag inside the left/right width × centered height zones (defaults: `0.3` left, `0.3` right, `0.7` height) adjusts brightness and volume (default left brightness / right volume; swap via `verticalGestureMapping`, customize `0.0..1.0` ratios via `verticalGestureLeftWidthRatio`, `verticalGestureRightWidthRatio` with `left + right <= 1.0`, and `verticalGestureHeightRatio`, or disable via `enableFullscreenVerticalGestures`; brightness swipe is skipped on Web). Default `PlayerGestureHud` adapts to Material and Cupertino themes; replace with `gestureHudBuilder`.
- Screen lock & bidirectional landscape: `VideoPlayer` shows a fullscreen lock/unlock button (`showLockButton`, `lockButtonPosition` left/right, customizable via `lockButtonBuilder`) wired to `controller.toggleLocked()`. Locking fixes the current orientation via `SystemChrome.setPreferredOrientations`, hides chrome, and blocks drag gestures while keeping tap-to-toggle unlock access; unlocking restores gravity-driven bidirectional landscape (`landscapeLeft` / `landscapeRight`).
- Keyboard runs when `VideoPlayer` is focused on Web or desktop (macOS / Windows / Linux), fullscreen or inline: Space play/pause, arrows seek / volume ±0.05, Escape unlocks when locked or exits fullscreen when already fullscreen.
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
