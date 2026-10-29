import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
import 'package:xue_hua_navite_video_player_example/models/demo_item.dart';
import 'package:xue_hua_navite_video_player_example/widgets/covers_dialog.dart';
import 'package:xue_hua_navite_video_player_example/widgets/design_style_selector.dart';
import 'package:xue_hua_navite_video_player_example/widgets/snapshot_dialog.dart';

/// 完整功能视频播放器页面（支持全屏、切集、截图、封面候选帧提取、预缓存等）。
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
    final playlist = demoPlaylist;
    if (_index < 0 || _index >= playlist.length) return;
    final item = playlist[_index];
    if (isLocalSource(item.url)) {
      await _controller.playFile(item.url);
    } else {
      await _controller.playNetwork(item.url);
    }
  }

  Future<void> _playAt(int index) async {
    final playlist = demoPlaylist;
    if (index < 0 || index >= playlist.length) return;
    setState(() => _index = index);
    await _openCurrent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMoreSheet() {
    final playlist = demoPlaylist;
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
                  child: DesignStyleSelector(),
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
                  enabled: _index < playlist.length - 1,
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
                if (_index + 1 < playlist.length &&
                    !isLocalSource(playlist[_index + 1].url))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Precache next video'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final next = playlist[_index + 1];
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
        builder: (_) => SnapshotDialog(file: xfile),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
    }
  }

  Future<void> _extractCovers() async {
    final item = demoPlaylist[_index];
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
        builder: (_) => CoversDialog(frames: frames),
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
    final playlist = demoPlaylist;
    final current = (_index >= 0 && _index < playlist.length)
        ? playlist[_index]
        : null;

    return Scaffold(
      key: const ValueKey<String>('player_page'),
      backgroundColor: Colors.black,
      body: VideoPlayer(
        controller: _controller,
        fill: true,
        onClose: () => Navigator.of(context).maybePop(),
        title: Text(
          current?.title ?? '',
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
