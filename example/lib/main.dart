import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:signals_flutter/signals_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData.light(useMaterial3: true).copyWith(
        extensions: const <ThemeExtension<dynamic>>[
          VideoPlayerTheme(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
        ],
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        extensions: const <ThemeExtension<dynamic>>[
          VideoPlayerTheme(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
        ],
      ),
      home: const HomePage(),
    );
  }

  @override
  void dispose() {
    XueHuaNaviteVideoPlayer.instance.dispose();
    super.dispose();
  }
}

class _DemoItem {
  final String title;
  final String url;

  const _DemoItem(this.title, this.url);
}

const List<_DemoItem> _demoPlaylist = <_DemoItem>[
  _DemoItem(
    'ce shi',
    'https://jsontodart.cn/api/object/7976982000/msg_video_dd802bb84715adfbbf71fa7413eb1d29.mp4',
  ),
  _DemoItem(
    'Pexels · 4K Landscape',
    'https://videos.pexels.com/video-files/29603233/12740435_3840_2160_30fps.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://media.w3.org/2010/05/bunny/trailer.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://media.w3.org/2010/05/sintel/trailer.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://media.w3.org/2010/05/video/movie_300.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://www.w3schools.com/html/mov_bbb.mp4',
  ),
  _DemoItem(
    '横屏',
    'https://jsontodart.cn/api/object/7976982000/msg_video_7976982000_1782918277290246.mp4',
  ),
  _DemoItem(
    '竖屏',
    'https://jsontodart.cn/api/object/7976982000/msg_video_7976982000_1782632016859201.mp4',
  ),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Player')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _demoPlaylist.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _demoPlaylist[index];
          return ListTile(
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
    await _controller.playNetwork(item.url);
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
                        ? 'Exit immersive'
                        : 'Enter immersive',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
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
      backgroundColor: Colors.black,
      body: VideoPlayer(
        controller: _controller,
        fill: true,
        onClose: () => Navigator.of(context).maybePop(),
        title: Text(
          current.title,
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
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
  final XFile file;

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
              child: _imageFor(file),
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
                        child: _imageFor(f.image, fit: BoxFit.cover),
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

Widget _imageFor(XFile file, {BoxFit fit = BoxFit.contain}) {
  if (kIsWeb) {
    // On web, path is a data: or blob: URL.
    return Image.network(file.path, fit: fit);
  }
  return Image.file(File(file.path), fit: fit);
}
