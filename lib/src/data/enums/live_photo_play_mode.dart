/// 动态照片（[LivePhotoPlayer]）的交互与播放触发模式。
///
/// Playback trigger and loop mode for [LivePhotoPlayer].
enum LivePhotoPlayMode {
  /// 按住画面（长按）或点击/悬停 LIVE 徽标时播放动态视频，松开手指后平滑切回静态封面图（iOS / Android 系统相册默认交互）。
  ///
  /// Plays while long-pressing the photo (or interacting with the LIVE badge) and smoothly
  /// crossfades back to the still image when released.
  longPress,

  /// 鼠标悬停在画面上时自动播放动态视频，鼠标移出后平滑切回静态封面图（macOS / Windows / Linux 桌面端相册推荐交互）。
  ///
  /// Plays automatically while the mouse pointer hovers over the photo and returns
  /// to the still image when the pointer exits (ideal for desktop & web).
  hover,

  /// 点击画面或 LIVE 徽标完整播放一次动态视频，播放结束后自动切回静态封面图；播放中再次点击可停止。
  ///
  /// Tapping the photo or LIVE badge plays the full motion clip once and returns
  /// to the still image upon completion.
  tap,

  /// 组件加载完成后自动播放一次动态视频，结束后停留在静态封面图（仍支持点击、长按或桌面悬停重播）。
  ///
  /// Automatically plays the motion clip once when loaded, then settles on the
  /// still image (can be re-triggered by tap, long-press, or hover).
  autoPlayOnce,

  /// 持续无缝循环播放动态视频（适合社交信息流卡片、动态壁纸预览）。
  ///
  /// Continuously loops the motion clip.
  loop,
}
