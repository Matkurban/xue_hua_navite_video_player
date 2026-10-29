/// 样例视频条目数据结构。
class DemoItem {
  final String title;
  final String url;

  const DemoItem(this.title, this.url);
}

/// GitHub 上公开的在线动态照片（Motion Photo）URL 列表。
const List<String> onlineLivePhotoUrls = <String>[
  'https://raw.githubusercontent.com/Matkurban/xue_hua_navite_video_player/main/example/assets/live_photo/motion_city_walk.jpg',
  'https://raw.githubusercontent.com/Matkurban/xue_hua_navite_video_player/main/example/assets/live_photo/motion_park_pan.jpg',
  'https://raw.githubusercontent.com/Matkurban/xue_hua_navite_video_player/main/example/assets/live_photo/motion_street_clip.jpg',
];

/// 本地备用动态照片资源（网络异常时回退保障）。
const List<String> bundledLivePhotoAssets = <String>[
  'assets/live_photo/motion_city_walk.jpg',
  'assets/live_photo/motion_park_pan.jpg',
  'assets/live_photo/motion_street_clip.jpg',
];

/// GitHub 及公开可信源多分辨率视频测试列表（覆盖 8K 到 180p）。
const List<DemoItem> networkDemoPlaylist = <DemoItem>[
  DemoItem(
    'GitHub · 8K UHD (7680x4320)',
    'https://thetestdata.com/assets/video/mp4/highquality/8K_Thetestdata.mp4',
  ),

  DemoItem(
    'GitHub · 4K UHD (3840x2160 · Sizzle)',
    'https://github.com/stevederico/omarchy-quattro-sizzle/releases/download/v1-4k/v1-4k.mp4',
  ),
  DemoItem(
    'Demo1',
    'https://file.icve.com.cn/file_doc/805/748/193/cpRdydfH.mp4',
  ),
  DemoItem(
    'Demo3',
    'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-1080p-30sec.mp4',
  ),
  DemoItem(
    'Demo4',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ),
  DemoItem(
    'Chromium · 720p HD (1280x720 · Bear)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bear-1280x720.mp4',
  ),
  DemoItem(
    'GitHub · 480p SD (854x480 · Big Buck Bunny)',
    'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-480p-30sec.mp4',
  ),
  DemoItem(
    'W3C · Sintel',
    'https://raw.githubusercontent.com/andreasbotsikas/DemoVideos/master/sintel.mp4',
  ),
  DemoItem(
    'W3C · Movie 300',
    'https://raw.githubusercontent.com/web-platform-tests/wpt/master/media/movie_300.mp4',
  ),
  DemoItem(
    'Chromium · 240p LD (320x240 · Big Buck Bunny)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bbb-320x240-2video-2audio.mp4',
  ),
  DemoItem(
    'Chromium · 180p LD (320x180 · Bear)',
    'https://raw.githubusercontent.com/chromium/chromium/master/media/test/data/bear-320x180-hi10p.mp4',
  ),
];

/// 判断给定的 URL 是否为本地文件源。
bool isLocalSource(String url) {
  return url.startsWith('file:') ||
      (!url.contains('://') && !url.startsWith('http'));
}

/// 格式化字节数大小显示。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
