# Changelog

## 1.1.0

- Declare full Linux / Web / WASM support: remove `screen_brightness`, stop importing `dart:io` from the default library graph, and load `path_provider` only through `dart.library.io` conditional exports.
- Implement native screen brightness on Android, iOS, macOS, Windows, and Linux (`getBrightness` / `setBrightness`, restored on player dispose). Web remains a no-op.
- Enable fullscreen brightness / volume / seek gestures on desktop (not only mobile). Web assets resolve to Flutter-hosted `assets/` URLs instead of temp-file extraction.

## 1.0.1

- Fix Windows build failure when CMake extracts the bundled libmpv SDK through Flutter's `.plugin_symlinks` path (`Cannot extract through symlink`). Resolve the plugin `windows/` directory to a real path before download/extract.

## 1.0.0

- initialized projects
- Implement features for all platforms
