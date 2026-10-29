#include "xue_hua_navite_video_player_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
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
#include <sstream>
#include <string>
#include <thread>
#include <variant>
#include <vector>

namespace xue_hua_navite_video_player {

	namespace {

		constexpr wchar_t kMessageWindowClass[] = L"FcvpMpvMessageWindow";

		std::string WideToUtf8(const std::wstring& w) {
			if (w.empty()) return {};
			int sz = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
			std::string s(sz, '\0');
			WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), s.data(), sz, nullptr, nullptr);
			return s;
		}

		std::wstring Utf8ToWide(const std::string& s) {
			if (s.empty()) return {};
			int sz = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
			std::wstring w(sz, L'\0');
			MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), w.data(), sz);
			return w;
		}

		std::string DefaultCoverDir() {
			wchar_t tmp[MAX_PATH] = { 0 };
			GetTempPathW(MAX_PATH, tmp);
			std::wstring dir = std::wstring(tmp) + L"xue_hua_navite_video_player\\covers";
			std::error_code ec;
			std::filesystem::create_directories(dir, ec);
			return WideToUtf8(dir);
		}

		template <typename T>
		const T* GetArg(const flutter::EncodableMap* map, const char* key) {
			auto it = map->find(flutter::EncodableValue(key));
			if (it == map->end()) return nullptr;
			return std::get_if<T>(&it->second);
		}

	}  // namespace

	struct WinRtCastContext {
		winrt::Windows::Media::Casting::CastingDevicePicker picker{ nullptr };
		winrt::Windows::Media::Casting::CastingConnection connection{ nullptr };
		winrt::Windows::Media::Playback::MediaPlayer media_player{ nullptr };
		winrt::event_token selected_token{};
		winrt::event_token state_changed_token{};
		winrt::event_token error_token{};
		bool is_casting = false;
		std::string device_name;
	};

	void XueHuaNaviteVideoPlayerPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
		auto plugin = std::make_unique<XueHuaNaviteVideoPlayerPlugin>(registrar);

		auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
			registrar->messenger(), "xue_hua_navite_video_player/player",
			&flutter::StandardMethodCodec::GetInstance());
		auto* raw = plugin.get();
		method_channel->SetMethodCallHandler(
			[raw](const auto& call, auto result) { raw->HandleMethodCall(call, std::move(result)); });
		plugin->method_channel_ = std::move(method_channel);

		auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
			registrar->messenger(), "xue_hua_navite_video_player/player/events",
			&flutter::StandardMethodCodec::GetInstance());
		event_channel->SetStreamHandler(
			std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
				[raw](const flutter::EncodableValue*,
					std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
				-> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
					raw->event_sink_ = std::move(events);
					if (raw->cast_ctx_ && raw->cast_ctx_->is_casting) {
						raw->SendCastState("connected", raw->cast_ctx_->device_name);
					} else {
						raw->SendCastState("notConnected");
					}
					return nullptr;
				},
				[raw](const flutter::EncodableValue*)
				-> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
					raw->event_sink_.reset();
					return nullptr;
				}));
		plugin->event_channel_ = std::move(event_channel);

		registrar->AddPlugin(std::move(plugin));
	}

	XueHuaNaviteVideoPlayerPlugin::XueHuaNaviteVideoPlayerPlugin(flutter::PluginRegistrarWindows* registrar)
		: registrar_(registrar), texture_registrar_(registrar->texture_registrar()),
		  cast_ctx_(std::make_unique<WinRtCastContext>()) {
		platform_thread_id_ = GetCurrentThreadId();
		WNDCLASSEXW wc = {};
		wc.cbSize = sizeof(wc);
		wc.lpfnWndProc = &XueHuaNaviteVideoPlayerPlugin::MessageProc;
		wc.hInstance = GetModuleHandle(nullptr);
		wc.lpszClassName = kMessageWindowClass;
		RegisterClassExW(&wc);
		message_window_ = CreateWindowExW(0, kMessageWindowClass, L"", 0, 0, 0, 0, 0,
			HWND_MESSAGE, nullptr, wc.hInstance, this);
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
		RestoreWindowFullscreen();
		if (window_proc_id_ >= 0 && registrar_) {
			registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
			window_proc_id_ = -1;
		}
		RestoreBrightness();
		DisposePlayer();
		JoinProbeWorkers();
		if (message_window_) {
			KillTimer(message_window_, 1);
			DestroyWindow(message_window_);
			message_window_ = nullptr;
		}
	}

	LRESULT CALLBACK XueHuaNaviteVideoPlayerPlugin::MessageProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
		auto* self = reinterpret_cast<XueHuaNaviteVideoPlayerPlugin*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
		if (!self) return DefWindowProcW(hwnd, msg, w, l);
		if (msg == kMsgDrain || msg == WM_TIMER) {
			self->drain_posted_.store(false);
			if (self->player_ && !(self->cast_ctx_ && self->cast_ctx_->is_casting)) {
				self->player_->DrainEvents();
			} else if (self->cast_ctx_ && self->cast_ctx_->is_casting && self->cast_ctx_->media_player) {
				try {
					auto session = self->cast_ctx_->media_player.PlaybackSession();
					auto pos_ms = std::chrono::duration_cast<std::chrono::milliseconds>(session.Position()).count();
					if (pos_ms >= 0) {
						self->last_local_position_ms_ = pos_ms;
						self->SendEvent("position", flutter::EncodableValue(static_cast<int64_t>(pos_ms)));
					}
					auto dur_ms = std::chrono::duration_cast<std::chrono::milliseconds>(session.NaturalDuration()).count();
					if (dur_ms > 0) {
						self->SendEvent("duration", flutter::EncodableValue(static_cast<int64_t>(dur_ms)));
					}
				} catch (...) {}
			}
			return 0;
		}
		if (msg == kMsgSendEvent) {
			auto* payload = reinterpret_cast<std::pair<std::string, flutter::EncodableValue>*>(l);
			if (payload) {
				self->SendEvent(payload->first, std::move(payload->second));
				delete payload;
			}
			return 0;
		}
		if (msg == kMsgMethodReply) {
			auto* payload = reinterpret_cast<
				std::pair<std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>,
					flutter::EncodableValue>*>(l);
			if (payload) {
				if (payload->first) {
					payload->first->Success(std::move(payload->second));
				}
				delete payload;
			}
			return 0;
		}
		return DefWindowProcW(hwnd, msg, w, l);
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
				if (texture_id_ >= 0)
					texture_registrar_->MarkTextureFrameAvailable(texture_id_);
			}
		}
	}

	void XueHuaNaviteVideoPlayerPlugin::EnsurePlayer() {
		if (player_) return;
		auto p = std::make_unique<MpvPlayer>();
		std::string err;
		if (!p->Initialize(&err)) {
			SendEvent("error", flutter::EncodableValue("mpv init failed: " + err));
			return;
		}
		HWND hwnd = message_window_;
		p->SetWakeupHandler([this, hwnd]() {
			bool expected = false;
			if (drain_posted_.compare_exchange_strong(expected, true))
				PostMessageW(hwnd, kMsgDrain, 0, 0);
			});
		p->SetUpdateHandler([this]() {
			render_request_.store(true, std::memory_order_release);
			render_cv_.notify_one();
			});
		p->SetOnPosition([this](int64_t ms) {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			last_local_position_ms_ = ms;
			SendEvent("position", flutter::EncodableValue(ms));
			});
		p->SetOnBuffered([this](int64_t ms) {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			SendEvent("buffered", flutter::EncodableValue(ms));
			});
		p->SetOnDuration([this](int64_t ms) {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			SendEvent("duration", flutter::EncodableValue(ms));
			});
		p->SetOnPlaying([this](bool pl) {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			local_playing_ = pl;
			SendEvent("playing", flutter::EncodableValue(pl));
			});
		p->SetOnBuffering([this](bool b) {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			SendEvent("buffering", flutter::EncodableValue(b));
			});
		p->SetOnCompleted([this]() {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			SendEvent("completed", flutter::EncodableValue());
			});
		p->SetOnError([this](const std::string& m) {
			if (cast_ctx_ && cast_ctx_->is_casting) return;
			SendEvent("error", flutter::EncodableValue(m));
			});
		p->SetOnFrame([this](const uint8_t* rgba, uint32_t w, uint32_t h) {
			std::lock_guard<std::mutex> lk(pixel_mutex_);
			size_t need = static_cast<size_t>(w) * h * 4;
			if (pixel_buffer_data_.size() < need) pixel_buffer_data_.resize(need);
			std::memcpy(pixel_buffer_data_.data(), rgba, need);
			pixel_buffer_.buffer = pixel_buffer_data_.data();
			pixel_buffer_.width = w;
			pixel_buffer_.height = h;
			});
		p->SetOnVideoSize([this](int64_t w, int64_t h) {
			if (w <= 0 || h <= 0) return;
			flutter::EncodableMap size;
			size[flutter::EncodableValue("width")] = flutter::EncodableValue(w);
			size[flutter::EncodableValue("height")] = flutter::EncodableValue(h);
			SendEvent("videoSize", flutter::EncodableValue(std::move(size)));
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
		SendCastState("notConnected");
		if (texture_id_ >= 0) return texture_id_;
		{
			std::lock_guard<std::mutex> lk(pixel_mutex_);
			if (pixel_buffer_.buffer == nullptr) {
				pixel_buffer_data_.assign({ 0, 0, 0, 255 });
				pixel_buffer_.buffer = pixel_buffer_data_.data();
				pixel_buffer_.width = 1;
				pixel_buffer_.height = 1;
			}
		}
		texture_variant_ = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
			[this](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
				std::lock_guard<std::mutex> lk(pixel_mutex_);
				if (pixel_buffer_.buffer == nullptr) {
					static const uint8_t kPlaceholder[] = { 0, 0, 0, 255 };
					static FlutterDesktopPixelBuffer placeholder{
						kPlaceholder, 1, 1, nullptr, nullptr };
					return &placeholder;
				}
				return &pixel_buffer_;
			}));
		texture_id_ = texture_registrar_->RegisterTexture(texture_variant_.get());
		return texture_id_;
	}

	void XueHuaNaviteVideoPlayerPlugin::DisposePlayer() {
		StopCasting();
		if (render_thread_.joinable()) {
			render_thread_stop_.store(true, std::memory_order_release);
			render_cv_.notify_all();
			render_thread_.join();
		}
		if (player_) player_.reset();
		if (texture_id_ >= 0) { texture_registrar_->UnregisterTexture(texture_id_); texture_id_ = -1; }
		texture_variant_.reset();
		std::lock_guard<std::mutex> lk(pixel_mutex_);
		pixel_buffer_.buffer = nullptr;
		pixel_buffer_.width = 0;
		pixel_buffer_.height = 0;
		pixel_buffer_data_.clear();
	}

	void XueHuaNaviteVideoPlayerPlugin::SendCastState(
		const std::string& state, const std::string& device_name) {
		flutter::EncodableMap payload;
		payload[flutter::EncodableValue("state")] = flutter::EncodableValue(state);
		if (!device_name.empty()) {
			payload[flutter::EncodableValue("deviceName")] = flutter::EncodableValue(device_name);
		}
		SendEvent("castState", flutter::EncodableValue(std::move(payload)));
	}

	void XueHuaNaviteVideoPlayerPlugin::OpenCastMediaIfActive(const std::string& url) {
		if (!cast_ctx_ || !cast_ctx_->is_casting || !cast_ctx_->media_player || url.empty()) {
			return;
		}
		try {
			winrt::Windows::Foundation::Uri uri(Utf8ToWide(url));
			auto source = winrt::Windows::Media::Core::MediaSource::CreateFromUri(uri);
			cast_ctx_->media_player.Source(source);
		} catch (...) {}
	}

	void XueHuaNaviteVideoPlayerPlugin::ShowCastPicker() {
		HWND hwnd = RootWindow();
		if (!hwnd || !cast_ctx_) return;
		try {
			using namespace winrt::Windows::Media::Casting;
			using namespace winrt::Windows::Media::Playback;
			using namespace winrt::Windows::Media::Core;
			using namespace winrt::Windows::Foundation;

			if (!cast_ctx_->picker) {
				CastingDevicePicker picker;
				picker.Filter().SupportsVideo(true);
				cast_ctx_->selected_token = picker.CastingDeviceSelected(
					[this](const CastingDevicePicker& /*sender*/, const CastingDeviceSelectedEventArgs& args) {
						try {
							auto device = args.SelectedCastingDevice();
							std::string dev_name = WideToUtf8(std::wstring(device.FriendlyName().c_str()));
							if (dev_name.empty()) dev_name = "Windows Cast";
							cast_ctx_->device_name = dev_name;
							SendCastState("connecting", dev_name);

							const bool was_playing = local_playing_;
							const int64_t resume_ms = last_local_position_ms_;
							if (player_) player_->Pause();

							if (!cast_ctx_->media_player) {
								cast_ctx_->media_player = MediaPlayer();
								cast_ctx_->media_player.MediaEnded([this](const MediaPlayer&, const IInspectable&) {
									SendEvent("playing", flutter::EncodableValue(false));
									SendEvent("completed", flutter::EncodableValue());
								});
								cast_ctx_->media_player.CurrentStateChanged([this](const MediaPlayer& mp, const IInspectable&) {
									try {
										auto state = mp.PlaybackSession().PlaybackState();
										SendEvent("buffering", flutter::EncodableValue(
											state == MediaPlaybackState::Buffering || state == MediaPlaybackState::Opening));
										SendEvent("playing", flutter::EncodableValue(
											state == MediaPlaybackState::Playing));
									} catch (...) {}
								});
							}

							const std::string target_url = !current_cast_url_.empty() ? current_cast_url_ : current_url_;
							if (!target_url.empty()) {
								Uri uri(Utf8ToWide(target_url));
								cast_ctx_->media_player.Source(MediaSource::CreateFromUri(uri));
								cast_ctx_->media_player.Volume(current_volume_);
								cast_ctx_->media_player.PlaybackSession().PlaybackRate(current_speed_);
								cast_ctx_->media_player.PlaybackSession().Position(std::chrono::milliseconds(resume_ms));
								if (was_playing) {
									cast_ctx_->media_player.Play();
								}
							}

							auto conn = device.CreateCastingConnection();
							cast_ctx_->connection = conn;
							conn.StateChanged([this](const CastingConnection& c, const IInspectable&) {
								try {
									switch (c.State()) {
									case CastingConnectionState::Connected:
									case CastingConnectionState::Rendering:
										cast_ctx_->is_casting = true;
										SendCastState("connected", cast_ctx_->device_name);
										break;
									case CastingConnectionState::Connecting:
										SendCastState("connecting", cast_ctx_->device_name);
										break;
									case CastingConnectionState::Disconnecting:
										SendCastState("disconnecting", cast_ctx_->device_name);
										break;
									case CastingConnectionState::Disconnected:
										if (cast_ctx_->is_casting) {
											cast_ctx_->is_casting = false;
											if (player_) {
												player_->Pause();
												player_->Seek(last_local_position_ms_);
											}
											SendEvent("playing", flutter::EncodableValue(false));
										}
										SendCastState("notConnected");
										break;
									}
								} catch (...) {}
							});
							conn.RequestStartCastingAsync(cast_ctx_->media_player.GetAsCastingSource());
						} catch (...) {
							SendCastState("notConnected");
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
			cast_ctx_->picker.Show(
				winrt::Windows::Foundation::Rect{ x, 48.0f, 1.0f, 1.0f },
				winrt::Windows::UI::Popups::Placement::Below);
		} catch (...) {
			// Safe no-op if Windows Casting API is unavailable on current SKU.
		}
	}

	void XueHuaNaviteVideoPlayerPlugin::StopCasting() {
		if (!cast_ctx_ || !cast_ctx_->is_casting) return;
		cast_ctx_->is_casting = false;
		try {
			if (cast_ctx_->media_player) {
				auto pos_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
					cast_ctx_->media_player.PlaybackSession().Position()).count();
				if (pos_ms >= 0) {
					last_local_position_ms_ = pos_ms;
				}
				cast_ctx_->media_player.Pause();
			}
			if (cast_ctx_->connection) {
				cast_ctx_->connection.DisconnectAsync();
				cast_ctx_->connection = nullptr;
			}
		} catch (...) {}
		if (player_) {
			player_->Pause();
			if (last_local_position_ms_ > 0) {
				player_->Seek(last_local_position_ms_);
			}
		}
		SendEvent("playing", flutter::EncodableValue(false));
		SendCastState("notConnected");
	}

	void XueHuaNaviteVideoPlayerPlugin::SendEvent(const std::string& name, flutter::EncodableValue value) {
		if (GetCurrentThreadId() != platform_thread_id_) {
			SendEventOnPlatformThread(name, std::move(value));
			return;
		}
		if (!event_sink_) return;
		flutter::EncodableMap map;
		map[flutter::EncodableValue("event")] = flutter::EncodableValue(name);
		map[flutter::EncodableValue("value")] = std::move(value);
		event_sink_->Success(flutter::EncodableValue(std::move(map)));
	}

	void XueHuaNaviteVideoPlayerPlugin::SendEventOnPlatformThread(
		const std::string& name, flutter::EncodableValue value) {
		if (!message_window_) return;
		auto* payload = new std::pair<std::string, flutter::EncodableValue>(name, std::move(value));
		if (!PostMessageW(message_window_, kMsgSendEvent, 0, reinterpret_cast<LPARAM>(payload))) {
			delete payload;
		}
	}

	void XueHuaNaviteVideoPlayerPlugin::ReplyOnPlatformThread(
		std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
		flutter::EncodableValue value) {
		if (!result) return;
		if (GetCurrentThreadId() == platform_thread_id_) {
			result->Success(std::move(value));
			return;
		}
		if (!message_window_) {
			return;
		}
		auto* payload = new std::pair<
			std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>,
			flutter::EncodableValue>(std::move(result), std::move(value));
		if (!PostMessageW(message_window_, kMsgMethodReply, 0, reinterpret_cast<LPARAM>(payload))) {
			delete payload;
		}
	}

	void XueHuaNaviteVideoPlayerPlugin::LaunchProbe(std::function<void()> fn) {
		std::lock_guard<std::mutex> lock(probe_mutex_);
		probe_threads_.emplace_back(std::move(fn));
	}

	void XueHuaNaviteVideoPlayerPlugin::JoinProbeWorkers() {
		std::vector<std::thread> threads;
		{
			std::lock_guard<std::mutex> lock(probe_mutex_);
			threads.swap(probe_threads_);
		}
		for (auto& t : threads) {
			if (t.joinable()) t.join();
		}
	}

	bool XueHuaNaviteVideoPlayerPlugin::QueryMonitorBrightness(
		DWORD* min_out, DWORD* current_out, DWORD* max_out) {
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
		const bool ok = GetMonitorBrightness(
			monitors[0].hPhysicalMonitor, min_out, current_out, max_out) == TRUE;
		DestroyPhysicalMonitors(count, monitors.data());
		return ok;
	}

	bool XueHuaNaviteVideoPlayerPlugin::ApplyMonitorBrightness(DWORD value) {
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
		const bool ok = SetMonitorBrightness(monitors[0].hPhysicalMonitor, value) == TRUE;
		DestroyPhysicalMonitors(count, monitors.data());
		return ok;
	}

	double XueHuaNaviteVideoPlayerPlugin::GetBrightness() {
		DWORD min_b = 0, cur_b = 0, max_b = 0;
		if (!QueryMonitorBrightness(&min_b, &cur_b, &max_b) || max_b <= min_b) {
			return 1.0;
		}
		return (static_cast<double>(cur_b - min_b) / static_cast<double>(max_b - min_b));
	}

	void XueHuaNaviteVideoPlayerPlugin::SetBrightness(double value) {
		DWORD min_b = 0, cur_b = 0, max_b = 0;
		if (!QueryMonitorBrightness(&min_b, &cur_b, &max_b) || max_b <= min_b) {
			return;
		}
		if (!brightness_saved_) {
			saved_brightness_ = cur_b;
			brightness_saved_ = true;
		}
		const double clamped = std::clamp(value, 0.0, 1.0);
		const DWORD target = min_b + static_cast<DWORD>((max_b - min_b) * clamped + 0.5);
		ApplyMonitorBrightness(target);
	}

	void XueHuaNaviteVideoPlayerPlugin::RestoreBrightness() {
		if (!brightness_saved_) return;
		brightness_saved_ = false;
		ApplyMonitorBrightness(saved_brightness_);
	}

	namespace {
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

	HWND XueHuaNaviteVideoPlayerPlugin::RootWindow() const {
		HWND hwnd = nullptr;
		if (registrar_ && registrar_->GetView()) {
			hwnd = registrar_->GetView()->GetNativeWindow();
		}
		if (!hwnd) return nullptr;
		HWND root = GetAncestor(hwnd, GA_ROOT);
		return root ? root : hwnd;
	}

	void XueHuaNaviteVideoPlayerPlugin::NotifyWindowFullscreen(bool fullscreen) {
		if (!method_channel_) return;
		method_channel_->InvokeMethod(
			"onWindowFullscreen",
			std::make_unique<flutter::EncodableValue>(fullscreen));
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

	void XueHuaNaviteVideoPlayerPlugin::SetWindowFullscreen(bool enable) {
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

				SetWindowLongPtrW(hwnd, GWL_STYLE,
					saved_style_ & ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MAXIMIZEBOX | WS_MINIMIZEBOX));
				SetWindowLongPtrW(hwnd, GWL_EXSTYLE,
					saved_ex_style_ & ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));
				SetWindowPos(hwnd, HWND_TOP,
					mi.rcMonitor.left, mi.rcMonitor.top,
					mi.rcMonitor.right - mi.rcMonitor.left,
					mi.rcMonitor.bottom - mi.rcMonitor.top,
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
		HWND /*hwnd*/, UINT message, WPARAM /*wparam*/, LPARAM /*lparam*/) {
		if (applying_window_fullscreen_ || !window_fullscreen_) {
			return std::nullopt;
		}
		if (message == WM_WINDOWPOSCHANGED || message == WM_SIZE || message == WM_EXITSIZEMOVE) {
			CheckWindowFullscreenLost();
		}
		return std::nullopt;
	}

	void XueHuaNaviteVideoPlayerPlugin::HandleMethodCall(
		const flutter::MethodCall<flutter::EncodableValue>& call,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
		const auto& name = call.method_name();
		const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

		if (name == "create") {
			const int64_t id = CreateTextureIfNeeded();
			if (id < 0) {
				result->Error("CREATE_FAIL", "Failed to initialize native player");
				return;
			}
			result->Success(flutter::EncodableValue(id));
			return;
		}
		if (name == "open") {
			EnsurePlayer();
			if (args) {
				const auto* url = GetArg<std::string>(args, "url");
				const auto* cast_url = GetArg<std::string>(args, "castUrl");
				current_cast_url_ = cast_url ? *cast_url : "";
				if (url) {
					current_url_ = *url;
					last_local_position_ms_ = 0;
					if (player_) {
						player_->Open(*url);
						SendEvent("buffering", flutter::EncodableValue(true));
					}
					OpenCastMediaIfActive(!current_cast_url_.empty() ? current_cast_url_ : current_url_);
				}
			}
			result->Success(); return;
		}
		if (name == "play") {
			if (cast_ctx_ && cast_ctx_->is_casting && cast_ctx_->media_player) {
				try { cast_ctx_->media_player.Play(); } catch (...) {}
			} else if (player_) {
				player_->Play();
			}
			result->Success(); return;
		}
		if (name == "pause") {
			if (cast_ctx_ && cast_ctx_->is_casting && cast_ctx_->media_player) {
				try { cast_ctx_->media_player.Pause(); } catch (...) {}
			} else if (player_) {
				player_->Pause();
			}
			result->Success(); return;
		}
		if (name == "seek") {
			int64_t seek_ms = 0;
			bool has_seek = false;
			if (args) {
				if (const auto* pos = GetArg<int64_t>(args, "position")) { seek_ms = *pos; has_seek = true; }
				else if (const auto* p32 = GetArg<int32_t>(args, "position")) { seek_ms = static_cast<int64_t>(*p32); has_seek = true; }
			}
			if (has_seek) {
				last_local_position_ms_ = seek_ms;
				if (cast_ctx_ && cast_ctx_->is_casting && cast_ctx_->media_player) {
					try {
						cast_ctx_->media_player.PlaybackSession().Position(std::chrono::milliseconds(seek_ms));
					} catch (...) {}
				} else if (player_) {
					player_->Seek(seek_ms);
				}
			}
			result->Success(); return;
		}
		if (name == "setVolume") {
			if (args) {
				if (const auto* v = GetArg<double>(args, "volume")) {
					current_volume_ = std::clamp(*v, 0.0, 1.0);
					if (player_) player_->SetVolume(current_volume_);
					if (cast_ctx_ && cast_ctx_->media_player) {
						try { cast_ctx_->media_player.Volume(current_volume_); } catch (...) {}
					}
				}
			}
			result->Success(); return;
		}
		if (name == "setSpeed") {
			if (args) {
				if (const auto* s = GetArg<double>(args, "speed")) {
					current_speed_ = *s;
					if (player_) player_->SetSpeed(current_speed_);
					if (cast_ctx_ && cast_ctx_->media_player) {
						try { cast_ctx_->media_player.PlaybackSession().PlaybackRate(current_speed_); } catch (...) {}
					}
				}
			}
			result->Success(); return;
		}
		if (name == "setAspectRatioMode") {
			EnsurePlayer();
			if (args && player_) {
				if (const auto* mode = GetArg<std::string>(args, "mode")) {
					player_->SetAspectRatioMode(*mode);
				}
			}
			result->Success(); return;
		}
		if (name == "setVideoViewSize") {
			EnsurePlayer();
			if (args && player_) {
				double width = 0, height = 0, dpr = 1.0;
				if (const auto* w = GetArg<double>(args, "width")) width = *w;
				else if (const auto* wi = GetArg<int32_t>(args, "width")) width = *wi;
				if (const auto* h = GetArg<double>(args, "height")) height = *h;
				else if (const auto* hi = GetArg<int32_t>(args, "height")) height = *hi;
				if (const auto* r = GetArg<double>(args, "devicePixelRatio")) dpr = *r;
				if (dpr <= 0) dpr = 1.0;
				player_->SetVideoViewSize(
					static_cast<uint32_t>(width * dpr + 0.5),
					static_cast<uint32_t>(height * dpr + 0.5));
			}
			result->Success(); return;
		}
		if (name == "showCastPicker") {
			ShowCastPicker();
			result->Success();
			return;
		}
		if (name == "stopCasting") {
			StopCasting();
			result->Success();
			return;
		}
		if (name == "dispose") {
			RestoreBrightness();
			DisposePlayer();
			result->Success();
			return;
		}
		if (name == "getBrightness") {
			result->Success(flutter::EncodableValue(GetBrightness()));
			return;
		}
		if (name == "setBrightness") {
			double value = 1.0;
			if (args) {
				if (const auto* v = GetArg<double>(args, "value")) value = *v;
			}
			SetBrightness(value);
			result->Success();
			return;
		}
		if (name == "setWindowFullscreen") {
			bool enable = false;
			if (args) {
				if (const auto* v = GetArg<bool>(args, "value")) enable = *v;
			}
			SetWindowFullscreen(enable);
			result->Success();
			return;
		}
		if (name == "takeSnapshot") {
			if (!player_) { result->Error("NO_PLAYER", "Player not initialized"); return; }
			std::vector<uint8_t> bytes;
			std::string err;
			if (player_->TakeSnapshot(&bytes, &err)) result->Success(flutter::EncodableValue(std::move(bytes)));
			else result->Error("SNAPSHOT_FAIL", err);
			return;
		}
		if (name == "extractCovers") {
			std::string url;
			int count = 5, candidates = 15;
			double min_brightness = 0.08;
			std::string output_dir;
			if (args) {
				if (const auto* v = GetArg<std::string>(args, "url")) url = *v;
				if (const auto* v = GetArg<int32_t>(args, "count")) count = *v;
				else if (const auto* v64 = GetArg<int64_t>(args, "count")) count = static_cast<int>(*v64);
				if (const auto* v = GetArg<int32_t>(args, "candidates")) candidates = *v;
				else if (const auto* v64 = GetArg<int64_t>(args, "candidates")) candidates = static_cast<int>(*v64);
				if (const auto* v = GetArg<double>(args, "minBrightness")) min_brightness = *v;
				if (const auto* v = GetArg<std::string>(args, "outputDir")) output_dir = *v;
			}
			if (output_dir.empty()) output_dir = DefaultCoverDir();
			else { std::error_code ec; std::filesystem::create_directories(Utf8ToWide(output_dir), ec); }

			auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(result.release());
			LaunchProbe([this, url, count, candidates, min_brightness, output_dir, shared]() {
				auto frames = MpvPlayer::ExtractCovers(url, count, candidates, min_brightness, output_dir);
				flutter::EncodableList list;
				for (const auto& f : frames) {
					flutter::EncodableMap m;
					m[flutter::EncodableValue("path")] = flutter::EncodableValue(f.path);
					m[flutter::EncodableValue("positionMs")] = flutter::EncodableValue(f.position_ms);
					m[flutter::EncodableValue("brightness")] = flutter::EncodableValue(f.brightness);
					list.emplace_back(std::move(m));
				}
				ReplyOnPlatformThread(shared, flutter::EncodableValue(std::move(list)));
			});
			return;
		}
		if (name == "getDuration") {
			std::string url;
			int timeout_ms = 15000;
			if (args) {
				if (const auto* v = GetArg<std::string>(args, "url")) url = *v;
				if (const auto* v = GetArg<int32_t>(args, "timeoutMs")) timeout_ms = *v;
				else if (const auto* v64 = GetArg<int64_t>(args, "timeoutMs")) timeout_ms = static_cast<int>(*v64);
			}
			auto shared = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(result.release());
			LaunchProbe([this, url, timeout_ms, shared]() {
				int64_t duration_ms = 0;
				if (!url.empty()) {
					duration_ms = MpvPlayer::GetDurationMs(url, timeout_ms);
				}
				if (duration_ms > 0) {
					ReplyOnPlatformThread(shared, flutter::EncodableValue(duration_ms));
				}
				else {
					ReplyOnPlatformThread(shared, flutter::EncodableValue());
				}
			});
			return;
		}
		if (name == "getPlatformVersion") {
			std::ostringstream os;
			os << "Windows";
			using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
			HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
			if (ntdll != nullptr) {
				auto fn = reinterpret_cast<RtlGetVersionFn>(
					::GetProcAddress(ntdll, "RtlGetVersion"));
				if (fn != nullptr) {
					RTL_OSVERSIONINFOW info{};
					info.dwOSVersionInfoSize = sizeof(info);
					if (fn(&info) == 0) {
						os << " " << info.dwMajorVersion << "." << info.dwMinorVersion
							<< "." << info.dwBuildNumber;
					}
				}
			}
			result->Success(flutter::EncodableValue(os.str()));
			return;
		}
		result->NotImplemented();
	}

}  // namespace xue_hua_navite_video_player
