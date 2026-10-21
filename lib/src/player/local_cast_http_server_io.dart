import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../utils/mime_detector.dart';

/// 轻量级局域网单文件 HTTP Range 媒体代理服务。
///
/// 用于在投屏本地文件（`VideoSource.file`）或已解压资源（`VideoSource.asset`）时，
/// 为只接受 `http://` 地址的远端接收器（如 Android Google Cast、Linux DLNA/UPnP）
/// 提供支持 `206 Partial Content` 字节范围拖动（Seek）的局域网流地址。
class LocalCastHttpServer {
  HttpServer? _server;
  File? _activeFile;
  String? _activeToken;
  String? _activeMimeType;
  String? _servingUrl;

  /// 当前正在提供服务的局域网 HTTP URL（若未启动则为 `null`）。
  String? get servingUrl => _servingUrl;

  /// 绑定指定 IP 地址（默认 `InternetAddress.anyIPv4`，测试时可传入 `loopbackIPv4`）。
  final InternetAddress? bindAddress;

  /// 覆盖主机 IP 字符串（仅用于单元测试环境）。
  final String? overrideHostIp;

  LocalCastHttpServer({this.bindAddress, this.overrideHostIp});

  /// 若 [nativeUrl] 是本地路径或 `file://` URI，启动（或复用）局域网 HTTP 服务并返回
  /// `http://<lan-ip>:<port>/cast/<token>.<ext>`；若非本地文件或无法获取局域网 IP 则返回 `null`。
  Future<String?> serveLocalFileUrl(String nativeUrl, {String? mimeType}) async {
    final filePath = _extractFilePath(nativeUrl);
    if (filePath == null) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    final hostIp = overrideHostIp ?? await _resolveLanIpv4();
    if (hostIp == null || hostIp.isEmpty) return null;

    await _ensureServerStarted();
    final server = _server;
    if (server == null) return null;

    _activeFile = file;
    _activeMimeType = mimeType ?? MimeDetector.detect(filePath) ?? 'video/mp4';
    final ext = _extensionOf(filePath);
    _activeToken = '${_randomHex(16)}$ext';
    _servingUrl = 'http://$hostIp:${server.port}/cast/$_activeToken';
    return _servingUrl;
  }

  /// 停止 HTTP 服务并释放端口。
  Future<void> stop() async {
    _activeFile = null;
    _activeToken = null;
    _activeMimeType = null;
    _servingUrl = null;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _ensureServerStarted() async {
    if (_server != null) return;
    final addr = bindAddress ?? InternetAddress.anyIPv4;
    final server = await HttpServer.bind(addr, 0, shared: true);
    _server = server;
    server.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final file = _activeFile;
      final token = _activeToken;
      final expectedPath = token != null ? '/cast/$token' : null;
      if (file == null || expectedPath == null || request.uri.path != expectedPath) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final totalLength = await file.length();
      final contentType = _activeMimeType ?? 'video/mp4';

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      response.headers.set('Access-Control-Allow-Origin', '*');

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final rangeSpec = rangeHeader.substring('bytes='.length).split(',').first.trim();
        final parts = rangeSpec.split('-');
        if (parts.length == 2) {
          int? start = parts[0].isEmpty ? null : int.tryParse(parts[0]);
          int? end = parts[1].isEmpty ? null : int.tryParse(parts[1]);

          if (start == null && end != null) {
            // Suffix byte range: bytes=-500
            start = (totalLength - end).clamp(0, totalLength);
            end = totalLength - 1;
          } else {
            start ??= 0;
            end = (end == null || end >= totalLength) ? (totalLength - 1) : end;
          }

          if (start < 0 || start >= totalLength || end < start) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
            await response.close();
            return;
          }

          final chunkLength = end - start + 1;
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$totalLength',
          );
          response.contentLength = chunkLength;

          if (request.method == 'HEAD') {
            await response.close();
            return;
          }

          await response.addStream(file.openRead(start, end + 1));
          await response.close();
          return;
        }
      }

      response.statusCode = HttpStatus.ok;
      response.contentLength = totalLength;
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await response.addStream(file.openRead());
      await response.close();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static String? _extractFilePath(String url) {
    if (url.startsWith('file://')) {
      try {
        return Uri.parse(url).toFilePath();
      } catch (_) {
        return url.substring('file://'.length);
      }
    }
    if (url.startsWith('/')) {
      return url;
    }
    // Windows drive path (e.g. C:\...)
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(url)) {
      return url;
    }
    return null;
  }

  static String _extensionOf(String path) {
    final slashIdx = path.replaceAll('\\', '/').lastIndexOf('/');
    final fileName = slashIdx >= 0 ? path.substring(slashIdx + 1) : path;
    final dotIdx = fileName.lastIndexOf('.');
    if (dotIdx <= 0) return '.mp4';
    return fileName.substring(dotIdx);
  }

  static String _randomHex(int length) {
    final rng = Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static Future<String?> _resolveLanIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      String? fallbackIp;
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        // Skip virtual/tunnel interfaces when possible
        final isVirtual = name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('utun') ||
            name.startsWith('docker') ||
            name.startsWith('veth') ||
            name.startsWith('vmnet');
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (!isVirtual &&
              (ip.startsWith('192.168.') ||
                  ip.startsWith('10.') ||
                  ip.startsWith('172.'))) {
            return ip;
          }
          fallbackIp ??= ip;
        }
      }
      return fallbackIp;
    } catch (_) {
      return null;
    }
  }
}
