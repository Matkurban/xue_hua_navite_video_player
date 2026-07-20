// Core
export 'src/core/video_source.dart';

// Data models
export 'src/data/models/video_cover_frame.dart';
export 'src/data/enums/play_state.dart';
export 'src/data/enums/skip_second_type.dart';
export 'src/data/enums/aspect_ratio_mode.dart';

// Player
export 'src/player/video_player_controller.dart';

// UI
export 'src/ui/core_player.dart';
export 'src/ui/video_player.dart';
export 'src/ui/style/video_player_theme.dart';
export 'src/ui/widgets/player_scrubber_slider.dart';

// App
export 'src/xue_hua_navite_video_player.dart';

// Re-export XFile so consumers can use it without adding cross_file explicitly.
export 'package:cross_file/cross_file.dart' show XFile;
