import 'dart:typed_data';

/// Web / WASM stub: covers are not written to a filesystem.
Future<String> pluginCoverDir() async => '';

/// Web / WASM stub: snapshots are kept in memory, not as files.
Future<String> pluginSnapshotPath(String name) async => name;

/// Web / WASM stub: there is no local filesystem to write.
Future<void> writeFileBytes(String path, List<int> bytes) async {
  throw UnsupportedError('Writing snapshot files is not supported on this platform.');
}

/// Web / WASM stub: there is no local filesystem to read.
Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('Reading local files is not supported on this platform.');
}

/// Web / WASM stub: there is no local filesystem to inspect.
Future<int> readFileLength(String path) async {
  throw UnsupportedError('Reading local file length is not supported on this platform.');
}
