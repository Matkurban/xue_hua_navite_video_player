# VideoPlayerController

Public facade over the (unexported) `PlaybackSession`. Import from the barrel only.

Constructor injection types `PlayerBackend`, `FullscreenCoordinator`, and `BrightnessController` are **not exported**. In apps, use the default constructor.

```dart
VideoPlayerController({
  PlayerBackend? backend,           // not exported — tests only
  FullscreenCoordinator? fullscreen, // not exported — tests only
  BrightnessController? brightness,  // not exported — tests only
});
```

Call `initialize()` once before transport methods. After `dispose()`, create a new instance.

Signals are `FlutterSignal` / `FlutterComputed` from `signals_flutter`. Read `.value` inside `SignalBuilder` or `effect`.

## Reactive signals

Defaults after construction (before open):

| Getter | Type | Default | Meaning |
|--------|------|---------|---------|
| `playState` | `FlutterSignal<PlayState>` | `PlayState.idle` | High-level state. |
| `position` | `FlutterSignal<Duration>` | `Duration.zero` | Playhead. Ignored until the session is ready. |
| `duration` | `FlutterSignal<Duration>` | `Duration.zero` | Media duration. Zero for live / unknown. |
| `volume` | `FlutterSignal<double>` | `1.0` | 0.0–1.0 after `setVolume`. |
| `speed` | `FlutterSignal<double>` | `1.0` | Playback rate. Not clamped by the API. |
| `isBuffering` | `FlutterSignal<bool>` | `false` | Buffering flag; can overlap other states. |
| `errorMessage` | `FlutterSignal<String?>` | `null` | Set on `PlayState.error`. |
| `currentUrl` | `FlutterSignal<String?>` | `null` | **Source identity** (`url` / `file://…` / `asset://…`), not the extracted native path. |
| `mimeType` | `FlutterSignal<String?>` | `null` | Inferred from identity extension; unknown → `application/octet-stream`. |
| `videoSize` | `FlutterSignal<Size>` | `Size.zero` | Decoded video size. |
| `rotationDegrees` | `FlutterSignal<int>` | `0` | Rotation reported by native. |
| `muted` | `FlutterSignal<bool>` | `false` | Mute flag. |
| `skipSecondType` | `FlutterSignal<SkipSecondType>` | `SkipSecondType.second10` | Step used by `seekForward` / `seekBackward`. |
| `aspectRatioMode` | `FlutterSignal<AspectRatioMode>` | `AspectRatioMode.fit` | Native fit mode. |
| `isFullscreen` | `FlutterSignal<bool>` | `false` | Fullscreen flag (set before the platform host runs). |
| `brightness` | `FlutterSignal<double>` | `1.0` | Screen brightness 0.0–1.0. Refreshed from native in `initialize()` when possible. |
| `textureId` | `FlutterSignal<int?>` | `null` until create | Flutter `Texture` id on Linux/Windows. PlatformView platforms return `0` from native create (not a Texture id). |

## Computed values

| Getter | Type | Formula |
|--------|------|---------|
| `videoAspectRatio` | `FlutterComputed<double>` | If width or height `<= 0`, `16 / 9`. If `rotationDegrees % 360` is `90` or `270`, `height / width`; else `width / height`. |
| `isVideo` | `FlutterComputed<bool>` | `mimeType?.startsWith('video/') ?? false`. |
| `isAudio` | `FlutterComputed<bool>` | `mimeType?.startsWith('audio/') ?? false`. |
| `isPlaying` | `FlutterComputed<bool>` | `playState == PlayState.playing`. |
| `progressPercent` | `FlutterComputed<double>` | `0.0` when duration ms is 0; else `position.inMilliseconds / duration.inMilliseconds` (not clamped). |

## Lifecycle

### `Future<void> initialize()`

Creates the native session and listens to events **before** `create()` so events during create are not lost.

- Throws `StateError('PlaybackSession has been disposed.')` if already disposed.
- For the default channel backend: throws `StateError` if another native `PlaybackSession` is already active. Dispose that controller first.
- On `create()` failure: cancels the event subscription, releases the native-session slot, rethrows.
- After success: sends current `aspectRatioMode` to native; reads current brightness (errors ignored).

### `Future<void> dispose()`

Idempotent. If fullscreen, attempts `exit()` then clears `isFullscreen`. Marks disposed, cancels timers/subscriptions, disposes fullscreen coordinator, disposes native backend, releases the process-wide session slot. The instance cannot be initialized again.

### `void reset()`

Cancels the ready-fallback timer. Clears open-epoch bookkeeping used for readiness. In one `batch()`:

- `playState = idle`
- `position` / `duration` = zero
- `isBuffering = false`
- `errorMessage` / `currentUrl` / `mimeType` = null
- `videoSize = Size.zero`
- `rotationDegrees = 0`

Does **not** change volume, speed, muted, skipSecondType, aspectRatioMode, isFullscreen, brightness. Does **not** dispose the native session. `openSource` calls `reset()` at the start of each open.

## Open and play

All of these no-op if already disposed (except `initialize` / `takeSnapshot`, which throw).

| Method | Signature | Behavior |
|--------|-----------|----------|
| `playNetwork` | `Future<void> playNetwork(String url)` | `openSource(VideoSource.network(url), autoPlay: true)` |
| `openNetwork` | `Future<void> openNetwork(String url)` | Same, `autoPlay: false` |
| `playFile` | `Future<void> playFile(String path)` | `openSource(VideoSource.file(path), autoPlay: true)` |
| `openFile` | `Future<void> openFile(String path)` | `autoPlay: false` |
| `playAsset` | `Future<void> playAsset(String assetPath, {AssetBundle? bundle})` | `VideoSource.asset(assetPath, bundle: bundle)`, auto-play |
| `openAsset` | `Future<void> openAsset(String assetPath, {AssetBundle? bundle})` | Same, no auto-play |
| `playSource` | `Future<void> playSource(VideoSource source)` | `openSource(source, autoPlay: true)` |
| `openSource` | `Future<void> openSource(VideoSource source)` | `autoPlay: false` |

Internal open sequence (`openSource`):

1. Increment open epoch; `reset()`.
2. `currentUrl = source.identity`; `mimeType` from identity extension; `playState = loading`.
3. `mediaUrl = await source.resolveToNativeUrl()`.
4. `_backend.open(mediaUrl)`.
5. Re-apply `setVolume(muted ? 0 : volume)`, `setSpeed(speed)`, `setAspectRatioMode`.
6. If `autoPlay`, `_backend.play()`.
7. On throw: `errorMessage = e.toString()`, `playState = error`.
8. Stale epochs (superseded open) are ignored.

A 3-second ready fallback leaves `loading` if native never reports duration/metadata (live / audio-only).

## Transport

| Method | Signature | Behavior |
|--------|-----------|----------|
| `play` | `Future<void> play()` | If `playState == completed`, seek 0 and set `position` to zero, then native play. |
| `pause` | `Future<void> pause()` | Native pause. |
| `playOrPause` | `Future<void> playOrPause()` | If `isPlaying`, pause; else `play()`. |
| `stop` | `Future<void> stop()` | Native pause, then `playState = stopped` (not `completed`). |
| `seek` | `Future<void> seek(Duration position)` | Native seek with `position.inMilliseconds`. |

## Volume, mute, skip, speed, brightness

| Method | Signature | Behavior |
|--------|-----------|----------|
| `setVolume` | `Future<void> setVolume(double value)` | Clamp `0.0–1.0`, send to native, write `volume`. If clamped `> 0` and muted, unmute. If clamped `== 0`, set muted. |
| `setMuted` | `Future<void> setMuted(bool value)` | Mute: remember previous volume (`> 0` ? current : `1.0`), set muted, native volume 0, `volume = 0`. Unmute: restore remembered volume (or `1.0`). |
| `toggleMuted` | `Future<void> toggleMuted()` | `setMuted(!muted.value)`. |
| `setSkipSecondType` | `void setSkipSecondType(SkipSecondType type)` | Dart-only; writes the signal. |
| `seekForward` | `Future<void> seekForward()` | Seek `position + skipSecondType.duration`, clamped to `[0, duration]` when duration `> 0`. |
| `seekBackward` | `Future<void> seekBackward()` | Same with negative delta. |
| `setSpeed` | `Future<void> setSpeed(double value)` | Native + signal. **Not clamped.** |
| `setBrightness` | `Future<void> setBrightness(double value)` | Clamp `0.0–1.0`, native screen brightness, write signal. Web no-op. |

## Aspect and view size

| Method | Signature | Behavior |
|--------|-----------|----------|
| `setAspectRatioMode` | `Future<void> setAspectRatioMode(AspectRatioMode mode)` | Write signal, send native `mode.wireName` (`fit` / `fill` / `stretch`). |
| `setVideoViewSize` | `Future<void> setVideoViewSize({required double width, required double height, required double devicePixelRatio})` | Returns immediately if width or height `<= 0`. Needed for libmpv panscan vs Flutter view. No-op on PlatformView platforms that size themselves. `CorePlayer` Texture already calls this. |

## Fullscreen

| Method | Signature | Behavior |
|--------|-----------|----------|
| `enterFullscreen` | `Future<void> enterFullscreen()` | No-op if disposed or already fullscreen. Sets `isFullscreen = true` first (so Overlay can reparent), then platform host with `landscapeVideo: videoAspectRatio > 1.0`. |
| `exitFullscreen` | `Future<void> exitFullscreen()` | No-op if disposed or not fullscreen. Sets flag false, restores host. |
| `toggleFullscreen` | `Future<void> toggleFullscreen()` | Exit if fullscreen, else enter. |

Platform host: mobile orientation + immersive UI; desktop window fullscreen; web browser Fullscreen API on the Flutter document (not the `<video>` element). OS/browser leaving fullscreen syncs `isFullscreen` without a second `exit()`.

Visual edge-to-edge Overlay chrome requires a mounted `VideoPlayer` under an `Overlay` ancestor.

## Snapshot

```dart
Future<XFile> takeSnapshot({String? savePath});
```

- Throws `StateError('PlaybackSession has been disposed.')` if disposed.
- Throws `StateError('No media is currently loaded.')` if `currentUrl` is null.
- Returns a PNG `XFile` (barrel re-exports `XFile`). `savePath` optional.
- iOS/macOS: `AVAssetImageGenerator` at current time. Other platforms: native snapshot paths.

## Watch state

```dart
SignalBuilder(
  builder: (context) {
    final state = controller.playState.value;
    final pos = controller.position.value;
    return Text('${state.name} ${pos.inSeconds}s');
  },
);
```
