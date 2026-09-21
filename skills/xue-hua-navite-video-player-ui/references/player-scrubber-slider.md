# PlayerScrubberSlider

Barrel-exported scrubber. **There is no `controller` parameter.** Pass a 0.0–1.0 `value` and commit seek in `onChangeEnd`.

```dart
class PlayerScrubberSlider extends StatefulWidget {
  const PlayerScrubberSlider({
    super.key,
    required this.value,
    this.bufferedValue = 0.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.trackHeight,
    this.activeTrackHeight,
    this.activeColor,
    this.bufferedColor,
    this.inactiveColor,
    this.thumbColor,
    this.thumbShadowColor,
    this.thumbRadius,
    this.activeThumbRadius,
    this.showThumb = true,
  });
}
```

## Fields

| Field | Type | Default | Behavior |
|-------|------|---------|----------|
| `value` | `double` | required | Played fraction 0.0–1.0. NaN treated as 0. |
| `bufferedValue` | `double` | `0.0` | Buffered fraction. Painted clamped to `[value, 1.0]`. |
| `onChanged` | `ValueChanged<double>?` | `null` | Continuous updates while dragging. |
| `onChangeStart` | `ValueChanged<double>?` | `null` | Press-down. Argument is the current `value` (thumb does not jump yet). |
| `onChangeEnd` | `ValueChanged<double>?` | `null` | Release. If the pointer **moved**, argument is the drag value. If press without drag, argument is the original `value` (no seek). Always invoked on end/cancel so callers can resume auto-hide. |
| `trackHeight` | `double?` | theme `scrubberTrackHeight` | Rest track thickness. |
| `activeTrackHeight` | `double?` | theme `scrubberActiveTrackHeight` | Thickness while pressing. |
| `activeColor` | `Color?` | theme `scrubberActiveColor` | Played fill. |
| `bufferedColor` | `Color?` | theme `scrubberBufferedColor` | Buffered fill. |
| `inactiveColor` | `Color?` | theme `scrubberInactiveColor` | Background track. |
| `thumbColor` | `Color?` | theme `scrubberThumbColor` | Thumb fill. |
| `thumbShadowColor` | `Color?` | theme `scrubberThumbShadowColor` | Glow under thumb. |
| `thumbRadius` | `double?` | theme `scrubberThumbRadius` | Rest radius. |
| `activeThumbRadius` | `double?` | theme `scrubberActiveThumbRadius` | Pressed radius. |
| `showThumb` | `bool` | `true` | Draw the thumb dot. |

## Interaction

- Press-down enlarges the track/thumb but does **not** move the thumb or seek.
- Horizontal drag updates `onChanged`.
- Seek only when the user actually moved, via `onChangeEnd`.
- Tap without drag: `onChangeEnd` with the original value (cancel).

## Correct wiring

```dart
SignalBuilder(
  builder: (context) {
    final duration = controller.duration.value;
    final position = controller.position.value;
    final hasDuration = duration.inMilliseconds > 0;
    final progress = hasDuration
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return PlayerScrubberSlider(
      value: progress,
      onChangeEnd: hasDuration
          ? (v) {
              controller.seek(
                Duration(milliseconds: (duration.inMilliseconds * v).round()),
              );
            }
          : null,
    );
  },
);
```

Do not write `PlayerScrubberSlider(controller: controller)` — that constructor does not exist.
