import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/enums/fullscreen_gesture_side_mapping.dart';
import '../../player/video_player_controller.dart';
import '../player_gesture_hud_context.dart';
import '../style/video_player_theme.dart';
import 'player_gesture_hud.dart';

export '../player_gesture_hud_context.dart';

const double _seekDragThreshold = 48.0;
const double _gestureActivationDistance = 12.0;

enum _GestureZone { left, center, right }

/// Fullscreen gesture layer: horizontal seek and landscape vertical
/// brightness / volume swipe controls with configurable hot-zones and HUD.
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.controller,
    required this.onTap,
    required this.child,
    this.isLocked = false,
    this.enableVerticalGestures = true,
    this.verticalGestureMapping = FullscreenGestureSideMapping.leftBrightnessRightVolume,
    this.verticalGestureLeftWidthRatio = 0.3,
    this.verticalGestureRightWidthRatio = 0.3,
    this.verticalGestureHeightRatio = 0.7,
    this.gestureHudBuilder,
  }) : assert(
         verticalGestureLeftWidthRatio >= 0.0 && verticalGestureLeftWidthRatio <= 1.0,
         'verticalGestureLeftWidthRatio must be between 0.0 and 1.0.',
       ),
       assert(
         verticalGestureRightWidthRatio >= 0.0 && verticalGestureRightWidthRatio <= 1.0,
         'verticalGestureRightWidthRatio must be between 0.0 and 1.0.',
       ),
       assert(
         verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0,
         'verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio must not exceed 1.0.',
       ),
       assert(
         verticalGestureHeightRatio >= 0.0 && verticalGestureHeightRatio <= 1.0,
         'verticalGestureHeightRatio must be between 0.0 and 1.0.',
       );

  final VideoPlayerController controller;
  final VoidCallback onTap;
  final Widget child;

  /// When true, drag gestures are disabled while single-tap remains active.
  final bool isLocked;

  /// Enables vertical brightness/volume drag gestures in fullscreen landscape.
  final bool enableVerticalGestures;

  /// Controls which side adjusts brightness vs. volume.
  final FullscreenGestureSideMapping verticalGestureMapping;

  /// Width fraction (`0.0..1.0`) of the left vertical swipe zone. Defaults to `0.3`.
  ///
  /// Must satisfy `verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0`.
  final double verticalGestureLeftWidthRatio;

  /// Width fraction (`0.0..1.0`) of the right vertical swipe zone. Defaults to `0.3`.
  ///
  /// Must satisfy `verticalGestureLeftWidthRatio + verticalGestureRightWidthRatio <= 1.0`.
  final double verticalGestureRightWidthRatio;

  /// Vertically centered height fraction (`0.0..1.0`) of the active vertical swipe band.
  /// Defaults to `0.7`.
  final double verticalGestureHeightRatio;

  /// Optional custom center indicator builder replacing [PlayerGestureHud].
  final Widget Function(BuildContext context, PlayerGestureHudContext hud)? gestureHudBuilder;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  late final FlutterSignal<PlayerGestureHudContext?> _hud = signal<PlayerGestureHudContext?>(null);

  Offset? _panStart;
  _GestureZone? _zone;
  bool _verticalZoneEligible = false;
  double _horizontalDrag = 0.0;
  bool _axisResolved = false;
  bool _isHorizontal = false;
  double? _brightnessBaseline;
  double? _volumeBaseline;

  double get _effectiveLeftWidthRatio => widget.verticalGestureLeftWidthRatio.clamp(0.0, 1.0);

  double get _effectiveRightWidthRatio {
    final double maxRight = (1.0 - _effectiveLeftWidthRatio).clamp(0.0, 1.0);
    return widget.verticalGestureRightWidthRatio.clamp(0.0, maxRight);
  }

  double get _effectiveHeightRatio => widget.verticalGestureHeightRatio.clamp(0.0, 1.0);

  _GestureZone _zoneFor(double x, double width) {
    final double leftRatio = _effectiveLeftWidthRatio;
    if (leftRatio > 0.0 && x <= width * leftRatio) {
      return _GestureZone.left;
    }
    final double rightRatio = _effectiveRightWidthRatio;
    if (rightRatio > 0.0 && x >= width * (1.0 - rightRatio)) {
      return _GestureZone.right;
    }
    return _GestureZone.center;
  }

  bool _isInsideVerticalBand(double y, double height) {
    final double heightRatio = _effectiveHeightRatio;
    if (heightRatio <= 0.0) {
      return false;
    }
    final double verticalMargin = height * (1.0 - heightRatio) / 2.0;
    return y >= verticalMargin && y <= height - verticalMargin;
  }

  double _seekSeconds({
    required double horizontalDrag,
    required double width,
    required int maxStepSeconds,
  }) {
    final double maxStep = maxStepSeconds.toDouble();
    return (horizontalDrag / width * maxStep * 3.0).clamp(-maxStep, maxStep);
  }

  void _resetGestureState() {
    _hud.value = null;
    _panStart = null;
    _zone = null;
    _verticalZoneEligible = false;
    _horizontalDrag = 0.0;
    _axisResolved = false;
    _isHorizontal = false;
    _brightnessBaseline = null;
    _volumeBaseline = null;
  }

  void _onPanStart(DragStartDetails details) {
    if (widget.isLocked) {
      _resetGestureState();
      return;
    }
    final Size? size = context.size;
    if (size == null || size.width <= 0.0 || size.height <= 0.0) {
      return;
    }
    final Offset localPosition = details.localPosition;
    final _GestureZone zone = _zoneFor(localPosition.dx, size.width);
    final bool isLandscape = size.width > size.height;

    _panStart = localPosition;
    _zone = zone;
    _verticalZoneEligible =
        widget.enableVerticalGestures &&
        isLandscape &&
        zone != _GestureZone.center &&
        _isInsideVerticalBand(localPosition.dy, size.height);
    _horizontalDrag = 0.0;
    _axisResolved = false;
    _isHorizontal = false;
    _brightnessBaseline = null;
    _volumeBaseline = widget.controller.volume.value;
  }

  Future<void> _onPanUpdate(DragUpdateDetails details) async {
    if (widget.isLocked) {
      if (_hud.value != null) {
        _resetGestureState();
      }
      return;
    }
    final Size? size = context.size;
    final Offset? start = _panStart;
    if (size == null || start == null || size.width <= 0.0 || size.height <= 0.0) {
      return;
    }

    final Offset delta = details.localPosition - start;
    if (!_axisResolved) {
      if (delta.distance < _gestureActivationDistance) {
        return;
      }
      _axisResolved = true;
      _isHorizontal = delta.dx.abs() >= delta.dy.abs();
    }

    final VideoPlayerTheme theme = VideoPlayerTheme.of(context);

    if (_isHorizontal) {
      _horizontalDrag = delta.dx;
      if (_horizontalDrag.abs() < _seekDragThreshold) {
        _hud.value = null;
        return;
      }
      final double seconds = _seekSeconds(
        horizontalDrag: _horizontalDrag,
        width: size.width,
        maxStepSeconds: widget.controller.skipSecondType.value.value,
      );
      final String sign = seconds >= 0.0 ? '+' : '';
      _hud.value = PlayerGestureHudContext(
        controller: widget.controller,
        theme: theme,
        kind: PlayerHudKind.seek,
        value: 0.0,
        label: '$sign${seconds.toStringAsFixed(0)}s',
        seekForward: seconds >= 0.0,
      );
      return;
    }

    if (!_verticalZoneEligible || _zone == null || _zone == _GestureZone.center) {
      return;
    }

    final double activeHeight = size.height * _effectiveHeightRatio;
    if (activeHeight <= 0.0) {
      return;
    }
    final double deltaNorm = (-delta.dy / activeHeight).clamp(-1.0, 1.0);
    final bool controlsBrightness = _zone == _GestureZone.left
        ? widget.verticalGestureMapping.isLeftBrightness
        : widget.verticalGestureMapping.isRightBrightness;

    if (controlsBrightness) {
      if (kIsWeb) {
        return;
      }
      _brightnessBaseline ??= widget.controller.brightness.value;
      final double next = (_brightnessBaseline! + deltaNorm).clamp(0.0, 1.0);
      await widget.controller.setBrightness(next);
      if (!mounted) {
        return;
      }
      _hud.value = PlayerGestureHudContext(
        controller: widget.controller,
        theme: theme,
        kind: PlayerHudKind.brightness,
        value: next,
        label: '${(next * 100.0).round()}%',
        seekForward: true,
      );
    } else {
      _volumeBaseline ??= widget.controller.volume.value;
      final double next = (_volumeBaseline! + deltaNorm).clamp(0.0, 1.0);
      await widget.controller.setVolume(next);
      if (!mounted) {
        return;
      }
      _hud.value = PlayerGestureHudContext(
        controller: widget.controller,
        theme: theme,
        kind: PlayerHudKind.volume,
        value: next,
        label: '${(next * 100.0).round()}%',
        seekForward: true,
      );
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final Size? size = context.size;
    if (!widget.isLocked &&
        _isHorizontal &&
        size != null &&
        size.width > 0.0 &&
        _horizontalDrag.abs() >= _seekDragThreshold) {
      final double seconds = _seekSeconds(
        horizontalDrag: _horizontalDrag,
        width: size.width,
        maxStepSeconds: widget.controller.skipSecondType.value.value,
      );
      final Duration delta = Duration(milliseconds: (seconds * 1000.0).round());
      Duration target = widget.controller.position.value + delta;
      if (target < Duration.zero) {
        target = Duration.zero;
      }
      final Duration total = widget.controller.duration.value;
      if (total > Duration.zero && target > total) {
        target = total;
      }
      await widget.controller.seek(target);
    }
    _resetGestureState();
  }

  @override
  void didUpdateWidget(covariant PlayerGestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLocked && widget.isLocked) {
      _resetGestureState();
    }
  }

  @override
  void dispose() {
    _hud.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: _resetGestureState,
          child: widget.child,
        ),
        IgnorePointer(
          child: SignalBuilder(
            builder: (BuildContext context) {
              final PlayerGestureHudContext? hud = _hud.value;
              if (hud == null) {
                return const SizedBox.shrink();
              }
              return Center(
                child: widget.gestureHudBuilder?.call(context, hud) ?? PlayerGestureHud(hud: hud),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Desktop / web key handler (active when the player Focus is focused).
KeyEventResult handlePlayerKeyEvent(VideoPlayerController controller, KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  if (controller.isLocked.value) {
    if (event.logicalKey == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      controller.unlock();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  switch (event.logicalKey) {
    case LogicalKeyboardKey.space:
      if (event is KeyDownEvent) {
        controller.playOrPause();
      }
      return KeyEventResult.handled;
    case LogicalKeyboardKey.arrowLeft:
      controller.seekBackward();
      return KeyEventResult.handled;
    case LogicalKeyboardKey.arrowRight:
      controller.seekForward();
      return KeyEventResult.handled;
    case LogicalKeyboardKey.arrowUp:
      controller.setVolume(math.min(1.0, controller.volume.value + 0.05));
      return KeyEventResult.handled;
    case LogicalKeyboardKey.arrowDown:
      controller.setVolume(math.max(0.0, controller.volume.value - 0.05));
      return KeyEventResult.handled;
    case LogicalKeyboardKey.escape:
      if (controller.isFullscreen.value) {
        if (event is KeyDownEvent) {
          controller.exitFullscreen();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    default:
      return KeyEventResult.ignored;
  }
}
