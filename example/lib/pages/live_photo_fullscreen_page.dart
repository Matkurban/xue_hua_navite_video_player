import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

/// 动态照片全屏查看沉浸页面。
class LivePhotoFullscreenPage extends StatelessWidget {
  const LivePhotoFullscreenPage({
    super.key,
    required this.source,
    required this.playMode,
    required this.title,
  });

  final LivePhotoSource source;
  final LivePhotoPlayMode playMode;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('live_photo_fullscreen_page'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('live_photo_fullscreen_close'),
            icon: const Icon(Icons.fullscreen_exit),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: LivePhotoPlayer(
            key: ValueKey<String>(
              'demo_live_photo_fullscreen_${source.identity}',
            ),
            source: source,
            playMode: playMode == LivePhotoPlayMode.longPress
                ? LivePhotoPlayMode.tap
                : playMode,
            fit: BoxFit.contain,
            badgeLabel: '实况',
          ),
        ),
      ),
    );
  }
}
