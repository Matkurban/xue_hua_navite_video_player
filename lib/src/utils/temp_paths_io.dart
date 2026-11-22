import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 获取抽取视频封面帧的默认临时目录路径。
///
/// Returns the default temporary directory path for extracted cover frames.
Future<String> pluginCoverDir() async {
  final base = await getTemporaryDirectory();
  return '${base.path}/xue_hua_navite_video_player/covers';
}

/// 获取拆分实况照片 / 动态照片资源的默认临时目录路径（若不存在会自动创建）。
///
/// Returns the default temporary directory for extracted Live Photo / Motion Photo
/// assets, creating it if it does not yet exist.
Future<String> pluginLivePhotoDir() async {
  final base = await _safeTemporaryDirectory();
  final dir = Directory('${base.path}/xue_hua_navite_video_player/live_photos');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

/// 获取网络媒体磁盘缓存的默认目录路径（若不存在会自动创建）。
///
/// Returns the default directory for cached network media files, creating it if needed.
Future<String> pluginMediaCacheDir() async {
  final base = await _safeTemporaryDirectory();
  final dir = Directory('${base.path}/xue_hua_navite_video_player/media_cache');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

Future<Directory> _safeTemporaryDirectory() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    return Directory.systemTemp;
  }
}

/// 获取名为 [name] 的截图 PNG 文件的默认临时保存路径。
///
/// Returns the default temporary file path for a snapshot PNG named [name].
Future<String> pluginSnapshotPath(String name) async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/xue_hua_navite_video_player/snapshots/$name';
}

/// 将字节数据 [bytes] 写入目标文件 [path]（自动创建缺失的父级目录并强制落盘）。
///
/// Writes [bytes] to [path], creating parent directories as needed and flushing to disk.
Future<void> writeFileBytes(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes is Uint8List ? bytes : Uint8List.fromList(bytes), flush: true);
}

/// 读取本地文件 [path] 的全部字节数据。
///
/// Reads all bytes from the file at [path].
Future<Uint8List> readFileBytes(String path) async {
  return File(path).readAsBytes();
}

/// 返回本地文件 [path] 的字节长度。
///
/// Returns the byte length of the file at [path].
Future<int> readFileLength(String path) async {
  return File(path).length();
}
