# Changelog

## 1.1.1

- Fix Android crash when entering fullscreen: `NullPointerException` in Flutter's `SurfaceProducer.getWidth()` during Virtual Display resize after the PlatformView was disposed.
- Reparent the player surface with a `GlobalKey` in the same frame (`OverlayPortal.show` before suppressing inline; un-suppress before hide). Set `isFullscreen` before applying orientation.
- Android uses default `AndroidView` plus Media3 `TextureView` (not expensive Hybrid Composition, which caused NativeAlloc GC about every 70ms while playing).
- Stabilize the Dart session: listen to native events before `create()`, ignore stale events after a superseded `open`, and leave `loading` for live/audio-only streams (zero duration, metadata, or a short ready fallback).
- Enforce the process-wide single native session in `PlaybackSession.initialize()`.
- `MediaProbe` now times out on the Dart side even if native ignores `timeoutMs`.
- Android: honor `getDuration` timeout, shut down worker threads on engine detach, report video rotation, return `NO_PLAYER` when the session is missing, PixelCopy snapshots, ExoPlayer audio focus, pause on Activity `onStop`, and trim cover-cache files.
- iOS/macOS: guard non-finite duration, dispose on engine detach, async-load cover duration, snapshot generation tokens, detach the player layer when the PlatformView is destroyed (without pausing). iOS configures `AVAudioSession` and pauses on interruption/background. macOS no longer silently retries a failed `open`.
- Windows: set `LC_NUMERIC=C` for libmpv, join probe workers instead of detaching them, return a 1×1 texture placeholder, and fail `create` when mpv init fails.
- Linux: run `extractCovers` / `getDuration` off the GTK thread; fail snapshot temp-file creation instead of using an unexpanded `XXXXXX` path.
- Web: set `crossOrigin` on the playback element, surface autoplay / `MediaError` details, and skip tainted cover frames instead of aborting the whole probe.

## 1.1.0

- Declare full Linux / Web / WASM support: remove `screen_brightness`, stop importing `dart:io` from the default library graph, and load `path_provider` only through `dart.library.io` conditional exports.
- Implement native screen brightness on Android, iOS, macOS, Windows, and Linux (`getBrightness` / `setBrightness`, restored on player dispose). Web remains a no-op.
- Enable fullscreen brightness / volume / seek gestures on desktop (not only mobile). Web assets resolve to Flutter-hosted `assets/` URLs instead of temp-file extraction.

## 1.0.1

- Fix Windows build failure when CMake extracts the bundled libmpv SDK through Flutter's `.plugin_symlinks` path (`Cannot extract through symlink`). Resolve the plugin `windows/` directory to a real path before download/extract.

## 1.0.0

- initialized projects
- Implement features for all platforms
