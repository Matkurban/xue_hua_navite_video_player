#include "xue_hua_navite_video_player_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <highlevelmonitorconfigurationapi.h>
#include <physicalmonitorenumerationapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Casting.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.UI.Popups.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace xue_hua_navite_video_player {

namespace {

constexpr wchar_t kMessageWindowClass[] = L"FcvpMpvMessageWindow";
constexpr const char* kDesktopCacheUnsupportedMsg =
    "Native media cache is handled in Dart on Windows.";

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int sz = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), nullptr, 0,
                               nullptr, nullptr);
  std::string s(sz, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), s.data(), sz, nullptr,
                      nullptr);
  return s;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  int sz = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(sz, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), w.data(), sz);
  return w;
}

std::string DefaultCoverDir() {
  wchar_t tmp[MAX_PATH] = {0};
  GetTempPathW(MAX_PATH, tmp);
  std::wstring dir = std::wstring(tmp) + L"xue_hua_navite_video_player\\covers";
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  return WideToUtf8(dir);
}

std::string AspectModeToString(NativeAspectRatioMode mode) {
  switch (mode) {
    case NativeAspectRatioMode::kFill:
      return "fill";
    case NativeAspectRatioMode::kStretch:
      return "stretch";
    case NativeAspectRatioMode::kFit:
    default:
      return "fit";
  }
}

PlayerEventData MakeIntEvent(NativePlayerEventType kind, int64_t value) {
  PlayerEventData event(kind);
  event.set_int_value(value);
  return event;
}

PlayerEventData MakeBoolEvent(NativePlayerEventType kind, bool value) {
  PlayerEventData event(kind);
  event.set_bool_value(value);
  return event;
}

PlayerEventData MakeStringEvent(NativePlayerEventType kind, const std::string& message) {
  PlayerEventData event(kind);
  event.set_message(message);
  return event;
}

PlayerEventData MakeVideoSizeEvent(double width, double height) {
  PlayerEventData event(NativePlayerEventType::kVideoSize);
  event.set_width(width);
  event.set_height(height);
  return event;
}

PlayerEventData MakeCastStateEvent(NativeCastState state, const std::string& device_name) {
  PlayerEventData event(NativePlayerEventType::kCastState);
  event.set_cast_state(state);
  if (!device_name.empty()) {
    event.set_cast_device_name(device_name);
  }
  return event;
}

bool RectsAlmostEqual(const RECT& a, const RECT& b, int slop = 2) {
  return std::abs(a.left - b.left) <= slop && std::abs(a.top - b.top) <= slop &&
         std::abs(a.right - b.right) <= slop && std::abs(a.bottom - b.bottom) <= slop;
}

bool IsBorderlessMonitorFullscreen(HWND hwnd) {
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mi)) {
    return false;
  }
  RECT wr{};
  if (!GetWindowRect(hwnd, &wr)) return false;
  const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
  const bool no_caption = (style & WS_CAPTION) == 0;
  return no_caption && RectsAlmostEqual(wr, mi.rcMonitor);
}

}  // namespace

struct WinRtCastContext {
  winrt::Windows::Media::Casting::CastingDevicePicker picker{nullptr};
  winrt::Windows::Media::Casting::CastingConnection connection{nullptr};
  winrt::Windows::Media::Playback::MediaPlayer media_player{nullptr};
  winrt::event_token selected_token{};
  winrt::event_token state_changed_token{};
  winrt::event_token media_ended_token{};
  winrt::event_token media_state_token{};
  bool is_casting = false;
  std::string device_name;
};

void XueHuaNaviteVideoPlayerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<XueHuaNaviteVideoPlayerPlugin>(registrar);
  PlayerHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

XueHuaNaviteVideoPlayerPlugin::XueHuaNaviteVideoPlayerPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      texture_registrar_(registrar->texture_registrar()),
      flutter_api_(std::make_unique<PlayerFlutterApi>(registrar->messenger())),
      cast_ctx_(std::make_unique<WinRtCastContext>()) {
  platform_thread_id_ = GetCurrentThreadId();
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &XueHuaNaviteVideoPlayerPlugin::MessageProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kMessageWindowClass;
  RegisterClassExW(&wc);
  message_window_ = CreateWindowExW(0, kMessageWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                                    nullptr, wc.hInstance, this);
  if (message_window_) {
    SetWindowLongPtrW(message_window_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    SetTimer(message_window_, /*id=*/1, /*ms=*/100, nullptr);
  }
  if (registrar_) {
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
          return OnTopLevelWindowProc(hwnd, message, wparam, lparam);
        });
  }
}

XueHuaNaviteVideoPlayerPlugin::~XueHuaNaviteVideoPlayerPlugin() {
  if (alive_) {
    alive_->store(false, std::memory_order_release);
  }
  if (registrar_ && registrar_->messenger()) {
    PlayerHostApi::SetUp(registrar_->messenger(), nullptr);
  }
  RestoreWindowFullscreen();
  if (window_proc_id_ >= 0 && registrar_) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    window_proc_id_ = -1;
  }
  RestoreBrightness();
  JoinWorkers();
  DisposePlayer();
  {
    std::lock_guard<std::mutex> lock(ui_task_mutex_);
    shutting_down_ = true;
    pending_ui_tasks_.clear();
    ui_task_posted_ = false;
  }
  if (message_window_) {
    KillTimer(message_window_, 1);
    DestroyWindow(message_window_);
    message_window_ = nullptr;
  }
  flutter_api_.reset();
}

LRESULT CALLBACK XueHuaNaviteVideoPlayerPlugin::MessageProc(
    HWND hwnd,
    UINT msg,
    WPARAM w,
    LPARAM l) {
  auto* self =
      reinterpret_cast<XueHuaNaviteVideoPlayerPlugin*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (!self) return DefWindowProcW(hwnd, msg, w, l);

  if (msg == kMsgDrain || msg == WM_TIMER) {
    self->drain_posted_.store(false, std::memory_order_release);
    if (self->player_ && !(self->cast_ctx_ && self->cast_ctx_->is_casting)) {
      self->player_->DrainEvents();
    } else if (self->cast_ctx_ && self->cast_ctx_->is_casting && self->cast_ctx_->media_player) {
      try {
        auto session = self->cast_ctx_->media_player.PlaybackSession();
        auto pos_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(session.Position()).count();
        if (pos_ms >= 0) {
          self->last_local_position_ms_ = pos_ms;
          self->EmitPlayerEvent(MakeIntEvent(NativePlayerEventType::kPosition, pos_ms));
        }
        auto dur_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(session.NaturalDuration())
                .count();
        if (dur_ms > 0) {
          self->EmitPlayerEvent(MakeIntEvent(NativePlayerEventType::kDuration, dur_ms));
        }
      } catch (...) {
      }
    }
    return 0;
  }

  if (msg == kMsgRunUiTasks) {
    self->DrainUiTasks();
    return 0;
  }

  return DefWindowProcW(hwnd, msg, w, l);
}

void XueHuaNaviteVideoPlayerPlugin::EnqueueUiTask(std::function<void()> task) {
  HWND hwnd = nullptr;
  {
    std::lock_guard<std::mutex> lock(ui_task_mutex_);
    if (shutting_down_ || (alive_ && !alive_->load(std::memory_order_acquire))) {
      return;
    }
    pending_ui_tasks_.push_back(std::move(task));
    hwnd = message_window_;
    if (!hwnd || ui_task_posted_) {
      return;
    }
    ui_task_posted_ = true;
  }
  if (!PostMessageW(hwnd, kMsgRunUiTasks, 0, 0)) {
    std::lock_guard<std::mutex> lock(ui_task_mutex_);
    ui_task_posted_ = false;
  }
}

void XueHuaNaviteVideoPlayerPlugin::DrainUiTasks() {
  if (draining_ui_tasks_) return;
  draining_ui_tasks_ = true;
  for (;;) {
    std::deque<std::function<void()>> batch;
    {
      std::lock_guard<std::mutex> lock(ui_task_mutex_);
      if (shutting_down_ || pending_ui_tasks_.empty()) {
        ui_task_posted_ = false;
        draining_ui_tasks_ = false;
        return;
      }
      batch.swap(pending_ui_tasks_);
      ui_task_posted_ = false;
    }
    for (auto& fn : batch) {
      if (fn && alive_ && alive_->load(std::memory_order_acquire)) {
        fn();
      }
    }
  }
}

void XueHuaNaviteVideoPlayerPlugin::RunOnUiThread(std::function<void()> task) {
  if (!alive_ || !alive_->load(std::memory_order_acquire)) {
    return;
  }
  if (GetCurrentThreadId() == platform_thread_id_ && !draining_ui_tasks_) {
    DrainUiTasks();
    bool queue_empty = false;
    {
      std::lock_guard<std::mutex> lock(ui_task_mutex_);
      queue_empty = pending_ui_tasks_.empty();
    }
    if (queue_empty && alive_->load(std::memory_order_acquire)) {
      task();
      return;
    }
  }
  EnqueueUiTask(std::move(task));
}

void XueHuaNaviteVideoPlayerPlugin::EmitPlayerEvent(PlayerEventData event) {
  auto alive = alive_;
  RunOnUiThread([this, alive, event = std::move(event)]() {
    if (!alive || !alive->load(std::memory_order_acquire) || !flutter_api_) {
      return;
    }
    flutter_api_->OnPlayerEvent(event, []() {}, [](const FlutterError&) {});
  });
}

void XueHuaNaviteVideoPlayerPlugin::EmitCastState(
    NativeCastState state,
    const std::string& device_name) {
  EmitPlayerEvent(MakeCastStateEvent(state, device_name));
}

void XueHuaNaviteVideoPlayerPlugin::NotifyWindowFullscreen(bool fullscreen) {
  auto alive = alive_;
  RunOnUiThread([this, alive, fullscreen]() {
    if (!alive || !alive->load(std::memory_order_acquire) || !flutter_api_) {
      return;
    }
    flutter_api_->OnWindowFullscreen(fullscreen, []() {}, [](const FlutterError&) {});
  });
}

void XueHuaNaviteVideoPlayerPlugin::RenderLoop() {
  while (!render_thread_stop_.load(std::memory_order_acquire)) {
    {
      std::unique_lock<std::mutex> lk(render_mutex_);
      render_cv_.wait(lk, [this] {
        return render_request_.load(std::memory_order_acquire) ||
               render_thread_stop_.load(std::memory_order_acquire);
      });
      if (render_thread_stop_.load(std::memory_order_acquire)) return;
      render_request_.store(false, std::memory_order_release);
    }
    if (player_ && player_->Render()) {
      if (texture_id_ >= 0) {
        texture_registrar_->MarkTextureFrameAvailable(texture_id_);
      }
    }
  }
}

void XueHuaNaviteVideoPlayerPlugin::EnsurePlayer() {
  if (player_) return;
  auto p = std::make_shared<MpvPlayer>();
  std::string err;
  if (!p->Initialize(&err)) {
    EmitPlayerEvent(MakeStringEvent(NativePlayerEventType::kError, "mpv init failed: " + err));
    return;
  }
  HWND hwnd = message_window_;
  auto alive = alive_;
  p->SetWakeupHandler([this, hwnd, alive]() {
    if (!alive || !alive->load(std::memory_order_acquire) || !hwnd) return;
    bool expected = false;
    if (drain_posted_.compare_exchange_strong(expected, true)) {
      PostMessageW(hwnd, kMsgDrain, 0, 0);
    }
  });
  p->SetUpdateHandler([this, alive]() {
    if (!alive || !alive->load(std::memory_order_acquire)) return;
    render_request_.store(true, std::memory_order_release);
    render_cv_.notify_one();
  });
  p->SetOnPosition([this](int64_t ms) {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    last_local_position_ms_ = ms;
    EmitPlayerEvent(MakeIntEvent(NativePlayerEventType::kPosition, ms));
  });
  p->SetOnBuffered([this](int64_t ms) {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    EmitPlayerEvent(MakeIntEvent(NativePlayerEventType::kBuffered, ms));
  });
  p->SetOnDuration([this](int64_t ms) {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    EmitPlayerEvent(MakeIntEvent(NativePlayerEventType::kDuration, ms));
  });
  p->SetOnPlaying([this](bool pl) {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    local_playing_ = pl;
    EmitPlayerEvent(MakeBoolEvent(NativePlayerEventType::kPlaying, pl));
  });
  p->SetOnBuffering([this](bool b) {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    EmitPlayerEvent(MakeBoolEvent(NativePlayerEventType::kBuffering, b));
  });
  p->SetOnCompleted([this]() {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    EmitPlayerEvent(PlayerEventData(NativePlayerEventType::kCompleted));
  });
  p->SetOnError([this](const std::string& m) {
    if (cast_ctx_ && cast_ctx_->is_casting) return;
    EmitPlayerEvent(MakeStringEvent(NativePlayerEventType::kError, m));
  });
  p->SetOnFrame([this](const uint8_t* rgba, uint32_t w, uint32_t h) {
    std::lock_guard<std::mutex> lk(pixel_mutex_);
    const size_t need = static_cast<size_t>(w) * h * 4;
    if (pixel_buffer_data_.size() < need) pixel_buffer_data_.resize(need);
    std::memcpy(pixel_buffer_data_.data(), rgba, need);
    pixel_buffer_.buffer = pixel_buffer_data_.data();
    pixel_buffer_.width = w;
    pixel_buffer_.height = h;
  });
  p->SetOnVideoSize([this](int64_t w, int64_t h) {
    if (w <= 0 || h <= 0) return;
    EmitPlayerEvent(MakeVideoSizeEvent(static_cast<double>(w), static_cast<double>(h)));
  });

  player_ = std::move(p);
  if (!render_thread_.joinable()) {
    render_thread_stop_.store(false, std::memory_order_release);
    render_thread_ = std::thread([this]() { RenderLoop(); });
  }
}

int64_t XueHuaNaviteVideoPlayerPlugin::CreateTextureIfNeeded() {
  EnsurePlayer();
  if (!player_) return -1;
  if (cast_ctx_ && cast_ctx_->is_casting) {
    EmitCastState(NativeCastState::kConnected, cast_ctx_->device_name);
  } else {
    EmitCastState(NativeCastState::kNotConnected);
  }
  if (texture_id_ >= 0) return texture_id_;
  {
    std::lock_guard<std::mutex> lk(pixel_mutex_);
    if (pixel_buffer_.buffer == nullptr) {
      pixel_buffer_data_.assign({0, 0, 0, 255});
      pixel_buffer_.buffer = pixel_buffer_data_.data();
      pixel_buffer_.width = 1;
      pixel_buffer_.height = 1;
    }
  }
  texture_variant_ = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
      [this](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
        std::lock_guard<std::mutex> lk(pixel_mutex_);
        if (pixel_buffer_.buffer == nullptr) {
          static const uint8_t kPlaceholder[] = {0, 0, 0, 255};
          static FlutterDesktopPixelBuffer placeholder{kPlaceholder, 1, 1, nullptr, nullptr};
          return &placeholder;
        }
        return &pixel_buffer_;
      }));
  texture_id_ = texture_registrar_->RegisterTexture(texture_variant_.get());
  return texture_id_;
}

void XueHuaNaviteVideoPlayerPlugin::DisposePlayer() {
  StopCastingImpl();
  if (cast_ctx_) {
    try {
      if (cast_ctx_->picker && cast_ctx_->selected_token) {
        cast_ctx_->picker.CastingDeviceSelected(cast_ctx_->selected_token);
        cast_ctx_->selected_token = {};
      }
      if (cast_ctx_->media_player) {
        if (cast_ctx_->media_ended_token) {
          cast_ctx_->media_player.MediaEnded(cast_ctx_->media_ended_token);
          cast_ctx_->media_ended_token = {};
        }
        if (cast_ctx_->media_state_token) {
          cast_ctx_->media_player.CurrentStateChanged(cast_ctx_->media_state_token);
          cast_ctx_->media_state_token = {};
        }
      }
    } catch (...) {
    }
  }
  if (render_thread_.joinable()) {
    render_thread_stop_.store(true, std::memory_order_release);
    render_cv_.notify_all();
    render_thread_.join();
  }
  player_.reset();
  if (texture_id_ >= 0) {
    texture_registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  texture_variant_.reset();
  std::lock_guard<std::mutex> lk(pixel_mutex_);
  pixel_buffer_.buffer = nullptr;
  pixel_buffer_.width = 0;
  pixel_buffer_.height = 0;
  pixel_buffer_data_.clear();
}

void XueHuaNaviteVideoPlayerPlugin::OpenCastMediaIfActive(const std::string& url) {
  if (!cast_ctx_ || !cast_ctx_->is_casting || !cast_ctx_->media_player || url.empty()) {
    return;
  }
  try {
    winrt::Windows::Foundation::Uri uri(Utf8ToWide(url));
    auto source = winrt::Windows::Media::Core::MediaSource::CreateFromUri(uri);
    cast_ctx_->media_player.Source(source);
  } catch (...) {
  }
}

void XueHuaNaviteVideoPlayerPlugin::ShowCastPickerImpl() {
  HWND hwnd = RootWindow();
  if (!hwnd || !cast_ctx_) return;
  try {
    using namespace winrt::Windows::Media::Casting;
    using namespace winrt::Windows::Media::Playback;
    using namespace winrt::Windows::Media::Core;
    using namespace winrt::Windows::Foundation;

    auto alive = alive_;
    if (!cast_ctx_->picker) {
      CastingDevicePicker picker;
      picker.Filter().SupportsVideo(true);
      cast_ctx_->selected_token = picker.CastingDeviceSelected(
          [this, alive](const CastingDevicePicker&, const CastingDeviceSelectedEventArgs& args) {
            if (!alive || !alive->load(std::memory_order_acquire)) return;
            try {
              auto device = args.SelectedCastingDevice();
              RunOnUiThread([this, alive, device]() {
                if (!alive || !alive->load(std::memory_order_acquire) || !cast_ctx_) return;
                try {
                  std::string dev_name = WideToUtf8(std::wstring(device.FriendlyName().c_str()));
                  if (dev_name.empty()) dev_name = "Windows Cast";
                  cast_ctx_->device_name = dev_name;
                  EmitCastState(NativeCastState::kConnecting, dev_name);

                  const bool was_playing = local_playing_;
                  const int64_t resume_ms = last_local_position_ms_;
                  if (player_) player_->Pause();

                  if (!cast_ctx_->media_player) {
                    cast_ctx_->media_player = MediaPlayer();
                    cast_ctx_->media_ended_token = cast_ctx_->media_player.MediaEnded(
                        [this, alive](const MediaPlayer&, const IInspectable&) {
                          if (!alive || !alive->load(std::memory_order_acquire)) return;
                          EmitPlayerEvent(MakeBoolEvent(NativePlayerEventType::kPlaying, false));
                          EmitPlayerEvent(PlayerEventData(NativePlayerEventType::kCompleted));
                        });
                    cast_ctx_->media_state_token = cast_ctx_->media_player.CurrentStateChanged(
                        [this, alive](const MediaPlayer& mp, const IInspectable&) {
                          if (!alive || !alive->load(std::memory_order_acquire)) return;
                          try {
                            auto state = mp.PlaybackSession().PlaybackState();
                            EmitPlayerEvent(MakeBoolEvent(
                                NativePlayerEventType::kBuffering,
                                state == MediaPlaybackState::Buffering ||
                                    state == MediaPlaybackState::Opening));
                            EmitPlayerEvent(MakeBoolEvent(NativePlayerEventType::kPlaying,
                                                          state == MediaPlaybackState::Playing));
                          } catch (...) {
                          }
                        });
                  }

                  const std::string target_url =
                      !current_cast_url_.empty() ? current_cast_url_ : current_url_;
                  if (!target_url.empty()) {
                    Uri uri(Utf8ToWide(target_url));
                    cast_ctx_->media_player.Source(MediaSource::CreateFromUri(uri));
                    cast_ctx_->media_player.Volume(current_volume_);
                    cast_ctx_->media_player.PlaybackSession().PlaybackRate(current_speed_);
                    cast_ctx_->media_player.PlaybackSession().Position(
                        std::chrono::milliseconds(resume_ms));
                    if (was_playing) {
                      cast_ctx_->media_player.Play();
                    }
                  }

                  if (cast_ctx_->connection && cast_ctx_->state_changed_token) {
                    cast_ctx_->connection.StateChanged(cast_ctx_->state_changed_token);
                    cast_ctx_->state_changed_token = {};
                  }
                  auto conn = device.CreateCastingConnection();
                  cast_ctx_->connection = conn;
                  cast_ctx_->state_changed_token = conn.StateChanged(
                      [this, alive](const CastingConnection& c, const IInspectable&) {
                        if (!alive || !alive->load(std::memory_order_acquire)) return;
                        try {
                          auto state = c.State();
                          RunOnUiThread([this, alive, state]() {
                            if (!alive || !alive->load(std::memory_order_acquire) || !cast_ctx_) {
                              return;
                            }
                            switch (state) {
                              case CastingConnectionState::Connected:
                              case CastingConnectionState::Rendering:
                                cast_ctx_->is_casting = true;
                                EmitCastState(NativeCastState::kConnected, cast_ctx_->device_name);
                                break;
                              case CastingConnectionState::Connecting:
                                EmitCastState(NativeCastState::kConnecting, cast_ctx_->device_name);
                                break;
                              case CastingConnectionState::Disconnecting:
                                EmitCastState(NativeCastState::kDisconnecting,
                                              cast_ctx_->device_name);
                                break;
                              case CastingConnectionState::Disconnected:
                                if (cast_ctx_->is_casting) {
                                  cast_ctx_->is_casting = false;
                                  if (player_) {
                                    player_->Pause();
                                    player_->Seek(last_local_position_ms_);
                                  }
                                  EmitPlayerEvent(
                                      MakeBoolEvent(NativePlayerEventType::kPlaying, false));
                                }
                                EmitCastState(NativeCastState::kNotConnected);
                                break;
                            }
                          });
                        } catch (...) {
                        }
                      });
                  conn.RequestStartCastingAsync(cast_ctx_->media_player.GetAsCastingSource());
                } catch (...) {
                  EmitCastState(NativeCastState::kNotConnected);
                }
              });
            } catch (...) {
              EmitCastState(NativeCastState::kNotConnected);
            }
          });
      cast_ctx_->picker = picker;
    }

    auto init_window = cast_ctx_->picker.as<IInitializeWithWindow>();
    if (init_window) {
      init_window->Initialize(hwnd);
    }
    RECT rc{};
    GetClientRect(hwnd, &rc);
    const float x = static_cast<float>((std::max)(0L, rc.right - rc.left - 60));
    cast_ctx_->picker.Show(winrt::Windows::Foundation::Rect{x, 48.0f, 1.0f, 1.0f},
                           winrt::Windows::UI::Popups::Placement::Below);
  } catch (...) {
    // Safe no-op if Windows Casting API is unavailable on current SKU.
  }
}

void XueHuaNaviteVideoPlayerPlugin::StopCastingImpl() {
  if (!cast_ctx_ || !cast_ctx_->is_casting) return;
  cast_ctx_->is_casting = false;
  try {
    if (cast_ctx_->media_player) {
      auto pos_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        cast_ctx_->media_player.PlaybackSession().Position())
                        .count();
      if (pos_ms >= 0) {
        last_local_position_ms_ = pos_ms;
      }
      cast_ctx_->media_player.Pause();
    }
    if (cast_ctx_->connection) {
      if (cast_ctx_->state_changed_token) {
        cast_ctx_->connection.StateChanged(cast_ctx_->state_changed_token);
        cast_ctx_->state_changed_token = {};
      }
      cast_ctx_->connection.DisconnectAsync();
      cast_ctx_->connection = nullptr;
    }
  } catch (...) {
  }
  if (player_) {
    player_->Pause();
    if (last_local_position_ms_ > 0) {
      player_->Seek(last_local_position_ms_);
    }
  }
  EmitPlayerEvent(MakeBoolEvent(NativePlayerEventType::kPlaying, false));
  EmitCastState(NativeCastState::kNotConnected);
}

void XueHuaNaviteVideoPlayerPlugin::LaunchWorker(std::function<void()> fn) {
  std::vector<WorkerEntry> finished;
  auto done = std::make_shared<std::atomic<bool>>(false);
  {
    std::lock_guard<std::mutex> lock(worker_mutex_);
    auto it = workers_.begin();
    while (it != workers_.end()) {
      if (it->done->load(std::memory_order_acquire)) {
        finished.push_back(std::move(*it));
        it = workers_.erase(it);
      } else {
        ++it;
      }
    }
    workers_.push_back(WorkerEntry{
        done,
        std::thread([done, fn = std::move(fn)]() mutable {
          fn();
          done->store(true, std::memory_order_release);
        }),
    });
  }
  for (auto& entry : finished) {
    if (entry.thread.joinable()) entry.thread.join();
  }
}

void XueHuaNaviteVideoPlayerPlugin::JoinWorkers() {
  std::vector<WorkerEntry> entries;
  {
    std::lock_guard<std::mutex> lock(worker_mutex_);
    entries.swap(workers_);
  }
  for (auto& entry : entries) {
    if (entry.thread.joinable()) entry.thread.join();
  }
}

template <typename Fn>
bool XueHuaNaviteVideoPlayerPlugin::WithPhysicalMonitor(Fn&& fn) {
  HWND hwnd = nullptr;
  if (registrar_ && registrar_->GetView()) {
    hwnd = registrar_->GetView()->GetNativeWindow();
  }
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
  DWORD count = 0;
  if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0) {
    return false;
  }
  std::vector<PHYSICAL_MONITOR> monitors(count);
  if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, monitors.data())) {
    return false;
  }
  const bool ok = fn(monitors[0].hPhysicalMonitor);
  DestroyPhysicalMonitors(count, monitors.data());
  return ok;
}

double XueHuaNaviteVideoPlayerPlugin::GetBrightnessImpl() {
  DWORD min_b = 0, cur_b = 0, max_b = 0;
  const bool ok = WithPhysicalMonitor([&](HANDLE mon) {
    return GetMonitorBrightness(mon, &min_b, &cur_b, &max_b) == TRUE;
  });
  if (!ok || max_b <= min_b) {
    return 1.0;
  }
  return static_cast<double>(cur_b - min_b) / static_cast<double>(max_b - min_b);
}

void XueHuaNaviteVideoPlayerPlugin::SetBrightnessImpl(double value) {
  DWORD min_b = 0, cur_b = 0, max_b = 0;
  const bool queried = WithPhysicalMonitor([&](HANDLE mon) {
    return GetMonitorBrightness(mon, &min_b, &cur_b, &max_b) == TRUE;
  });
  if (!queried || max_b <= min_b) {
    return;
  }
  if (!brightness_saved_) {
    saved_brightness_ = cur_b;
    brightness_saved_ = true;
  }
  const double clamped = std::clamp(value, 0.0, 1.0);
  const DWORD target = min_b + static_cast<DWORD>((max_b - min_b) * clamped + 0.5);
  WithPhysicalMonitor([&](HANDLE mon) { return SetMonitorBrightness(mon, target) == TRUE; });
}

void XueHuaNaviteVideoPlayerPlugin::RestoreBrightness() {
  if (!brightness_saved_) return;
  brightness_saved_ = false;
  const DWORD target = saved_brightness_;
  WithPhysicalMonitor([&](HANDLE mon) { return SetMonitorBrightness(mon, target) == TRUE; });
}

HWND XueHuaNaviteVideoPlayerPlugin::RootWindow() const {
  HWND hwnd = nullptr;
  if (registrar_ && registrar_->GetView()) {
    hwnd = registrar_->GetView()->GetNativeWindow();
  }
  if (!hwnd) return nullptr;
  HWND root = GetAncestor(hwnd, GA_ROOT);
  return root ? root : hwnd;
}

void XueHuaNaviteVideoPlayerPlugin::RestoreWindowFullscreen() {
  HWND hwnd = RootWindow();
  if (!window_state_saved_ || !hwnd) {
    window_fullscreen_ = false;
    window_state_saved_ = false;
    return;
  }
  SetWindowLongPtrW(hwnd, GWL_STYLE, saved_style_);
  SetWindowLongPtrW(hwnd, GWL_EXSTYLE, saved_ex_style_);
  SetWindowPlacement(hwnd, &saved_placement_);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  window_fullscreen_ = false;
  window_state_saved_ = false;
}

void XueHuaNaviteVideoPlayerPlugin::SetWindowFullscreenImpl(bool enable) {
  HWND hwnd = RootWindow();
  if (!hwnd) return;

  applying_window_fullscreen_ = true;
  if (enable) {
    if (!window_fullscreen_) {
      saved_placement_.length = sizeof(WINDOWPLACEMENT);
      GetWindowPlacement(hwnd, &saved_placement_);
      saved_style_ = GetWindowLongPtrW(hwnd, GWL_STYLE);
      saved_ex_style_ = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
      window_state_saved_ = true;

      MONITORINFO mi{};
      mi.cbSize = sizeof(mi);
      GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mi);

      SetWindowLongPtrW(
          hwnd, GWL_STYLE,
          saved_style_ & ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MAXIMIZEBOX |
                           WS_MINIMIZEBOX));
      SetWindowLongPtrW(
          hwnd, GWL_EXSTYLE,
          saved_ex_style_ &
              ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));
      SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right - mi.rcMonitor.left, mi.rcMonitor.bottom - mi.rcMonitor.top,
                   SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
      window_fullscreen_ = true;
    }
  } else {
    RestoreWindowFullscreen();
  }
  applying_window_fullscreen_ = false;
}

void XueHuaNaviteVideoPlayerPlugin::CheckWindowFullscreenLost() {
  if (applying_window_fullscreen_ || !window_fullscreen_) return;
  HWND hwnd = RootWindow();
  if (!hwnd) return;
  if (IsBorderlessMonitorFullscreen(hwnd)) return;
  applying_window_fullscreen_ = true;
  RestoreWindowFullscreen();
  applying_window_fullscreen_ = false;
  NotifyWindowFullscreen(false);
}

std::optional<LRESULT> XueHuaNaviteVideoPlayerPlugin::OnTopLevelWindowProc(
    HWND /*hwnd*/,
    UINT message,
    WPARAM /*wparam*/,
    LPARAM /*lparam*/) {
  if (applying_window_fullscreen_ || !window_fullscreen_) {
    return std::nullopt;
  }
  if (message == WM_WINDOWPOSCHANGED || message == WM_SIZE || message == WM_EXITSIZEMOVE) {
    CheckWindowFullscreenLost();
  }
  return std::nullopt;
}

// ---------------------------------------------------------------------------
// PlayerHostApi implementation
// ---------------------------------------------------------------------------

void XueHuaNaviteVideoPlayerPlugin::Create(std::function<void(ErrorOr<int64_t> reply)> result) {
  const int64_t id = CreateTextureIfNeeded();
  if (id < 0) {
    result(FlutterError("CREATE_FAIL", "Failed to initialize native player"));
    return;
  }
  result(id);
}

void XueHuaNaviteVideoPlayerPlugin::Open(
    const OpenMediaRequest& request,
    std::function<void(std::optional<FlutterError> reply)> result) {
  EnsurePlayer();
  current_cast_url_ = request.cast_url() ? *request.cast_url() : "";
  current_url_ = request.url();
  last_local_position_ms_ = 0;
  if (player_ && !current_url_.empty()) {
    player_->Open(current_url_);
    EmitPlayerEvent(MakeBoolEvent(NativePlayerEventType::kBuffering, true));
  }
  OpenCastMediaIfActive(!current_cast_url_.empty() ? current_cast_url_ : current_url_);
  result(std::nullopt);
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::Play() {
  if (cast_ctx_ && cast_ctx_->is_casting && cast_ctx_->media_player) {
    try {
      cast_ctx_->media_player.Play();
    } catch (...) {
    }
  } else if (player_) {
    player_->Play();
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::Pause() {
  if (cast_ctx_ && cast_ctx_->is_casting && cast_ctx_->media_player) {
    try {
      cast_ctx_->media_player.Pause();
    } catch (...) {
    }
  } else if (player_) {
    player_->Pause();
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::Seek(int64_t position_ms) {
  last_local_position_ms_ = position_ms;
  if (cast_ctx_ && cast_ctx_->is_casting && cast_ctx_->media_player) {
    try {
      cast_ctx_->media_player.PlaybackSession().Position(std::chrono::milliseconds(position_ms));
    } catch (...) {
    }
  } else if (player_) {
    player_->Seek(position_ms);
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::SetVolume(double volume) {
  current_volume_ = std::clamp(volume, 0.0, 1.0);
  if (player_) {
    player_->SetVolume(current_volume_);
  }
  if (cast_ctx_ && cast_ctx_->media_player) {
    try {
      cast_ctx_->media_player.Volume(current_volume_);
    } catch (...) {
    }
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::SetSpeed(double speed) {
  current_speed_ = speed;
  if (player_) {
    player_->SetSpeed(current_speed_);
  }
  if (cast_ctx_ && cast_ctx_->media_player) {
    try {
      cast_ctx_->media_player.PlaybackSession().PlaybackRate(current_speed_);
    } catch (...) {
    }
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::SetAspectRatioMode(
    const NativeAspectRatioMode& mode) {
  EnsurePlayer();
  if (player_) {
    player_->SetAspectRatioMode(AspectModeToString(mode));
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::SetVideoViewSize(
    double width,
    double height,
    double device_pixel_ratio) {
  EnsurePlayer();
  if (player_) {
    const double dpr = device_pixel_ratio <= 0.0 ? 1.0 : device_pixel_ratio;
    player_->SetVideoViewSize(static_cast<uint32_t>(width * dpr + 0.5),
                              static_cast<uint32_t>(height * dpr + 0.5));
  }
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::ShowCastPicker() {
  ShowCastPickerImpl();
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::StopCasting() {
  StopCastingImpl();
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::Dispose() {
  RestoreBrightness();
  DisposePlayer();
  return std::nullopt;
}

ErrorOr<double> XueHuaNaviteVideoPlayerPlugin::GetBrightness() {
  return ErrorOr<double>(GetBrightnessImpl());
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::SetBrightness(double value) {
  SetBrightnessImpl(value);
  return std::nullopt;
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::SetWindowFullscreen(bool value) {
  SetWindowFullscreenImpl(value);
  return std::nullopt;
}

void XueHuaNaviteVideoPlayerPlugin::TakeSnapshot(
    std::function<void(ErrorOr<std::optional<SnapshotData>> reply)> result) {
  auto player = player_;
  if (!player) {
    result(FlutterError("NO_PLAYER", "Player not initialized"));
    return;
  }
  auto alive = alive_;
  // Offload synchronous mpv screenshot-to-file I/O off the merged UI/platform thread.
  LaunchWorker([this, alive, player = std::move(player), result = std::move(result)]() mutable {
    std::vector<uint8_t> bytes;
    std::string err;
    const bool ok = player->TakeSnapshot(&bytes, &err);
    RunOnUiThread([alive, ok, bytes = std::move(bytes), err = std::move(err),
                   result = std::move(result)]() mutable {
      if (!alive || !alive->load(std::memory_order_acquire)) return;
      if (ok) {
        SnapshotData data;
        data.set_bytes(std::move(bytes));
        result(std::optional<SnapshotData>(std::move(data)));
      } else {
        result(FlutterError("SNAPSHOT_FAIL", err));
      }
    });
  });
}

void XueHuaNaviteVideoPlayerPlugin::GetDuration(
    const DurationProbeRequest& request,
    std::function<void(ErrorOr<std::optional<int64_t>> reply)> result) {
  const std::string url = request.url();
  const int timeout_ms =
      request.timeout_ms() > 0 ? static_cast<int>(request.timeout_ms()) : 15000;
  auto alive = alive_;
  LaunchWorker([this, alive, url, timeout_ms, result = std::move(result)]() mutable {
    const int64_t duration_ms = url.empty() ? 0 : MpvPlayer::GetDurationMs(url, timeout_ms);
    RunOnUiThread([alive, duration_ms, result = std::move(result)]() mutable {
      if (!alive || !alive->load(std::memory_order_acquire)) return;
      if (duration_ms > 0) {
        result(std::optional<int64_t>(duration_ms));
      } else {
        result(std::optional<int64_t>(std::nullopt));
      }
    });
  });
}

void XueHuaNaviteVideoPlayerPlugin::ExtractCovers(
    const CoverExtractRequest& request,
    std::function<void(ErrorOr<::flutter::EncodableList> reply)> result) {
  const std::string url = request.url();
  const int count = static_cast<int>(request.count());
  const int candidates = static_cast<int>(request.candidates());
  const double min_brightness = request.min_brightness();
  std::string output_dir = request.output_dir();
  if (output_dir.empty()) {
    output_dir = DefaultCoverDir();
  } else {
    std::error_code ec;
    std::filesystem::create_directories(Utf8ToWide(output_dir), ec);
  }

  auto alive = alive_;
  LaunchWorker([this, alive, url, count, candidates, min_brightness, output_dir,
                result = std::move(result)]() mutable {
    auto frames =
        MpvPlayer::ExtractCovers(url, count, candidates, min_brightness, output_dir);
    ::flutter::EncodableList list;
    list.reserve(frames.size());
    for (const auto& f : frames) {
      list.emplace_back(
          ::flutter::CustomEncodableValue(CoverFrameData(f.path, f.position_ms, f.brightness)));
    }
    RunOnUiThread([alive, list = std::move(list), result = std::move(result)]() mutable {
      if (!alive || !alive->load(std::memory_order_acquire)) return;
      result(std::move(list));
    });
  });
}

void XueHuaNaviteVideoPlayerPlugin::ConfigureCache(
    const CacheConfigRequest& /*request*/,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg));
}

void XueHuaNaviteVideoPlayerPlugin::Precache(
    const PrecacheRequest& /*request*/,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg));
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::CancelPrecache(
    const std::string& /*cache_key*/) {
  return FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg);
}

void XueHuaNaviteVideoPlayerPlugin::IsCached(
    const CacheEntryRequest& /*request*/,
    std::function<void(ErrorOr<bool> reply)> result) {
  result(FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg));
}

void XueHuaNaviteVideoPlayerPlugin::GetCacheSize(
    const std::string* /*cache_dir*/,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  result(FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg));
}

void XueHuaNaviteVideoPlayerPlugin::RemoveCache(
    const CacheEntryRequest& /*request*/,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg));
}

void XueHuaNaviteVideoPlayerPlugin::ClearCache(
    const std::string* /*cache_dir*/,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg));
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::PinCacheKey(
    const std::string& /*cache_key*/) {
  return FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg);
}

std::optional<FlutterError> XueHuaNaviteVideoPlayerPlugin::UnpinCacheKey(
    const std::string& /*cache_key*/) {
  return FlutterError("UNSUPPORTED", kDesktopCacheUnsupportedMsg);
}

}  // namespace xue_hua_navite_video_player
