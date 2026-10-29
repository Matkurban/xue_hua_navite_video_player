import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/models/demo_item.dart';
import 'package:xue_hua_navite_video_player_example/pages/live_photo_fullscreen_page.dart';
import 'package:xue_hua_navite_video_player_example/widgets/design_style_selector.dart';

/// 动态照片画廊中解析就绪的条目元数据。
class ResolvedGalleryLivePhoto {
  final String title;
  final String assetPath;
  final LivePhotoSource source;
  final String subtitle;

  const ResolvedGalleryLivePhoto({
    required this.title,
    required this.assetPath,
    required this.source,
    required this.subtitle,
  });
}

/// 动态照片（Live Photo / Motion Photo）画廊演示页面。
class LivePhotoDemoPage extends StatefulWidget {
  const LivePhotoDemoPage({super.key});

  @override
  State<LivePhotoDemoPage> createState() => _LivePhotoDemoPageState();
}

class _LivePhotoDemoPageState extends State<LivePhotoDemoPage> {
  LivePhotoPlayMode _playMode = LivePhotoPlayMode.longPress;
  int _selectedIndex = 0;
  List<ResolvedGalleryLivePhoto> _items = const <ResolvedGalleryLivePhoto>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLivePhotos();
  }

  Future<void> _loadLivePhotos() async {
    final resolved = <ResolvedGalleryLivePhoto>[];

    for (var i = 0; i < onlineLivePhotoUrls.length; i++) {
      final url = onlineLivePhotoUrls[i];
      final fileName = url.split('/').last;
      final fallbackAsset = i < bundledLivePhotoAssets.length
          ? bundledLivePhotoAssets[i]
          : null;

      LivePhotoBundle? probed;
      try {
        probed = await XueHuaNaviteVideoPlayer.instance.extractLivePhoto(
          VideoSource.network(url),
        );
      } catch (e) {
        debugPrint('Online live photo probe error for $url: $e');
      }

      final source = (probed != null || fallbackAsset == null)
          ? LivePhotoSource.network(imageUrl: url)
          : LivePhotoSource.asset(imageAsset: fallbackAsset);

      final metaInfo = probed != null
          ? 'GitHub 在线 · ${probed.metadata.format.name} · 视频轨 ${probed.metadata.videoLength ?? 0}B'
          : (fallbackAsset != null ? 'GitHub 在线加载中 (备用可用)' : '未识别到内嵌视频轨');

      resolved.add(
        ResolvedGalleryLivePhoto(
          title: fileName,
          assetPath: url,
          source: source,
          subtitle: metaInfo,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _items = resolved;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _items.isNotEmpty ? _items[_selectedIndex] : null;

    return Scaffold(
      key: const ValueKey<String>('live_photo_demo_page'),
      appBar: AppBar(title: const Text('Live Photo · 动态照片')),
      body: _loading || current == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final useSplit = constraints.maxWidth >= 720;
                final stage = _buildLivePhotoStage(context, current);
                final sidebar = _buildLivePhotoSidebar(context, current);
                if (useSplit) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(flex: 7, child: stage),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 3, child: sidebar),
                    ],
                  );
                }
                return Column(
                  children: <Widget>[
                    Expanded(flex: 7, child: stage),
                    const Divider(height: 1),
                    Expanded(flex: 3, child: sidebar),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildLivePhotoStage(
    BuildContext context,
    ResolvedGalleryLivePhoto current,
  ) {
    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final aspectRatio = (width > 0 && height > 0)
                ? width / height
                : 3 / 4;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Center(
                  child: LivePhotoPlayer(
                    key: ValueKey<String>(
                      'demo_live_photo_${current.assetPath}',
                    ),
                    source: current.source,
                    playMode: _playMode,
                    aspectRatio: aspectRatio,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(16),
                    badgeLabel: '实况',
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: IconButton(
                      key: const ValueKey<String>(
                        'live_photo_fullscreen_button',
                      ),
                      tooltip: '全屏查看',
                      icon: const Icon(Icons.fullscreen, color: Colors.white),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LivePhotoFullscreenPage(
                              source: current.source,
                              playMode: _playMode,
                              title: current.title,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLivePhotoSidebar(
    BuildContext context,
    ResolvedGalleryLivePhoto current,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(child: DesignStyleSelector()),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CupertinoSlidingSegmentedControl<LivePhotoPlayMode>(
              groupValue: _playMode,
              children: const <LivePhotoPlayMode, Widget>{
                LivePhotoPlayMode.longPress: Padding(
                  key: ValueKey<String>('live_photo_mode_long_press'),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('长按'),
                ),
                LivePhotoPlayMode.hover: Padding(
                  key: ValueKey<String>('live_photo_mode_hover'),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('悬停'),
                ),
                LivePhotoPlayMode.tap: Padding(
                  key: ValueKey<String>('live_photo_mode_tap'),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('点击'),
                ),
                LivePhotoPlayMode.autoPlayOnce: Padding(
                  key: ValueKey<String>('live_photo_mode_once'),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('一次'),
                ),
                LivePhotoPlayMode.loop: Padding(
                  key: ValueKey<String>('live_photo_mode_loop'),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('循环'),
                ),
              },
              onValueChanged: (mode) {
                if (mode != null) {
                  setState(() => _playMode = mode);
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                '样例为 GitHub 上公开的在线单文件 Motion Photo（JPEG+内嵌 MP4）。'
                '长按/悬停/点击「实况」可播动效；全屏走同一播放器。'
                '若使用 Apple Live Photo，请把同名 .MOV 放在图片同目录以自动配对。',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            current.title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              current.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '选择动态照片 (${_items.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    key: ValueKey<String>('live_photo_item_$i'),
                    selected: i == _selectedIndex,
                    dense: true,
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(
                      _items[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _items[i].subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: i == _selectedIndex
                        ? const Icon(Icons.check_circle_rounded)
                        : const Icon(Icons.play_circle_outline_rounded),
                    onTap: () {
                      setState(() => _selectedIndex = i);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
