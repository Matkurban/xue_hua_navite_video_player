import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/enums/cast_state.dart';
import '../../data/enums/skip_second_type.dart';

/// 按 Material 与 Cupertino 设计风格解析播放器内置图标的目录工具类。
///
/// Resolves theme-specific icons for Material and Cupertino design styles.
abstract final class PlayerIconCatalog {
  /// 返回顶栏关闭或退出全屏按钮的图标。
  ///
  /// Returns the close or exit-fullscreen icon for the top bar.
  ///
  /// - [isCupertino]：是否使用 Cupertino 图标风格。Whether to use Cupertino icons.
  /// - [isFullscreen]：当前是否处于全屏状态。Whether fullscreen mode is active.
  ///
  /// 返回值 / Returns：匹配当前主题与全屏状态的 [IconData]。
  static IconData close({required bool isCupertino, required bool isFullscreen}) {
    if (isFullscreen) {
      return isCupertino ? CupertinoIcons.fullscreen_exit : Icons.fullscreen_exit;
    }
    return isCupertino ? CupertinoIcons.xmark : Icons.close;
  }

  /// 返回无线投屏按钮图标（根据 [state] 区分已连接与未连接态）。
  ///
  /// Returns the wireless casting icon reflecting [state].
  static IconData cast({required bool isCupertino, required CastState state}) {
    final connected = state == CastState.connected;
    if (isCupertino) {
      return connected ? CupertinoIcons.tv_fill : CupertinoIcons.tv;
    }
    return connected ? Icons.cast_connected : Icons.cast;
  }

  /// 返回停止投屏按钮图标。
  ///
  /// Returns the stop-casting action icon.
  static IconData stopCast({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.xmark_rectangle : Icons.stop_screen_share_outlined;
  }

  /// 返回画面适应模式切换按钮图标。
  ///
  /// Returns the aspect-ratio mode selector icon.
  static IconData aspectRatio({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.viewfinder : Icons.aspect_ratio;
  }

  /// 返回弹出菜单当前选中项的勾选图标。
  ///
  /// Returns the checkmark icon for selected popup menu options.
  static IconData check({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.checkmark_alt : Icons.check;
  }

  /// 返回播放按钮图标。
  ///
  /// Returns the play transport icon.
  static IconData play({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.play_fill : Icons.play_arrow_rounded;
  }

  /// 返回暂停按钮图标。
  ///
  /// Returns the pause transport icon.
  static IconData pause({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.pause_fill : Icons.pause_rounded;
  }

  /// 返回播完重播按钮图标。
  ///
  /// Returns the replay transport icon.
  static IconData replay({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.arrow_counterclockwise : Icons.replay_rounded;
  }

  /// 返回动态照片（Live Photo）徽标图标。
  ///
  /// Returns the Live Photo badge icon reflecting [active] state.
  static IconData livePhoto({required bool isCupertino, bool active = true}) {
    if (isCupertino) {
      return active
          ? CupertinoIcons.smallcircle_fill_circle
          : CupertinoIcons.smallcircle_fill_circle_fill;
    }
    return active ? Icons.motion_photos_on_rounded : Icons.motion_photos_paused_rounded;
  }

  /// 返回按 [seconds] 步进快退的图标。
  ///
  /// Returns the skip-backward icon for the given [seconds] step.
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

  /// 返回按 [seconds] 步进快进的图标。
  ///
  /// Returns the skip-forward icon for the given [seconds] step.
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

  /// 返回底栏音量/静音按钮图标。
  ///
  /// Returns the volume/mute icon for the bottom scrubber bar.
  static IconData volume({required bool isCupertino, required bool muted}) {
    if (isCupertino) {
      return muted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill;
    }
    return muted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
  }

  /// 返回倍速菜单按钮图标。
  ///
  /// Returns the playback speed menu icon.
  static IconData speed({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.speedometer : Icons.speed_rounded;
  }

  /// 返回底栏进入/退出全屏按钮图标。
  ///
  /// Returns the enter/exit fullscreen icon for the bottom bar.
  static IconData fullscreen({required bool isCupertino, required bool isFullscreen}) {
    if (isCupertino) {
      return isFullscreen ? CupertinoIcons.fullscreen_exit : CupertinoIcons.fullscreen;
    }
    return isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded;
  }

  /// 返回手势 HUD 快进/快退图标。
  ///
  /// Returns the seek preview icon displayed in the gesture HUD.
  static IconData hudSeek({required bool isCupertino, required bool forward}) {
    if (isCupertino) {
      return forward ? CupertinoIcons.forward_fill : CupertinoIcons.backward_fill;
    }
    return forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded;
  }

  /// 返回手势 HUD 亮度调节图标。
  ///
  /// Returns the brightness icon displayed in the gesture HUD.
  static IconData hudBrightness({required bool isCupertino}) {
    return isCupertino ? CupertinoIcons.sun_max_fill : Icons.brightness_6_rounded;
  }

  /// 返回手势 HUD 音量调节图标。
  ///
  /// Returns the volume/muted icon displayed in the gesture HUD.
  static IconData hudVolume({required bool isCupertino, required bool muted}) {
    if (isCupertino) {
      return muted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill;
    }
    return muted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
  }

  /// 返回全屏锁定/解锁按钮图标。
  ///
  /// Returns the screen lock or unlock icon based on [isLocked].
  static IconData lock({required bool isCupertino, required bool isLocked}) {
    if (isCupertino) {
      return isLocked ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open_fill;
    }
    return isLocked ? Icons.lock_rounded : Icons.lock_open_rounded;
  }
}
