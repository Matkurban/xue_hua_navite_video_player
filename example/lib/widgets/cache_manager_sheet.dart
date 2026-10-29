import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/models/demo_item.dart';

/// 磁盘媒体缓存管理 BottomSheet（查看缓存占用、逐条预缓存、移除缓存与一键清空）。
class CacheManagerSheet extends StatefulWidget {
  final Future<void> Function() onChanged;

  const CacheManagerSheet({super.key, required this.onChanged});

  @override
  State<CacheManagerSheet> createState() => _CacheManagerSheetState();
}

class _CacheManagerSheetState extends State<CacheManagerSheet> {
  int _cacheBytes = 0;
  final Set<String> _cachedUrls = <String>{};
  String? _precachingUrl;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final size = await XueHuaNaviteVideoPlayer.instance.getCacheSize();
    final hits = <String>{};
    for (final item in networkDemoPlaylist) {
      if (await XueHuaNaviteVideoPlayer.instance.isCached(
        VideoSource.network(item.url),
      )) {
        hits.add(item.url);
      }
    }
    if (!mounted) return;
    setState(() {
      _cacheBytes = size;
      _cachedUrls
        ..clear()
        ..addAll(hits);
    });
  }

  Future<void> _precacheItem(DemoItem item) async {
    setState(() => _precachingUrl = item.url);
    try {
      await XueHuaNaviteVideoPlayer.instance.precache(
        VideoSource.network(item.url),
      );
    } finally {
      if (mounted) {
        setState(() => _precachingUrl = null);
      }
      await _reload();
      await widget.onChanged();
    }
  }

  Future<void> _removeItem(DemoItem item) async {
    await XueHuaNaviteVideoPlayer.instance.removeCache(
      VideoSource.network(item.url),
    );
    await _reload();
    await widget.onChanged();
  }

  Future<void> _clearAll() async {
    await XueHuaNaviteVideoPlayer.instance.clearCache();
    await _reload();
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '磁盘媒体缓存',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '当前占用：${formatBytes(_cacheBytes)}（边播边存 · 二次秒开）',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _cacheBytes > 0 ? _clearAll : null,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空缓存'),
                ),
              ],
            ),
            const Divider(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: networkDemoPlaylist.length,
                itemBuilder: (context, index) {
                  final item = networkDemoPlaylist[index];
                  final hit = _cachedUrls.contains(item.url);
                  final busy = _precachingUrl == item.url;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      hit
                          ? Icons.offline_pin_rounded
                          : Icons.cloud_download_outlined,
                      color: hit ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(item.title),
                    subtitle: Text(hit ? '已完整缓存到本地磁盘' : '未完整缓存'),
                    trailing: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : hit
                        ? IconButton(
                            tooltip: '移除此条缓存',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _removeItem(item),
                          )
                        : TextButton(
                            onPressed: _precachingUrl == null
                                ? () => _precacheItem(item)
                                : null,
                            child: const Text('预缓存'),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
