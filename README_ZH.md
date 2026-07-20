# xue_hua_navite_video_player

[English](README.md)

跨平台 Flutter 音视频播放插件，基于原生引擎（ExoPlayer、AVPlayer、libmpv、HTML5）。

## 功能

- **原生渲染** — PlatformView（Android / iOS / macOS）或 Texture（Linux / Windows / Web HTML5）
- **六端支持** — Android、iOS、macOS、Linux、Windows、Web
- **内置 UI** — 开箱即用的 `VideoPlayer` / `CorePlayer` 与主题
- **多来源** — 网络 URL、本地文件、Flutter asset
- **播放控制** — 播放、暂停、跳转、静音、画面模式、音量、倍速菜单、亮度、截图
- **全屏** — 控制器负责方向 / 沉浸式系统 UI；视觉全屏 Overlay 需挂载 `VideoPlayer`
- **工具能力** — 封面候选帧抽取、无需起播即可探测时长

## 平台引擎

| 平台    | 原生引擎                    |
|---------|-----------------------------|
| Android | ExoPlayer (Media3)          |
| iOS     | AVPlayer                    |
| macOS   | AVPlayer                    |
| Linux   | libmpv（软件渲染）          |
| Windows | libmpv（软件渲染）          |
| Web     | HTML5 `<video>`             |

## 快速开始

### 安装

```yaml
dependencies:
  xue_hua_navite_video_player: ^lasted
```

### 平台配置

#### Android

确保具备网络权限：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

#### macOS

在 `macos/Runner/Release.entitlements` 与 `DebugProfile.entitlements` 中加入：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

#### Linux

安装 libmpv 开发库：

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev
# Fedora
sudo dnf install mpv-libs-devel
# Arch
sudo pacman -S mpv
```

### 最小示例

```dart
await XueHuaNaviteVideoPlayer.instance.initialize();

final controller = VideoPlayerController();
await controller.initialize();
await controller.playNetwork('https://example.com/video.mp4');

VideoPlayer(controller: controller);
```

> **单一活跃会话：** 插件在全局 channel 后只挂一个原生播放器。不要把多个 `VideoPlayerController` 当成可并行的独立实例。

## 组件

### `CorePlayer` — 纯画面

只渲染原生画面与加载/缓冲/错误态，适合完全自定义 UI。

### `VideoPlayer` — 完整控件

带顶部栏、中央控制区与底部进度条的即用型播放器。

`VideoPlayer` 负责**视觉全屏**：将同一路画面通过 `OverlayPortal` 挂到根 Overlay，
PlatformView 会迁移而不是销毁重建。请在挂载本组件时调用
`controller.toggleFullscreen()`。

### 主题

在 `ThemeData.extensions` 中注册 `VideoPlayerTheme`。播放器控件的视觉样式
（颜色、图标尺寸、菜单 / 手势 HUD / 进度条外观）均从此扩展读取；未配置时使用
内置默认外观。

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const [
      VideoPlayerTheme(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        // 可选：chromeIconSize、menuBackgroundColor、hudTextStyle 等
      ),
    ],
  ),
  home: …,
);
```

## 全屏契约

```dart
await controller.enterFullscreen(); // 系统 UI + isFullscreen
await controller.exitFullscreen();
```

| 调用场景 | 效果 |
|----------|------|
| 已挂载 `VideoPlayer` 且存在 `Overlay` 祖先 | 方向 / 沉浸式 UI **以及** 铺满 Overlay 画面 |
| 仅控制器或 `CorePlayer` | 仅方向 / 沉浸式 UI，无视觉全屏宿主 |

手势（移动端）与快捷键（桌面端）仅在全屏且 `VideoPlayer` 已挂载时生效。

## 播放来源

```dart
await controller.playNetwork('https://example.com/video.mp4');
await controller.openNetwork('https://example.com/video.mp4');
await controller.play();

await controller.playFile('/absolute/path/to/movie.mp4');
await controller.playAsset('assets/videos/intro.mp4');
await controller.playSource(VideoSource.network('https://...'));
```

使用 `playAsset` 时在应用 `pubspec.yaml` 中声明资源：

```yaml
flutter:
  assets:
    - assets/videos/intro.mp4
```

## 截图与封面

```dart
final XFile png = await controller.takeSnapshot();
```

**iOS / macOS** 在当前播放时间点用 `AVAssetImageGenerator` 取帧（画面由
`AVPlayerLayer` PlatformView 显示，不依赖 Texture 推帧）。其他平台走各自原生截图路径。

```dart
final frames = await XueHuaNaviteVideoPlayer.instance.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,
);
```

## 探测时长

```dart
final duration = await XueHuaNaviteVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
);
```

失败、超时或非有限时长（如直播）时返回 `null`。

## 示例

见 [example](example/) 目录。

## 许可证

详见 [LICENSE](LICENSE)。
