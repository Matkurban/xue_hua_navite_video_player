/// Web 平台本地投屏 HTTP 服务占位实现。
class LocalCastHttpServer {
  final Object? bindAddress;
  final String? overrideHostIp;

  LocalCastHttpServer({this.bindAddress, this.overrideHostIp});

  String? get servingUrl => null;

  /// 将本地 `file://` URL 映射为局域网可访问的 HTTP Range 流地址。
  /// Web 端无本地文件路径，原样返回 `null`。
  Future<String?> serveLocalFileUrl(String nativeUrl, {String? mimeType}) async {
    return null;
  }

  Future<void> stop() async {}
}
