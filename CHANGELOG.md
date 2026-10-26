## 2.6.5

- Tests / example: replace deprecated `package:flutter/material.dart` imports in integration tests with `material_ui` so `flutter analyze` is clean on Flutter 3.50+.
- Tests / example: resolve local `test.mp4` fixture and screenshot directories on Windows as well as Linux; example playlist auto-detects the Windows plugin-tree fixture for fast EOS UI coverage.
- Verified on Windows desktop: `flutter analyze` clean, unit tests, `plugin_integration_test`, and `example_ui_test` (list → open, play/pause, keyboard, scrub → completed/replay, open another).

## 2.6.4

- Example: support local file playlist entries (`playFile` vs `playNetwork`) and auto-prepend `/workspace/test.mp4` when present for Linux/CI UI EOS coverage.
- Example + plugin UI: add stable `ValueKey`s for home/player pages, demo items, play/pause, replay, and scrubber so `integration_test` can drive real UI flows under Xvfb.
- Add `example/integration_test/example_ui_test.dart` covering list → open, play/pause, keyboard shortcuts, scrub near end → completed/replay, and opening another item.
- Tests: clear `HttpOverrides` for `LocalCastHttpServer` range serving; extra `pump` for cast-button SignalBuilder rebuild in widget tests.

## 2.6.3

- Fix (Windows): define `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` so MSVC 14.5x / VS 18 can compile C++/WinRT casting code (STL1011 experimental coroutine hard-error).

## 2.6.2

- Fix (Windows): replace invalid `CastingConnectionState::Reconnecting` with `Connecting` so MSVC builds succeed (WinRT casting enum has no `Reconnecting` member).

## 2.6.1

- Fix (Windows): update the pinned shinchiro/mpv-winbuild-cmake libmpv SDK download from pruned tag `20260814` to `20261021` (`mpv-dev-x86_64` / `mpv-dev-aarch64`), restoring Windows builds that failed with HTTP 404 on `file(DOWNLOAD)`.

## 2.6.0

- **Remove `cross_file` Dependency & Introduce `NaviteFile`**:
  - Removed the `cross_file` package dependency to prevent version conflicts (`0.3.x` vs `0.4.x`) across ecosystem plugins.
  - Added built-in cross-platform `NaviteFile` model (`path`, `uri`, `name`, `mimeType`, `readAsBytes()`, `length()`, `saveTo()`), exported directly from the main barrel.
  - **Breaking**: `VideoPlayerController.takeSnapshot()` and `VideoCoverFrame.image` now return `NaviteFile` instead of `XFile` / `FileSystemXFile`.
- Updated `web` dependency constraint to `^1.1.2`.
- Updated `README.md`, `README_ZH.md`, example app, and package `skills/` documentation for `NaviteFile`.

## 2.5.0

- **Material & Cupertino Design Separation**:
  - Added `VideoPlayerDesignStyle` (`material`, `cupertino`, `adaptive`) and `VideoPlayerTheme` presets (`VideoPlayerTheme.material()`, `VideoPlayerTheme.cupertino()`, `VideoPlayerTheme.adaptive()`), plus optional per-instance `VideoPlayer(theme: ...)` override.
  - Material style uses Material 3 `IconButton` / `TextButton.icon` ink ripples, `CircularProgressIndicator`, compact `ListTile` popup menus, and rounded Material `Icons`.
  - Cupertino style uses `CupertinoButton` spring opacity feedback, `CupertinoActivityIndicator`, frosted glass translucent chrome bars and pills (`BackdropFilter` via `backdropBlurSigma`, `barBackgroundColor`, `barBorderRadius`), and Apple SF-style `CupertinoIcons`.
- **Architecture & Modularization**:
  - Split `video_player.dart` and UI chrome into focused, single-responsibility widget files (`PlayerBody`, `PlayerTopBar`, `PlayerCenterControls`, `PlayerBottomScrubber`, `PlayerCastingOverlay`, `PlayerGlassSurface`, `PlayerIconButton`, `PlayerLoadingIndicator`, `PlayerMenuOptionTile`, `VideoPlayerSlotContext`) and eliminated widget-returning helper methods.
  - Modularized `PlaybackSession` (`PlaybackSessionState`), `ChannelPlayerBackend` (`PlayerEventDecoder`), and Web implementation (`WebRemotePlaybackInterop`, `WebRemotePlaybackController`, `WebMediaProbeService`).
- **Bug Fixes & Stability**:
  - Fixed `VideoPlayer` controller hot-swap in `didUpdateWidget` so reactive signal effects rebind cleanly when the `controller` instance changes.
  - Fixed `AnimatedSwitcher` fade transitions in `PlayerBody` by keying visible/hidden children outside `SignalBuilder`, and ensured fullscreen gesture layers react immediately inside the fullscreen overlay.
  - Fixed `PlaybackSession.seek()` while in `PlayState.completed` so seeking away from the end transitions back to `paused`/`playing` instead of resetting to `00:00` on subsequent `play()`.
  - Cleared stale scrubber drag state when switching sources or when media duration resets to zero.
  - Made native asset extraction atomic via temp-file write + rename in `AssetExtractor` to prevent corrupted partial cache files.
  - Hardened `MediaProbe.extractCovers` error handling and normalized negative video rotation angles in `PlayerEventDecoder`.

## 2.4.0

- Add wireless casting: `showCastPicker()`, `stopCasting()`, `CastState`, and a `VideoPlayer` cast button plus status overlay (`showCastButton`, `castingOverlayBuilder`).
- Android uses Google Cast. The device dialog is shown from a normal `FlutterActivity` (AppCompat theme wrapper). Devices without Play services stay `CastState.unavailable` and the button stays hidden. Cast receivers are Chromecast and other Cast devices on the same LAN, not AirPlay.
- iOS and macOS present the system AirPlay picker and play the `AVPlayer` item. Web uses the Remote Playback API, or Safari's AirPlay picker when that is what the browser exposes.
- Windows uses the system Casting device picker. Linux launches GNOME Network Displays when that program is installed; otherwise it shows a native notice. Linux does not stream the current item to a DLNA renderer.
- File and asset sources start an in-process LAN HTTP range server. Android and Windows hand that URL to the receiver. Network URLs are cast directly. A server failure does not fail local playback.
- `reset()` keeps the cast session so a new source can load while still connected. `dispose()` sets `unavailable` and stops the local server.

## 2.3.2

- Fix: a freshly initialized `VideoPlayerController` now stays `PlayState.idle` until a source is opened; native events before the first open are ignored (all platforms).
- Fix (Linux): natural end of stream now emits `completed` (mpv `eof-reached` with `keep-open=yes`), enabling replay UI. Fires once per EOS; re-armed on open/seek.
- Fix (Windows): same mpv `eof-reached` completion fix as Linux (Windows mpv backend also used `keep-open=yes` and never emitted `completed`).
- Fix (iOS/macOS): observe `AVPlayerItemFailedToPlayToEndTime` and report mid-stream playback failures through the `error` event.
- Example: correct demo playlist titles; add a real integration test (init, playback, pause/resume, seek, local file, completion, network).

## 2.3.1

- Pin the Android toolchain to AGP `9.1.0`, Gradle `9.3.1`, and Kotlin `2.4.0` in both the plugin and the example app.
- AGP `9.1.1` is outside the Kotlin `2.4.0` support range (AGP `8.5.2`–`9.1.0`).
- Raise the plugin Gradle wrapper from `8.14.5` to `9.3.1`, and refresh the example app wrapper to the same Gradle `9.3.1`. AGP `9.1` requires Gradle `9.3.1`.

## 2.3.0

- update `com.android.tools.build:gradle` to `9.1.0` version
- this version build need `compileSdk` = `37`
- update example android project version

## 2.2.0

- Adapt snapshots and cover frames to `cross_file` 0.4.0.
- **Breaking**: re-exported `XFile` no longer exposes `path`, `mimeType`, or `saveTo`. Use `uri` as the cross-platform identifier. Native filesystem paths are `FileSystemXFile.path` (now re-exported). `name()` is asynchronous and may be null.
- Raise the macOS deployment target from 10.11 to 10.15 so it matches `cross_file`.
- Document platform minimums: Android API 24, iOS 13, macOS 10.15, Windows 10. Linux and Web have no extra OS floor.

## 2.1.0

- update `material_ui` version to ^1.4.0
- update `cupertino_ui` version to ^1.1.1
- **SDK Constraints**: Bumped minimum Flutter SDK requirement to `>=3.47.0` and Bumped minimum Dart SDK requirement to `>=3.13.0`

## 2.0.3

- Bump `chat_context_menu` to `^4.0.3`.

## 2.0.2

- Ship Dart package skills (`skills/`) so AI coding agents can install official usage guidance with `dart run skills@ get`.
- Document every barrel-exported type and method in skill `references/` (signatures, defaults, errors, and platform behavior).
- Fix README / README_ZH mismatches with the public API: install constraint `^2.0.2`, `PlayerScrubberSlider` constructor (`value` not `controller`), Web asset URLs vs native temp extract, `setVideoViewSize`, plugin `isInitialized` / `dispose()`, `VideoPlayer.topBarActions`, `currentUrl` identity, and non-Web fullscreen gestures.

## 2.0.1

- update package version
- fix android player buffering bugs

## 2.0.0

### Breaking Changes ⚠️

- **Dependency Migration**: Replaced legacy Flutter package imports with `material_ui` and `cupertino_ui` following the Flutter 3.47 package decoupling.
- **SDK Constraints**: Bumped minimum Flutter SDK requirement to `>=3.44.0`.

### Features & Improvements

- **Example App**: Updated the example application code and import paths to align with the new dependencies.
- **Linter & Analysis**: Added build directory exclusions (`build/**`) in `analysis_options.yaml` to optimize static analysis performance.

## 1.3.0

- Desktop fullscreen now enters true window fullscreen (Windows borderless, macOS native space, Linux `gtk_window_fullscreen`) instead of only Overlay + SystemChrome.
- Web fullscreen uses the browser Fullscreen API on the Flutter document. The `<video>` element ignores pointer events so Overlay chrome stays clickable.
- Escape exits fullscreen. OS / browser leaving fullscreen (Esc, swipe out of a macOS space) syncs `isFullscreen` without a second `exit()` call.

## 1.2.2

- Windows: refresh the pinned libmpv SDK download to shinchiro/mpv-winbuild-cmake 20260814, and fetch `mpv-dev-aarch64` when targeting `windows-arm64`.
- Windows: link `dxva2` into the plugin test runner so the example can finish linking.
- Document the first-build libmpv download and manual `MPV_DIR` override.

## 1.2.1

- The Gradle tool version has been downgraded to 8.13.2.

## 1.2.0

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
