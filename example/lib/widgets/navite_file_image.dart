import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

/// 跨平台展示 `NaviteFile` 图片的组件（支持 Web 与 Native 文件/内存流）。
class NaviteFileImage extends StatelessWidget {
  final NaviteFile file;
  final BoxFit fit;

  const NaviteFileImage({
    super.key,
    required this.file,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // On web, uri is a data: or blob: URL.
      return Image.network(file.uri, fit: fit);
    }
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return const SizedBox.shrink();
        return Image.memory(bytes, fit: fit);
      },
    );
  }
}
