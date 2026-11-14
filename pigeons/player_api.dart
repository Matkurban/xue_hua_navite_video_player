import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    appDirectory: 'example',
    configDirectory: '.',
    dartPackageName: 'xue_hua_navite_video_player',
    dartOut: 'lib/src/pigeon/player_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/com/kurban/xue_hua_navite_video_player/PlayerApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.kurban.xue_hua_navite_video_player', useJni: true),
    swiftOut: <String>[
      'ios/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/PlayerApi.g.swift',
      'macos/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/PlayerApi.g.swift',
    ],
    swiftOptions: SwiftOptions(useFfi: true, ffiModuleName: 'xue_hua_navite_video_player'),
    cppHeaderOut: 'windows/player_api.g.h',
    cppSourceOut: 'windows/player_api.g.cpp',
    cppOptions: CppOptions(namespace: 'xue_hua_navite_video_player'),
    gobjectHeaderOut: 'linux/player_api.g.h',
    gobjectSourceOut: 'linux/player_api.g.c',
    gobjectOptions: GObjectOptions(module: 'XueHuaNaviteVideoPlayer'),
  ),
)
enum NativeAspectRatioMode { fit, fill, stretch }

enum NativeCastState { unavailable, notConnected, connecting, connected, disconnecting }

enum NativePlayerEventType {
  position,
  buffered,
  duration,
  playing,
  buffering,
  error,
  completed,
  videoSize,
  castState,
}

class OpenMediaRequest {
  OpenMediaRequest({
    required this.url,
    this.castUrl,
    this.cacheKey,
    this.headers,
    this.enableCache,
  });

  String url;
  String? castUrl;
  String? cacheKey;
  Map<String, String>? headers;
  bool? enableCache;
}

class DurationProbeRequest {
  DurationProbeRequest({required this.url, required this.timeoutMs, this.cacheKey, this.headers});

  String url;
  int timeoutMs;
  String? cacheKey;
  Map<String, String>? headers;
}

class CoverExtractRequest {
  CoverExtractRequest({
    required this.url,
    required this.count,
    required this.candidates,
    required this.minBrightness,
    required this.outputDir,
    this.cacheKey,
    this.headers,
  });

  String url;
  int count;
  int candidates;
  double minBrightness;
  String outputDir;
  String? cacheKey;
  Map<String, String>? headers;
}

class CoverFrameData {
  CoverFrameData({required this.path, required this.positionMs, required this.brightness});

  String path;
  int positionMs;
  double brightness;
}

class SnapshotData {
  SnapshotData({this.bytes, this.dataUri});

  Uint8List? bytes;
  String? dataUri;
}

class CacheConfigRequest {
  CacheConfigRequest({
    required this.enabled,
    required this.maxCacheBytes,
    required this.maxSingleFileBytes,
    this.cacheDir,
  });

  bool enabled;
  int maxCacheBytes;
  int maxSingleFileBytes;
  String? cacheDir;
}

class PrecacheRequest {
  PrecacheRequest({
    required this.url,
    this.cacheKey,
    this.cacheDir,
    this.headers,
    this.preloadBytes,
    required this.maxSingleFileBytes,
    required this.maxCacheBytes,
  });

  String url;
  String? cacheKey;
  String? cacheDir;
  Map<String, String>? headers;
  int? preloadBytes;
  int maxSingleFileBytes;
  int maxCacheBytes;
}

class CacheEntryRequest {
  CacheEntryRequest({required this.url, this.cacheKey, this.cacheDir});

  String url;
  String? cacheKey;
  String? cacheDir;
}

class PlayerEventData {
  PlayerEventData({
    required this.kind,
    this.intValue,
    this.boolValue,
    this.message,
    this.width,
    this.height,
    this.rotationDegrees,
    this.castState,
    this.castDeviceName,
  });

  NativePlayerEventType kind;
  int? intValue;
  bool? boolValue;
  String? message;
  double? width;
  double? height;
  int? rotationDegrees;
  NativeCastState? castState;
  String? castDeviceName;
}

@HostApi()
abstract class PlayerHostApi {
  @async
  int create();

  @async
  void open(OpenMediaRequest request);

  void play();

  void pause();

  void seek(int positionMs);

  void setVolume(double volume);

  void setSpeed(double speed);

  void setAspectRatioMode(NativeAspectRatioMode mode);

  void setVideoViewSize(double width, double height, double devicePixelRatio);

  void showCastPicker();

  void stopCasting();

  void dispose();

  double getBrightness();

  void setBrightness(double value);

  void setWindowFullscreen(bool value);

  @async
  SnapshotData? takeSnapshot();

  @async
  int? getDuration(DurationProbeRequest request);

  @async
  List<CoverFrameData> extractCovers(CoverExtractRequest request);

  @async
  void configureCache(CacheConfigRequest request);

  @async
  void precache(PrecacheRequest request);

  void cancelPrecache(String cacheKey);

  @async
  bool isCached(CacheEntryRequest request);

  @async
  int getCacheSize(String? cacheDir);

  @async
  void removeCache(CacheEntryRequest request);

  @async
  void clearCache(String? cacheDir);

  void pinCacheKey(String cacheKey);

  void unpinCacheKey(String cacheKey);
}

@FlutterApi()
abstract class PlayerFlutterApi {
  @async
  void onPlayerEvent(PlayerEventData event);

  @async
  void onWindowFullscreen(bool isFullscreen);
}
