import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Default directory for extracted cover frames.
Future<String> pluginCoverDir() async {
  final base = await getTemporaryDirectory();
  return '${base.path}/xue_hua_navite_video_player/covers';
}

/// Default directory for extracted Live Photo / Motion Photo assets.
Future<String> pluginLivePhotoDir() async {
  final base = await _safeTemporaryDirectory();
  final dir = Directory('${base.path}/xue_hua_navite_video_player/live_photos');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

/// Default directory for cached network media files.
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

/// Default path for a snapshot PNG named [name].
Future<String> pluginSnapshotPath(String name) async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/xue_hua_navite_video_player/snapshots/$name';
}

/// Writes [bytes] to [path], creating parent directories as needed.
Future<void> writeFileBytes(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes is Uint8List ? bytes : Uint8List.fromList(bytes), flush: true);
}

/// Reads all bytes from [path].
Future<Uint8List> readFileBytes(String path) async {
  return File(path).readAsBytes();
}

/// Returns the byte length of the file at [path].
Future<int> readFileLength(String path) async {
  return File(path).length();
}
