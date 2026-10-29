import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

/// Boots the example app for integration / driver tests.
Future<void> startExampleApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

/// Boots only [LivePhotoDemoPage] so flutter drive stays on one screen.
Future<void> startLivePhotoDemoApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const LivePhotoDemoApp());
}

/// Minimal app shell whose home is the live-photo demo (driver / IT).
class LivePhotoDemoApp extends StatelessWidget {
  const LivePhotoDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final playerTheme = _resolveExamplePlayerTheme(
          _playerStyleSignal.value,
        );
        return MaterialApp(
          title: 'Live Photo Demo',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: AppTheme.light.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          darkTheme: AppTheme.dark.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          home: const LivePhotoDemoPage(),
        );
      },
    );
  }
}

final FlutterSignal<VideoPlayerDesignStyle> _playerStyleSignal = signal(
  VideoPlayerDesignStyle.adaptive,
);

VideoPlayerTheme _resolveExamplePlayerTheme(VideoPlayerDesignStyle style) {
  return switch (style) {
    VideoPlayerDesignStyle.material => const VideoPlayerTheme.material(),
    VideoPlayerDesignStyle.cupertino => const VideoPlayerTheme.cupertino(),
    VideoPlayerDesignStyle.adaptive => VideoPlayerTheme.adaptive(),
  };
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final playerTheme = _resolveExamplePlayerTheme(
          _playerStyleSignal.value,
        );
        return MaterialApp(
          title: 'Video Player',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: AppTheme.light.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          darkTheme: AppTheme.dark.copyWith(
            extensions: <ThemeExtension<dynamic>>[playerTheme],
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

class _DemoItem {
  final String title;
  final String url;

  const _DemoItem(this.title, this.url);
}

/// GitHub 上公开的在线动态照片（Motion Photo）URL 列表。
const List<String> _onlineLivePhotoUrls = <String>[
  'https://raw.githubusercontent.com/Matkurban/xue_hua_navite_video_player/main/example/assets/live_photo/motion_city_walk.jpg',
  'https://raw.githubusercontent.com/Matkurban/xue_hua_navite_video_player/main/example/assets/live_photo/motion_park_pan.jpg',
  'https://raw.githubusercontent.com/Matkurban/xue_hua_navite_video_player/main/example/assets/live_photo/motion_street_clip.jpg',
];

/// 本地备用动态照片资源（网络异常时回退保障）。
const List<String> _bundledLivePhotoAssets = <String>[
  'assets/live_photo/motion_city_walk.jpg',
  'assets/live_photo/motion_park_pan.jpg',
  'assets/live_photo/motion_street_clip.jpg',
];

const List<_DemoItem> _networkDemoPlaylist = <_DemoItem>[
  _DemoItem(
    'GitHub · 8K UHD (7680x4320)',
    'https://thetestdata.com/assets/video/mp4/highquality/8K_Thetestdata.mp4',
  ),
  _DemoItem(
    'Chromium · 4K UHD (3840x2160 · HEVC)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bear-3840x2160-hevc.mp4',
  ),
  _DemoItem(
    'GitHub · 4K UHD (3840x2160 · Sizzle)',
    'https://github.com/stevederico/omarchy-quattro-sizzle/releases/download/v1-4k/v1-4k.mp4',
  ),
  _DemoItem(
    'GitHub · 2K QHD (2560x1440)',
    'https://placeholdervideo.dev/2560x1440',
  ),
  _DemoItem(
    'GitHub · 1K FHD (1920x1080 · Big Buck Bunny)',
    'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-1080p-30sec.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ),
  _DemoItem(
    'Chromium · 720p HD (1280x720 · Bear)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bear-1280x720.mp4',
  ),
  _DemoItem(
    'GitHub · 480p SD (854x480 · Big Buck Bunny)',
    'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-480p-30sec.mp4',
  ),
  _DemoItem(
    'W3C · Sintel',
    'https://raw.githubusercontent.com/andreasbotsikas/DemoVideos/master/sintel.mp4',
  ),
  _DemoItem(
    'W3C · Movie 300',
    'https://raw.githubusercontent.com/web-platform-tests/wpt/master/media/movie_300.mp4',
  ),
  _DemoItem(
    'Chromium · 240p LD (320x240 · Big Buck Bunny)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bbb-320x240-2video-2audio.mp4',
  ),
  _DemoItem(
    'Chromium · 180p LD (320x180 · Bear)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bear-320x180-hi10p.mp4',
  ),
];

/// Prefer a short local fixture when present (Linux/macOS/Windows CI) so UI EOS tests are fast.
///
/// On web, `dart:io` Platform/File/Directory are unavailable; keep network demos only.
List<_DemoItem> get _demoPlaylist {
  if (kIsWeb) {
    return List<_DemoItem>.from(_networkDemoPlaylist);
  }
  final sep = Platform.pathSeparator;
  final localCandidates = <String>[
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS)
      '${Directory.systemTemp.path}${sep}xh_it_test.mp4',
    '/workspace/test.mp4',
    r'/Users/admin/XueHuaPackages/xue_hua_navite_video_player/test.mp4',
    r'E:\XueHuaPackages\xue_hua_navite_video_player\test.mp4',
    '${Directory.systemTemp.path}${sep}xh_it_test.mp4',
    'test.mp4',
    '../test.mp4',
  ];
  for (final path in localCandidates) {
    if (File(path).existsSync()) {
      return <_DemoItem>[
        _DemoItem('Local · test.mp4', path),
        ..._networkDemoPlaylist,
      ];
    }
  }
  return List<_DemoItem>.from(_networkDemoPlaylist);
}

bool _isLocalSource(String url) {
  return url.startsWith('file:') ||
      (!url.contains('://') && !url.startsWith('http'));
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

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
      for (final item in _networkDemoPlaylist) {
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
      builder: (_) => _CacheManagerSheet(onChanged: _refreshCacheStatus),
    );
    await _refreshCacheStatus();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _demoPlaylist;
    return Scaffold(
      key: const ValueKey<String>('home_page'),
      appBar: AppBar(
        title: const Text('Video Player'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('cache_manage_button'),
            tooltip: '媒体缓存 (${_formatBytes(_cacheBytes)})',
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
            child: _DesignStyleSelector(),
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

class _CacheManagerSheet extends StatefulWidget {
  final Future<void> Function() onChanged;

  const _CacheManagerSheet({required this.onChanged});

  @override
  State<_CacheManagerSheet> createState() => _CacheManagerSheetState();
}

class _CacheManagerSheetState extends State<_CacheManagerSheet> {
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
    for (final item in _networkDemoPlaylist) {
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

  Future<void> _precacheItem(_DemoItem item) async {
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

  Future<void> _removeItem(_DemoItem item) async {
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
                        '当前占用：${_formatBytes(_cacheBytes)}（边播边存 · 二次秒开）',
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
                itemCount: _networkDemoPlaylist.length,
                itemBuilder: (context, index) {
                  final item = _networkDemoPlaylist[index];
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

class _DesignStyleSelector extends StatelessWidget {
  const _DesignStyleSelector();

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final current = _playerStyleSignal.value;
        return CupertinoSlidingSegmentedControl<VideoPlayerDesignStyle>(
          groupValue: current,
          children: const <VideoPlayerDesignStyle, Widget>{
            VideoPlayerDesignStyle.adaptive: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('Adaptive'),
            ),
            VideoPlayerDesignStyle.material: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('Material'),
            ),
            VideoPlayerDesignStyle.cupertino: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text('Cupertino'),
            ),
          },
          onValueChanged: (value) {
            if (value != null) {
              _playerStyleSignal.value = value;
            }
          },
        );
      },
    );
  }
}

class _ResolvedGalleryLivePhoto {
  final String title;
  final String assetPath;
  final LivePhotoSource source;
  final String subtitle;

  const _ResolvedGalleryLivePhoto({
    required this.title,
    required this.assetPath,
    required this.source,
    required this.subtitle,
  });
}

class LivePhotoDemoPage extends StatefulWidget {
  const LivePhotoDemoPage({super.key});

  @override
  State<LivePhotoDemoPage> createState() => _LivePhotoDemoPageState();
}

class _LivePhotoDemoPageState extends State<LivePhotoDemoPage> {
  LivePhotoPlayMode _playMode = LivePhotoPlayMode.longPress;
  int _selectedIndex = 0;
  List<_ResolvedGalleryLivePhoto> _items = const <_ResolvedGalleryLivePhoto>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLivePhotos();
  }

  Future<void> _loadLivePhotos() async {
    final resolved = <_ResolvedGalleryLivePhoto>[];

    for (var i = 0; i < _onlineLivePhotoUrls.length; i++) {
      final url = _onlineLivePhotoUrls[i];
      final fileName = url.split('/').last;
      final fallbackAsset =
          i < _bundledLivePhotoAssets.length ? _bundledLivePhotoAssets[i] : null;

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
          : (fallbackAsset != null
              ? 'GitHub 在线加载中 (备用可用)'
              : '未识别到内嵌视频轨');

      resolved.add(
        _ResolvedGalleryLivePhoto(
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
    _ResolvedGalleryLivePhoto current,
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
    _ResolvedGalleryLivePhoto current,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(child: _DesignStyleSelector()),
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
            // Fullscreen stage: no ClipRRect / Opacity around the video surface
            // (LivePhotoPlayer already keeps CorePlayer free of those ancestors).
          ),
        ),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final int initialIndex;

  const PlayerPage({super.key, required this.initialIndex});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final VideoPlayerController _controller = VideoPlayerController();
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _controller.initialize();
    if (!mounted) return;
    await _openCurrent();
  }

  Future<void> _openCurrent() async {
    final item = _demoPlaylist[_index];
    if (_isLocalSource(item.url)) {
      await _controller.playFile(item.url);
    } else {
      await _controller.playNetwork(item.url);
    }
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _demoPlaylist.length) return;
    setState(() => _index = index);
    await _openCurrent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _DesignStyleSelector(),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.skip_previous),
                  title: const Text('Previous'),
                  enabled: _index > 0,
                  onTap: () {
                    Navigator.pop(ctx);
                    _playAt(_index - 1);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.skip_next),
                  title: const Text('Next'),
                  enabled: _index < _demoPlaylist.length - 1,
                  onTap: () {
                    Navigator.pop(ctx);
                    _playAt(_index + 1);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    _controller.isFullscreen.value
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                  ),
                  title: Text(
                    _controller.isFullscreen.value
                        ? 'Exit fullscreen'
                        : 'Enter fullscreen',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _controller.toggleFullscreen();
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take snapshot (PNG)'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _takeSnapshot();
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Extract cover candidates'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _extractCovers();
                  },
                ),
                if (_index + 1 < _demoPlaylist.length &&
                    !_isLocalSource(_demoPlaylist[_index + 1].url))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Precache next video'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final next = _demoPlaylist[_index + 1];
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Precaching ${next.title}...')),
                      );
                      await XueHuaNaviteVideoPlayer.instance.precache(
                        VideoSource.network(next.url),
                      );
                      if (!mounted) return;
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(content: Text('Cached: ${next.title}')),
                      );
                    },
                  ),
                const Divider(height: 1),
                _PlayerStateBar(controller: _controller),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _takeSnapshot() async {
    try {
      final xfile = await _controller.takeSnapshot();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => _SnapshotDialog(file: xfile),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
    }
  }

  Future<void> _extractCovers() async {
    final item = _demoPlaylist[_index];
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Extracting covers...')),
    );
    try {
      final frames = await XueHuaNaviteVideoPlayer.instance
          .extractCoverCandidates(VideoSource.network(item.url), count: 5);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (frames.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No covers extracted.')),
        );
        return;
      }
      showDialog<void>(
        context: context,
        builder: (_) => _CoversDialog(frames: frames),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Cover extraction failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _demoPlaylist[_index];

    return Scaffold(
      key: const ValueKey<String>('player_page'),
      backgroundColor: Colors.black,
      body: VideoPlayer(
        controller: _controller,
        fill: true,
        onClose: () => Navigator.of(context).maybePop(),
        title: Text(
          current.title,
          key: const ValueKey<String>('player_title'),
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('player_more_button'),
            icon: const Icon(Icons.more_horiz),
            color: Colors.white,
            onPressed: _showMoreSheet,
          ),
        ],
      ),
    );
  }
}

class _PlayerStateBar extends StatelessWidget {
  final VideoPlayerController controller;

  const _PlayerStateBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SignalBuilder(
        builder: (context) {
          final state = controller.playState.value;
          final buffering = controller.isBuffering.value;
          final bufferedPct = (controller.bufferedPercent.value * 100).round();
          final speed = controller.speed.value;
          final mime = controller.mimeType.value ?? '—';
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _Chip(label: 'State: ${state.name}'),
              _Chip(label: buffering ? 'Buffering' : 'Idle'),
              _Chip(label: 'Buf: $bufferedPct%'),
              _Chip(label: '${speed}x'),
              Text(mime, style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: cs.onSecondaryContainer, fontSize: 12),
      ),
    );
  }
}

class _SnapshotDialog extends StatelessWidget {
  final NaviteFile file;

  const _SnapshotDialog({required this.file});

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
              child: _NaviteFileImage(file: file),
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

class _CoversDialog extends StatelessWidget {
  final List<VideoCoverFrame> frames;

  const _CoversDialog({required this.frames});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cover candidates (${frames.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: frames.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final f = frames[i];
                  return Row(
                    children: <Widget>[
                      SizedBox(
                        width: 100,
                        height: 56,
                        child: _NaviteFileImage(
                          file: f.image,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Pos: ${f.position.inMilliseconds}ms',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              'Brightness: ${f.brightness.toStringAsFixed(3)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
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

class _NaviteFileImage extends StatelessWidget {
  final NaviteFile file;
  final BoxFit fit;

  const _NaviteFileImage({required this.file, this.fit = BoxFit.contain});

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
