import 'package:flutter/painting.dart';

import '../data/enums/cast_state.dart';
import '../pigeon/player_api.g.dart';
import 'player_event.dart';

/// 将 Pigeon 强类型事件载荷 [PlayerEventData] 解码为领域层 [PlayerEvent] 的工具类。
///
/// Decodes strongly-typed Pigeon [PlayerEventData] payloads into [PlayerEvent].
abstract final class PlayerEventDecoder {
  /// 解析单条 Pigeon [PlayerEventData]；载荷字段不完整时安全返回 `null`。
  ///
  /// Decodes a Pigeon [PlayerEventData] into a [PlayerEvent], returning `null`
  /// when required payload fields are missing.
  ///
  /// - [data]：来自宿主桥接的原始 Pigeon 事件数据。Raw Pigeon event payload.
  ///
  /// 返回值 / Returns：解码后的 [PlayerEvent]，或字段缺失时返回 `null`。
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
