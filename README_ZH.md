# xue_hua_navite_video_player

[English](README.md)

跨平台 Flutter 音视频播放插件。Dart 侧提供统一的控制器与可选 UI；各端由原生引擎负责解码与渲染（ExoPlayer / AVPlayer / libmpv / HTML5）。

| 项 | 说明 |
|----|------|
| 当前版本 | `1.0.1` |
| Flutter | `>= 3.44.0` |
| Dart SDK | `^3.12.0` |
| 仓库 | [GitHub](https://github.com/MatkurbanWeiXin/xue_hua_navite_video_player) |
| 主页 | [jsontodart.cn](https://jsontodart.cn) |
| 许可证 | Apache 2.0 |

---

## 目录

- [功能一览](#功能一览)
- [平台引擎与渲染方式](#平台引擎与渲染方式)
- [架构概览](#架构概览)
- [安装](#安装)
- [平台配置](#平台配置)
- [快速开始](#快速开始)
- [重要约束：单一活跃会话](#重要约束单一活跃会话)
- [媒体来源 VideoSource](#媒体来源-videosource)
- [控制器 VideoPlayerController](#控制器-videoplayercontroller)
- [播放状态 PlayState](#播放状态-playstate)
- [UI 组件](#ui-组件)
- [主题 VideoPlayerTheme](#主题-videoplayertheme)
- [全屏契约](#全屏契约)
- [手势与快捷键](#手势与快捷键)
- [截图与媒体探测](#截图与媒体探测)
- [自定义 UI（Signals）](#自定义-ui-signals)
- [示例应用](#示例应用)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 功能一览

- **六端支持**：Android、iOS、macOS、Linux、Windows、Web
- **原生渲染**：Android / iOS / macOS 使用 PlatformView；Linux / Windows 使用 Texture（libmpv）；Web 使用 HTML5 `<video>`
- **多来源播放**：网络 URL、本地文件、Flutter asset（asset 会自动抽取到临时目录）
- **完整控制**：播放 / 暂停 / 跳转 / 音量 / 静音 / 倍速 / 亮度 / 画面适应模式 / 截图
- **内置 UI**：开箱即用的 `VideoPlayer`（带控件层）与纯画面 `CorePlayer`
- **主题扩展**：通过 `ThemeData.extensions` 注册 `VideoPlayerTheme`
- **全屏**：控制器管理方向与沉浸式系统 UI；视觉全屏 Overlay 需挂载 `VideoPlayer`
- **工具能力**：不启动播放会话即可探测时长、抽取封面候选帧
- **响应式状态**：基于 [`signals_flutter`](https://pub.dev/packages/signals_flutter) 暴露播放状态，便于自定义 UI

---

## 平台引擎与渲染方式

| 平台 | 原生引擎 | 画面承载 |
|------|----------|----------|
| Android | ExoPlayer (Media3) | `AndroidView` PlatformView |
| iOS | AVPlayer | `UiKitView` PlatformView |
| macOS | AVPlayer | `AppKitView` PlatformView |
| Linux | libmpv（软件渲染） | Flutter `Texture` |
| Windows | libmpv（软件渲染） | Flutter `Texture` |
| Web | HTML5 `<video>` | `HtmlElementView` |

画面适应模式 `AspectRatioMode`（`fit` / `fill` / `stretch`）会映射到各端原生属性（如 videoGravity、resizeMode、object-fit、mpv keepaspect/panscan）。

---

## 架构概览

```text
┌─────────────────────────────────────────────────────────┐
│  App UI                                                  │
│  VideoPlayer / CorePlayer / 自定义 Widget                │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  VideoPlayerController（公开门面）                        │
│  └── PlaybackSession（状态机 + Signals）                  │
│       └── PlayerBackend / ChannelPlayerBackend           │
└───────────────────────────┬─────────────────────────────┘
                            │ MethodChannel / EventChannel
┌───────────────────────────▼─────────────────────────────┐
│  Native：ExoPlayer / AVPlayer / libmpv / HTML5           │
└─────────────────────────────────────────────────────────┘

XueHuaNaviteVideoPlayer.instance
  └── MediaProbe（时长探测 / 封面抽取，不占用播放会话）
```

| 概念 | 含义 |
|------|------|
| **VideoSource** | 密封来源模型（network / file / asset），解析为原生可消费 URL |
| **PlayState** | 高层播放状态，由 `PlaybackSession` 维护 |
| **PlayerBackend** | 会话传输接口：create / open / play / pause / seek / volume / speed / snapshot 等 |
| **PlaybackSession** | 管理 open → ready → playing / paused / stopped / completed / error |
| **VideoPlayerController** | 面向应用与 UI 的稳定公开 API |
| **MediaProbe** | 不创建播放会话的探测能力（时长、封面） |

更细的领域说明见仓库内 [CONTEXT.md](CONTEXT.md)。

---

## 安装

在应用的 `pubspec.yaml` 中加入：

```yaml
dependencies:
  xue_hua_navite_video_player: ^1.0.1
```

然后执行：

```bash
flutter pub get
```

引入：

```dart
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';
```

公开导出主要包括：`VideoSource`、`VideoPlayerController`、`VideoPlayer`、`CorePlayer`、`VideoPlayerTheme`、`PlayState`、`AspectRatioMode`、`SkipSecondType`、`VideoCoverFrame`、`XueHuaNaviteVideoPlayer`，以及 `XFile`（来自 `cross_file`）。

---

## 平台配置

### Android

在 `android/app/src/main/AndroidManifest.xml` 中确保具备网络权限（播放网络资源时）：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS

一般无需额外权限即可播放 HTTPS 资源。若需访问明文 HTTP，请在 `Info.plist` 中按需配置 App Transport Security（不推荐生产环境放开全部 HTTP）。

本地文件需保证沙盒路径可读。

### macOS

网络播放需在 `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 中加入：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

若需访问用户选中的文件以外的路径，还需配置相应的文件访问 entitlement。

### Linux

需安装 libmpv 开发库，以便编译与运行：

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev

# Fedora
sudo dnf install mpv-libs-devel

# Arch
sudo pacman -S mpv
```

### Windows

插件通过 libmpv 软件渲染。请确保运行环境能加载对应的 mpv 动态库（随插件 / 构建配置提供）。若播放失败，优先检查本机是否缺少 mpv 运行时依赖。

### Web

使用 HTML5 `<video>`。注意：

- 跨域视频需目标服务器提供正确的 CORS 头，否则可能无法播放或无法截图
- 部分浏览器对自动播放有策略限制（通常需要用户手势后才能出声播放）

---

## 快速开始

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_navite_video_player/xue_hua_navite_video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await XueHuaNaviteVideoPlayer.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final VideoPlayerController _controller = VideoPlayerController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _controller.initialize();
    await _controller.playNetwork('https://example.com/video.mp4');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        extensions: const [
          VideoPlayerTheme(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
        ],
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayer(
          controller: _controller,
          fill: true,
          onClose: () {},
        ),
      ),
    );
  }
}
```

`XueHuaNaviteVideoPlayer.instance.initialize()` 是幂等的轻量初始化（确保 Flutter binding 就绪）。真正创建原生播放器的是 `VideoPlayerController.initialize()`。

---

## 重要约束：单一活跃会话

插件在进程内通过全局 MethodChannel / EventChannel **只挂载一个原生播放器**。

这意味着：

- 不要把多个 `VideoPlayerController` 当成可并行、互不干扰的独立播放器
- 后一次 `open` / `play*` 会接管同一原生会话
- 页面切换时务必在旧页面 `dispose()` 控制器，再在新页面创建并 `initialize()`

若业务需要「画中画 + 后台列表预览」等多实例并发，当前版本**不支持**；请在产品层串行复用同一会话，或等待后续多实例方案。

---

## 媒体来源 VideoSource

`VideoSource` 是密封类型，三种实现：

| 类型 | 工厂 | 说明 |
|------|------|------|
| `NetworkVideoSource` | `VideoSource.network(url)` | HTTP(S) URL，原生直连 |
| `FileVideoSource` | `VideoSource.file(path)` | 绝对路径或 `file://` URI |
| `AssetVideoSource` | `VideoSource.asset(path)` | Flutter asset，首次使用时抽取到临时目录 |

```dart
final network = VideoSource.network('https://example.com/a.mp4');
final file = VideoSource.file('/absolute/path/to/movie.mp4');
final asset = VideoSource.asset('assets/videos/intro.mp4');

// 解析为原生可播放 URL（asset 会触发抽取）
final nativeUrl = await network.resolveToNativeUrl();
```

使用 asset 时，请在应用 `pubspec.yaml` 中声明：

```yaml
flutter:
  assets:
    - assets/videos/intro.mp4
```

网络资源由原生播放器直接打开原始 URL。

---

## 控制器 VideoPlayerController

### 生命周期

```dart
final controller = VideoPlayerController();
await controller.initialize(); // 创建原生会话并订阅事件
// ... 播放控制 ...
await controller.dispose();    // 释放原生资源；之后不可再用
controller.reset();            // 重置 Dart 侧状态（不销毁会话）
```

构造时可注入测试用依赖（一般应用无需关心）：

```dart
VideoPlayerController({
  PlayerBackend? backend,
  FullscreenCoordinator? fullscreen,
  BrightnessController? brightness,
});
```

### 打开与播放

| API | 行为 |
|-----|------|
| `playNetwork(url)` | 打开网络源并开始播放 |
| `openNetwork(url)` | 仅打开，不自动开播 |
| `playFile(path)` / `openFile(path)` | 本地文件 |
| `playAsset(path, {bundle})` / `openAsset(...)` | Flutter asset |
| `playSource(source)` / `openSource(source)` | 通用入口 |
| `play()` / `pause()` / `playOrPause()` | 播放控制 |
| `stop()` | 主动停止（区别于播完） |
| `seek(position)` | 跳转到指定位置 |
| `seekForward()` / `seekBackward()` | 按 `skipSecondType` 步进 |

```dart
// 打开后手动开播
await controller.openNetwork('https://example.com/video.mp4');
await controller.play();

// 或一步到位
await controller.playSource(VideoSource.file('/tmp/a.mp4'));
```

### 音量、静音、倍速、亮度

```dart
await controller.setVolume(0.8);      // 0.0 – 1.0
await controller.setMuted(true);
await controller.toggleMuted();
await controller.setSpeed(1.5);       // 内置菜单提供 0.5 / 1.0 / 1.25 / 1.5 / 2.0
await controller.setBrightness(0.6);  // 0.0 – 1.0（屏幕亮度，移动端手势常用）
```

### 跳过步进与画面模式

```dart
controller.setSkipSecondType(SkipSecondType.second15);
// second5 / second10 / second15 / second30 / second45 / second60

await controller.setAspectRatioMode(AspectRatioMode.fill);
// fit：适应留边 | fill：等比裁切铺满 | stretch：拉伸填满
```

### 全屏

```dart
await controller.enterFullscreen();
await controller.exitFullscreen();
await controller.toggleFullscreen();
```

详见 [全屏契约](#全屏契约)。

### 截图

```dart
final XFile png = await controller.takeSnapshot();
// 可选：指定保存路径
final XFile saved = await controller.takeSnapshot(savePath: '/tmp/frame.png');
```

### 响应式 Signals

控制器通过 Signals 暴露状态，可用 `SignalBuilder` / `effect` / `watch` 等订阅：

| Signal / Computed | 类型 | 含义 |
|-------------------|------|------|
| `playState` | `PlayState` | 播放状态 |
| `position` / `duration` | `Duration` | 进度与总时长 |
| `volume` / `speed` | `double` | 音量与倍速 |
| `isBuffering` | `bool` | 是否缓冲中 |
| `errorMessage` | `String?` | 错误信息 |
| `currentUrl` | `String?` | 当前原生 URL |
| `mimeType` | `String?` | MIME 类型 |
| `videoSize` | `Size` | 视频尺寸 |
| `rotationDegrees` | `int` | 旋转角度 |
| `videoAspectRatio` | `double` | 考虑旋转后的宽高比 |
| `isVideo` / `isAudio` | `bool` | 根据 mime 推断 |
| `isPlaying` | `bool` | 是否正在播放 |
| `progressPercent` | `double` | 0.0 – 1.0 |
| `muted` | `bool` | 是否静音 |
| `skipSecondType` | `SkipSecondType` | 跳过步进 |
| `aspectRatioMode` | `AspectRatioMode` | 画面模式 |
| `isFullscreen` | `bool` | 是否全屏 |
| `brightness` | `double` | 屏幕亮度 |
| `textureId` | `int?` | Texture 平台的纹理 ID |

```dart
SignalBuilder(
  builder: (context) {
    final state = controller.playState.value;
    final pos = controller.position.value;
    return Text('${state.name}  ${pos.inSeconds}s');
  },
);
```

---

## 播放状态 PlayState

```dart
enum PlayState { idle, loading, playing, paused, stopped, completed, error }
```

| 状态 | 含义 |
|------|------|
| `idle` | 初始 / 重置后 |
| `loading` | 打开媒体、准备中 |
| `playing` | 正在播放 |
| `paused` | 已暂停 |
| `stopped` | 调用 `stop()` 主动停止 |
| `completed` | 自然播放到结尾（UI 可显示重播） |
| `error` | 出错，见 `errorMessage` |

`isBuffering` 可与上述状态叠加（例如 `playing` + buffering）。

---

## UI 组件

### `CorePlayer` — 纯画面

只渲染原生画面与加载 / 缓冲 / 错误态，适合完全自定义控件层。

```dart
CorePlayer(
  controller: controller,
  aspectRatio: 16 / 9,          // 可选；默认取视频上报比例，否则 16:9
  backgroundColor: Colors.black,
  loadingBuilder: (context) => const CircularProgressIndicator(),
  errorBuilder: (context, message) => Text(message ?? 'Error'),
);
```

> 仅使用 `CorePlayer` 时，调用 `enterFullscreen()` **只会**改变系统方向 / 沉浸式 UI，**不会**出现边缘到边缘的视觉全屏 Overlay。

### `VideoPlayer` — 完整控件

带顶部栏、中央传输控件、底部进度条的即用型播放器。点击画面可显隐控件；播放中默认约 3 秒自动隐藏。

```dart
VideoPlayer(
  controller: controller,
  fill: true,                                    // 铺满父布局
  aspectRatio: null,                             // 可选固定比例
  autoHideDelay: const Duration(seconds: 3),
  fadeDuration: const Duration(milliseconds: 250),
  initiallyVisible: true,
  onClose: () => Navigator.pop(context),
  leading: null,                                 // 默认关闭按钮
  title: const Text('标题'),
  actions: const [],                             // 顶部右侧操作
  showAspectRatioMenu: true,
  enableFullscreen: true,
  skipSecondType: SkipSecondType.second10,
  // 自定义槽位：
  // topBarBuilder / centerControlsBuilder /
  // bottomScrubberBuilder / extraOverlayBuilder
  // errorBuilder / loadingBuilder
);
```

#### 自定义槽位

槽位 builder 会收到 `VideoPlayerSlotContext`：

```dart
class VideoPlayerSlotContext {
  final VideoPlayerController controller;
  final VideoPlayerTheme theme;
  final VoidCallback showControls;
  final VoidCallback hideControls;
}
```

示例：替换底部进度条区域：

```dart
VideoPlayer(
  controller: controller,
  bottomScrubberBuilder: (context, slot) {
    return PlayerScrubberSlider(controller: slot.controller);
  },
);
```

#### 视觉全屏

`VideoPlayer` 通过 `OverlayPortal` 将同一路画面挂到根 `Overlay`：

- 进入全屏时抑制树内画面，由 Overlay 宿主单独展示
- PlatformView 会迁移，而不是简单销毁再重建（仍可能发生 remount）
- 请在已挂载 `VideoPlayer` 且存在 `Overlay` 祖先时调用 `controller.toggleFullscreen()`

---

## 主题 VideoPlayerTheme

通过 `ThemeData.extensions` 注册。未配置时使用内置默认外观。

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const [
      VideoPlayerTheme(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        chromeIconSize: 22,
        scrubberActiveColor: Colors.white,
        menuBackgroundColor: Color(0xF01A1A1A),
        // 另见：centerPlayButtonIconSize、hudTextStyle、
        // scrubberTrackHeight、topBarPadding …
      ),
    ],
  ),
);
```

常用字段分组：

| 分组 | 字段示例 |
|------|----------|
| 基础色 | `foregroundColor`、`backgroundColor` |
| 中央控件 | `centerControlsSpacing`、`centerPlayButtonIconSize`、`centerSkipButtonIconSize`、`centerButtonBackgroundColor` |
| 顶栏 / 底栏 | `chromeIconSize`、`topBarPadding`、`bottomBarPadding`、`timeTextStyle` |
| 进度条 | `scrubberActiveColor`、`scrubberBufferedColor`、`scrubberInactiveColor`、`scrubberThumbColor`、轨道/滑块尺寸 |
| 菜单 | `menuBackgroundColor`、`menuBorderRadius`、`menuItemTextStyle`、`menuIconSize` |
| 手势 HUD | `hudBackgroundColor`、`hudBorderRadius`、`hudPadding`、`hudIconSize`、`hudTextStyle` |

在子树中读取：

```dart
final theme = VideoPlayerTheme.of(context);
```

---

## 全屏契约

```dart
await controller.enterFullscreen(); // 更新 isFullscreen + 系统 UI / 方向
await controller.exitFullscreen();
```

| 调用场景 | 效果 |
|----------|------|
| 已挂载 `VideoPlayer`，且存在 `Overlay` 祖先 | 方向 / 沉浸式 UI **以及** 铺满的视觉全屏 Overlay |
| 仅控制器，或只有 `CorePlayer` | 仅方向 / 沉浸式 UI，**无**视觉全屏宿主 |

方向策略会参考 `videoAspectRatio`（横竖屏视频选择合适的 `preferredOrientations`）。

手势（移动端）仅在 **全屏且 `VideoPlayer` 已挂载** 时生效。快捷键（桌面 / Web）在全屏或非全屏下均可使用，需 **`VideoPlayer` 已挂载且获得焦点**（点击播放器区域即可）。

---

## 手势与快捷键

### 移动端（全屏）

| 手势 | 区域 | 作用 |
|------|------|------|
| 水平滑动 | 任意（超过阈值） | 快进 / 快退（幅度受 `skipSecondType` 影响） |
| 垂直滑动 | 左侧约 40% | 调节屏幕亮度 |
| 垂直滑动 | 右侧约 40% | 调节音量 |
| 单击 | — | 显隐控件 |

手势过程中会显示 HUD（亮度 / 音量 / 跳转秒数）。

### 桌面 / Web（已聚焦 — 全屏或非全屏）

| 按键 | 作用 |
|------|------|
| `Space` | 播放 / 暂停 |
| `←` / `→` | 按步进后退 / 前进 |
| `↑` / `↓` | 音量 ±0.05 |

---

## 截图与媒体探测

### 当前帧截图

```dart
final XFile png = await controller.takeSnapshot();
```

- **iOS / macOS**：在当前播放时间点用 `AVAssetImageGenerator` 取帧（画面由 `AVPlayerLayer` PlatformView 显示，不依赖 Texture 推帧）
- **其他平台**：走各自原生截图路径
- 返回 PNG 格式的 `XFile`（已由 barrel 文件 re-export，无需单独依赖 `cross_file`）

### 封面候选帧（无需起播）

```dart
final frames = await XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,
  minBrightness: 0.08, // 过滤过暗 / 纯黑帧
  // outputDir: '/tmp/covers', // 可选输出目录
);

for (final frame in frames) {
  // frame.image      → XFile（PNG）
  // frame.position   → 帧时间戳
  // frame.brightness → 0.0 – 1.0 平均亮度
}
```

原生平台上 `XFile.path` 为真实文件路径；Web 上可能是 blob / data URL。

### 探测时长（无需起播）

```dart
final duration = await XueHuaNaviteVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
  timeout: const Duration(seconds: 15),
);
// 失败、超时或非有限时长（如直播）时返回 null
```

探测走 `MediaProbe`，**不占用**当前播放会话的原生播放器状态机（与 transport 共享部分底层通道能力，但 API 独立）。

---

## 自定义 UI（Signals）

若内置 `VideoPlayer` 不满足需求，可用 `CorePlayer` + 控制器 Signals 自建控件：

```dart
class MyPlayer extends StatelessWidget {
  const MyPlayer({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: CorePlayer(controller: controller)),
        SignalBuilder(
          builder: (context) {
            final playing = controller.isPlaying.value;
            return IconButton(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: controller.playOrPause,
            );
          },
        ),
      ],
    );
  }
}
```

进度条也可直接使用导出的 `PlayerScrubberSlider`：

```dart
PlayerScrubberSlider(controller: controller);
```

---

## 示例应用

仓库 [`example/`](example/) 提供完整演示，包括：

- 网络播放列表
- 内置 `VideoPlayer` UI 与主题
- 全屏切换
- 截图预览
- 封面候选帧抽取
- 播放状态展示

运行：

```bash
cd example
flutter run
```

---

## 常见问题

### 为什么同时创建两个控制器，第二个会打断第一个？

这是设计约束：进程内只有一个原生播放会话。请串行复用，并在页面销毁时 `dispose()`。

### 全屏后画面没有铺满？

确认：

1. 使用的是 `VideoPlayer`（不是单独的 `CorePlayer`）
2. 组件已挂载，且祖先树中有 `Overlay`（`MaterialApp` 默认提供）
3. 通过 `controller.enterFullscreen()` / `toggleFullscreen()` 进入

### Asset 播放失败？

检查 `pubspec.yaml` 是否声明了对应 asset，且 `playAsset` / `VideoSource.asset` 的路径与声明一致。首次播放会抽取到临时目录，需有写入权限。

### Linux 编译报找不到 mpv？

安装 `libmpv-dev`（或发行版对应包），见 [平台配置 · Linux](#linux)。

### Web 上无法截图或黑屏？

检查视频 URL 的 CORS 配置，以及浏览器是否允许对跨域媒体做像素读取。

### `initialize()` 要调几次？

- `XueHuaNaviteVideoPlayer.instance.initialize()`：可选、幂等，通常在 `main` 调一次
- `VideoPlayerController.initialize()`：每个控制器生命周期调一次；`dispose()` 后不可再使用同一实例

---

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。
