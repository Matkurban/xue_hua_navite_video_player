import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/temp_paths.dart';

/// 跨平台文件封装（用于播放器截图与视频封面帧），无需依赖第三方 `cross_file`。
///
/// Cross-platform file representation used for player snapshots and cover
/// frames without depending on `package:cross_file`.
@immutable
class NaviteFile {
  /// 原生平台为本地文件系统路径；Web 平台为 `data:` 或 `blob:` URL。
  ///
  /// Local filesystem path on native platforms, or a `data:` / `blob:` URL on Web.
  final String path;

  /// 跨平台统一 URI 标识：原生平台为 `file://` URI，Web 平台为 `data:` 或 `blob:` URL。
  ///
  /// Cross-platform URI identifier (`file://` on native, `data:` or `blob:` URL on Web).
  final String uri;

  /// 文件名（如 `snapshot-1700000000000.png`）。
  ///
  /// File name (for example `snapshot-1700000000000.png`).
  final String name;

  /// MIME 类型，默认 `'image/png'`。
  ///
  /// MIME type, defaults to `'image/png'`.
  final String mimeType;

  final Uint8List? _bytes;

  const NaviteFile({
    required this.path,
    required this.uri,
    required this.name,
    this.mimeType = 'image/png',
    this._bytes,
  });

  /// 从本地文件路径、`file://` URI 或 Web `data:` / `blob:` URL 构造 [NaviteFile]。
  ///
  /// Creates a [NaviteFile] from a local file path, `file://` URI, or Web
  /// `data:` / `blob:` URL.
  factory NaviteFile.fromLocation(String location, {String? name, String mimeType = 'image/png'}) {
    if (location.startsWith('data:') ||
        location.startsWith('blob:') ||
        location.startsWith('http://') ||
        location.startsWith('https://')) {
      return NaviteFile(
        path: location,
        uri: location,
        name: name ?? _extractNameFromUri(location, mimeType: mimeType),
        mimeType: mimeType,
      );
    }

    if (location.startsWith('file://')) {
      final parsed = Uri.parse(location);
      final filePath = parsed.toFilePath();
      return NaviteFile(
        path: filePath,
        uri: location,
        name: name ?? _extractNameFromPath(filePath),
        mimeType: mimeType,
      );
    }

    return NaviteFile(
      path: location,
      uri: Uri.file(location).toString(),
      name: name ?? _extractNameFromPath(location),
      mimeType: mimeType,
    );
  }

  /// 从内存字节构造 [NaviteFile]，自动生成 `data:` URI 以兼容 Web 与跨平台读取。
  ///
  /// Creates a [NaviteFile] from in-memory [bytes], wrapping them in a `data:`
  /// URI for cross-platform compatibility.
  factory NaviteFile.fromBytes(
    Uint8List bytes, {
    String name = 'snapshot.png',
    String mimeType = 'image/png',
    String? path,
  }) {
    final dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final resolvedPath = path ?? dataUri;
    final resolvedUri =
        (path != null &&
            !path.startsWith('data:') &&
            !path.startsWith('blob:') &&
            !path.startsWith('http://') &&
            !path.startsWith('https://'))
        ? (path.startsWith('file://') ? path : Uri.file(path).toString())
        : dataUri;
    return NaviteFile(
      path: resolvedPath,
      uri: resolvedUri,
      name: name,
      mimeType: mimeType,
      bytes: bytes,
    );
  }

  /// 读取文件的全部字节。
  ///
  /// Reads the entire file contents as bytes.
  Future<Uint8List> readAsBytes() async {
    final inMemory = _bytes;
    if (inMemory != null) {
      return inMemory;
    }
    if (uri.startsWith('data:')) {
      return UriData.parse(uri).contentAsBytes();
    }
    return readFileBytes(path);
  }

  /// 获取文件字节长度。
  ///
  /// Returns the length of the file in bytes.
  Future<int> length() async {
    final inMemory = _bytes;
    if (inMemory != null) {
      return inMemory.length;
    }
    if (uri.startsWith('data:')) {
      return UriData.parse(uri).contentAsBytes().length;
    }
    return readFileLength(path);
  }

  /// 将文件字节保存到 [targetPath]（仅支持原生文件系统平台）。
  ///
  /// Writes the file contents to [targetPath] on native platforms.
  Future<void> saveTo(String targetPath) async {
    final data = await readAsBytes();
    await writeFileBytes(targetPath, data);
  }

  static String _extractNameFromPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final segments = normalized.split('/').where((s) => s.isNotEmpty);
    if (segments.isEmpty) return 'snapshot.png';
    return segments.last;
  }

  static String _extractNameFromUri(String rawUri, {required String mimeType}) {
    if (rawUri.startsWith('data:')) {
      final ext = _extensionFromMime(mimeType);
      return 'snapshot.$ext';
    }
    final parsed = Uri.tryParse(rawUri);
    if (parsed != null && parsed.pathSegments.isNotEmpty) {
      final last = parsed.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    final ext = _extensionFromMime(mimeType);
    return 'snapshot.$ext';
  }

  static String _extensionFromMime(String mimeType) {
    final slashIndex = mimeType.indexOf('/');
    if (slashIndex == -1 || slashIndex == mimeType.length - 1) {
      return 'png';
    }
    return mimeType.substring(slashIndex + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaviteFile &&
          other.path == path &&
          other.uri == uri &&
          other.name == name &&
          other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(path, uri, name, mimeType);

  @override
  String toString() => 'NaviteFile(name: $name, path: $path, mimeType: $mimeType)';
}
