/// 无线投屏连接状态。
///
/// Wireless casting connection state.
enum CastState {
  /// 当前平台、运行环境（如无 GMS 服务）或当前媒体源不支持投屏。
  ///
  /// Casting is not supported on the current platform or runtime environment.
  unavailable,

  /// 支持投屏且当前处于本地播放状态（可发起投屏）。
  ///
  /// Casting is available and playback is currently local.
  notConnected,

  /// 用户已在系统选择器中选中设备，正在握手建立会话或加载远端媒体。
  ///
  /// Handshaking with the selected cast receiver or loading media remotely.
  connecting,

  /// 已成功连接远端设备，正在远端投屏播放。
  ///
  /// Actively connected and casting to a remote receiver.
  connected,

  /// 正在断开投屏并将播放进度切回本地播放器。
  ///
  /// Disconnecting from the remote receiver and restoring local playback.
  disconnecting;

  /// 用于原生桥接通信的协议字符串名称。
  ///
  /// Wire string name used across the native bridge.
  String get wireName => name;

  /// 从原生端传回的字符串解析对应的 [CastState]。
  ///
  /// Parses a [CastState] from a serialized wire string.
  ///
  /// - [raw]：原生端传回的状态字符串（可为 `null`）。
  ///   Raw status string returned by the native host (may be `null`).
  ///
  /// 返回值 / Returns：匹配到的 [CastState]；无法识别或为 `null` 时回退为 [CastState.unavailable]。
  /// The matching [CastState], or [CastState.unavailable] if unrecognized or `null`.
  static CastState fromWire(String? raw) {
    return switch (raw) {
      'notConnected' => CastState.notConnected,
      'connecting' => CastState.connecting,
      'connected' => CastState.connected,
      'disconnecting' => CastState.disconnecting,
      _ => CastState.unavailable,
    };
  }
}
