import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/video_source.dart';
import '../../data/models/live_photo_bundle.dart';
import '../../data/models/navite_file.dart';

/// 跨平台渲染动态照片的静态封面图组件（支持内存字节、本地文件、Asset 与网络 URL）。
///
/// Cross-platform widget that renders the still cover image of a [LivePhotoBundle]
/// without importing `dart:io` directly.
class LivePhotoStillView extends StatefulWidget {
  const LivePhotoStillView({
    super.key,
    this.bundle,
    this.fallbackImageSource,
    this.fit = BoxFit.cover,
    this.placeholderBuilder,
  });

  final LivePhotoBundle? bundle;
  final VideoSource? fallbackImageSource;
  final BoxFit fit;
  final Widget Function(BuildContext context)? placeholderBuilder;

  @override
  State<LivePhotoStillView> createState() => _LivePhotoStillViewState();
}

class _LivePhotoStillViewState extends State<LivePhotoStillView> {
  Future<Uint8List?>? _bytesFuture;
  Uint8List? _cachedBytes;
  String? _cachedKey;

  @override
  void initState() {
    super.initState();
    _prepareImageBytes();
  }

  @override
  void didUpdateWidget(covariant LivePhotoStillView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bundle != widget.bundle ||
        oldWidget.fallbackImageSource != widget.fallbackImageSource) {
      _prepareImageBytes();
    }
  }

  void _prepareImageBytes() {
    final naviteFile = widget.bundle?.imageFile;
    final imgSource = widget.bundle?.imageSource ?? widget.fallbackImageSource;

    if (naviteFile != null && !_isDirectUrl(naviteFile.uri)) {
      final key = naviteFile.uri;
      if (_cachedKey == key && _cachedBytes != null) return;
      _cachedKey = key;
      _bytesFuture = naviteFile.readAsBytes().then<Uint8List?>((b) {
        if (mounted && _cachedKey == key) {
          setState(() => _cachedBytes = b);
        }
        return b;
      }).catchError((_) => null);
      return;
    }

    if (imgSource is FileVideoSource && !kIsWeb) {
      final file = NaviteFile.fromLocation(imgSource.path);
      final key = file.uri;
      if (_cachedKey == key && _cachedBytes != null) return;
      _cachedKey = key;
      _bytesFuture = file.readAsBytes().then<Uint8List?>((b) {
        if (mounted && _cachedKey == key) {
          setState(() => _cachedBytes = b);
        }
        return b;
      }).catchError((_) => null);
      return;
    }

    _cachedKey = null;
    _cachedBytes = null;
    _bytesFuture = null;
  }

  static bool _isDirectUrl(String uri) {
    return uri.startsWith('http://') ||
        uri.startsWith('https://') ||
        uri.startsWith('blob:') ||
        (kIsWeb && uri.startsWith('assets/'));
  }

  @override
  Widget build(BuildContext context) {
    final naviteFile = widget.bundle?.imageFile;
    final imgSource = widget.bundle?.imageSource ?? widget.fallbackImageSource;

    // 1. In-memory or preloaded local file bytes
    if (_cachedBytes != null) {
      return Image.memory(
        _cachedBytes!,
        key: const ValueKey<String>('live_photo_still_image'),
        fit: widget.fit,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, _) =>
            widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            ),
      );
    }

    // 2. Asset source (when not yet extracted into a NaviteFile)
    if (imgSource is AssetVideoSource && _bytesFuture == null) {
      return Image.asset(
        imgSource.assetPath,
        key: const ValueKey<String>('live_photo_still_image'),
        bundle: imgSource.bundle,
        fit: widget.fit,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, _) =>
            widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            ),
      );
    }

    // 3. Direct network / blob URL
    if (naviteFile != null && _isDirectUrl(naviteFile.uri)) {
      return Image.network(
        naviteFile.uri,
        key: const ValueKey<String>('live_photo_still_image'),
        fit: widget.fit,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, _) =>
            widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            ),
      );
    }
    if (imgSource is NetworkVideoSource) {
      return Image.network(
        imgSource.url,
        key: const ValueKey<String>('live_photo_still_image'),
        fit: widget.fit,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, _) =>
            widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            ),
      );
    }

    // 4. Async bytes loading
    if (_bytesFuture != null) {
      return FutureBuilder<Uint8List?>(
        future: _bytesFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data ?? _cachedBytes;
          if (bytes == null) {
            return widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            );
          }
          return Image.memory(
            bytes,
            key: const ValueKey<String>('live_photo_still_image'),
            fit: widget.fit,
            gaplessPlayback: true,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, _, _) =>
                widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            ),
          );
        },
      );
    }

    return widget.placeholderBuilder?.call(context) ??
            const ColoredBox(
              color: Color(0xFF1A1A1A),
              child: Center(
                child: Icon(Icons.photo_outlined, color: Color(0x66FFFFFF), size: 36),
              ),
            );
  }
}
