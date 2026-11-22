import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 负责将 Flutter Assets 中的媒体文件懒抽取并原子落盘至临时目录，供原生播放器直接读取。
///
/// Lazily extracts bundled Flutter media assets to atomic temporary files on
/// disk so native players (ExoPlayer, AVPlayer, libmpv) can open them directly.
class AssetExtractor {
  AssetExtractor._();

  /// 同一 asset 的抽取过程只进行一次，多次并发调用共享同一个 future。
  static final Map<String, Future<String>> _inflight = <String, Future<String>>{};

  /// 抽取 [assetPath] 并返回本地落地文件的绝对路径；若已存在有效文件则直接复用。
  ///
  /// - [assetPath]：Flutter `pubspec.yaml` 中声明的资源路径。
  /// - [bundle]：可选资源加载 [AssetBundle]，默认使用 [rootBundle]。
  /// - 返回值：提取后本地文件的绝对路径。
  ///
  /// Extracts [assetPath] using optional [bundle] (defaulting to [rootBundle])
  /// and returns the absolute local file path, reusing cached files if present.
  static Future<String> extract(String assetPath, {AssetBundle? bundle}) {
    final key = assetPath;
    final inflight = _inflight[key];
    if (inflight != null) return inflight;
    final future = _doExtract(assetPath, bundle ?? rootBundle);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  static Future<String> _doExtract(String assetPath, AssetBundle bundle) async {
    final tempDir = await getTemporaryDirectory();
    final root = Directory('${tempDir.path}/xue_hua_navite_video_player/assets');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final hash = sha1.convert(assetPath.codeUnits).toString();
    final baseName = assetPath.split('/').last;
    final safeName = baseName.isEmpty ? 'media' : baseName;
    final outPath = '${root.path}/$hash-$safeName';
    final file = File(outPath);
    if (await file.exists() && await file.length() > 0) {
      return outPath;
    }

    final bytes = await bundle.load(assetPath);
    final buffer = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);

    // Write to a temporary file first and rename atomically so interrupted writes
    // never leave a truncated/corrupted media file at outPath.
    final tmpFile = File('$outPath.tmp.${DateTime.now().microsecondsSinceEpoch}');
    try {
      await tmpFile.writeAsBytes(buffer, flush: true);
      await tmpFile.rename(outPath);
    } catch (_) {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
    return outPath;
  }
}
