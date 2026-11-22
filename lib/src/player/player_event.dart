import 'package:flutter/painting.dart';

import '../data/enums/cast_state.dart';

/// 来自 `PlayerBackend` 的强类型传输层事件基类（由 `PlayerEventDecoder` 解码生成）。
///
/// Sealed base class for typed transport events emitted by `PlayerBackend`.
sealed class PlayerEvent {
  /// 构造播放器传输事件基类。
  ///
  /// Base constructor for sealed [PlayerEvent] subclasses.
  const PlayerEvent();

  /// 创建当前播放进度事件。
  ///
  /// Creates a [PlayerPositionEvent] for [position].
  const factory PlayerEvent.position(Duration position) = PlayerPositionEvent;

  /// 创建已缓冲媒体位置事件。
  ///
  /// Creates a [PlayerBufferedEvent] for [bufferedPosition].
  const factory PlayerEvent.buffered(Duration bufferedPosition) = PlayerBufferedEvent;

  /// 创建媒体总时长事件。
  ///
  /// Creates a [PlayerDurationEvent] for [duration].
  const factory PlayerEvent.duration(Duration duration) = PlayerDurationEvent;

  /// 创建播放/暂停状态事件。
  ///
  /// Creates a [PlayerPlayingEvent] with [playing].
  const factory PlayerEvent.playing(bool playing) = PlayerPlayingEvent;

  /// 创建缓冲中状态事件。
  ///
  /// Creates a [PlayerBufferingEvent] with [buffering].
  const factory PlayerEvent.buffering(bool buffering) = PlayerBufferingEvent;

  /// 创建播放错误事件。
  ///
  /// Creates a [PlayerErrorEvent] with error [message].
  const factory PlayerEvent.error(String message) = PlayerErrorEvent;

  /// 创建媒体自然播完事件。
  ///
  /// Creates a [PlayerCompletedEvent] pulse when native playback reaches end-of-stream.
  const factory PlayerEvent.completed() = PlayerCompletedEvent;

  /// 创建视频分辨率与旋转角度事件。
  ///
  /// Creates a [PlayerVideoSizeEvent] with [size] and [rotationDegrees].
  const factory PlayerEvent.videoSize(Size size, int rotationDegrees) = PlayerVideoSizeEvent;

  /// 创建原生无线投屏状态变更事件。
  ///
  /// Creates a [PlayerCastStateEvent] with [state] and optional [deviceName].
  const factory PlayerEvent.castState(CastState state, {String? deviceName}) = PlayerCastStateEvent;
}

/// 当前播放时间点更新事件。
///
/// Event reporting the current playback position.
final class PlayerPositionEvent extends PlayerEvent {
  /// 创建播放进度事件。
  const PlayerPositionEvent(this.position);

  /// 当前播放时间位置。
  ///
  /// Current playhead position.
  final Duration position;
}

/// 媒体已缓冲进度更新事件。
///
/// Event reporting the buffered media position.
final class PlayerBufferedEvent extends PlayerEvent {
  /// 创建已缓冲位置事件。
  const PlayerBufferedEvent(this.bufferedPosition);

  /// 当前已缓冲到的时间位置。
  ///
  /// Buffered timeline position.
  final Duration bufferedPosition;
}

/// 媒体总时长更新事件。
///
/// Event reporting the total media duration.
final class PlayerDurationEvent extends PlayerEvent {
  /// 创建媒体总时长事件。
  const PlayerDurationEvent(this.duration);

  /// 媒体总时长。
  ///
  /// Total media duration.
  final Duration duration;
}

/// 播放状态（播放中 / 非播放中）更新事件。
///
/// Event reporting whether playback is actively running.
final class PlayerPlayingEvent extends PlayerEvent {
  /// 创建播放状态事件。
  const PlayerPlayingEvent(this.playing);

  /// 为 `true` 表示正在播放，`false` 表示暂停或停止。
  ///
  /// `true` when playing, `false` otherwise.
  final bool playing;
}

/// 缓冲状态更新事件。
///
/// Event reporting whether the player is currently buffering.
final class PlayerBufferingEvent extends PlayerEvent {
  /// 创建缓冲状态事件。
  const PlayerBufferingEvent(this.buffering);

  /// 为 `true` 表示正在缓冲数据。
  ///
  /// `true` when buffering.
  final bool buffering;
}

/// 播放错误事件。
///
/// Event reporting a playback error.
final class PlayerErrorEvent extends PlayerEvent {
  /// 创建错误事件。
  const PlayerErrorEvent(this.message);

  /// 可读错误描述信息。
  ///
  /// Human-readable error message.
  final String message;
}

/// 媒体自然播放完成事件。
///
/// Event emitted when playback reaches end-of-stream naturally.
final class PlayerCompletedEvent extends PlayerEvent {
  /// 创建播完事件。
  const PlayerCompletedEvent();
}

/// 视频画面尺寸与旋转角度事件。
///
/// Event reporting decoded video dimensions and rotation degrees.
final class PlayerVideoSizeEvent extends PlayerEvent {
  /// 创建视频尺寸事件。
  const PlayerVideoSizeEvent(this.size, this.rotationDegrees);

  /// 视频画面宽高尺寸（像素）。
  ///
  /// Decoded video dimensions.
  final Size size;

  /// 规范化后的顺时针旋转角度（`0`、`90`、`180`、`270`）。
  ///
  /// Normalized clockwise rotation in degrees.
  final int rotationDegrees;
}

/// 无线投屏状态变更事件。
///
/// Event reporting wireless cast state and remote receiver name.
final class PlayerCastStateEvent extends PlayerEvent {
  /// 创建投屏状态事件。
  const PlayerCastStateEvent(this.state, {this.deviceName});

  /// 最新投屏连接状态。
  ///
  /// Updated [CastState].
  final CastState state;

  /// 远端接收设备名称（未连接时通常为 `null`）。
  ///
  /// Optional friendly name of the remote receiver.
  final String? deviceName;
}
