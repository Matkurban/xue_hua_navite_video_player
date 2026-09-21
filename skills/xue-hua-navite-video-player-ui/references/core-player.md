# CorePlayer

Barrel-exported surface widget. Extends `SignalWidget` (rebuilds when read signals change).

```dart
class CorePlayer extends SignalWidget {
  const CorePlayer({
    super.key,
    required this.controller,
    this.aspectRatio,
    this.backgroundColor,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final VideoPlayerController controller;
  final double? aspectRatio;
  final Color? backgroundColor;
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;
}
```

## Fields

| Field | Type | Default | Behavior |
|-------|------|---------|----------|
| `controller` | `VideoPlayerController` | required | Session to render. |
| `aspectRatio` | `double?` | `null` | **Not used as a layout constraint.** `CorePlayer` always expands (`Stack` / `Positioned.fill`). When `null`, the build method reads `controller.videoAspectRatio` so size/rotation changes rebuild. When non-null, that watch is skipped. Wrap `CorePlayer` yourself to impose a ratio. |
| `backgroundColor` | `Color?` | `null` → `VideoPlayerTheme.of(context).backgroundColor` | Fill behind the frame / error. |
| `errorBuilder` | `Widget Function(BuildContext, String?)?` | `null` | Shown when `playState == error`. Second arg is `errorMessage.value`. If null, an empty `SizedBox` is shown. |
| `loadingBuilder` | `Widget Function(BuildContext)?` | `null` | Overlay when `playState == loading` **or** `isBuffering`. If null, `SizedBox.shrink()`. |

## Surfaces

| Platform | Widget |
|----------|--------|
| Web | `HtmlElementView` (`kWebPlayerViewType`) |
| Android | `AndroidView` (`kNativePlayerViewType`), hit-test transparent |
| iOS | `UiKitView`, hit-test transparent |
| macOS | `AppKitView`, hit-test transparent |
| Linux / Windows | Flutter `Texture` using `textureId`; reports view size via `controller.setVideoViewSize`; applies `RotatedBox` from `rotationDegrees` |

PlatformView `create` returns `0` — that is not a Flutter texture id. Picture is the registered PlatformView, not `Texture`.

## Fullscreen

`CorePlayer` does not host Overlay chrome. `enterFullscreen()` still changes orientation / window / browser fullscreen.

## Example

```dart
CorePlayer(
  controller: controller,
  backgroundColor: Colors.black,
  loadingBuilder: (context) => const Center(child: CircularProgressIndicator()),
  errorBuilder: (context, message) => Text(message ?? 'Error'),
)
```
