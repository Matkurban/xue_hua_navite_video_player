# XueHuaNaviteVideoPlayer, VideoCoverFrame, XFile

`MediaProbe` is **not** exported. Use the singleton below.

## `XueHuaNaviteVideoPlayer`

```dart
class XueHuaNaviteVideoPlayer {
  XueHuaNaviteVideoPlayer._();
  static XueHuaNaviteVideoPlayer get instance;
  factory XueHuaNaviteVideoPlayer() => instance;
}
```

`XueHuaNaviteVideoPlayer()` and `.instance` are the same singleton.

Probe work shares the player MethodChannel (`xue_hua_navite_video_player/player`) but does **not** call native `create()`. Do not run heavy probe work concurrently with an active playback session (process-wide native engine).

### `bool get isInitialized`

`true` after a successful plugin `initialize()`, `false` after plugin `dispose()` or before the first initialize.

### `Future<void> initialize()`

Idempotent binding helper:

- If already initialized, returns an already-completed future.
- Otherwise calls `WidgetsFlutterBinding.ensureInitialized()` and sets `isInitialized`.
- Does **not** create the native player session. That is `VideoPlayerController.initialize()`.

### `Future<void> dispose()`

Sets `isInitialized` to `false` and clears the in-flight init future. Does **not** dispose `VideoPlayerController` or the native playback session.

### `Future<List<VideoCoverFrame>> extractCoverCandidates`

```dart
Future<List<VideoCoverFrame>> extractCoverCandidates(
  VideoSource source, {
  int count = 5,
  double minBrightness = 0.08,
  String? outputDir,
})
```

Extract non-black cover candidates without starting playback.

| Parameter | Default | Rules |
|-----------|---------|--------|
| `source` | required | Resolved with `resolveToNativeUrl()`. |
| `count` | `5` | Must be `> 0` (`assert`). Native is asked for `count` frames from `(count * 3).clamp(count, 30)` candidates. |
| `minBrightness` | `0.08` | Filter threshold sent to native. |
| `outputDir` | `null` | **Web:** ignored (empty string). **Native:** `outputDir ??` plugin cover cache dir. |

Behavior:

- Channel timeout **60 seconds**. `TimeoutException` → empty list (not thrown).
- Other channel failures throw (not swallowed except timeout).
- Null channel result → empty list.
- Frames with missing/empty `path` are dropped.
- Remaining frames sorted by `brightness` **descending**.
- Each frame image is PNG `XFile`. Native `XFile.path` is a real file; web may be a blob URL.

### `Future<Duration?> getDuration`

```dart
Future<Duration?> getDuration(
  VideoSource source, {
  Duration timeout = const Duration(seconds: 15),
})
```

Probe duration without a playback session.

- Resolves `source` then invokes native `getDuration` with `timeoutMs`.
- Dart always applies `Future.timeout(timeout)` even if native ignores `timeoutMs`.
- Returns `null` when: exception/timeout, null payload, non-numeric payload, or milliseconds `<= 0` (includes live / non-finite duration).
- Success: `Duration(milliseconds: ms)`.

## `VideoCoverFrame`

```dart
@immutable
class VideoCoverFrame {
  const VideoCoverFrame({
    required this.image,
    required this.position,
    required this.brightness,
  });

  final XFile image;
  final Duration position;
  final double brightness;
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `image` | `XFile` | Cover PNG. Native: real path. Web: blob URL. |
| `position` | `Duration` | Timestamp in the video. |
| `brightness` | `double` | Average brightness 0.0–1.0 (clamped when parsed from native). |

`toString()` includes position, brightness (3 decimals), and `image.path`. No `copyWith` / `==` override.

## `XFile`

Re-exported from `package:cross_file/cross_file.dart` (`show XFile`). Dependents do not need a direct `cross_file` dependency for snapshot/cover return types.

## Example

```dart
final frames = await XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,
  minBrightness: 0.08,
);

final duration = await XueHuaNaviteVideoPlayer.instance.getDuration(
  VideoSource.file('/absolute/path/to/movie.mp4'),
  timeout: const Duration(seconds: 15),
);
```
