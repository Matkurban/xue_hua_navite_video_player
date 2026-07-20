# Changelog

## 1.0.0

### Breaking changes

- Removed the stream-while-download cache stack (local HTTP proxy, chunk download workers, ToStore cache index).
- Removed playback history / resume-position persistence.
- Removed `CacheConfig`, `cachedProgress` / `downloadedBytes` / `isFullyCached`, and related public exports.
- Network playback now opens the original URL directly via the native player.

### Features

- **6-platform support**: Android (ExoPlayer), iOS (AVPlayer), macOS (AVPlayer), Linux (libmpv), Windows (libmpv), Web (HTML5)
- **Player controls**: play, pause, seek, volume, speed
- **`playNetwork` / `playFile` / `playAsset` / `playSource`** for explicit per-source playback
- **Cover frame extraction** and duration probing without starting playback
- **Snapshot capture** of the current frame as PNG `XFile`
- **Built-in UI** with theme support (`VideoPlayerTheme`)
