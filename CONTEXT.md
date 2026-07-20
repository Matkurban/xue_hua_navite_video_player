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
| **Single active session** | Process-wide invariant: one native player behind the global channels. Multiple Dart controllers are not independent parallel players. |

## Implemented architecture

- `PlayerBackend` / `PlayerEvent` / `ChannelPlayerBackend`
- `PlaybackSession` + thin `VideoPlayerController` facade
- `MediaProbe`; plugin singleton delegates probe APIs
- `PlatformPlayerFactory` / `PlatformDetector` removed; `MimeDetector` kept internal (not barrel-exported)
- Plugin `initialize()` is an idempotent binding no-op
- Unused deps removed: `universal_platform`, `plugin_platform_interface`

## Deferred

- **Engine adapter dedup** (iOS↔macOS Swift, linux↔windows mpv): large platform-specific diffs; revisit when native churn hurts locality. See `docs/adr/0001-defer-native-engine-dedup.md`.
- **Multi-instance / texture-scoped players**: not required; document single-session invariant instead.
