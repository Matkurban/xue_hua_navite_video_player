import 'package:flutter/painting.dart';

import '../data/enums/cast_state.dart';
import '../pigeon/player_api.g.dart';
import 'player_event.dart';

/// Decodes strongly-typed Pigeon [PlayerEventData] payloads into [PlayerEvent].
abstract final class PlayerEventDecoder {
  static PlayerEvent? fromPigeon(PlayerEventData data) {
    switch (data.kind) {
      case NativePlayerEventType.position:
        final ms = data.intValue;
        if (ms == null) return null;
        return PlayerEvent.position(Duration(milliseconds: ms));
      case NativePlayerEventType.buffered:
        final ms = data.intValue;
        if (ms == null) return null;
        return PlayerEvent.buffered(Duration(milliseconds: ms < 0 ? 0 : ms));
      case NativePlayerEventType.duration:
        final ms = data.intValue;
        if (ms == null) return null;
        return PlayerEvent.duration(Duration(milliseconds: ms));
      case NativePlayerEventType.playing:
        final playing = data.boolValue;
        if (playing == null) return null;
        return PlayerEvent.playing(playing);
      case NativePlayerEventType.buffering:
        final buffering = data.boolValue;
        if (buffering == null) return null;
        return PlayerEvent.buffering(buffering);
      case NativePlayerEventType.error:
        final message = data.message;
        if (message == null) return null;
        return PlayerEvent.error(message);
      case NativePlayerEventType.completed:
        return const PlayerEvent.completed();
      case NativePlayerEventType.videoSize:
        final w = data.width ?? 0;
        final h = data.height ?? 0;
        final rotation = data.rotationDegrees ?? 0;
        final normalizedRotation = ((rotation % 360) + 360) % 360;
        final size = (w > 0 && h > 0) ? Size(w, h) : Size.zero;
        return PlayerEvent.videoSize(size, normalizedRotation);
      case NativePlayerEventType.castState:
        final nativeCastState = data.castState;
        if (nativeCastState == null) return null;
        final rawName = data.castDeviceName?.trim();
        final deviceName = (rawName != null && rawName.isNotEmpty) ? rawName : null;
        return PlayerEvent.castState(_toCastState(nativeCastState), deviceName: deviceName);
    }
  }

  static CastState _toCastState(NativeCastState state) {
    return switch (state) {
      NativeCastState.unavailable => CastState.unavailable,
      NativeCastState.notConnected => CastState.notConnected,
      NativeCastState.connecting => CastState.connecting,
      NativeCastState.connected => CastState.connected,
      NativeCastState.disconnecting => CastState.disconnecting,
    };
  }
}
