import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../cache/video_cache_manager.dart';
import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import '../orientation/player_orientation_controller.dart';
import 'brightness_controller.dart';
import 'fullscreen_coordinator.dart';
import 'local_cast_http_server.dart';
import 'playback_session.dart';
import 'player_backend.dart';

/// 音视频与实况照片播放器的核心公开控制器（[PlaybackSession] 的稳定对外门面）。
///
/// 负责向应用层与 UI 组件暴露响应式播放状态信号（基于 `signals_flutter`）以及加载、
/// 播放控制、进度跳转、音量/亮度调节、全屏与锁屏、无线投屏、截图等操作接口。
/// 底层状态机规则与原生会话唯一性约束由 [PlaybackSession] 内部维护。
///
/// Public facade over [PlaybackSession] providing a stable call-site name for
/// apps and UI widgets. Exposes reactive playback signals (`signals_flutter`)
/// and control APIs for media loading, playback, seeking, volume/brightness,
/// fullscreen & screen lock, wireless casting, and snapshots.
class VideoPlayerController {
  /// 创建一个 [VideoPlayerController] 实例。
  ///
  /// 所有依赖参数均可选，默认使用插件内置的跨平台实现；在单元测试或高级定制场景下可
  /// 注入自定义实现：
  /// - [backend]：底层播放器传输后端（默认使用 [PlayerBackend]）。
  /// - [fullscreen]：全屏与方向锁定协调器（默认使用 [SystemChromeFullscreenCoordinator]）。
  /// - [brightness]：屏幕亮度控制器（默认使用 [ChannelBrightnessController]）。
  /// - [localCastServer]：本地文件投屏使用的局域网 HTTP 代理服务。
  /// - [cacheManager]：网络媒体磁盘缓存管理器（默认使用 [VideoCacheManager.instance]）。
  ///
  /// Creates a [VideoPlayerController] with optional dependency overrides for
  /// [backend], [fullscreen], [brightness], [localCastServer], and [cacheManager].
  VideoPlayerController({
    PlayerBackend? backend,
    FullscreenCoordinator? fullscreen,
    BrightnessController? brightness,
    LocalCastHttpServer? localCastServer,
    VideoCacheManager? cacheManager,
  }) : _session = PlaybackSession(
         backend: backend,
         fullscreen: fullscreen,
         brightness: brightness,
         localCastServer: localCastServer,
         cacheManager: cacheManager,
       );

  final PlaybackSession _session;

  /// 当前播放状态信号（如空闲、加载中、播放中、暂停、已停止、已完成、错误）。
  ///
  /// Reactive signal of the current [PlayState].
  FlutterSignal<PlayState> get playState => _session.playState;

  /// 当前播放进度位置信号。
  ///
  /// Reactive signal of the current playback position.
  FlutterSignal<Duration> get position => _session.position;

  /// 当前已缓冲到的时间位置信号。
  ///
  /// Reactive signal of the furthest buffered playback position.
  FlutterSignal<Duration> get bufferedPosition => _session.bufferedPosition;

  /// 当前媒体总时长信号（直播流或未知时长媒体可能为 [Duration.zero]）。
  ///
  /// Reactive signal of the total media duration (`Duration.zero` if unknown or live).
  FlutterSignal<Duration> get duration => _session.duration;

  /// 当前音量信号，取值范围 `0.0`（静音）至 `1.0`（最大）。
  ///
  /// Reactive signal of the playback volume in `[0.0, 1.0]`.
  FlutterSignal<double> get volume => _session.volume;

  /// 当前播放倍速信号（例如 `0.5`、`1.0`、`1.5`、`2.0`）。
  ///
  /// Reactive signal of the playback rate multiplier (e.g. `1.0` for normal speed).
  FlutterSignal<double> get speed => _session.speed;

  /// 当前是否正在网络或解码缓冲的信号。
  ///
  /// Reactive signal indicating whether playback is currently buffering.
  FlutterSignal<bool> get isBuffering => _session.isBuffering;

  /// 最近一次播放错误的描述信息信号；无错误时为 `null`。
  ///
  /// Reactive signal holding the latest error message, or `null` when healthy.
  FlutterSignal<String?> get errorMessage => _session.errorMessage;

  /// 当前已加载媒体源的标识 URL 或路径信号；未加载时为 `null`。
  ///
  /// Reactive signal of the currently loaded media URL or identifier, or `null`.
  FlutterSignal<String?> get currentUrl => _session.currentUrl;

  /// 当前媒体的 MIME 类型信号（例如 `video/mp4`、`audio/mpeg`）；未知时为 `null`。
  ///
  /// Reactive signal of the detected MIME type of the active media, or `null`.
  FlutterSignal<String?> get mimeType => _session.mimeType;

  /// 当前视频帧的原始逻辑分辨率尺寸信号（音频或尚未就绪时为 [Size.zero]）。
  ///
  /// Reactive signal of the decoded video frame dimensions (`Size.zero` for audio-only).
  FlutterSignal<Size> get videoSize => _session.videoSize;

  /// 当前视频的显示旋转角度信号（常见值为 `0`、`90`、`180`、`270`）。
  ///
  /// Reactive signal of the video rotation metadata in degrees (`0`, `90`, `180`, `270`).
  FlutterSignal<int> get rotationDegrees => _session.rotationDegrees;

  /// 结合 [videoSize] 与 [rotationDegrees] 计算得到的有效显示宽高比信号。
  ///
  /// Computed display aspect ratio accounting for [videoSize] and [rotationDegrees].
  FlutterComputed<double> get videoAspectRatio => _session.videoAspectRatio;

  /// 当前媒体是否为视频流（存在有效视频画面或视频 MIME 类型）的计算信号。
  ///
  /// Computed signal that is `true` when the active media is video.
  FlutterComputed<bool> get isVideo => _session.isVideo;

  /// 当前媒体是否为纯音频的计算信号。
  ///
  /// Computed signal that is `true` when the active media is audio-only.
  FlutterComputed<bool> get isAudio => _session.isAudio;

  /// 当前是否正处于播放状态（`playState == PlayState.playing`）的计算信号。
  ///
  /// Computed signal that is `true` when [playState] is [PlayState.playing].
  FlutterComputed<bool> get isPlaying => _session.isPlaying;

  /// 当前播放进度百分比计算信号，取值范围 `0.0` 至 `1.0`。
  ///
  /// Computed playback progress ratio in `[0.0, 1.0]`.
  FlutterComputed<double> get progressPercent => _session.progressPercent;

  /// 当前已缓冲进度百分比计算信号，取值范围 `0.0` 至 `1.0`。
  ///
  /// Computed buffered progress ratio in `[0.0, 1.0]`.
  FlutterComputed<double> get bufferedPercent => _session.bufferedPercent;

  /// 当前是否处于静音状态的信号。
  ///
  /// Reactive signal indicating whether audio output is muted.
  FlutterSignal<bool> get muted => _session.muted;

  /// 当前是否开启播完自动循环重播的信号。
  ///
  /// Reactive signal indicating whether playback loops automatically at end-of-stream.
  FlutterSignal<bool> get isLooping => _session.isLooping;

  /// 快进/快退步进时长枚举信号（例如 5 秒、10 秒、15 秒、30 秒）。
  ///
  /// Reactive signal of the configured [SkipSecondType] step for forward/backward seeks.
  FlutterSignal<SkipSecondType> get skipSecondType => _session.skipSecondType;

  /// 当前视频画面填充比例模式信号（适应、填充、拉伸）。
  ///
  /// Reactive signal of the active [AspectRatioMode].
  FlutterSignal<AspectRatioMode> get aspectRatioMode => _session.aspectRatioMode;

  /// 当前是否处于全屏模式的信号。
  ///
  /// Reactive signal indicating whether the player is currently in fullscreen mode.
  FlutterSignal<bool> get isFullscreen => _session.isFullscreen;

  /// 当前全屏界面与屏幕方向是否处于锁定状态的信号。
  ///
  /// Reactive signal indicating whether fullscreen controls and orientation are locked.
  FlutterSignal<bool> get isLocked => _session.isLocked;

  /// 当前屏幕亮度信号，取值范围 `0.0` 至 `1.0`。
  ///
  /// Reactive signal of the current screen brightness in `[0.0, 1.0]`.
  FlutterSignal<double> get brightness => _session.brightness;

  /// 当前加载媒体解析出的实况照片 / 动态照片数据包信号；非实况照片时为 `null`。
  ///
  /// Resolved Live Photo / Motion Photo bundle for the currently loaded media, if any.
  FlutterSignal<LivePhotoBundle?> get livePhotoBundle => _session.livePhotoBundle;

  /// 当前加载的媒体是否为实况照片 / 动态照片的计算信号。
  ///
  /// `true` when the currently loaded media is a Live Photo / Motion Photo.
  FlutterComputed<bool> get isLivePhoto => _session.isLivePhoto;

  /// 当前实况照片 / 动态照片的解析元数据计算信号；无数据时为 `null`。
  ///
  /// Parsed metadata for the currently loaded Live Photo / Motion Photo, if any.
  FlutterComputed<LivePhotoMetadata?> get livePhotoMetadata => _session.livePhotoMetadata;

  /// 当前实况照片的静态封面图文件计算信号；无数据时为 `null`。
  ///
  /// Extracted or paired still cover image file for the active Live Photo, if any.
  FlutterComputed<NaviteFile?> get livePhotoStillImage => _session.livePhotoStillImage;

  /// 当前无线投屏（AirPlay / Chromecast / Remote Playback）状态信号。
  ///
  /// Current wireless casting state.
  FlutterSignal<CastState> get castState => _session.castState;

  /// 已连接或正在连接的远端投屏设备名称信号；未连接时为 `null`。
  ///
  /// Friendly name of the connected or connecting remote cast device, if any.
  FlutterSignal<String?> get castDeviceName => _session.castDeviceName;

  /// 当前运行平台与环境是否支持无线投屏的计算信号。
  ///
  /// `true` when the current platform/environment supports wireless casting.
  FlutterComputed<bool> get isCastSupported => _session.isCastSupported;

  /// 当前是否正在连接或已连接到无线投屏设备的计算信号。
  ///
  /// `true` when a cast session is currently connecting or connected.
  FlutterComputed<bool> get isCasting => _session.isCasting;

  /// 关联的设备方向与重力传感器状态机控制器（支持锁屏状态查询、自动旋转开关与 iOS Safari 权限请求）。
  ///
  /// Associated [PlayerOrientationController] for gravity rotation and orientation lock.
  PlayerOrientationController? get orientationController => _session.orientationController;

  /// 原生视频渲染纹理 ID 信号（移动端/桌面端用于 [Texture] 渲染，Web 端为 `0` 或 `null`）。
  ///
  /// Reactive signal of the native video rendering texture ID (`null` before initialization).
  FlutterSignal<int?> get textureId => _session.textureId;

  /// 初始化播放器底层会话与原生渲染资源。
  ///
  /// 必须在调用任何打开或播放方法前执行一次。注意同一进程内仅允许存在一个活跃的原生
  /// 会话，否则将抛出 [StateError]。
  ///
  /// Initializes the underlying playback session and allocates native resources.
  /// Throws [StateError] if the controller is disposed or another native session
  /// is already active in this process.
  Future<void> initialize() => _session.initialize();

  /// 打开并立即开始播放网络音视频流。
  ///
  /// - [url]：网络媒体地址（HTTP/HTTPS/HLS 等）。
  /// - [cacheKey]：可选的自定义磁盘缓存键，适用于带签名参数的动态 URL。
  /// - [headers]：可选的自定义 HTTP 请求头（如鉴权 Token、Referer）。
  /// - [enableCache]：是否启用边播边缓存；为 `null` 时遵循全局 [VideoCacheConfig] 设置。
  ///
  /// Opens and immediately starts playing a network media stream at [url] with
  /// optional [cacheKey], HTTP [headers], and [enableCache] override.
  Future<void> playNetwork(
    String url, {
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) => _session.playNetwork(url, cacheKey: cacheKey, headers: headers, enableCache: enableCache);

  /// 仅打开并预加载网络音视频流，不自动开始播放。
  ///
  /// 参数 [url]、[cacheKey]、[headers]、[enableCache] 含义同 [playNetwork]。
  ///
  /// Opens a network media stream at [url] without starting playback immediately.
  Future<void> openNetwork(
    String url, {
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) => _session.openNetwork(url, cacheKey: cacheKey, headers: headers, enableCache: enableCache);

  /// 打开并立即开始播放本地文件。
  ///
  /// - [path]：本地音视频文件的绝对路径（若为 Motion Photo/Live Photo 容器也会自动识别）。
  ///
  /// Opens and starts playing a local media file at [path].
  Future<void> playFile(String path) => _session.playFile(path);

  /// 仅打开并预加载本地文件，不自动开始播放。
  ///
  /// - [path]：本地音视频文件的绝对路径。
  ///
  /// Opens a local media file at [path] without starting playback immediately.
  Future<void> openFile(String path) => _session.openFile(path);

  /// 打开并立即开始播放 Flutter 应用内置 Asset 资源。
  ///
  /// - [assetPath]：在 `pubspec.yaml` 中声明的资源路径。
  /// - [bundle]：可选的资源加载 [AssetBundle]，默认使用 [rootBundle]。
  ///
  /// Opens and starts playing a Flutter asset at [assetPath] using an optional [bundle].
  Future<void> playAsset(String assetPath, {AssetBundle? bundle}) =>
      _session.playAsset(assetPath, bundle: bundle);

  /// 仅打开并预加载 Flutter 应用内置 Asset 资源，不自动开始播放。
  ///
  /// - [assetPath]：在 `pubspec.yaml` 中声明的资源路径。
  /// - [bundle]：可选的资源加载 [AssetBundle]，默认使用 [rootBundle]。
  ///
  /// Opens a Flutter asset at [assetPath] without starting playback immediately.
  Future<void> openAsset(String assetPath, {AssetBundle? bundle}) =>
      _session.openAsset(assetPath, bundle: bundle);

  /// 打开并立即开始播放实况照片 / 动态照片源（支持配对图+视频或单文件 Motion Photo）。
  ///
  /// - [source]：实况照片源描述对象。
  /// - [loop]：可选的循环播放开关，传入时会同步更新 [isLooping]。
  ///
  /// Opens and starts playing a [LivePhotoSource] (paired image+video or single-file Motion Photo),
  /// optionally overriding [isLooping] via [loop].
  Future<void> playLivePhoto(LivePhotoSource source, {bool? loop}) =>
      _session.playLivePhoto(source, loop: loop);

  /// 仅打开并解析实况照片 / 动态照片源，不自动开始播放。
  ///
  /// - [source]：实况照片源描述对象。
  /// - [loop]：可选的循环播放开关，传入时会同步更新 [isLooping]。
  ///
  /// Opens a [LivePhotoSource] without starting playback immediately.
  Future<void> openLivePhoto(LivePhotoSource source, {bool? loop}) =>
      _session.openLivePhoto(source, loop: loop);

  /// 打开并立即开始播放任意类型的 [VideoSource]。
  ///
  /// - [source]：统一的媒体源抽象（网络、本地文件、Asset 或实况照片）。
  ///
  /// Opens and immediately starts playing any [VideoSource].
  Future<void> playSource(VideoSource source) => _session.playSource(source);

  /// 仅打开并预加载任意类型的 [VideoSource]，不自动开始播放。
  ///
  /// - [source]：统一的媒体源抽象。
  ///
  /// Opens any [VideoSource] without starting playback immediately.
  Future<void> openSource(VideoSource source) => _session.openSource(source);

  /// 开始或恢复播放；若当前处于 [PlayState.completed]，会自动回到起点重播。
  ///
  /// Starts or resumes playback, automatically rewinding to zero if completed.
  Future<void> play() => _session.play();

  /// 暂停当前播放。
  ///
  /// Pauses playback.
  Future<void> pause() => _session.pause();

  /// 在播放与暂停之间切换。
  ///
  /// Toggles between playing and paused states.
  Future<void> playOrPause() => _session.playOrPause();

  /// 跳转到指定的播放位置。
  ///
  /// - [position]：目标播放时间点，会自动钳制在 `[Duration.zero, duration]` 范围内。
  ///
  /// Seeks playback to [position], clamped within the valid media duration.
  Future<void> seek(Duration position) => _session.seek(position);

  /// 设置播放音量。
  ///
  /// - [value]：目标音量值，会自动钳制到 `[0.0, 1.0]`，并联动更新 [muted] 状态。
  ///
  /// Sets playback volume to [value] (clamped to `[0.0, 1.0]`) and updates [muted].
  Future<void> setVolume(double value) => _session.setVolume(value);

  /// 设置静音状态；取消静音时会恢复静音前的音量。
  ///
  /// - [value]：`true` 表示静音，`false` 表示取消静音并恢复先前音量。
  ///
  /// Sets mute state to [value], restoring the prior non-zero volume when unmuted.
  Future<void> setMuted(bool value) => _session.setMuted(value);

  /// 切换静音状态。
  ///
  /// Toggles [muted].
  Future<void> toggleMuted() => _session.toggleMuted();

  /// 开启或关闭播完自动循环重播。
  ///
  /// - [looping]：`true` 开启循环，`false` 关闭循环。
  ///
  /// Enables or disables automatic replay at end-of-stream.
  void setLooping(bool looping) => _session.setLooping(looping);

  /// 切换循环播放开关（[isLooping]）。
  ///
  /// Toggles [isLooping].
  void toggleLooping() => _session.toggleLooping();

  /// 设置快进/快退按钮与双击手势使用的步进时长。
  ///
  /// - [type]：目标步进时长枚举值。
  ///
  /// Updates the [SkipSecondType] used by [seekForward] and [seekBackward].
  void setSkipSecondType(SkipSecondType type) => _session.setSkipSecondType(type);

  /// 按当前 [skipSecondType] 配置的步长向前快进。
  ///
  /// Seeks forward by the duration configured in [skipSecondType].
  Future<void> seekForward() => _session.seekForward();

  /// 按当前 [skipSecondType] 配置的步长向后快退。
  ///
  /// Seeks backward by the duration configured in [skipSecondType].
  Future<void> seekBackward() => _session.seekBackward();

  /// 切换视频画面的宽高比填充模式并同步至原生层。
  ///
  /// - [mode]：目标画面填充模式（[AspectRatioMode]）。
  ///
  /// Sets the video [AspectRatioMode] and syncs it to the native backend.
  Future<void> setAspectRatioMode(AspectRatioMode mode) => _session.setAspectRatioMode(mode);

  /// 通知原生渲染层当前视频视图的逻辑尺寸与设备像素比（主要用于桌面端 libmpv 纹理尺寸同步）。
  ///
  /// - [width]：视图逻辑宽度。
  /// - [height]：视图逻辑高度。
  /// - [devicePixelRatio]：设备像素比。
  ///
  /// Reports the rendered viewport [width], [height], and [devicePixelRatio] to
  /// the native backend so backing textures match the on-screen resolution.
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) => _session.setVideoViewSize(width: width, height: height, devicePixelRatio: devicePixelRatio);

  /// 弹出操作系统原生的无线投屏 / 音频路由选择器。
  ///
  /// Presents the operating system's native wireless cast / route picker.
  Future<void> showCastPicker() => _session.showCastPicker();

  /// 断开当前活跃的无线投屏会话并将播放切换回本地设备。
  ///
  /// Disconnects the active wireless cast session and returns playback locally.
  Future<void> stopCasting() => _session.stopCasting();

  /// 进入全屏模式：更新 [isFullscreen] 并应用平台级全屏行为（移动端横竖屏旋转与沉浸式
  /// 系统栏、桌面端窗口全屏或 Web 浏览器 Fullscreen API）。
  ///
  /// 完整的视觉全屏（全屏浮层 Overlay、控制栏与手势）需要挂载位于 [Overlay] 下的
  /// [VideoPlayer] 组件；仅使用 [CorePlayer] 或无 UI 调用时仍会切换窗口/浏览器/屏幕方向。
  ///
  /// Enters fullscreen mode: updates [isFullscreen], then applies the platform
  /// host (mobile orientation / immersive UI, desktop window fullscreen, or
  /// the browser Fullscreen API).
  ///
  /// Visual fullscreen (edge-to-edge Overlay + chrome / gestures) requires a
  /// mounted [VideoPlayer] under an [Overlay] ancestor. Calling this with only
  /// a [CorePlayer] (or no UI) still changes the window / browser / orientation.
  Future<void> enterFullscreen() => _session.enterFullscreen();

  /// 退出全屏模式：恢复窗口、浏览器或系统 UI 状态，并重置 [isFullscreen] 与 [isLocked]。
  ///
  /// Leaves fullscreen: restores the window / browser / system UI and clears
  /// [isFullscreen] and [isLocked].
  Future<void> exitFullscreen() => _session.exitFullscreen();

  /// 在全屏与非全屏模式之间切换。
  ///
  /// Toggles fullscreen mode between [enterFullscreen] and [exitFullscreen].
  Future<void> toggleFullscreen() => _session.toggleFullscreen();

  /// 锁定或解锁全屏控制界面及设备屏幕方向（通过 Flutter `SystemChrome` 实现）。
  ///
  /// 仅在全屏模式下生效；解锁后会恢复基于重力感应的双向横屏自动旋转。
  /// - [locked]：`true` 锁定，`false` 解锁。
  /// - [lockedOrientation]：锁定时可选显式指定的目标 [DeviceOrientation]。
  ///
  /// Locks or unlocks fullscreen controls and orientation via `SystemChrome`.
  /// When unlocking, restores gravity-driven bidirectional landscape rotation.
  Future<void> setLocked(bool locked, {DeviceOrientation? lockedOrientation}) =>
      _session.setLocked(locked, lockedOrientation: lockedOrientation);

  /// 锁定全屏控制界面与当前屏幕方向。
  ///
  /// - [lockedOrientation]：可选显式指定的锁定方向。
  ///
  /// Locks fullscreen controls and orientation.
  Future<void> lock({DeviceOrientation? lockedOrientation}) =>
      _session.lock(lockedOrientation: lockedOrientation);

  /// 解锁全屏控制界面并恢复重力感应双向旋转。
  ///
  /// Unlocks fullscreen controls and restores gravity-driven bidirectional rotation.
  Future<void> unlock() => _session.unlock();

  /// 在全屏模式下切换锁定状态（[isLocked]）。
  ///
  /// - [lockedOrientation]：由未锁定切换为锁定时可选指定的锁定方向。
  ///
  /// Toggles [isLocked] while in fullscreen.
  Future<void> toggleLocked({DeviceOrientation? lockedOrientation}) =>
      _session.toggleLocked(lockedOrientation: lockedOrientation);

  /// 调节屏幕亮度并同步更新 [brightness] 信号。
  ///
  /// - [value]：目标亮度值，会自动钳制到 `[0.0, 1.0]`。
  ///
  /// Sets screen brightness to [value] (clamped to `[0.0, 1.0]`).
  Future<void> setBrightness(double value) => _session.setBrightness(value);

  /// 设置播放倍速并同步更新 [speed] 信号。
  ///
  /// - [value]：目标倍速（如 `0.5`、`1.0`、`1.25`、`1.5`、`2.0`）。
  ///
  /// Sets the playback speed multiplier to [value].
  Future<void> setSpeed(double value) => _session.setSpeed(value);

  /// 停止当前播放并将状态置为 [PlayState.stopped]。
  ///
  /// Stops playback and transitions [playState] to [PlayState.stopped].
  Future<void> stop() => _session.stop();

  /// 截取当前播放画面并输出为 PNG 格式的 [NaviteFile]。
  ///
  /// 在 iOS/macOS 上基于当前时间点调用 `AVAssetImageGenerator` 生成（无需依赖纹理帧推送）；
  /// 其他平台则使用各自的原生截图通道。
  /// - [savePath]：可选的本地保存路径；传入时会同时写入到该文件。
  /// - 返回值：包含 PNG 字节数据或本地路径的 [NaviteFile]。
  ///
  /// Captures the current playback frame as a PNG [NaviteFile], optionally
  /// saving it to [savePath].
  ///
  /// On iOS/macOS this uses `AVAssetImageGenerator` at the current time (does
  /// not require Texture frame pushing). Other platforms use their native
  /// snapshot path.
  Future<NaviteFile> takeSnapshot({String? savePath}) => _session.takeSnapshot(savePath: savePath);

  /// 销毁控制器、退出全屏、停止本地投屏代理并释放所有原生播放器资源。
  ///
  /// 销毁后不应再调用该控制器的任何控制方法。
  ///
  /// Disposes the session, exits fullscreen if active, stops the local cast
  /// server, and releases all native player resources.
  Future<void> dispose() => _session.dispose();

  /// 重置当前媒体相关的状态信号与内部缓冲标记，准备加载新媒体源。
  ///
  /// Resets media-scoped signals and internal playback flags to idle defaults.
  void reset() => _session.reset();
}
