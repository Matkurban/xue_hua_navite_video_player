import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/widgets/navite_file_image.dart';

/// 截图查看与路径展示对话框。
class SnapshotDialog extends StatelessWidget {
  final NaviteFile file;

  const SnapshotDialog({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Snapshot', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: NaviteFileImage(file: file),
            ),
            const SizedBox(height: 8),
            SelectableText(
              file.path,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
