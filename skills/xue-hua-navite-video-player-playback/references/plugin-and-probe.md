# XueHuaNaviteVideoPlayer, VideoCoverFrame, NaviteFile

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

### `Future<void> initialize({VideoCacheConfig? cacheConfig})`

Idempotent binding helper:

- Ensures `WidgetsFlutterBinding.ensureInitialized()` and sets `isInitialized`.
- When `cacheConfig` is provided, applies it via `configureCache(cacheConfig)` (even if already initialized).
- Does **not** create the native player session. That is `VideoPlayerController.initialize()`.

### Media cache APIs (`VideoCacheConfig`)

On-disk media caching is enabled by default (`maxCacheBytes = 512 * 1024 * 1024`, `maxSingleFileBytes = 256 * 1024 * 1024`).

```dart
class VideoCacheConfig {
  const VideoCacheConfig({
    this.enabled = true,
    this.maxCacheBytes = 512 * 1024 * 1024,
    this.maxSingleFileBytes = 256 * 1024 * 1024,
    this.cacheDirectory,
    this.cacheKeyBuilder,
  });
}
```

Methods on `XueHuaNaviteVideoPlayer.instance`:

- `VideoCacheConfig get cacheConfig`
- `Future<void> configureCache(VideoCacheConfig config)`
- `Future<void> precache(VideoSource source, {int? preloadBytes})` — preloads head bytes (`preloadBytes`) or the full file (`preloadBytes == null`) for `NetworkVideoSource`.
- `Future<void> cancelPrecache(VideoSource source)`
- `Future<bool> isCached(VideoSource source)` — `true` when 100% cached on disk (or local/asset).
- `Future<int> getCacheSize()` — total disk cache bytes across complete files and sparse `.part` segments.
- `Future<void> removeCache(VideoSource source)`
- `Future<void> clearCache()` — clears unpinned cache entries while preserving any entry currently pinned by active playback.

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

| Parameter       | Default  | Rules                                                                                                        |
| --------------- | -------- | ------------------------------------------------------------------------------------------------------------ |
| `source`        | required | Resolved with `resolveToNativeUrl()`.                                                                        |
| `count`         | `5`      | Must be `> 0` (`assert`). Native is asked for `count` frames from `(count * 3).clamp(count, 30)` candidates. |
| `minBrightness` | `0.08`   | Filter threshold sent to native.                                                                             |
| `outputDir`     | `null`   | **Web:** ignored (empty string). **Native:** `outputDir ??` plugin cover cache dir.                          |

Behavior:

- Channel timeout **60 seconds**. `TimeoutException` → empty list (not thrown).
- Other channel failures throw (not swallowed except timeout).
- Null channel result → empty list.
- Frames with missing/empty `path` are dropped.
- Remaining frames sorted by `brightness` **descending**.
- Each frame image is PNG `NaviteFile`. `uri` is the cross-platform id (`file://` on native, a data or blob URL on web). The local file path is `NaviteFile.path`.

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

  final NaviteFile image;
  final Duration position;
  final double brightness;
}
```

| Field        | Type         | Meaning                                                                                                    |
| ------------ | ------------ | ---------------------------------------------------------------------------------------------------------- |
| `image`      | `NaviteFile` | Cover PNG. `uri` is `file://` on native and a data or blob URL on web. Local file path: `NaviteFile.path`. |
| `position`   | `Duration`   | Timestamp in the video.                                                                                    |
| `brightness` | `double`     | Average brightness 0.0–1.0 (clamped when parsed from native).                                              |

`toString()` includes position, brightness (3 decimals), and `image.uri`. No `copyWith` / `==` override.

## `NaviteFile`

Built-in cross-platform file representation exported from `package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart` (no `cross_file` dependency needed).

```dart
@immutable
class NaviteFile {
  final String path;
  final String uri;
  final String name;
  final String mimeType;

  const NaviteFile({
    required this.path,
    required this.uri,
    required this.name,
    this.mimeType = 'image/png',
    Uint8List? bytes,
  });

  factory NaviteFile.fromLocation(String location, {String? name, String mimeType = 'image/png'});
  factory NaviteFile.fromBytes(Uint8List bytes, {String name = 'snapshot.png', String mimeType = 'image/png', String? path});

  Future<Uint8List> readAsBytes();
  Future<int> length();
  Future<void> saveTo(String targetPath);
}
```

- `uri` is the cross-platform identifier (`file://` on native, `data:` or `blob:` URL on Web).
- `path` is the local filesystem path on native, or the URL on Web.
- `name` is the synchronous file name (for example `snapshot-1700000000000.png`).
- `mimeType` defaults to `'image/png'`.
- `readAsBytes()`, `length()`, and `saveTo(targetPath)` provide unified byte reading and saving.

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
