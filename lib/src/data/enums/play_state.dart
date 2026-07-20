/// 播放状态枚举。
/// Playback state enumeration.
///
/// [stopped] is an explicit API stop (mid-playback). [completed] means the
/// media reached end-of-stream naturally — UI may show replay.
enum PlayState { idle, loading, playing, paused, stopped, completed, error }
