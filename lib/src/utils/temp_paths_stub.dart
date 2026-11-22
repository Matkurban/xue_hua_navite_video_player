import 'dart:typed_data';

/// Web / WASM 桩实现：封面帧不写入本地文件系统，返回空路径。
///
/// Web / WASM stub: covers are not written to a local filesystem.
Future<String> pluginCoverDir() async => '';

/// Web / WASM 桩实现：实况照片保存在内存或 `blob:` / `data:` URL 中，返回空路径。
///
/// Web / WASM stub: live photos are kept in memory / `blob:` or `data:` URLs.
Future<String> pluginLivePhotoDir() async => '';

/// Web / WASM 桩实现：媒体缓存使用浏览器与内存存储，无本地目录路径。
///
/// Web / WASM stub: media cache uses browser / memory storage rather than a filesystem path.
Future<String> pluginMediaCacheDir() async => '';

/// Web / WASM 桩实现：截图仅保留在内存中，直接返回文件名 [name]。
///
/// Web / WASM stub: snapshots are kept in memory rather than written as files.
Future<String> pluginSnapshotPath(String name) async => name;

/// Web / WASM 桩实现：无本地文件系统可写，调用时抛出 [UnsupportedError]。
///
/// Web / WASM stub: throws [UnsupportedError] because no local filesystem is available.
Future<void> writeFileBytes(String path, List<int> bytes) async {
  throw UnsupportedError('Writing snapshot files is not supported on this platform.');
}

/// Web / WASM 桩实现：无本地文件系统可读，调用时抛出 [UnsupportedError]。
///
/// Web / WASM stub: throws [UnsupportedError] because no local filesystem is available.
Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('Reading local files is not supported on this platform.');
}

/// Web / WASM 桩实现：无本地文件系统可查询长度，调用时抛出 [UnsupportedError]。
///
/// Web / WASM stub: throws [UnsupportedError] because no local filesystem is available.
Future<int> readFileLength(String path) async {
  throw UnsupportedError('Reading local file length is not supported on this platform.');
}
