#ifndef FLUTTER_PLUGIN_XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN_H_

// Windows video player plugin — libmpv backend (software rendering).

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "mpv_player.h"

namespace xue_hua_navite_video_player {

	class XueHuaNaviteVideoPlayerPlugin : public flutter::Plugin {
	public:
		static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

		explicit XueHuaNaviteVideoPlayerPlugin(flutter::PluginRegistrarWindows* registrar);
		~XueHuaNaviteVideoPlayerPlugin() override;

		XueHuaNaviteVideoPlayerPlugin(const XueHuaNaviteVideoPlayerPlugin&) = delete;
		XueHuaNaviteVideoPlayerPlugin& operator=(const XueHuaNaviteVideoPlayerPlugin&) = delete;

		std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

	private:
		void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
			std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

		void EnsurePlayer();
		int64_t CreateTextureIfNeeded();
		void DisposePlayer();
		void SendEvent(const std::string& name, flutter::EncodableValue value);
		void SendEventOnPlatformThread(const std::string& name, flutter::EncodableValue value);
		void ReplyOnPlatformThread(
			std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
			flutter::EncodableValue value);

		flutter::PluginRegistrarWindows* registrar_;
		flutter::TextureRegistrar* texture_registrar_;
		std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
		std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;

		std::unique_ptr<MpvPlayer> player_;
		std::unique_ptr<flutter::TextureVariant> texture_variant_;
		int64_t texture_id_ = -1;
		FlutterDesktopPixelBuffer pixel_buffer_{};
		std::vector<uint8_t> pixel_buffer_data_;
		std::mutex pixel_mutex_;

		HWND message_window_ = nullptr;
		std::atomic<bool> drain_posted_{ false };
		std::atomic<bool> render_posted_{ false };
		DWORD platform_thread_id_ = 0;

		// Dedicated render worker. mpv's SW render is a *heavy* operation (decode +
		// full-frame RGBA memcpy); running it on the Flutter platform thread blocks
		// the Dart event loop and causes visible stutter. Keep render off the
		// platform thread entirely — the platform thread only handles event drain
		// and MethodChannel calls.
		std::thread render_thread_;
		std::mutex render_mutex_;
		std::condition_variable render_cv_;
		std::atomic<bool> render_request_{ false };
		std::atomic<bool> render_thread_stop_{ false };
		void RenderLoop();

		static LRESULT CALLBACK MessageProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l);
		static constexpr UINT kMsgDrain = WM_USER + 1;
		static constexpr UINT kMsgRender = WM_USER + 2;
		static constexpr UINT kMsgSendEvent = WM_USER + 3;
		static constexpr UINT kMsgMethodReply = WM_USER + 4;
	};

}  // namespace xue_hua_navite_video_player

#endif  // FLUTTER_PLUGIN_XUE_HUA_NAVITE_VIDEO_PLAYER_PLUGIN_H_
