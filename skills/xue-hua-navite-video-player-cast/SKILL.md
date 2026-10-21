---
name: xue-hua-navite-video-player-cast
description: >-
  Cast with xue_hua_navite_video_player (投屏). Use when calling showCastPicker,
  stopCasting, CastState, isCastSupported, isCasting, castDeviceName, or
  VideoPlayer showCastButton / castingOverlayBuilder. Covers AirPlay, Google
  Cast, Windows Casting, Web Remote Playback, and local-file LAN streaming.
  Read references/cast.md before stating platform behavior.
---

# Cast — xue_hua_navite_video_player

Import the barrel only:

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

Setup: [xue-hua-navite-video-player-setup](../xue-hua-navite-video-player-setup/SKILL.md).
Transport: [xue-hua-navite-video-player-playback](../xue-hua-navite-video-player-playback/SKILL.md).
Widgets: [xue-hua-navite-video-player-ui](../xue-hua-navite-video-player-ui/SKILL.md).

Before writing cast code, read [references/cast.md](references/cast.md).

`LocalCastHttpServer`, `PlaybackSession`, and `PlayerBackend` are not barrel-exported. Apps do not construct the HTTP server.

## Guidelines

- `showCastPicker()` presents the platform picker and completes without throwing when the picker cannot be shown (disposed controller, missing plugin, or native failure). `stopCasting()` asks native to end the session.
- `castState` starts at `CastState.unavailable` and changes only when native sends a cast event. `isCastSupported` is `castState != unavailable`. `isCasting` is `connecting` or `connected`.
- `castDeviceName` is cleared on `notConnected` and `unavailable`. Other states keep the previous name when the event omits `deviceName`.
- `VideoPlayer.showCastButton` defaults to `true` and the default top bar still renders the icon only when `isCastSupported` is true. A custom `topBarBuilder` replaces that bar. `CorePlayer` has no cast button and no overlay.
- While `isCasting`, default chrome does not auto-hide, the picture is covered with the theme background, and the default overlay shows 切换设备 (`showCastPicker`) and 退出投屏 (`stopCasting`). Those strings are fixed Chinese. Replace the overlay with `castingOverlayBuilder`.
- `play` / `pause` / `seek` / `setVolume` / `setSpeed` stay the same methods while casting. Native forwards them to the remote player where that platform implements remote transport.
- `reset()` does not clear `castState` or `castDeviceName`. `openSource` calls `reset()`, so changing media while connected keeps the session. `dispose()` sets `unavailable`, clears the device name, and stops the local HTTP server.
- File and asset opens try to start that server and pass a LAN `http://` URL as `castUrl`. Failure is ignored and playback continues with `castUrl == null`. Network opens stop the server and cast the network URL.
- Android and Windows receivers load `castUrl` when it is set, otherwise the playback URL. iOS and macOS AirPlay play the `AVPlayer` item (the file or network URL) and do not switch to `castUrl`. Linux and Web ignore `castUrl`.
- Android lists Google Cast devices and needs Play services plus the same LAN. An AirPlay-only TV is absent from that dialog. The host stays `FlutterActivity`; the plugin already merges the Cast options provider and `MediaTransferReceiver`.
- Do not tell the user Linux streams the open item to a DLNA renderer. Linux launches `gnome-network-displays` when that binary exists, and otherwise shows a notice dialog.

## Example — button the widget already provides

```dart
VideoPlayer(
  controller: controller,
  fill: true,
  showCastButton: true,
)
```

## Example — custom cast action

```dart
SignalBuilder(
  builder: (context) {
    if (!controller.isCastSupported.value) return const SizedBox.shrink();
    final casting = controller.isCasting.value;
    return IconButton(
      onPressed: casting ? controller.stopCasting : controller.showCastPicker,
      icon: Icon(casting ? Icons.cast_connected : Icons.cast),
    );
  },
);
```
