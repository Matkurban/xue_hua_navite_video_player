import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';

/// Holds all reactive [FlutterSignal] and [FlutterComputed] properties for a
/// [PlaybackSession].
class PlaybackSessionState {
  final FlutterSignal<PlayState> playState = signal(PlayState.idle);
  final FlutterSignal<Duration> position = signal(Duration.zero);
  final FlutterSignal<Duration> duration = signal(Duration.zero);
  final FlutterSignal<double> volume = signal(1.0);
  final FlutterSignal<double> speed = signal(1.0);
  final FlutterSignal<bool> isBuffering = signal(false);
  final FlutterSignal<String?> errorMessage = signal<String?>(null);
  final FlutterSignal<String?> currentUrl = signal<String?>(null);
  final FlutterSignal<String?> mimeType = signal<String?>(null);
  final FlutterSignal<Size> videoSize = signal<Size>(Size.zero);
  final FlutterSignal<int> rotationDegrees = signal<int>(0);
  final FlutterSignal<bool> muted = signal(false);
  final FlutterSignal< bool> isLooping = signal(false);
  final FlutterSignal<SkipSecondType> skipSecondType = signal(SkipSecondType.second10);
  final FlutterSignal<AspectRatioMode> aspectRatioMode = signal(AspectRatioMode.fit);
  final FlutterSignal<bool> isFullscreen = signal(false);
  final FlutterSignal<double> brightness = signal(1.0);
  final FlutterSignal<CastState> castState = signal(CastState.unavailable);
  final FlutterSignal<String?> castDeviceName = signal<String?>(null);

  /// Resolved Live Photo / Motion Photo bundle for the currently loaded media, if any.
  final FlutterSignal<LivePhotoBundle?> livePhotoBundle = signal<LivePhotoBundle?>(null);

  /// Whether the currently loaded media is a Live Photo / Motion Photo.
  late final FlutterComputed<bool> isLivePhoto = computed(() {
    return livePhotoBundle.value != null;
  });

  /// Parsed metadata for the currently loaded Live Photo / Motion Photo, if any.
  late final FlutterComputed<LivePhotoMetadata?> livePhotoMetadata = computed(() {
    return livePhotoBundle.value?.metadata;
  });

  /// Extracted or paired still cover image file for the active Live Photo, if any.
  late final FlutterComputed<NaviteFile?> livePhotoStillImage = computed(() {
    return livePhotoBundle.value?.imageFile;
  });

  late final FlutterComputed<double> videoAspectRatio = computed(() {
    final size = videoSize.value;
    if (size.width <= 0 || size.height <= 0) return 16 / 9;
    final rot = rotationDegrees.value % 360;
    if (rot == 90 || rot == 270) {
      return size.height / size.width;
    }
    return size.width / size.height;
  });

  late final FlutterComputed<bool> isVideo = computed(() {
    return mimeType.value?.startsWith('video/') ?? false;
  });

  late final FlutterComputed<bool> isAudio = computed(() {
    return mimeType.value?.startsWith('audio/') ?? false;
  });

  late final FlutterComputed<bool> isPlaying = computed(() {
    return playState.value == PlayState.playing;
  });

  late final FlutterComputed<double> progressPercent = computed(() {
    if (duration.value.inMilliseconds == 0) return 0.0;
    return position.value.inMilliseconds / duration.value.inMilliseconds;
  });

  /// Whether the current platform/environment supports wireless casting.
  late final FlutterComputed<bool> isCastSupported = computed(() {
    return castState.value != CastState.unavailable;
  });

  /// Whether a wireless cast session is currently connecting or connected.
  late final FlutterComputed<bool> isCasting = computed(() {
    final s = castState.value;
    return s == CastState.connecting || s == CastState.connected;
  });

  /// Resets media-specific playback signals while preserving session settings
  /// (`volume`, `speed`, `muted`, `isLooping`, `aspectRatioMode`, `castState`, `castDeviceName`).
  void resetMediaSignals() {
    batch(() {
      playState.value = PlayState.idle;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isBuffering.value = false;
      errorMessage.value = null;
      currentUrl.value = null;
      mimeType.value = null;
      videoSize.value = Size.zero;
      rotationDegrees.value = 0;
      livePhotoBundle.value = null;
    });
  }
}
