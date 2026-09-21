# PlayState, SkipSecondType, AspectRatioMode

Barrel-exported enums.

## `PlayState`

```dart
enum PlayState { idle, loading, playing, paused, stopped, completed, error }
```

| Value | Meaning |
|-------|---------|
| `idle` | Initial, and after `reset()`. |
| `loading` | Opening / preparing. |
| `playing` | Playing. |
| `paused` | Paused after ready. Buffering stalls may keep `playing` even if native reports paused. |
| `stopped` | Explicit `stop()` mid-playback. Not the same as end-of-stream. |
| `completed` | Natural end-of-stream after at least one play since open. UI may show replay. `play()` seeks to 0 then plays. |
| `error` | Failure; read `errorMessage`. |

`isBuffering` is a separate signal and can overlay these states.

`isPlaying` is true only when `playState == playing`.

## `SkipSecondType`

```dart
enum SkipSecondType {
  second5(value: 5),
  second10(value: 10),
  second15(value: 15),
  second30(value: 30),
  second45(value: 45),
  second60(value: 60);

  final int value;
  const SkipSecondType({required this.value});
  Duration get duration => Duration(seconds: value);
}
```

- Default on a new controller: `second10`.
- `VideoPlayer.skipSecondType` (widget param, default `second10`) is copied onto the controller in `initState` / `didUpdateWidget`.
- `value` is seconds (`int`). `duration` is `Duration(seconds: value)`.
- Used by `seekForward` / `seekBackward` and by fullscreen seek-gesture scaling.

## `AspectRatioMode`

```dart
enum AspectRatioMode { fit, fill, stretch }
```

| Value | Meaning | Native mapping (conceptually) |
|-------|---------|-------------------------------|
| `fit` | Letterbox / pillarbox, keep ratio. | Default. videoGravity resizeAspect, ExoPlayer FIT, object-fit contain, mpv keepaspect. |
| `fill` | Center-crop to fill. | resizeAspectFill / ZOOM / cover. |
| `stretch` | Ignore ratio, fill. | resize / FILL / fill. |

### `String get wireName => name`

Method-channel value: `'fit'`, `'fill'`, or `'stretch'`.

### `static AspectRatioMode fromWire(String? value)`

| Wire | Result |
|------|--------|
| `'fill'` | `fill` |
| `'stretch'` | `stretch` |
| `'fit'` or anything else (including `null`) | `fit` |

Default on a new controller: `fit`. `initialize()` and each `openSource` send the current mode to native.
