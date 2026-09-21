# VideoSource

Sealed public type. Import from `package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart`.

`VideoSource` describes playable media. Resolve it with `resolveToNativeUrl()` before native open. Controllers call that internally from `openSource`.

## `VideoSource` (sealed)

```dart
@immutable
sealed class VideoSource {
  const VideoSource();
}
```

### Members

- `String get identity` — stable id used for mime sniffing (`currentUrl` is set to this on open).
- `bool get isNetwork` — default `false`. Only `NetworkVideoSource` returns `true`.
- `Future<String> resolveToNativeUrl()` — URL the native player can consume.

### Factories

- `const factory VideoSource.network(String url) = NetworkVideoSource`
- `const factory VideoSource.file(String path) = FileVideoSource`
- `const factory VideoSource.asset(String assetPath, {AssetBundle? bundle}) = AssetVideoSource`

## `NetworkVideoSource`

```dart
class NetworkVideoSource extends VideoSource {
  const NetworkVideoSource(this.url);
  final String url;
}
```

| Member | Behavior |
|--------|----------|
| `url` | Original HTTP(S) URL. |
| `identity` | Same as `url`. |
| `isNetwork` | `true`. |
| `resolveToNativeUrl()` | Returns `url` unchanged. Native player opens it directly. |
| `==` / `hashCode` | Equal when `url` matches. |

## `FileVideoSource`

```dart
class FileVideoSource extends VideoSource {
  const FileVideoSource(this.path);
  final String path;
}
```

| Member | Behavior |
|--------|----------|
| `path` | Absolute filesystem path or `file://` URI. |
| `identity` | If `path` already starts with `file://`, that string; otherwise `'file://$path'`. |
| `isNetwork` | `false` (inherited). |
| `resolveToNativeUrl()` | If `path` starts with `file://`, return it; otherwise `Uri.file(path).toString()`. |
| `==` / `hashCode` | Equal when `path` matches. |

## `AssetVideoSource`

```dart
class AssetVideoSource extends VideoSource {
  const AssetVideoSource(this.assetPath, {this.bundle});
  final String assetPath;
  final AssetBundle? bundle;
}
```

Declare the asset in the **app** `pubspec.yaml` (`flutter.assets`). `assetPath` is the same key `rootBundle.load(...)` uses.

| Member | Behavior |
|--------|----------|
| `assetPath` | Flutter asset key. |
| `bundle` | Optional bundle; extractor defaults to `rootBundle` when null. |
| `identity` | `'asset://$assetPath'`. |
| `isNetwork` | `false`. |
| `resolveToNativeUrl()` | **Web / WASM (`kIsWeb`):** `'assets/$key'` where a leading `/` on `assetPath` is stripped. **Native:** extract to a temp file, then `Uri.file(path).toString()`. |
| `==` / `hashCode` | Equal when `assetPath` matches and `bundle` is `identical`. |

Web does **not** extract a temp file. Native does, on first use.

## Usage

```dart
final network = VideoSource.network('https://example.com/a.mp4');
final file = VideoSource.file('/absolute/path/to/movie.mp4');
final asset = VideoSource.asset('assets/videos/intro.mp4');

final nativeUrl = await network.resolveToNativeUrl();
await controller.playSource(file);
```
