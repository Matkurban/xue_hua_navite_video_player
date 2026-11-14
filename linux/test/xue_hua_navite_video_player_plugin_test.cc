#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "include/xue_hua_navite_video_player/xue_hua_navite_video_player_plugin.h"
#include "player_api.g.h"
#include "xue_hua_navite_video_player_plugin_private.h"

namespace xue_hua_navite_video_player {
namespace test {

TEST(XueHuaNaviteVideoPlayerPlugin, AspectRatioModesMapToMpvNames) {
  EXPECT_STREQ(
      xue_hua_navite_video_player_aspect_ratio_mode_to_string(
          XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_ASPECT_RATIO_MODE_FIT),
      "fit");
  EXPECT_STREQ(
      xue_hua_navite_video_player_aspect_ratio_mode_to_string(
          XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_ASPECT_RATIO_MODE_FILL),
      "fill");
  EXPECT_STREQ(
      xue_hua_navite_video_player_aspect_ratio_mode_to_string(
          XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_ASPECT_RATIO_MODE_STRETCH),
      "stretch");
}

TEST(XueHuaNaviteVideoPlayerPlugin, PlayerEventDataCarriesCastState) {
  XueHuaNaviteVideoPlayerNativeCastState state =
      XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_CAST_STATE_CONNECTED;
  g_autoptr(XueHuaNaviteVideoPlayerPlayerEventData) event =
      xue_hua_navite_video_player_player_event_data_new(
          XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_CAST_STATE,
          nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, &state, "Linux Cast");
  ASSERT_NE(event, nullptr);
  EXPECT_EQ(xue_hua_navite_video_player_player_event_data_get_kind(event),
            XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_PLAYER_EVENT_TYPE_CAST_STATE);
  ASSERT_NE(xue_hua_navite_video_player_player_event_data_get_cast_state(event), nullptr);
  EXPECT_EQ(*xue_hua_navite_video_player_player_event_data_get_cast_state(event),
            XUE_HUA_NAVITE_VIDEO_PLAYER_NATIVE_CAST_STATE_CONNECTED);
  EXPECT_STREQ(xue_hua_navite_video_player_player_event_data_get_cast_device_name(event),
               "Linux Cast");
}

}  // namespace test
}  // namespace xue_hua_navite_video_player
