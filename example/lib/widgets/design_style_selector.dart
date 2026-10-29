import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

/// 全局播放器设计风格状态信号（Adaptive / Material / Cupertino）。
final FlutterSignal<VideoPlayerDesignStyle> playerStyleSignal = signal(
  VideoPlayerDesignStyle.adaptive,
);

/// 根据风格枚举解析对应播放器主题扩展。
VideoPlayerTheme resolveExamplePlayerTheme(VideoPlayerDesignStyle style) {
  return switch (style) {
    VideoPlayerDesignStyle.material => const VideoPlayerTheme.material(),
    VideoPlayerDesignStyle.cupertino => const VideoPlayerTheme.cupertino(),
    VideoPlayerDesignStyle.adaptive => VideoPlayerTheme.adaptive(),
  };
}

/// 播放器设计风格切换分段选择器组件。
class DesignStyleSelector extends StatelessWidget {
  const DesignStyleSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final current = playerStyleSignal.value;
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
              playerStyleSignal.value = value;
            }
          },
        );
      },
    );
  }
}
