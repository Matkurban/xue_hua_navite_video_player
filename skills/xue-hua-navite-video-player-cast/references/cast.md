# Cast API

Barrel exports `CastState`. Controller methods and `VideoPlayer` fields below are on the public types. `LocalCastHttpServer` is internal.

## `CastState`

```dart
enum CastState { unavailable, notConnected, connecting, connected, disconnecting }
```

| Value | `wireName` | Meaning |
| ----- | ---------- | ------- |
| `unavailable` | `unavailable` | Native has not reported support, or this environment cannot cast. Default before the first native event, and after `dispose()`. |
| `notConnected` | `notConnected` | Casting is available and playback is local. |
| `connecting` | `connecting` | A device was chosen and the session or remote media is still coming up. |
| `connected` | `connected` | Remote playback is active. |
| `disconnecting` | `disconnecting` | The session is tearing down. |

`String get wireName => name`.

`static CastState fromWire(String? raw)` maps those four connected-family names. Any other string, including `null` and `'unavailable'`, returns `unavailable`.

## Controller

```dart
FlutterSignal<CastState> get castState;       // unavailable
FlutterSignal<String?> get castDeviceName;    // null
FlutterComputed<bool> get isCastSupported;    // castState != unavailable
FlutterComputed<bool> get isCasting;          // connecting || connected

Future<void> showCastPicker();
Future<void> stopCasting();
```

- Both methods return immediately when the controller is disposed.
- `ChannelPlayerBackend` swallows `MissingPluginException` and `PlatformException` from these two calls.
- Cast events are applied even before the first `open` and across `openSource`, unlike play/position events.
- `reset()` does not change `castState` or `castDeviceName`.
- `dispose()` sets `castState` to `unavailable`, `castDeviceName` to null, and stops the internal HTTP server.

`play` / `pause` / `seek` / `setVolume` / `setMuted` / `setSpeed` are unchanged. On Android they hit `activePlayer`, which is `CastPlayer` while a Cast session is available and `ExoPlayer` otherwise.

## Local files

On a file or asset open, Dart calls the internal server `serveLocalFileUrl`. Success yields `http://<lan-ipv4>:<ephemeral>/cast/<token>.<ext>` with HTTP range (`206`). The phone and the receiver must reach that address. One token, one file. Network open calls `stop()` on the server.

| Platform | What the receiver plays |
| -------- | ----------------------- |
| Android | `castUrl` if set, otherwise the playback URL. |
| Windows | Same as Android. |
| iOS, macOS | The `AVPlayer` item URL. `castUrl` is stored and not used as the asset URL. |
| Linux, Web | Playback URL only. Web's server implementation returns null. |

If the server throws or no LAN IPv4 exists, `castUrl` is null and open still proceeds.

## `VideoPlayer`

```dart
final bool showCastButton; // default true
final Widget Function(BuildContext, VideoPlayerSlotContext)? castingOverlayBuilder;
```

- The default top bar builds the button only when `showCastButton && isCastSupported`. A custom `topBarBuilder` replaces that bar, so it must call `showCastPicker` itself. The casting overlay is independent of the top bar.
- `notConnected`: `Icons.cast`, tooltip `投屏`, `onPressed` → `showCastPicker`.
- `connecting` or `disconnecting`: a `CupertinoActivityIndicator` in place of the icon. The button still calls `showCastPicker`.
- `connected`: `Icons.cast_connected`, tooltip `正在投屏`, still `showCastPicker`.
- `isCasting` disables chrome auto-hide and shows controls. A full-size background covers the surface. The overlay is `castingOverlayBuilder` or the default.
- Default overlay copy: `正在连接「name」...` / `正在连接投屏设备...`, or `正在投屏至「name」` / `正在投屏播放`. Actions: `切换设备` → `showCastPicker`, `退出投屏` → `stopCasting`.
- `CorePlayer` does not read these fields.

## Platforms

### Android

Google Cast (`androidx.media3:media3-cast`, `DefaultCastOptionsProvider`). `create` asks `CastContext.getSharedInstance`. Success and no current session → `notConnected`. Failure (no Play services, or Cast init throws) → `unavailable`.

`showCastPicker` uses `CastContext.mergedSelector`. No session → `MediaRouteChooserDialog`. Session available → `MediaRouteControllerDialog`. The activity is wrapped in `ContextThemeWrapper(..., Theme_AppCompat_DayNight_NoActionBar)` so a stock `FlutterActivity` can show the dialog. The plugin manifest already declares the options provider and `androidx.mediarouter.media.MediaTransferReceiver`. The app does not subclass `FlutterFragmentActivity`.

On session available: local `ExoPlayer` pauses, `CastPlayer` becomes active, and the current URL (cast URL preferred) loads at the local position with the previous play/pause and volume. On session lost: local player seeks to the remote position, stays paused, state `notConnected`. Start failure sends `notConnected` and does not set `PlayState.error`.

The dialog lists Cast devices (Chromecast, Cast-enabled displays), not AirPlay and not a generic Miracast picker.

### iOS and macOS

`AVRoutePickerView` (iOS prioritizes video devices). `create` / route changes emit `connected` when `isExternalPlaybackActive`, otherwise `notConnected`. Device name is the AirPlay port name, or `AirPlay`. These platforms do not emit `connecting`.

`stopCasting` pauses, then toggles `allowsExternalPlayback` off and back on so playback returns to the local window at the current time, paused. Opening a new item while external playback is active keeps the player and replaces the item.

### Windows

`create` emits `notConnected`. `showCastPicker` shows `CastingDevicePicker` filtered to video, anchored near the top-right of the root window. Selection emits `connecting` with the device friendly name (fallback `Windows Cast`), pauses libmpv, and loads `castUrl` or the current URL into a WinRT `MediaPlayer` plus `CastingConnection`. Connected / disconnecting follow the connection state. If the window or Casting API is missing, the call returns without a picker.

`stopCasting` disconnects, seeks libmpv to the remote position, pauses, and emits `notConnected`.

### Linux

`create` emits `notConnected`, so the button is shown. `showCastPicker` spawns `gnome-network-displays` when that executable is on `PATH`, emits `connected` with device name `GNOME Network Displays`, and pauses libmpv. Otherwise it shows a modal GTK notice that no UPnP / Miracast receiver was found. There is no device list and no media URL is sent to a renderer.

`stopCasting` pauses libmpv and emits `notConnected`.

### Web

If `HTMLVideoElement.remotePlayback` exists, state starts at `notConnected`. `connecting` / `connect` / `disconnect` use device name `Web Cast`. `watchAvailability` may later set `unavailable` when nothing can receive; a failure of that watch leaves `notConnected` so `prompt()` can still run. `showCastPicker` calls `remote.prompt()`.

Otherwise, if `webkitShowPlaybackTargetPicker` exists, state is `notConnected` and a wireless target emits `connected` with device name `AirPlay`. `showCastPicker` calls that picker.

If neither API exists, state is `unavailable`. `stopCasting` pauses, toggles `disableRemotePlayback`, and emits `notConnected`. If that throws, it falls back to `showCastPicker`. User cancel does not change state. There is no local HTTP cast server on web.
