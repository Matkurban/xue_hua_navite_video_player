import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/models/demo_item.dart';
import 'package:xue_hua_navite_video_player_example/pages/live_photo_demo_page.dart';
import 'package:xue_hua_navite_video_player_example/pages/player_page.dart';
import 'package:xue_hua_navite_video_player_example/widgets/cache_manager_sheet.dart';
import 'package:xue_hua_navite_video_player_example/widgets/design_style_selector.dart';

/// 样例首页：展示测试视频列表、缓存状态管理入口、动态照片画廊入口及风格切换。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Set<String> _cachedUrls = <String>{};
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshCacheStatus();
  }

  Future<void> _refreshCacheStatus() async {
    try {
      final size = await XueHuaNaviteVideoPlayer.instance.getCacheSize();
      final cached = <String>{};
      for (final item in networkDemoPlaylist) {
        final hit = await XueHuaNaviteVideoPlayer.instance.isCached(
          VideoSource.network(item.url),
        );
        if (hit) {
          cached.add(item.url);
        }
      }
      if (!mounted) return;
      setState(() {
        _cacheBytes = size;
        _cachedUrls
          ..clear()
          ..addAll(cached);
      });
    } catch (_) {}
  }

  Future<void> _openCacheSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => CacheManagerSheet(onChanged: _refreshCacheStatus),
    );
    await _refreshCacheStatus();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = demoPlaylist;
    return Scaffold(
      key: const ValueKey<String>('home_page'),
      appBar: AppBar(
        title: const Text('Video Player'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('cache_manage_button'),
            tooltip: '媒体缓存 (${formatBytes(_cacheBytes)})',
            icon: Badge(
              isLabelVisible: _cacheBytes > 0,
              smallSize: 8,
              child: const Icon(Icons.offline_bolt_outlined),
            ),
            onPressed: _openCacheSheet,
          ),
          IconButton(
            key: const ValueKey<String>('live_photo_demo_button'),
            tooltip: 'Live Photo / 动态照片',
            icon: const Icon(Icons.motion_photos_on_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LivePhotoDemoPage(),
                ),
              );
              await _refreshCacheStatus();
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: DesignStyleSelector(),
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: playlist.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == playlist.length) {
            return ListTile(
              key: const ValueKey<String>('demo_live_photo_entry'),
              leading: const CircleAvatar(
                child: Icon(Icons.motion_photos_on_rounded, size: 20),
              ),
              title: const Text('Live Photos · 动态照片画廊'),
              subtitle: const Text('GCamera Motion Photo JPEG（含可播视频轨）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LivePhotoDemoPage(),
                  ),
                );
                await _refreshCacheStatus();
              },
            );
          }

          final item = playlist[index];
          final isCached = _cachedUrls.contains(item.url);
          return ListTile(
            key: ValueKey<String>('demo_item_$index'),
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(item.title),
            subtitle: Text(
              item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isCached)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.offline_pin_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(initialIndex: index),
                ),
              );
              await _refreshCacheStatus();
            },
          );
        },
      ),
    );
  }
}
