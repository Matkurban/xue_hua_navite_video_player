import 'package:flutter/services.dart';

/// Web / WASM stub: assets are served by the browser, not extracted to disk.
class AssetExtractor {
  AssetExtractor._();

  /// Throws; callers should resolve web assets to a URL instead of extracting.
  static Future<String> extract(String assetPath, {AssetBundle? bundle}) {
    throw UnsupportedError(
      'AssetExtractor is not supported on web; asset URLs are served by '
      'the browser directly. Use the asset path as a network URL instead.',
    );
  }
}
