import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// Builds a PNG [XFile] from a filesystem path or a `data:` / `blob:` URL.
///
/// Local paths become [FileSystemXFile]. Web object and data URLs become
/// [ScopedStorageXFile], which `cross_file` 0.4 reads with `fetch`.
XFile pngXFileFromLocation(String location) {
  if (location.startsWith('data:') || location.startsWith('blob:')) {
    return XFile.scopedStorage(uri: location);
  }
  return XFile.fileSystem(path: location);
}

/// Builds a PNG [XFile] from in-memory bytes.
///
/// `cross_file` 0.4 removed `XFile.fromData`. Bytes are wrapped in a data URL
/// so the Web implementation can fetch them as scoped storage.
XFile pngXFileFromBytes(Uint8List bytes) {
  final uri = 'data:image/png;base64,${base64Encode(bytes)}';
  return XFile.scopedStorage(uri: uri);
}
