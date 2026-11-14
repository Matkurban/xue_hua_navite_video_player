#include "player_api.g.h"

#include <gtest/gtest.h>

#include <string>

namespace xue_hua_navite_video_player {
namespace test {

// Full plugin lifecycle requires a live Flutter TextureRegistrar and HWND.
// Verify the generated Pigeon API contracts and codec structures here; end-to-end
// playback checks live in example/integration_test/.

TEST(XueHuaNaviteVideoPlayerPlugin, CodecRoundTripsPlayerEventData) {
  PlayerEventData original(NativePlayerEventType::kCastState);
  original.set_cast_state(NativeCastState::kConnected);
  original.set_cast_device_name("Living Room TV");

  const ::flutter::EncodableValue encoded{
      ::flutter::CustomEncodableValue(original)};
  const auto bytes = PlayerHostApi::GetCodec().EncodeMessage(encoded);
  ASSERT_NE(bytes, nullptr);

  const auto decoded = PlayerHostApi::GetCodec().DecodeMessage(*bytes);
  ASSERT_NE(decoded, nullptr);
  const auto& custom = std::get<::flutter::CustomEncodableValue>(*decoded);
  const auto& round_tripped = std::any_cast<const PlayerEventData&>(custom);

  EXPECT_EQ(round_tripped.kind(), NativePlayerEventType::kCastState);
  ASSERT_NE(round_tripped.cast_state(), nullptr);
  EXPECT_EQ(*round_tripped.cast_state(), NativeCastState::kConnected);
  ASSERT_NE(round_tripped.cast_device_name(), nullptr);
  EXPECT_EQ(*round_tripped.cast_device_name(), "Living Room TV");
}

TEST(XueHuaNaviteVideoPlayerPlugin, WrapsFlutterErrorForPigeonChannel) {
  const auto wrapped = PlayerHostApi::WrapError(
      FlutterError("NO_PLAYER", "Player not initialized"));
  const auto& list = std::get<::flutter::EncodableList>(wrapped);
  ASSERT_EQ(list.size(), 3u);
  EXPECT_EQ(std::get<std::string>(list[0]), "NO_PLAYER");
  EXPECT_EQ(std::get<std::string>(list[1]), "Player not initialized");
}

}  // namespace test
}  // namespace xue_hua_navite_video_player
