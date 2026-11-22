import 'package:flutter/services.dart';

/// Web / WASM 平台 Asset 提取器桩实现：Web 端资源直接由浏览器以 URL 形式加载，无需落盘抽取。
///
/// Web / WASM stub for [AssetExtractor]: assets are served directly by the
/// browser over HTTP and are not extracted to a local filesystem.
class AssetExtractor {
  AssetExtractor._();

  /// 在 Web / 非 IO 平台上始终抛出 [UnsupportedError]；调用方应直接将 Asset 解析为网络 URL。
  ///
  /// - [assetPath]：目标 Asset 路径。
  /// - [bundle]：可选资源加载 [AssetBundle]。
  ///
  /// Always throws [UnsupportedError] on Web; resolve web assets as URLs instead.
  static Future<String> extract(String assetPath, {AssetBundle? bundle}) {
    throw UnsupportedError(
      'AssetExtractor is not supported on web; asset URLs are served by '
      'the browser directly. Use the asset path as a network URL instead.',
    );
  }
}
