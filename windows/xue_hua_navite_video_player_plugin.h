#ifndef FLUTTER_PLUGIN_XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN_H_

// Windows video player plugin — libmpv backend (software rendering) + WinRT Casting + Pigeon IPC.

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "mpv_player.h"
#include "player_api.g.h"

namespace xue_hua_navite_video_player {

struct WinRtCastContext;

/// Windows implementation of [PlayerHostApi] backed by libmpv and WinRT Casting.
class XueHuaNaviteVideoPlayerPlugin : public flutter::Plugin, public PlayerHostApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit XueHuaNaviteVideoPlayerPlugin(flutter::PluginRegistrarWindows* registrar);
  ~XueHuaNaviteVideoPlayerPlugin() override;

  XueHuaNaviteVideoPlayerPlugin(const XueHuaNaviteVideoPlayerPlugin&) = delete;
  XueHuaNaviteVideoPlayerPlugin& operator=(const XueHuaNaviteVideoPlayerPlugin&) = delete;

  // PlayerHostApi overrides
  void Create(std::function<void(ErrorOr<int64_t> reply)> result) override;
  void Open(
      const OpenMediaRequest& request,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  std::optional<FlutterError> Play() override;
  std::optional<FlutterError> Pause() override;
  std::optional<FlutterError> Seek(int64_t position_ms) override;
  std::optional<FlutterError> SetVolume(double volume) override;
  std::optional<FlutterError> SetSpeed(double speed) override;
  std::optional<FlutterError> SetAspectRatioMode(const NativeAspectRatioMode& mode) override;
  std::optional<FlutterError> SetVideoViewSize(
      double width,
      double height,
      double device_pixel_ratio) override;
  std::optional<FlutterError> ShowCastPicker() override;
  std::optional<FlutterError> StopCasting() override;
  std::optional<FlutterError> Dispose() override;
  ErrorOr<double> GetBrightness() override;
  std::optional<FlutterError> SetBrightness(double value) override;
  std::optional<FlutterError> SetWindowFullscreen(bool value) override;
  void TakeSnapshot(
      std::function<void(ErrorOr<std::optional<SnapshotData>> reply)> result) override;
  void GetDuration(
      const DurationProbeRequest& request,
      std::function<void(ErrorOr<std::optional<int64_t>> reply)> result) override;
  void ExtractCovers(
      const CoverExtractRequest& request,
      std::function<void(ErrorOr<::flutter::EncodableList> reply)> result) override;
  void ConfigureCache(
      const CacheConfigRequest& request,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void Precache(
      const PrecacheRequest& request,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  std::optional<FlutterError> CancelPrecache(const std::string& cache_key) override;
  void IsCached(
      const CacheEntryRequest& request,
      std::function<void(ErrorOr<bool> reply)> result) override;
  void GetCacheSize(
      const std::string* cache_dir,
      std::function<void(ErrorOr<int64_t> reply)> result) override;
  void RemoveCache(
      const CacheEntryRequest& request,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ClearCache(
      const std::string* cache_dir,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  std::optional<FlutterError> PinCacheKey(const std::string& cache_key) override;
  std::optional<FlutterError> UnpinCacheKey(const std::string& cache_key) override;

 private:
  struct WorkerEntry {
    std::shared_ptr<std::atomic<bool>> done;
    std::thread thread;
  };

  void EnsurePlayer();
  int64_t CreateTextureIfNeeded();
  void DisposePlayer();

  void RunOnUiThread(std::function<void()> task);
  void EnqueueUiTask(std::function<void()> task);
  void DrainUiTasks();

  void EmitPlayerEvent(PlayerEventData event);
  void EmitCastState(NativeCastState state, const std::string& device_name = "");
  void NotifyWindowFullscreen(bool fullscreen);

  void ShowCastPickerImpl();
  void StopCastingImpl();
  void OpenCastMediaIfActive(const std::string& url);

  template <typename Fn>
  bool WithPhysicalMonitor(Fn&& fn);
  double GetBrightnessImpl();
  void SetBrightnessImpl(double value);
  void RestoreBrightness();

  HWND RootWindow() const;
  void SetWindowFullscreenImpl(bool enable);
  void RestoreWindowFullscreen();
  void CheckWindowFullscreenLost();
  std::optional<LRESULT> OnTopLevelWindowProc(
      HWND hwnd,
      UINT message,
      WPARAM wparam,
      LPARAM lparam);

  void LaunchWorker(std::function<void()> fn);
  void JoinWorkers();

  void RenderLoop();
  static LRESULT CALLBACK MessageProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* texture_registrar_;
  std::unique_ptr<PlayerFlutterApi> flutter_api_;
  std::shared_ptr<std::atomic<bool>> alive_ = std::make_shared<std::atomic<bool>>(true);

  std::shared_ptr<MpvPlayer> player_;
  std::unique_ptr<WinRtCastContext> cast_ctx_;
  std::string current_url_;
  std::string current_cast_url_;
  int64_t last_local_position_ms_ = 0;
  bool local_playing_ = false;
  double current_volume_ = 1.0;
  double current_speed_ = 1.0;

  std::unique_ptr<flutter::TextureVariant> texture_variant_;
  int64_t texture_id_ = -1;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::vector<uint8_t> pixel_buffer_data_;
  std::mutex pixel_mutex_;

  HWND message_window_ = nullptr;
  DWORD platform_thread_id_ = 0;
  std::atomic<bool> drain_posted_{false};

  std::mutex ui_task_mutex_;
  std::deque<std::function<void()>> pending_ui_tasks_;
  bool ui_task_posted_ = false;
  bool draining_ui_tasks_ = false;
  bool shutting_down_ = false;

  std::mutex worker_mutex_;
  std::vector<WorkerEntry> workers_;

  bool brightness_saved_ = false;
  DWORD saved_brightness_ = 0;

  int window_proc_id_ = -1;
  bool window_fullscreen_ = false;
  bool applying_window_fullscreen_ = false;
  bool window_state_saved_ = false;
  WINDOWPLACEMENT saved_placement_{};
  LONG_PTR saved_style_ = 0;
  LONG_PTR saved_ex_style_ = 0;

  // Dedicated render worker: mpv SW rendering performs heavy decode + RGBA memcpy,
  // so keeping it off the merged UI/platform thread prevents jank.
  std::thread render_thread_;
  std::mutex render_mutex_;
  std::condition_variable render_cv_;
  std::atomic<bool> render_request_{false};
  std::atomic<bool> render_thread_stop_{false};

  static constexpr UINT kMsgDrain = WM_USER + 1;
  static constexpr UINT kMsgRunUiTasks = WM_USER + 2;
};

}  // namespace xue_hua_navite_video_player

#endif  // FLUTTER_PLUGIN_XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN_H_
