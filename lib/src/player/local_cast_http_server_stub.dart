/// Web 平台本地投屏 HTTP 代理服务空实现占位。
///
/// Web stub for [LocalCastHttpServer] (browsers have no local filesystem cast server).
class LocalCastHttpServer {
  /// 绑定地址占位参数（Web 端不使用）。
  ///
  /// Unused bind address placeholder on Web.
  final Object? bindAddress;

  /// 主机 IP 覆盖占位参数（Web 端不使用）。
  ///
  /// Unused host IP override placeholder on Web.
  final String? overrideHostIp;

  /// 创建 Web 占位本地投屏服务实例。
  ///
  /// Creates a no-op [LocalCastHttpServer] stub.
  LocalCastHttpServer({this.bindAddress, this.overrideHostIp});

  /// 当前正在服务的局域网 URL（Web 端恒为 `null`）。
  ///
  /// Active LAN serving URL (always `null` on Web).
  String? get servingUrl => null;

  /// 将本地 `file://` URL 映射为局域网 HTTP Range 流地址（Web 端恒返回 `null`）。
  ///
  /// Maps a local file URL to a LAN HTTP Range stream URL (always returns `null` on Web).
  Future<String?> serveLocalFileUrl(String nativeUrl, {String? mimeType}) async {
    return null;
  }

  /// 停止服务（Web 端为空操作）。
  ///
  /// Stops the server (no-op on Web).
  Future<void> stop() async {}
}
