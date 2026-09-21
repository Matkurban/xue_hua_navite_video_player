# VideoPlayer and VideoPlayerSlotContext

Full chrome player. Hosts visual fullscreen via `OverlayPortal` and reparents the in-tree `CorePlayer` with a `GlobalKey` in the same frame so Android PlatformViews are not disposed on enter.

## `VideoPlayerSlotContext`

Passed to every slot builder.

```dart
class VideoPlayerSlotContext {
  const VideoPlayerSlotContext({
    required this.controller,
    required this.theme,
    required this.showControls,
    required this.hideControls,
  });

  final VideoPlayerController controller;
  final VideoPlayerTheme theme;
  final VoidCallback showControls;
  final VoidCallback hideControls;
}
```

| Field | Meaning |
|-------|---------|
| `controller` | Same instance passed to `VideoPlayer`. |
| `theme` | `VideoPlayerTheme.of(context)` at build time. |
| `showControls` | Show chrome; schedules auto-hide when playing and not buffering. |
| `hideControls` | Hide chrome immediately. |

## `VideoPlayer`

```dart
class VideoPlayer extends StatefulWidget {
  const VideoPlayer({
    super.key,
    required this.controller,
    this.aspectRatio,
    this.fill = false,
    this.autoHideDelay = const Duration(seconds: 3),
    this.fadeDuration = const Duration(milliseconds: 250),
    this.initiallyVisible = true,
    this.onClose,
    this.leading,
    this.title,
    this.actions = const <Widget>[],
    this.topBarActions = const <Widget>[],
    this.showAspectRatioMenu = true,
    this.enableFullscreen = true,
    this.errorBuilder,
    this.loadingBuilder,
    this.topBarBuilder,
    this.centerControlsBuilder,
    this.bottomScrubberBuilder,
    this.extraOverlayBuilder,
    this.skipSecondType = SkipSecondType.second10,
  });
}
```

### Fields

| Field | Type | Default | Behavior |
|-------|------|---------|----------|
| `controller` | `VideoPlayerController` | required | Must already be constructed; call `initialize()` before or while mounting. |
| `aspectRatio` | `double?` | `null` | When `fill` is false and not fullscreen: layout ratio. If null, uses `videoAspectRatio` but not less than `16/9`. Fullscreen / `fill: true` ignore this and expand. Also forwarded to inner `CorePlayer` (watch flag only). |
| `fill` | `bool` | `false` | Expand to parent. Overlay fullscreen body always uses fill. |
| `autoHideDelay` | `Duration` | 3 seconds | Auto-hide while playing and not buffering. `Duration.zero` disables. |
| `fadeDuration` | `Duration` | 250 ms | Chrome `AnimatedSwitcher` duration. |
| `initiallyVisible` | `bool` | `true` | Initial chrome visibility. |
| `onClose` | `VoidCallback?` | `null` | Called by the default leading control when **not** fullscreen. If null, `Navigator.maybePop`. When fullscreen, close calls `exitFullscreen()` instead. |
| `leading` | `Widget?` | `null` | Top-bar leading; default is a close button. |
| `title` | `Widget?` | `null` | Centered top-bar title. |
| `actions` | `List<Widget>` | `[]` | Trailing widgets. Aspect-ratio menu is appended when `showAspectRatioMenu`. |
| `topBarActions` | `List<Widget>` | `[]` | Legacy extra trailing widgets, merged **after** `actions`. |
| `showAspectRatioMenu` | `bool` | `true` | Adds fit/fill/stretch menu (labels 适应 / 铺满 / 拉伸). |
| `enableFullscreen` | `bool` | `true` | Shows the fullscreen icon on the default bottom bar. Overlay still reacts if `isFullscreen` becomes true. |
| `errorBuilder` | `Widget Function(BuildContext, String?)?` | `null` | Forwarded to `CorePlayer`. |
| `loadingBuilder` | `Widget Function(BuildContext)?` | `null` | Forwarded to `CorePlayer`. |
| `topBarBuilder` | `Widget Function(BuildContext, VideoPlayerSlotContext)?` | `null` | Replaces default top bar. |
| `centerControlsBuilder` | same | `null` | Replaces center skip / play / skip. |
| `bottomScrubberBuilder` | same | `null` | Replaces mute, times, scrubber, speed menu, fullscreen. |
| `extraOverlayBuilder` | same | `null` | Extra `Positioned.fill` above chrome. |
| `skipSecondType` | `SkipSecondType` | `second10` | Written to `controller.setSkipSecondType` on init and when this field changes. |

### Runtime behavior

- Copies `skipSecondType` onto the controller in `initState` / `didUpdateWidget`.
- While playing and not buffering, schedules auto-hide. Buffering or `completed` shows chrome and does not auto-hide.
- Fullscreen: show OverlayPortal first, then suppress the inline body so the `GlobalKey` surface moves in one frame. Exit un-suppresses before hide.
- If there is no `Overlay` ancestor, OverlayPortal cannot show; platform fullscreen may still apply.
- Desktop/Web: wraps in `Focus` (`autofocus` when fullscreen). Keyboard: Space, arrows, Escape (see SKILL.md).
- Gestures: `PlayerGestureLayer` when `isFullscreen && !kIsWeb`. Otherwise tap toggles chrome (and requests focus on desktop).
- Default bottom scrubber commits `controller.seek` in `onChangeEnd` from the slider value × duration. Speed menu: `0.5, 1.0, 1.25, 1.5, 2.0`.

### Example — slot replacement

```dart
VideoPlayer(
  controller: controller,
  bottomScrubberBuilder: (context, slot) {
    return SignalBuilder(
      builder: (context) {
        final d = slot.controller.duration.value.inMilliseconds;
        final p = slot.controller.position.value.inMilliseconds;
        final v = d == 0 ? 0.0 : p / d;
        return PlayerScrubberSlider(
          value: v.clamp(0.0, 1.0),
          onChangeEnd: (value) {
            slot.controller.seek(Duration(milliseconds: (d * value).round()));
            slot.showControls();
          },
        );
      },
    );
  },
);
```
