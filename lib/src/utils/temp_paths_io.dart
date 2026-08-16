import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Default directory for extracted cover frames.
Future<String> pluginCoverDir() async {
  final base = await getTemporaryDirectory();
  return '${base.path}/xue_hua_navite_video_player/covers';
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
