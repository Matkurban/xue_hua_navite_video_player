import 'package:flutter/painting.dart';

/// Typed transport events from [PlayerBackend].
///
/// Wire format remains MethodChannel `{event, value}` maps; encoding lives in
/// [ChannelPlayerBackend].
sealed class PlayerEvent {
  const PlayerEvent();

  const factory PlayerEvent.position(Duration position) = PlayerPositionEvent;

  const factory PlayerEvent.duration(Duration duration) = PlayerDurationEvent;

  const factory PlayerEvent.playing(bool playing) = PlayerPlayingEvent;

  const factory PlayerEvent.buffering(bool buffering) = PlayerBufferingEvent;

  const factory PlayerEvent.error(String message) = PlayerErrorEvent;

  /// Pulse when the native player reports completion; subscribers may count.
  const factory PlayerEvent.completed() = PlayerCompletedEvent;

  const factory PlayerEvent.videoSize(Size size, int rotationDegrees) = PlayerVideoSizeEvent;
}

final class PlayerPositionEvent extends PlayerEvent {
  const PlayerPositionEvent(this.position);
  final Duration position;
}

final class PlayerDurationEvent extends PlayerEvent {
  const PlayerDurationEvent(this.duration);
  final Duration duration;
}

final class PlayerPlayingEvent extends PlayerEvent {
  const PlayerPlayingEvent(this.playing);
  final bool playing;
}

final class PlayerBufferingEvent extends PlayerEvent {
  const PlayerBufferingEvent(this.buffering);
  final bool buffering;
}

final class PlayerErrorEvent extends PlayerEvent {
  const PlayerErrorEvent(this.message);
  final String message;
}

final class PlayerCompletedEvent extends PlayerEvent {
  const PlayerCompletedEvent();
}

final class PlayerVideoSizeEvent extends PlayerEvent {
  const PlayerVideoSizeEvent(this.size, this.rotationDegrees);
  final Size size;
  final int rotationDegrees;
}
