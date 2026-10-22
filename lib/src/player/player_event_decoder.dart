import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';

/// Decodes raw event maps from `EventChannel('xue_hua_navite_video_player/player/events')`
/// into strongly-typed [PlayerEvent] instances.
import 'player_event.dart';

abstract final class PlayerEventDecoder {
  static PlayerEvent? decode(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    switch (type) {
      case 'position':
        final ms = _asInt(event['value']);
        if (ms == null) return null;
        return PlayerEvent.position(Duration(milliseconds: ms));
      case 'duration':
        final ms = _asInt(event['value']);
        if (ms == null) return null;
        return PlayerEvent.duration(Duration(milliseconds: ms));
      case 'playing':
        final playing = _asBool(event['value']);
        if (playing == null) return null;
        return PlayerEvent.playing(playing);
      case 'buffering':
        final buffering = _asBool(event['value']);
        if (buffering == null) return null;
        return PlayerEvent.buffering(buffering);
      case 'error':
        final message = event['value']?.toString();
        if (message == null) return null;
        return PlayerEvent.error(message);
      case 'completed':
        return const PlayerEvent.completed();
      case 'videoSize':
        final value = event['value'];
        if (value is! Map) return null;
        final w = (value['width'] as num?)?.toDouble() ?? 0;
        final h = (value['height'] as num?)?.toDouble() ?? 0;
        final rotation = (value['rotationDegrees'] as num?)?.toInt() ?? 0;
        final size = (w > 0 && h > 0) ? Size(w, h) : Size.zero;
        return PlayerEvent.videoSize(size, rotation % 360);
      case 'castState':
        final value = event['value'];
        if (value is Map) {
          final state = CastState.fromWire(value['state']?.toString());
          final rawName = value['deviceName']?.toString();
          final deviceName = (rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : null;
          return PlayerEvent.castState(state, deviceName: deviceName);
        }
        if (value is String) {
          return PlayerEvent.castState(CastState.fromWire(value));
        }
        return null;
      default:
        return null;
    }
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    return null;
  }
}
