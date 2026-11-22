/// 播放器高层播放状态枚举。
///
/// High-level playback state enumeration.
///
/// [stopped] 表示通过 API 主动停止播放（通常发生在播放中途）；[completed] 表示
/// 媒体自然播放至结尾，UI 可据此展示重播按钮。
///
/// [stopped] is an explicit API stop (mid-playback), whereas [completed] means
/// the media reached end-of-stream naturally and UI may display a replay control.
enum PlayState {
  /// 空闲状态：初始状态或调用 `reset()` 后的状态，尚未加载媒体。
  ///
  /// Idle state: initial state or after `reset()`, before any media is opened.
  idle,

  /// 加载准备中：正在解析、打开或缓冲首个可播放帧。
  ///
  /// Loading / preparing: resolving, opening, or buffering the initial frame.
  loading,

  /// 正在播放中。
  ///
  /// Actively playing media.
  playing,

  /// 已暂停（媒体已就绪且处于暂停态）。
  ///
  /// Paused while media is ready.
  paused,

  /// 已通过 API 主动停止播放。
  ///
  /// Explicitly stopped via API mid-playback.
  stopped,

  /// 媒体已自然播放至结尾。
  ///
  /// Reached end-of-stream naturally.
  completed,

  /// 播放发生错误，具体原因见控制器的 `errorMessage`。
  ///
  /// Playback encountered an error; inspect the controller's `errorMessage`.
  error,
}
