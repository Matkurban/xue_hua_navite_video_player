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

const List<String> _bundledLivePhotoAssets = <String>[
  'assets/live_photo/motion_city_walk.jpg',
  'assets/live_photo/motion_park_pan.jpg',
  'assets/live_photo/motion_street_clip.jpg',
];

const List<_DemoItem> _networkDemoPlaylist = <_DemoItem>[
  _DemoItem(
    'Pexels · 4K Landscape',
    'https://videos.pexels.com/video-files/29603233/12740435_3840_2160_30fps.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ),
  _DemoItem(
    'W3C · Big Buck Bunny',
    'https://media.w3.org/2010/05/bunny/trailer.mp4',
  ),
  _DemoItem('W3C · Sintel', 'https://media.w3.org/2010/05/sintel/trailer.mp4'),
  _DemoItem(
    'W3C · Movie 300',
    'https://media.w3.org/2010/05/video/movie_300.mp4',
  ),
  _DemoItem(
    'W3Schools · Big Buck Bunny',
    'https://www.w3schools.com/html/mov_bbb.mp4',
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('home_page'),
      appBar: AppBar(
        title: const Text('Video Player'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('live_photo_demo_button'),
            tooltip: 'Live Photo / 动态照片',
            icon: const Icon(Icons.motion_photos_on_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LivePhotoDemoPage(),
                ),
              );
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
        itemCount: _demoPlaylist.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _demoPlaylist.length) {
            return ListTile(
              key: const ValueKey<String>('demo_live_photo_entry'),
              leading: const CircleAvatar(
                child: Icon(Icons.motion_photos_on_rounded, size: 20),
              ),
              title: const Text('Live Photos · 动态照片画廊'),
              subtitle: const Text('GCamera Motion Photo JPEG（含可播视频轨）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LivePhotoDemoPage(),
                  ),
                );
              },
            );
          }

          final item = _demoPlaylist[index];
          return ListTile(
            key: ValueKey<String>('demo_item_$index'),
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(item.title),
            subtitle: Text(
              item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(initialIndex: index),
                ),
              );
            },
          );
        },
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
    _loadBundledLivePhotos();
  }

  Future<void> _loadBundledLivePhotos() async {
    final resolved = <_ResolvedGalleryLivePhoto>[];

    for (final assetPath in _bundledLivePhotoAssets) {
      final fileName = assetPath.split('/').last;
      final probed = await XueHuaNaviteVideoPlayer.instance.extractLivePhoto(
        VideoSource.asset(assetPath),
      );
      final metaInfo = probed != null
          ? '${probed.metadata.format.name} · video ${probed.metadata.videoLength ?? 0}B'
          : '未识别到内嵌视频轨';
      resolved.add(
        _ResolvedGalleryLivePhoto(
          title: fileName,
          assetPath: assetPath,
          source: LivePhotoSource.asset(imageAsset: assetPath),
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
                '样例为单文件 Motion Photo（JPEG+内嵌 MP4）。'
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
          final speed = controller.speed.value;
          final mime = controller.mimeType.value ?? '—';
          return Row(
            children: <Widget>[
              _Chip(label: 'State: ${state.name}'),
              const SizedBox(width: 8),
              _Chip(label: buffering ? 'Buffering' : 'Idle'),
              const SizedBox(width: 8),
              _Chip(label: '${speed}x'),
              const Spacer(),
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
