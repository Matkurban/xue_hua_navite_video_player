#include "xue_hua_navite_video_player_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <windows.h>

#include <cstring>
#include <filesystem>
#include <memory>
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
		: registrar_(registrar), texture_registrar_(registrar->texture_registrar()) {
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
			// Safety-net poll: fires WM_TIMER at 100 Hz (every 10 ms is overkill — we
			// use 100 ms which is invisible for UI state but still catches any lost
			// cross-thread wakeup). Rendering is still driven by mpv's render-update
			// callback, so this does not burn CPU on video decode.
			SetTimer(message_window_, /*id=*/1, /*ms=*/100, nullptr);
		}
	}

	XueHuaNaviteVideoPlayerPlugin::~XueHuaNaviteVideoPlayerPlugin() {
		DisposePlayer();
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
			// Cheap: just property-change notifications dispatching into event sink.
			self->drain_posted_.store(false);
			if (self->player_) self->player_->DrainEvents();
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
			// mpv SW render runs on this dedicated worker; MarkTextureFrameAvailable
			// is documented as thread-safe so it's fine to call from here.
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
			// Signal the dedicated render worker — do NOT render on the platform
			// thread. mpv's SW render is heavy enough that running it on the
			// platform thread starves the Flutter UI.
			render_request_.store(true, std::memory_order_release);
			render_cv_.notify_one();
			});
		p->SetOnPosition([this](int64_t ms) { SendEvent("position", flutter::EncodableValue(ms)); });
		p->SetOnDuration([this](int64_t ms) { SendEvent("duration", flutter::EncodableValue(ms)); });
		p->SetOnPlaying([this](bool pl) { SendEvent("playing", flutter::EncodableValue(pl)); });
		p->SetOnBuffering([this](bool b) { SendEvent("buffering", flutter::EncodableValue(b)); });
		p->SetOnCompleted([this]() { SendEvent("completed", flutter::EncodableValue()); });
		p->SetOnError([this](const std::string& m) { SendEvent("error", flutter::EncodableValue(m)); });
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
		// Spin up the dedicated render worker once the player exists.
		if (!render_thread_.joinable()) {
			render_thread_stop_.store(false, std::memory_order_release);
			render_thread_ = std::thread([this]() { RenderLoop(); });
		}
	}

	int64_t XueHuaNaviteVideoPlayerPlugin::CreateTextureIfNeeded() {
		EnsurePlayer();
		if (texture_id_ >= 0) return texture_id_;
		texture_variant_ = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
			[this](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
				std::lock_guard<std::mutex> lk(pixel_mutex_);
				if (pixel_buffer_.buffer == nullptr) return nullptr;
				return &pixel_buffer_;
			}));
		texture_id_ = texture_registrar_->RegisterTexture(texture_variant_.get());
		return texture_id_;
	}

	void XueHuaNaviteVideoPlayerPlugin::DisposePlayer() {
		// Stop the render worker first so it doesn't touch a half-destroyed player.
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
		if (GetCurrentThreadId() == platform_thread_id_ || !message_window_) {
			result->Success(std::move(value));
			return;
		}
		auto* payload = new std::pair<
			std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>,
			flutter::EncodableValue>(std::move(result), std::move(value));
		if (!PostMessageW(message_window_, kMsgMethodReply, 0, reinterpret_cast<LPARAM>(payload))) {
			delete payload;
		}
	}

	void XueHuaNaviteVideoPlayerPlugin::HandleMethodCall(
		const flutter::MethodCall<flutter::EncodableValue>& call,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
		const auto& name = call.method_name();
		const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

		if (name == "create") { result->Success(flutter::EncodableValue(CreateTextureIfNeeded())); return; }
		if (name == "open") {
			EnsurePlayer();
			if (args) {
				const auto* url = GetArg<std::string>(args, "url");
				if (url && player_) { player_->Open(*url); SendEvent("buffering", flutter::EncodableValue(true)); }
			}
			result->Success(); return;
		}
		if (name == "play") { if (player_) player_->Play();  result->Success(); return; }
		if (name == "pause") { if (player_) player_->Pause(); result->Success(); return; }
		if (name == "seek") {
			if (args && player_) {
				if (const auto* pos = GetArg<int64_t>(args, "position")) player_->Seek(*pos);
				else if (const auto* p32 = GetArg<int32_t>(args, "position")) player_->Seek(static_cast<int64_t>(*p32));
			}
			result->Success(); return;
		}
		if (name == "setVolume") {
			if (args && player_) { if (const auto* v = GetArg<double>(args, "volume")) player_->SetVolume(*v); }
			result->Success(); return;
		}
		if (name == "setSpeed") {
			if (args && player_) { if (const auto* s = GetArg<double>(args, "speed")) player_->SetSpeed(*s); }
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
		if (name == "dispose") { DisposePlayer(); result->Success(); return; }
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
			std::thread([this, url, count, candidates, min_brightness, output_dir, shared]() {
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
				}).detach();
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
			std::thread([this, url, timeout_ms, shared]() {
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
				}).detach();
			return;
		}
		if (name == "getPlatformVersion") {
			// Use RtlGetVersion (ntdll) to get the real OS build; GetVersion /
			// GetVersionEx are deprecated and lie on Windows 8.1+ without a manifest.
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
					if (fn(&info) == 0 /* STATUS_SUCCESS */) {
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
