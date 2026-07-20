#include "include/xue_hua_navite_video_player/xue_hua_navite_video_player_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "xue_hua_navite_video_player_plugin.h"

void XueHuaNaviteVideoPlayerPluginCApiRegisterWithRegistrar(
	FlutterDesktopPluginRegistrarRef registrar) {
	xue_hua_navite_video_player::XueHuaNaviteVideoPlayerPlugin::RegisterWithRegistrar(
		flutter::PluginRegistrarManager::GetInstance()
		->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
