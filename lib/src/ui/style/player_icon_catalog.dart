import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/enums/cast_state.dart';
import '../../data/enums/skip_second_type.dart';

/// Resolves theme-specific icons for Material and Cupertino design styles.
abstract final class PlayerIconCatalog {
  static IconData close({required bool isCupertino, required bool isFullscreen}) {
    if (isFullscreen) {
      return isCupertino ? CupertinoIcons.fullscreen_exit : Icons.fullscreen_exit;
    }
    return isCupertino ? CupertinoIcons.xmark : Icons.close;
  }

  static IconData cast({required bool isCupertino, required CastState state}) {
    final connected = state == CastState.connected;
    if (isCupertino) {
      return connected ? CupertinoIcons.tv_fill : CupertinoIcons.tv;
    }
    return connected ? Icons.cast_connected : Icons.cast;
  }

  static IconData stopCast({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.xmark_rectangle : Icons.stop_screen_share_outlined;
  }

  static IconData aspectRatio({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.viewfinder : Icons.aspect_ratio;
  }

  static IconData check({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.checkmark_alt : Icons.check;
  }

  static IconData play({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.play_fill : Icons.play_arrow_rounded;
  }

  static IconData pause({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.pause_fill : Icons.pause_rounded;
  }

  static IconData replay({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.arrow_counterclockwise : Icons.replay_rounded;
  }

  static IconData livePhoto({required bool isCupertino, bool active = true}) {
    if (isCupertino) {
      return active ? CupertinoIcons.smallcircle_fill_circle : CupertinoIcons.smallcircle_fill_circle_fill;
    }
    return active ? Icons.motion_photos_on_rounded : Icons.motion_photos_paused_rounded;
  }

  static IconData skipBackward({required bool isCupertino, required SkipSecondType seconds}) {
    if (isCupertino) {
      return switch (seconds) {
        SkipSecondType.second5 => CupertinoIcons.gobackward,
        SkipSecondType.second10 => CupertinoIcons.gobackward_10,
        SkipSecondType.second15 => CupertinoIcons.gobackward_15,
        SkipSecondType.second30 => CupertinoIcons.gobackward_30,
        SkipSecondType.second45 => CupertinoIcons.gobackward_45,
        SkipSecondType.second60 => CupertinoIcons.gobackward_60,
      };
    }
    return switch (seconds) {
      SkipSecondType.second5 => Icons.replay_5_rounded,
      SkipSecondType.second10 => Icons.replay_10_rounded,
      SkipSecondType.second15 => Icons.fast_rewind_rounded,
      SkipSecondType.second30 => Icons.replay_30_rounded,
      SkipSecondType.second45 => Icons.fast_rewind_rounded,
      SkipSecondType.second60 => Icons.fast_rewind_rounded,
    };
  }

  static IconData skipForward({required bool isCupertino, required SkipSecondType seconds}) {
    if (isCupertino) {
      return switch (seconds) {
        SkipSecondType.second5 => CupertinoIcons.goforward,
        SkipSecondType.second10 => CupertinoIcons.goforward_10,
        SkipSecondType.second15 => CupertinoIcons.goforward_15,
        SkipSecondType.second30 => CupertinoIcons.goforward_30,
        SkipSecondType.second45 => CupertinoIcons.goforward_45,
        SkipSecondType.second60 => CupertinoIcons.goforward_60,
      };
    }
    return switch (seconds) {
      SkipSecondType.second5 => Icons.forward_5_rounded,
      SkipSecondType.second10 => Icons.forward_10_rounded,
      SkipSecondType.second15 => Icons.fast_forward_rounded,
      SkipSecondType.second30 => Icons.forward_30_rounded,
      SkipSecondType.second45 => Icons.fast_forward_rounded,
      SkipSecondType.second60 => Icons.fast_forward_rounded,
    };
  }

  static IconData volume({required bool isCupertino, required bool muted}) {
    if (isCupertino) {
      return muted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill;
    }
    return muted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
  }

  static IconData speed({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.speedometer : Icons.speed_rounded;
  }

  static IconData fullscreen({required bool isCupertino, required bool isFullscreen}) {
    if (isCupertino) {
      return isFullscreen ? CupertinoIcons.fullscreen_exit : CupertinoIcons.fullscreen;
    }
    return isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded;
  }

  static IconData hudSeek({required bool isCupertino, required bool forward}) {
    if (isCupertino) {
      return forward ? CupertinoIcons.forward_fill : CupertinoIcons.backward_fill;
    }
    return forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded;
  }

  static IconData hudBrightness({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.sun_max_fill : Icons.brightness_6_rounded;
  }

  static IconData hudVolume({required bool isCupertino, required bool muted}) {
    if (isCupertino) {
      return muted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill;
    }
    return muted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
  }
}
