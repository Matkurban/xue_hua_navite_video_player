# `xue_hua_navite_video_player` 全端无线投屏（Casting）架构与详细设计文档

> **文档状态**：已实现  
> **适用版本**：`xue_hua_navite_video_player` `0.0.1+`  
> **覆盖平台**：iOS、macOS、Android、Web、Windows、Linux（全 6 端）

---

## 1. 背景与设计目标

`xue_hua_navite_video_player` 当前通过单活动会话（Single Active Native Session）模型，为 6 个平台提供统一的播放控制、响应式状态（基于 `signals_flutter`）与开箱即用的 UI 组件（`CorePlayer` / `VideoPlayer`）。

本次新增**无线投屏（Wireless Casting）**功能的核心目标如下：

1. **全端覆盖与官方原生优先**：优先采用各操作系统/浏览器官方提供的投屏框架与系统级原生设备选择器（Route Picker），避免在 Dart 层维护脆弱的自定义设备扫描弹窗。
2. **完整的投屏状态机闭环**：精确处理投屏全生命周期状态（不可用、未连接、连接中、已连接投屏、断开恢复中），保证本地与远端播放进度、播放/暂停、倍速、音量、缓冲、完成及错误状态的无缝同步。
3. **跨源支持（网络视频 + 本地/Asset 视频）**：原生支持 `VideoSource.network` 直投；针对不支持直接读取本机文件路径的投屏接收端（如 Android Google Cast），提供可选的插件内置轻量级局域网 HTTP Range 媒体代理服务，实现 `VideoSource.file` 与 `VideoSource.asset` 投屏。
4. **符合直觉的生命周期与交互行为**：
   - 投屏连接时自动携带当前播放进度（Seek 续播）。
   - 投屏期间切换视频源（如切集 `playNetwork`）直接在远端设备无缝加载新视频，不中断投屏会话。
   - 投屏期间 App 退至后台或锁屏**不中断**远端播放。
   - 远端断开（用户在电视端退出或手机端点击“退出投屏”）时，将远端最新进度同步回本地播放器并自动保持**暂停（Paused）**状态，避免手机扬声器突然外放。

---

## 2. 全端技术选型总览

各平台底层引擎不同，对应的官方投屏协议、系统原生选择器及媒体源支持能力汇总如下：

| 平台 | 现有本地播放引擎 | 官方投屏技术栈 | 系统原生选择器组件 | 网络源 (`http/https`) | 本地源 (`file/asset`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **iOS** | `AVPlayer` + `AVPlayerLayer` | `AVKit` / `AVFoundation` **AirPlay** (`allowsExternalPlayback`) | `AVRoutePickerView`（系统 AirPlay 浮层） | 原生直投 | `AVPlayer` 原生支持本地 MP4/MOV AirPlay 流式传输（辅以 LAN HTTP 兜底） |
| **macOS** | `AVPlayer` + `AVPlayerLayer` | `AVKit` / `AVFoundation` **AirPlay** (`allowsExternalPlayback`) | `AVRoutePickerView`（系统 AirPlay 气泡菜单） | 原生直投 | `AVPlayer` 原生支持（辅以 LAN HTTP 兜底） |
| **Android** | Media3 `ExoPlayer` + `PlayerView` | `androidx.media3:media3-cast` (**Google Cast** `CastPlayer`) + `MediaRouter` | `MediaRouteChooserDialog` / `MediaRouteControllerDialog` | 原生直投 | 通过插件内置 `LocalCastHttpServer` 转换为局域网 HTTP Range 流投送 |
| **Web** | HTML5 `<video>` | W3C **Remote Playback API** (`video.remote`) + Safari `webkitShowPlaybackTargetPicker` | `video.remote.prompt()`（浏览器原生 Cast / AirPlay 弹窗） | 原生直投 | `AssetVideoSource` 为 HTTP 相对路径可直投；本地 `blob:` 视浏览器支持降级为仅网络源 |
| **Windows** | `libmpv` + `PixelBufferTexture` | WinRT `Windows.Media.Casting` (**Miracast / DLNA / UPnP**) | `CastingDevicePicker.Show(Rect)`（Windows 原生设备浮层） | 原生直投 | WinRT `MediaSource` 原生支持本地文件流式传输（辅以 LAN HTTP 兜底） |
| **Linux** | `libmpv` + `FlPixelBufferTexture` | `GUPnP AV` (**DLNA / UPnP** `MediaRenderer`) 或 `xdg-desktop-portal` | 原生 `GtkDialog` 设备选择器（绑定主 `GtkWindow`） | 原生直投 | 通过插件内置 `LocalCastHttpServer` 转换为局域网 HTTP Range 流投送 |

> **实施分期建议**：
> - **第一阶段（P0）**：打通全端通道契约、状态机、UI 投屏遮罩，完成 **iOS / macOS / Android / Web / Windows** 官方原生选择器与网络视频（及 Apple/Windows 原生本地视频）投屏；Linux 提供基于 GUPnP 的可选编译支持及安全能力探测降级。
> - **第二阶段（P1）**：接入纯 Dart 实现的 `LocalCastHttpServer`（约 120 行，基于 `dart:io` `HttpServer` 支持 `206 Partial Content`），使 Android Google Cast 与 Linux DLNA 同样完整支持 `VideoSource.file` 与 `VideoSource.asset`。

---

## 3. 架构分层设计

插件延续现有的三层架构，不破坏单活动会话（Single Active Session）不变量：

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              UI Layer                                   │
│  VideoPlayer (_DefaultTopBar 投屏按钮) + CorePlayer (_CastingOverlay)   │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ Signals & Commands
┌───────────────────────────────────▼─────────────────────────────────────┐
│                          Controller & Session                           │
│  VideoPlayerController ──► PlaybackSession                              │
│  - Signals: castState, castDeviceName, isCasting, isCastSupported       │
│  - Handover: openSource 投屏态保活、LocalCastHttpServer 生命周期管理     │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ PlayerBackend / PlayerEvent
┌───────────────────────────────────▼─────────────────────────────────────┐
│                        Channel Transport Seam                           │
│  ChannelPlayerBackend                                                   │
│  - Methods: showCastPicker, stopCasting                                 │
│  - Events:  PlayerCastStateEvent(state, deviceName)                     │
└─────────┬─────────────┬─────────────┬─────────────┬───────────┬─────────┘
          │             │             │             │           │
     ┌────▼───┐    ┌────▼────┐   ┌────▼────┐   ┌────▼───┐  ┌────▼────────┐
     │iOS/mac │    │ Android │   │   Web   │   │Windows │  │    Linux    │
     │AirPlay │    │CastPlayr│   │.remote  │   │WinRT   │  │GUPnP/Portal │
     └────────┘    └─────────┘   └─────────┘   └────────┘  └─────────────┘
```

---

## 4. Dart 层模型与 API 设计

### 4.1 新增枚举：`CastState`

文件路径：`lib/src/data/enums/cast_state.dart`（并在 `lib/xue_hua_navite_video_player.dart` 导出）

```dart
/// 无线投屏连接状态。
enum CastState {
  /// 当前平台、运行环境（如无 GMS 服务）或当前媒体源不支持投屏。
  unavailable,

  /// 支持投屏且当前处于本地播放状态（可发起投屏）。
  notConnected,

  /// 用户已在系统选择器中选中设备，正在握手建立会话或加载远端媒体。
  connecting,

  /// 已成功连接远端设备，正在远端投屏播放。
  connected,

  /// 正在断开投屏并将播放进度切回本地播放器。
  disconnecting;

  String get wireName => name;

  static CastState fromWire(String? raw) {
    return switch (raw) {
      'notConnected' => CastState.notConnected,
      'connecting' => CastState.connecting,
      'connected' => CastState.connected,
      'disconnecting' => CastState.disconnecting,
      _ => CastState.unavailable,
    };
  }
}
```

### 4.2 扩展传输事件：`PlayerEvent`

在 [`lib/src/player/player_event.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/player/player_event.dart) 中新增 `PlayerCastStateEvent`：

```dart
sealed class PlayerEvent {
  // ... 现有事件 ...
  const factory PlayerEvent.castState(
    CastState state, {
    String? deviceName,
  }) = PlayerCastStateEvent;
}

final class PlayerCastStateEvent extends PlayerEvent {
  const PlayerCastStateEvent(this.state, {this.deviceName});
  final CastState state;
  final String? deviceName;
}
```

### 4.3 扩展后端接口：`PlayerBackend` 与 `ChannelPlayerBackend`

在 [`lib/src/player/player_backend.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/player/player_backend.dart) 中新增投屏控制方法：

```dart
abstract class PlayerBackend {
  // ... 现有方法 ...

  /// 调起系统原生投屏设备选择器（AirPlay RoutePicker / Cast Dialog / RemotePlayback Prompt / WinRT Picker）。
  Future<void> showCastPicker();

  /// 主动断开当前投屏会话，并将播放进度切回本地播放器。
  Future<void> stopCasting();
}
```

在 [`lib/src/player/channel_player_backend.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/player/channel_player_backend.dart) 的 `_decodeEvent` 中新增解码分支：

```dart
case 'castState':
  final value = event['value'];
  if (value is Map) {
    final state = CastState.fromWire(value['state'] as String?);
    final deviceName = value['deviceName'] as String?;
    return PlayerEvent.castState(state, deviceName: deviceName);
  }
  if (value is String) {
    return PlayerEvent.castState(CastState.fromWire(value));
  }
  return null;
```

### 4.4 `PlaybackSession` 与 `VideoPlayerController` 响应式状态与方法

在 [`lib/src/player/playback_session.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/player/playback_session.dart) 与 [`lib/src/player/video_player_controller.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/player/video_player_controller.dart) 中暴露：

```dart
/// 当前投屏连接状态。
final FlutterSignal<CastState> castState = signal(CastState.unavailable);

/// 当前已连接（或正在连接）的投屏设备名称（如 "客厅 Apple TV"、"Living Room TV"）。
final FlutterSignal<String?> castDeviceName = signal<String?>(null);

/// 当前环境是否支持投屏（用于控制 UI 是否显示/启用投屏按钮）。
late final FlutterComputed<bool> isCastSupported = computed(() {
  return castState.value != CastState.unavailable;
});

/// 是否正处于投屏模式（含连接中与已连接）。
late final FlutterComputed<bool> isCasting = computed(() {
  final s = castState.value;
  return s == CastState.connecting || s == CastState.connected;
});

/// 调起系统原生投屏选择器。
Future<void> showCastPicker();

/// 退出投屏并恢复到本地播放器。
Future<void> stopCasting();
```

---

## 5. 投屏状态机与核心边界场景处理

为了满足“**正确处理投屏后的各种状态**”的要求，插件在 `PlaybackSession` 与各平台 Native 层共同遵循以下状态机与边界规则：

### 5.1 投屏完整状态流转图

```
                   (探测到系统支持投屏 / 发现可用路由)
  [unavailable] ───────────────────────────────────────► [notConnected]
                                                           │        ▲
                          用户在原生选择器选中远端设备     │        │ 远端断开 / 调用 stopCasting()
                          (触发本地暂停 + 携带进度建连)    ▼        │ (同步远端进度回本地 + 本地保持 paused)
                                                         [connecting]
                                                           │        ▲
                                  远端播放器准备就绪       │        │
                                                           ▼        │
                                                         [connected] ──► [disconnecting]
```

### 5.2 八大核心状态与边界场景规范

#### 场景 1：本地播放切入投屏（Local → Remote Handover）
1. 用户点击投屏按钮调用 `showCastPicker()`，弹出操作系统原生选择器（此时本地播放不中断）。
2. 用户在系统选择器中点选目标设备后：
   - Native 层立即上报 `castState(connecting, deviceName)`。
   - 记录当前本地播放器的 `positionMs`、`isPlaying`（`wantsToPlay`）、`volume`、`speed`。
   - **暂停本地解码渲染**（Android 暂停 `ExoPlayer` 并解绑本地 Surface；Windows 暂停 `MpvPlayer`；iOS/macOS `AVPlayer` 由系统自动暂停本地 `AVPlayerLayer` 画面渲染并接管至 AirPlay）。
   - 远端播放器加载当前 URL 并自动 `seekTo(positionMs)`，若此前处于播放状态则自动开始远端播放。
   - 远端就绪后上报 `castState(connected, deviceName)`，同时继续通过统一事件通道上报 `playing`、`buffering`、`position`、`duration`。

#### 场景 2：投屏期间的常规控制（Play / Pause / Seek / Volume / Speed）
- 当 `castState == CastState.connected` 时，Dart 层调用 `play()`、`pause()`、`seek()`、`setVolume()`、`setMuted()`、`setSpeed()` 保持原有 API 不变。
- Native 层根据当前是否处于投屏态，将指令路由至活动播放器（如 Android 的 `activePlayer: Player`、Windows 的 `winrt_cast_player_`、iOS/macOS 的 `AVPlayer`、Web 的 `HTMLVideoElement`）。
- 远端播放进度通过 200ms–500ms 周期定时器持续向 Dart 发送 `position` 事件，保证底部进度条平滑走字。

#### 场景 3：投屏期间切换视频源 / 切集（`openSource` while Casting）
- **现有代码注意点**：在 [`PlaybackSession.openSource`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/player/playback_session.dart) 中，每次打开新视频都会先调用 `reset()`。
- **投屏态设计**：
  - `PlaybackSession.reset()` **仅重置单集媒体状态**（`playState`、`position`、`duration`、`isBuffering`、`errorMessage`、`videoSize`），**绝不重置 `castState` 和 `castDeviceName`**。
  - Native 层的 `open(url)` 在检测到当前已处于投屏连接状态时，**不销毁投屏会话**，而是直接在当前已连接的远端会话上替换媒体项（例如 Android `castPlayer.setMediaItem(newItem)`、iOS/macOS 在保留 `allowsExternalPlayback` 的同一个 `AVPlayer` 实例上调用 `replaceCurrentItem(with: newItem)` 而非销毁 `AVPlayer` 重建）。
  - 这样用户在投屏看剧时点击“下一集”，电视端直接无缝加载下一集，无需重新选择投屏设备。

#### 场景 4：投屏期间 App 退至后台或手机锁屏（Background & Lock Screen）
- **现有代码问题**：
  - iOS [`XueHuaNaviteVideoPlayerPlugin.swift`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/ios/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.swift) 监听了 `UIApplication.didEnterBackgroundNotification` 并无条件调用 `self?.videoPlayer?.pause()`。
  - Android [`XueHuaNaviteVideoPlayerPlugin.kt`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/android/src/main/kotlin/com/kurban/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.kt) 在 `onStop(owner: LifecycleOwner)` 中无条件暂停 `exoPlayer`。
- **投屏态设计**：
  - **iOS**：在 `didEnterBackgroundNotification` 回调中检查 `player?.isExternalPlaybackActive == true`，若正在 AirPlay 投屏则**跳过 `pause()`**，保证锁屏后电视继续播放。
  - **Android**：在 `onStop()` 中仅当 `activePlayer === exoPlayer`（即本地播放）时执行暂停；若当前 `activePlayer === castPlayer`（正在投屏），保持远端播放不暂停。

#### 场景 5：退出投屏与意外断连恢复（Remote → Local Handover）
无论是用户点击 UI 上的“退出投屏”按钮（调用 `stopCasting()`）、在系统选择器中切回“iPhone / 此设备”，还是电视关机导致网络断开：
1. Native 层捕获远端最后一次有效播放位置 `lastRemotePositionMs`。
2. 本地播放器加载当前媒体并 `seek(lastRemotePositionMs)`。
3. **强制保持本地暂停（`PlayState.paused`）**：投屏断开回到手机/电脑时，遵循主流播放器规范，**不自动恢复外放**，由用户手动点击播放键继续观看，防止在安静场合突然外放声音。
4. 上报 `castState(notConnected, deviceName: null)` 与 `playing(false)`、`position(lastRemotePositionMs)`。

#### 场景 6：远端播放自然结束（Remote EOS / Completed）
- 远端视频播放至末尾时，Native 层发送 `playing(false)` 与 `completed(null)`，`PlaybackSession` 转入 `PlayState.completed`，**同时保持 `castState == CastState.connected`**。
- 若此时用户点击界面中央的“重播（Replay）”按钮，`PlaybackSession.play()` 会执行 `seek(0)` + `play()`，远端电视立即从头重新播放。

#### 场景 7：投屏连接失败与播放错误区分（Cast Error vs Media Error）
- **握手/连接失败**（如电视拒绝连接或超时）：Native 层将 `castState` 回退至 `CastState.notConnected`，**不将本地 `playState` 置为 `PlayState.error`**， zodat 本地播放不受影响，可通过轻量级提示告知用户连接未成功。
- **远端媒体解码/网络错误**（已连接后远端拉流失败）：上报 `error(message)`，使 `PlaybackSession` 转入 `PlayState.error`，同时在错误视图中保留“退出投屏 / 重试”入口。

#### 场景 8：截图（`takeSnapshot`）在投屏态下的兼容
- 投屏期间本地渲染层（如 Android `PlayerView` 或 iOS `AVPlayerLayer`）可能处于黑屏或暂停状态。
- **iOS / macOS**：现有实现已使用 `AVAssetImageGenerator` 根据 `player?.currentTime()` 抽帧，投屏期间 `player.currentTime()` 依然实时反映 AirPlay 远端进度，因此**零改动即可在投屏时正常截图**。
- **Android**：当处于 `castPlayer` 投屏态时，`handleTakeSnapshot` 直接走现有的 `snapshotViaRetriever` 分支，将 `positionUs` 取自 `(activePlayer?.currentPosition ?: 0L) * 1000L`，同样可准确截取当前远端播放时间点的画面。

---

## 6. MethodChannel 与 EventChannel 协议扩展

在现有通道 `xue_hua_navite_video_player/player` 与 `xue_hua_navite_video_player/player/events` 上增量扩展，完全向后兼容：

### 6.1 新增 MethodChannel 方法（Dart → Native）

| 方法名 | 参数 | 返回值 | 说明 |
| :--- | :--- | :--- | :--- |
| `showCastPicker` | 无 | `Future<void>` | 调起当前平台的系统原生投屏设备选择器。若平台不支持则安全空操作。 |
| `stopCasting` | 无 | `Future<void>` | 主动结束当前投屏会话，将当前播放进度同步回本地播放器并暂停。 |

### 6.2 新增 EventChannel 事件（Native → Dart）

| `event` 字段 | `value` 结构 | 说明 |
| :--- | :--- | :--- |
| `"castState"` | `{"state": "unavailable" \| "notConnected" \| "connecting" \| "connected" \| "disconnecting", "deviceName": String?}` | 当系统投屏可用性变化、连接状态变化或目标设备切换时触发。在 `create` / `onListen` 时立即主动推送一次初始状态。 |

---

## 7. 各平台 Native 实现方案详解

### 7.1 iOS 端（`AVKit` AirPlay + `AVRoutePickerView`）

涉及文件：[`ios/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.swift`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/ios/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.swift)

1. **启用 AirPlay 与复用 `AVPlayer` 实例**：
   - 在 `NativeVideoPlayer` 中配置：
     ```swift
     player.allowsExternalPlayback = true
     player.usesExternalPlaybackWhileExternalScreenIsActive = true
     ```
   - **重要改造**：当前 `open(url:)` 每次调用都会 `cleanupPlayer()` 将 `player = nil` 并新建 `AVPlayer`。若正在 AirPlay 投屏，销毁 `AVPlayer` 会导致 AirPlay 断开！因此改为：**若 `player != nil && player?.isExternalPlaybackActive == true`，在 `open(url:)` 中只清理旧 `playerItem` 的 KVO，调用 `player?.replaceCurrentItem(with: newPlayerItem)`**，从而保持 AirPlay 连接不断开。
2. **调起系统原生选择器（`showCastPicker`）**：
   - 引入 `import AVKit`。
   - 在 `NativeVideoPlayer`（或 `PlayerContainerView`）中懒加载挂载一个隐藏的 `AVRoutePickerView(frame: .zero)`（`isHidden = true`, `prioritizesVideoDevices = true`）。
   - 当 Dart 调用 `showCastPicker` 时，在主线程查找 `AVRoutePickerView` 内部的 `UIButton` 子视图并触发点击：
     ```swift
     func showCastPicker() {
         DispatchQueue.main.async {
             guard let picker = self.ensureRoutePickerView() else { return }
             if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
                 button.sendActions(for: .touchUpInside)
             }
         }
     }
     ```
   - 该方式是 iOS 自定义播放器控件调起系统原生 AirPlay 面板的标准做法，弹出的是 100% Apple 官方系统级路由选择浮层。
3. **监听投屏状态与设备名称**：
   - 使用 KVO 监听 `player.observe(\.isExternalPlaybackActive, options: [.new, .initial])`。
   - 监听 `AVAudioSession.routeChangeNotification`。当 `isExternalPlaybackActive == true` 时，从 `AVAudioSession.sharedInstance().currentRoute.outputs` 中查找 `portType == .airPlay` 的输出端口，读取其 `portName`（如 `"客厅 Apple TV"`）作为 `deviceName`；若未读取到具体名称则兜底为 `"AirPlay"`。
   - iOS 端默认上报 `castState: "notConnected"`（使投屏按钮始终可用）。
4. **主动退出投屏（`stopCasting`）**：
   - 当用户点击 Flutter 界面上的“退出投屏”时：
     ```swift
     func stopCasting() {
         guard let player = player, player.isExternalPlaybackActive else { return }
         let currentTime = player.currentTime()
         player.pause()
         // 临时关闭再开启 allowsExternalPlayback 可强制系统将播放路由切回本机
         player.allowsExternalPlayback = false
         DispatchQueue.main.async { [weak self] in
             guard let self, let player = self.player else { return }
             player.allowsExternalPlayback = true
             player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
             self.emitCastState()
         }
     }
     ```

---

### 7.2 macOS 端（`AVKit` AirPlay + `AVRoutePickerView`）

涉及文件：[`macos/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.swift`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/macos/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.swift)

1. **启用 AirPlay**：
   - 引入 `import AVKit`，在 `AVPlayer` 上开启 `player.allowsExternalPlayback = true`，并在投屏态 `open(url:)` 时同样使用 `replaceCurrentItem(with:)` 保持会话。
2. **调起 macOS 原生 AirPlay 菜单（`showCastPicker`）**：
   - 在 `hostWindow()?.contentView`（或 `PlayerContainerView`）右上角挂载一个尺寸为 `1x1`、透明度 `0.01` 的 `AVRoutePickerView`（设置 `isRoutePickerButtonBordered = false`）。
   - 当收到 `showCastPicker` 调用时，遍历 `routePickerView.subviews` 找到内部 `NSButton` 并调用 `button.performClick(nil)`，即可在播放器右上角弹出 macOS 原生 AirPlay 设备选择 Popover。
3. **状态监听与退出投屏**：
   - KVO 监听 `player.observe(\.isExternalPlaybackActive)`。
   - `stopCasting()` 与 iOS 一致：先 `pause()`，再通过切换 `allowsExternalPlayback = false -> true` 将视频切回 Mac 本地窗口并保持在当前进度暂停。

---

### 7.3 Android 端（Media3 `CastPlayer` + 系统 `MediaRouteChooserDialog`）

涉及文件：
- [`android/build.gradle.kts`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/android/build.gradle.kts)
- [`android/src/main/kotlin/com/kurban/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.kt`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/android/src/main/kotlin/com/kurban/xue_hua_navite_video_player/XueHuaNaviteVideoPlayerPlugin.kt)

1. **Gradle 依赖升级**：
   在 `android/build.gradle.kts` 中与现有 Media3 `1.11.1` 版本对齐，引入官方 `media3-cast` 与 `mediarouter`：
   ```kotlin
   dependencies {
       implementation("androidx.media3:media3-exoplayer:1.11.1")
       implementation("androidx.media3:media3-common:1.11.1")
       implementation("androidx.media3:media3-ui:1.11.1")
       implementation("androidx.media3:media3-cast:1.11.1")
       implementation("androidx.mediarouter:mediarouter:1.7.0")
       implementation("com.google.android.gms:play-services-cast-framework:21.5.0")
       // ...
   }
   ```
   同时在插件自身的 `AndroidManifest.xml` 中声明默认的 `OPTIONS_PROVIDER_CLASS_NAME`（使用 `androidx.media3.cast.DefaultCastOptionsProvider`，无需宿主 App 手动编写 `OptionsProvider`，开箱即用）：
   ```xml
   <application>
       <meta-data
           android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
           android:value="androidx.media3.cast.DefaultCastOptionsProvider" />
   </application>
   ```
2. **双 `Player` 统一路由架构（`exoPlayer` + `castPlayer`）**：
   - Media3 的核心优势在于 `ExoPlayer` 与 `CastPlayer` **均实现了同一个 `androidx.media3.common.Player` 接口**。
   - 在 `XueHuaNaviteVideoPlayerPlugin` 中维护：
     - `private var exoPlayer: ExoPlayer? = null`
     - `private var castPlayer: CastPlayer? = null`
     - `private var activePlayer: Player? = null`
   - 初始化时通过 `CastContext.getSharedInstance(context, workerExecutor)` 异步获取 `CastContext`（包裹 `try-catch`，在无 GMS 的国产 ROM 上安全降级并发送 `castState("unavailable")`；若有 GMS 则初始化 `CastPlayer(castContext)` 并发送 `castState("notConnected")`）。
   - `handlePlay`、`handlePause`、`handleSeek`、`handleSetVolume`、`handleSetSpeed` 以及 `positionRunnable` 全部面向 `activePlayer` 操作。
3. **调起系统原生选择器（`showCastPicker`）**：
   - 使用 `android.app.Activity` 即可直接展示的 `MediaRouteChooserDialog`（来自 `androidx.mediarouter.app.MediaRouteChooserDialog`，**不强制要求宿主 `MainActivity` 继承 `FlutterFragmentActivity`**，普通 `FlutterActivity` 同样可用）：
     ```kotlin
     private fun handleShowCastPicker(result: Result) {
         val act = activity
         val ctx = castContext
         if (act == null || ctx == null) {
             result.success(null)
             return
         }
         val selector = ctx.mergedSelector ?: run {
             result.success(null)
             return
         }
         act.runOnUiThread {
             if (castPlayer?.isCastSessionAvailable == true) {
                 val controllerDialog = MediaRouteControllerDialog(act)
                 controllerDialog.show()
             } else {
                 val chooserDialog = MediaRouteChooserDialog(act)
                 chooserDialog.routeSelector = selector
                 chooserDialog.show()
             }
         }
         result.success(null)
     }
     ```
4. **本地与远端无缝切换（`SessionAvailabilityListener`）**：
   - 实现 `CastPlayer.setSessionAvailabilityListener`：
     - **`onCastSessionAvailable()`**：
       1. 读取 `val pos = exoPlayer?.currentPosition ?: 0L` 与 `val playWhenReady = exoPlayer?.isPlaying ?: false`。
       2. `exoPlayer?.pause()`。
       3. `activePlayer = castPlayer`。
       4. 获取设备名：`val deviceName = castContext?.sessionManager?.currentCastSession?.castDevice?.friendlyName ?: "Cast Device"`，发送 `sendCastState("connected", deviceName)`。
       5. 若 `currentUrl != null`，构造带 MIME 类型的 `MediaItem`（若是本地 `file://` URL，经由 `LocalCastHttpServer` 映射为局域网 `http://` URL），调用 `castPlayer.setMediaItem(item, pos)`、`castPlayer.playWhenReady = playWhenReady`、`castPlayer.prepare()`。
     - **`onCastSessionUnavailable()`**：
       1. 读取 `val pos = castPlayer?.currentPosition ?: 0L`。
       2. `activePlayer = exoPlayer`。
       3. `exoPlayer?.seekTo(pos)`，`exoPlayer?.pause()`（断开投屏后本地保持暂停）。
       4. 发送 `sendCastState("notConnected", null)`。
5. **主动退出投屏（`stopCasting`）**：
   - 调用 `castContext?.sessionManager?.endCurrentSession(true)`，自动触发 `onCastSessionUnavailable()` 完成进度回传与本地暂停。

---

### 7.4 Web 端（W3C `RemotePlayback` API + Safari AirPlay Fallback）

涉及文件：[`lib/xue_hua_navite_video_player_web.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player_web.dart)

1. **JS Interop 扩展定义**：
   在 `xue_hua_navite_video_player_web.dart` 中通过 `dart:js_interop` 为 `HTMLVideoElement` 扩展标准 W3C `remote` 属性及 Safari WebKit 专有方法：
   ```dart
   extension _VideoRemotePlaybackExt on html.HTMLVideoElement {
     external _JSRemotePlayback? get remote;
     @JS('webkitShowPlaybackTargetPicker')
     external JSFunction? get webkitShowPlaybackTargetPicker;
     @JS('webkitCurrentPlaybackTargetIsWireless')
     external bool? get webkitCurrentPlaybackTargetIsWireless;
   }

   extension type _JSRemotePlayback._(JSObject _) implements JSObject {
     external String get state; // 'connecting' | 'connected' | 'disconnected'
     external JSPromise<JSNumber> watchAvailability(JSFunction callback);
     external JSPromise<JSAny?> prompt();
     external void addEventListener(String type, JSFunction listener);
   }
   ```
2. **可用性探测与状态监听**：
   - 在 `_setupListeners` 中检测 `video.remote`：
     - 监听 `'connecting'` → `_sendEvent('castState', {'state': 'connecting', 'deviceName': 'Remote Device'})`
     - 监听 `'connect'` → `_sendEvent('castState', {'state': 'connected', 'deviceName': 'Remote Device'})`
     - 监听 `'disconnect'` → `_videoElement?.pause()` 并发送 `_sendEvent('castState', {'state': 'notConnected', 'deviceName': null})`
   - 同时兼容桌面/移动 Safari 的 `'webkitcurrentplaybacktargetiswirelesschanged'` 事件。
3. **调起浏览器原生选择器（`showCastPicker`）**：
   - 优先调用 `await video.remote!.prompt().toDart`（必须在用户点击事件调用链中触发，Flutter Web 按钮点击满足 User Activation 要求）。
   - 若 `video.remote` 不存在但存在 `webkitShowPlaybackTargetPicker`，调用 `webkitShowPlaybackTargetPicker`。
4. **主动退出投屏（`stopCasting`）**：
   - W3C `RemotePlayback` 规范中，浏览器再次调用 `video.remote.prompt()` 会直接弹出“停止投屏 / 切换回本机”系统确认框；或者通过临时设置 `video.disableRemotePlayback = true` 断开连接后再恢复 `false`。

---

### 7.5 Windows 端（WinRT `Windows.Media.Casting` 官方 API）

涉及文件：
- [`windows/CMakeLists.txt`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/windows/CMakeLists.txt)（链接 Windows SDK 自带的 `windowsapp` 库）
- [`windows/xue_hua_navite_video_player_plugin.h`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/windows/xue_hua_navite_video_player_plugin.h) / [`windows/xue_hua_navite_video_player_plugin.cpp`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/windows/xue_hua_navite_video_player_plugin.cpp)

1. **为什么使用 `Windows.Media.Casting`**：
   - Windows 10/11 SDK 原生内置了 `Windows::Media::Casting::CastingDevicePicker` 与 `CastingConnection`（C++/WinRT），无需安装任何第三方库即可同时支持局域网内的 **DLNA / UPnP 电视**、**Miracast 无线显示器**与蓝牙媒体接收器，且拥有 Windows 10/11 现代风格的原生系统浮层选择器。
2. **与现有 `libmpv` 的协同机制（Headless WinRT MediaPlayer 桥接）**：
   - Windows 本地播放继续使用高性能的 `MpvPlayer`。
   - 当用户点击投屏按钮调用 `showCastPicker` 时：
     1. 创建 `CastingDevicePicker`，设置 `picker.Filter().SupportsVideo(true)`。
     2. 通过 `IInitializeWithWindow` 将 `picker` 绑定到 Flutter 主窗口 `RootWindow()`（`HWND`）。
     3. 调用 `picker.Show(Rect(windowWidth - 48, 48, 1, 1), Placement::Below)` 弹出 Windows 系统原生投屏设备列表。
   - 当用户在原生列表中选中设备触发 `CastingDeviceSelected` 时：
     1. 上报 `castState(connecting, args.SelectedCastingDevice().FriendlyName())`。
     2. 暂停本地 `MpvPlayer` 并记录当前播放毫秒数 `pos_ms`。
     3. 实例化轻量级无头（Headless，不绑定本地 UI Surface）的 `Windows::Media::Playback::MediaPlayer`（`cast_media_player_`），设置 `Source(MediaSource::CreateFromUri(Uri(current_url_)))`，并将 `PlaybackSession().Position()` 设为 `pos_ms`。
     4. 创建 `casting_connection_ = selected_device.CreateCastingConnection()`，监听 `StateChanged` 与 `ErrorOccurred`，并调用 `casting_connection_.RequestStartCastingAsync(cast_media_player_.GetAsCastingSource())`。
     5. 投屏期间，插件的 `play`、`pause`、`seek`、`setVolume`、`setSpeed` 以及进度/缓冲回调自动切換至 `cast_media_player_.PlaybackSession()`。
     6. 当调用 `stopCasting` 或 `casting_connection_` 状态变为 `Disconnected` 时，读取 `cast_media_player_.PlaybackSession().Position()`，销毁 `casting_connection_`，将本地 `MpvPlayer` `Seek` 到该位置并保持暂停，上报 `castState(notConnected)`。

---

### 7.6 Linux 端（`GUPnP AV` + 原生 `GtkDialog` 选择器 / 安全降级）

涉及文件：
- [`linux/CMakeLists.txt`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/linux/CMakeLists.txt)
- [`linux/xue_hua_navite_video_player_plugin.cc`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/linux/xue_hua_navite_video_player_plugin.cc)

1. **构建期可选依赖探测（参考现有 `XRANDR` 模式）**：
   - 在 `linux/CMakeLists.txt` 中通过 `pkg_check_modules(GUPNP gupnp-1.6 gupnp-av-1.0)`（或 `gupnp-1.2`）进行可选探测：
     - 若系统安装了 `libgupnp` 与 `libgupnp-av`，定义宏 `HAS_GUPNP=1`，启用基于 UPnP/DLNA `urn:schemas-upnp-org:service:AVTransport:1` 的投屏控制器。
     - 若宿主 Linux 环境未安装 `gupnp`，插件依然 100% 正常编译，并在 `create` 时上报 `castState("unavailable")`，UI 自动隐藏投屏按钮。
2. **原生 GTK 设备选择器弹窗（`showCastPicker`）**：
   - 使用 `GUPnPControlPoint` 扫描局域网内的 `urn:schemas-upnp-org:device:MediaRenderer:1` 设备。
   - 调用 `showCastPicker` 时，创建绑定在 `plugin_window(self)` 上的原生 GTK 模态对话框（`gtk_dialog_new_with_buttons("选择投屏设备", parent_window, GTK_DIALOG_MODAL, ...)`），内嵌 `GtkListBox` 展示局域网内发现的电视/盒子列表。
   - 选中设备后暂停本地 `MpvPlayer`，通过 `AVTransport` SOAP 动作调用 `SetAVTransportURI` → `Play` → `Seek(REL_TIME)`，并通过每秒轮询 `GetPositionInfo` 与 `GetTransportInfo` 同步远端 `position`、`duration` 与播放完成状态。

---

## 8. 本地文件与 Asset 视频投屏方案（`LocalCastHttpServer`）

针对用户需求第 2 点（“如果使用官方的技术能实现全部支持最好，实现不了只是先网络视频也行”），我们设计了一套**零第三方依赖**的混合方案：

1. **天然支持的网络视频（`VideoSource.network`）**：
   - 全 6 端直接将 `http://` 或 `https://` URL 交给官方投屏组件，由远端电视直连拉流。
2. **纯 Dart 局域网文件流代理服务（`LocalCastHttpServer`）**：
   - 文件路径：`lib/src/player/local_cast_http_server.dart`（通过条件导入 `local_cast_http_server_io.dart` / `local_cast_http_server_stub.dart` 隔离 Web 平台）。
   - **工作原理**：
     - 当 `PlaybackSession` 打开的是 `FileVideoSource` 或 `AssetVideoSource`（在原生端已被 `AssetExtractor` 解压为本地临时文件 `file:///...`）时，若用户发起投屏且目标平台需要 HTTP URL（如 Android `CastPlayer`、Linux DLNA，或作为全平台通用本地投屏流）：
     - 使用 `dart:io` 的 `HttpServer.bind(InternetAddress.anyIPv4, 0)` 在随机空闲端口启动单文件只读 HTTP 服务。
     - 通过 `NetworkInterface.list(type: InternetAddressType.IPv4)` 获取本机局域网 IP（如 `192.168.1.x`），生成带一次性随机 Token 的局域网地址：`http://192.168.1.x:<port>/cast/<random_token>.mp4`。
     - **完整支持 HTTP `Range: bytes=start-end`（返回 `206 Partial Content`、`Accept-Ranges: bytes`、`Content-Range` 与正确的 `Content-Type`）**，确保电视端可以毫秒级任意拖动进度条（Seek）！
     - **安全与生命周期**：仅响应匹配当前一次性 Token 的单个媒体文件请求；当 `stopCasting()`、切换为网络视频或 `dispose()` 时立即关闭 `HttpServer` 释放端口。

---

## 9. UI 层与主题扩展设计（`VideoPlayer` & `CorePlayer`）

### 9.1 `VideoPlayer` 组件属性扩展

在 [`lib/src/ui/video_player.dart`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/ui/video_player.dart) 中新增可选参数（保持 100% 向后兼容）：

```dart
class VideoPlayer extends StatefulWidget {
  // ... 现有属性 ...

  /// 是否在顶栏右侧显示无线投屏按钮（默认 true，且仅当 controller.isCastSupported 为 true 时渲染）。
  final bool showCastButton;

  /// 自定义投屏状态遮罩层构建器（当 controller.isCasting 为 true 时覆盖在视频画面之上）。
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot)? castingOverlayBuilder;
}
```

### 9.2 顶栏投屏入口按钮（`_DefaultTopBar`）

在 `_DefaultTopBar` 的 `trailing` 动作列表中（位于 `showAspectRatioMenu` 左侧）：
- 监听 `controller.castState`：
  - 当 `castState == CastState.unavailable` 时：不渲染按钮（`SizedBox.shrink()`），界面保持清爽。
  - 当 `castState == CastState.notConnected` 时：渲染 `IconButton(icon: Icon(Icons.cast), tooltip: '投屏', onPressed: controller.showCastPicker)`。
  - 当 `castState == CastState.connecting || castState == CastState.disconnecting` 时：渲染带旋转指示器的投屏图标。
  - 当 `castState == CastState.connected` 时：渲染高亮的 `IconButton(icon: Icon(Icons.cast_connected), tooltip: '正在投屏', onPressed: controller.showCastPicker)`。

### 9.3 投屏专属状态遮罩层（`_DefaultCastingOverlay`）

当 `controller.isCasting.value == true` 时，在 [`CorePlayer`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/ui/core_player.dart) / [`VideoPlayer`](file:///Users/admin/XueHuaPackages/xue_hua_navite_video_player/lib/src/ui/video_player.dart) 的视频画面层之上展示投屏状态视图（防止黑屏或冻结帧让用户误以为播放器卡死）：

```
┌──────────────────────────────────────────────────────────────┐
│ [×]                       视频标题               [📺] [画面] │  ◄── 顶栏（常驻或轻触唤出）
│                                                              │
│                         ╭──────────╮                         │
│                         │   📺 ))  │                         │
│                         ╰──────────╯                         │
│                  正在投屏至「客厅 Apple TV」                  │  ◄── 投屏专属状态背景层
│                                                              │
│               [ 切换设备 ]        [ 退出投屏 ]               │
│                                                              │
│                  ( ⟲10 )   ( ⏸ )   ( 10⟳ )                  │  ◄── 中央播控（控制远端）
│                                                              │
│ 🔊  04:12 ━━━━━━━━━━━━━━●──────────────────── -18:45  1.0x ⛶ │  ◄── 底部进度条（控制远端）
└──────────────────────────────────────────────────────────────┘
```

- **交互细节**：
  - 点击 **「切换设备」**：调用 `controller.showCastPicker()` 重新打开系统原生选择器。
  - 点击 **「退出投屏」**：调用 `controller.stopCasting()` 立即切回本机并暂停。
  - 中央播放/暂停、快进/快退 10 秒、底部进度条拖拽、静音切换、倍速菜单在投屏期间**全部正常工作**并实时作用于远端投屏设备。

---

## 10. 新增与修改文件清单

| 模块 | 文件路径 | 变更类型 | 说明 |
| :--- | :--- | :--- | :--- |
| **Dart 枚举** | `lib/src/data/enums/cast_state.dart` | 新增 | 定义 `CastState` 枚举及序列化转换 |
| **Dart 导出** | `lib/xue_hua_navite_video_player.dart` | 修改 | 导出 `CastState` |
| **Dart 本地流服务** | `lib/src/player/local_cast_http_server.dart` (`_io.dart` / `_stub.dart`) | 新增 | 为本地文件/Asset 投屏提供 HTTP 206 Range 局域网流服务 |
| **Dart 通道层** | `lib/src/player/player_event.dart`<br>`lib/src/player/player_backend.dart`<br>`lib/src/player/channel_player_backend.dart` | 修改 | 新增 `PlayerCastStateEvent`、`showCastPicker()`、`stopCasting()` |
| **Dart 会话与控制器** | `lib/src/player/playback_session.dart`<br>`lib/src/player/video_player_controller.dart` | 修改 | 新增 `castState`、`castDeviceName`、`isCastSupported`、`isCasting` 及投屏态 `openSource` 保活逻辑 |
| **Dart UI 层** | `lib/src/ui/video_player.dart`<br>`lib/src/ui/style/video_player_theme.dart` | 修改 | 顶栏新增投屏按钮，画面层新增 `_DefaultCastingOverlay` 及主题样式字段 |
| **iOS 原生层** | `ios/.../XueHuaNaviteVideoPlayerPlugin.swift` | 修改 | 接入 `AVRoutePickerView`、`isExternalPlaybackActive` KVO、后台投屏保活与 `replaceCurrentItem` |
| **macOS 原生层** | `macos/.../XueHuaNaviteVideoPlayerPlugin.swift` | 修改 | 接入 AppKit `AVRoutePickerView`、`isExternalPlaybackActive` KVO 与 `replaceCurrentItem` |
| **Android 原生层** | `android/build.gradle.kts`<br>`android/src/main/AndroidManifest.xml`<br>`android/.../XueHuaNaviteVideoPlayerPlugin.kt` | 修改 | 引入 `media3-cast`，实现 `ExoPlayer` 与 `CastPlayer` 双引擎无缝切换及 `MediaRouteChooserDialog` |
| **Web 原生层** | `lib/xue_hua_navite_video_player_web.dart` | 修改 | 接入 `HTMLVideoElement.remote`（W3C Remote Playback API）与 Safari WebKit AirPlay 兜底 |
| **Windows 原生层** | `windows/CMakeLists.txt`<br>`windows/xue_hua_navite_video_player_plugin.h/.cpp` | 修改 | 接入 WinRT `CastingDevicePicker` + `CastingConnection` 与 `MpvPlayer` 进度桥接 |
| **Linux 原生层** | `linux/CMakeLists.txt`<br>`linux/xue_hua_navite_video_player_plugin.cc` | 修改 | 可选探测 `gupnp-1.6` + 原生 `GtkDialog` 设备选择器，未安装时安全降级为 `unavailable` |

---

## 11. 测试与验证计划

1. **Dart 单元测试（`test/`）**：
   - 验证 `ChannelPlayerBackend.decodeEventForTest` 对 `castState` 事件各状态的解码。
   - 使用 Fake `PlayerBackend` 测试 `PlaybackSession`：
     - 验证 `castState` 从 `notConnected` → `connecting` → `connected` → `notConnected` 的 Signal 更新。
     - 验证投屏状态下调用 `openSource` / `playNetwork` 不会重置 `castState` 与 `castDeviceName`。
     - 验证 `LocalCastHttpServer` 对 `HEAD`、`GET` 及 `Range: bytes=1024-4095` 请求返回 `206 Partial Content` 的字节精确性。
   - Widget 测试：验证 `VideoPlayer` 在 `CastState.unavailable` 时隐藏投屏按钮，在 `CastState.connected` 时展示投屏状态遮罩及“切换设备 / 退出投屏”按钮交互。
2. **各端真机联调清单**：
   - **iOS / macOS**：调起 AirPlay 选择器连接 Apple TV / 智能电视 / Mac，验证锁屏不中断、切集不断连、点击“退出投屏”回到本机暂停。
   - **Android**：调起 Google Cast 路由弹窗连接 Android TV / Chromecast，验证本地 `ExoPlayer` 与远端 `CastPlayer` 进度互传、无 GMS 设备安全隐藏投屏按钮。
   - **Windows / Linux / Web**：验证系统原生选择器弹出、网络流与本地文件流投屏播控同步。
