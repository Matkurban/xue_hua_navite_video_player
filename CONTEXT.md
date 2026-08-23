# Domain context — xue_hua_navite_video_player

Cross-platform Flutter plugin for native A/V playback (ExoPlayer / AVPlayer / libmpv / HTML5) behind a Dart controller and optional UI.

## Glossary

| Term | Meaning |
|------|---------|
| **VideoSource** | Sealed source model (network / file / asset); resolves to a native URL (assets may extract to a temp file). |
| **PlayState** | High-level playback state exposed to UI (`idle` / `loading` / …). Owned by [PlaybackSession]. |
| **PlayerBackend** | Seam interface for **session transport** only: create/open/play/pause/seek/volume/speed/dispose/takeSnapshot/textureId, plus a typed event stream. Does **not** include media probe. |
| **PlayerEvent** | Sealed transport events: `position`, `duration`, `playing`, `buffering`, `error`, `completed` (pulse), `videoSize(Size, rotationDegrees)`. Unknown wire events are dropped in the adapter. |
| **ChannelPlayerBackend** | Adapter that implements `PlayerBackend` over MethodChannel `…/player` and EventChannel `…/player/events`. |
| **PlaybackSession** | Deep module owning open→ready→playing/paused/stopped/error. Projects `PlayerEvent` into signals. |
| **VideoPlayerController** | Public facade over `PlaybackSession` (stable name for apps / UI). |
| **MediaProbe** | Module for `probeDuration` / `extractCovers` without a live session. Wire methods shared with transport; not part of `PlayerBackend`. |
| **Single active session** | Process-wide invariant: one native player behind the global channels. Multiple Dart controllers are not independent parallel players. `PlaybackSession.initialize()` throws if another native session is already active. |

## Implemented architecture

- `PlayerBackend` / `PlayerEvent` / `ChannelPlayerBackend`
- `PlaybackSession` + thin `VideoPlayerController` facade
- `MediaProbe`; plugin singleton delegates probe APIs
- `PlatformPlayerFactory` / `PlatformDetector` removed; `MimeDetector` kept internal (not barrel-exported)
- Plugin `initialize()` is an idempotent binding no-op
- Unused deps removed: `universal_platform`, `plugin_platform_interface`

## Native contract notes

- **Probe vs playback:** `getDuration` / `extractCovers` share the MethodChannel with transport but do not require `create()`. Do not run heavy probe work concurrently with an active playback session (native engines are process-wide).
- **`timeoutMs`:** Dart `MediaProbe.probeDuration` always applies its own `Future.timeout`. Native implementations should also honor `timeoutMs` (Android Retriever, mpv, AVAsset).
- **PlatformView remount:** iOS/macOS/Android show video via PlatformView. Fullscreen reparents the same widget with a `GlobalKey` in one frame (do not dispose then recreate). Detaching the view unbinds the layer but does **not** pause playback.
- **Desktop / Web fullscreen:** `FullscreenCoordinator` applies OS window fullscreen (Windows / macOS / Linux `setWindowFullscreen`) or the browser Fullscreen API. Overlay chrome is separate and still requires a mounted `VideoPlayer`.
- **Android composition:** default `AndroidView` (TLHC) + Media3 `TextureView`. Do not use `initExpensiveAndroidView`: Hybrid Composition copies every frame and can NativeAlloc-GC ~every 70ms on some OEMs. Fullscreen NPE is avoided by same-frame `GlobalKey` reparent, not by HC.
- **Windows locale:** libmpv requires `LC_NUMERIC=C`. The Windows plugin sets this before `mpv_create` (same as Linux).
- **Mobile lifecycle:** Android requests audio focus via ExoPlayer and pauses on Activity `onStop`. iOS uses `AVAudioSession` category `.playback` and pauses on interruption / background. Desktop and Web do not auto-pause.

## Deferred

- **Engine adapter dedup** (iOS↔macOS Swift, linux↔windows mpv): large platform-specific diffs; revisit when native churn hurts locality. See `docs/adr/0001-defer-native-engine-dedup.md`.
- **Multi-instance / texture-scoped players**: not required; document single-session invariant instead.
