import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../player/video_player_controller.dart';
import '../style/video_player_theme.dart';

const _leftZoneRatio = 0.4;
const _rightZoneRatio = 0.6;
const _seekDragThreshold = 48.0;

enum PlayerHudKind { seek, brightness, volume }

/// Mobile fullscreen gesture layer: horizontal seek, left brightness, right volume.
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.controller,
    required this.onTap,
    required this.child,
  });

  final VideoPlayerController controller;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

enum _GestureZone { left, center, right }

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  Offset? _panStart;
  _GestureZone? _zone;
  double _horizontalDrag = 0;
  bool _axisResolved = false;
  bool _isHorizontal = false;
  double? _brightnessBaseline;
  double? _volumeBaseline;
  PlayerHudKind? _hudKind;
  String? _hudLabel;

  _GestureZone _zoneFor(double x, double width) {
    if (x < width * _leftZoneRatio) return _GestureZone.left;
    if (x > width * _rightZoneRatio) return _GestureZone.right;
    return _GestureZone.center;
  }

  double _seekSeconds({
    required double horizontalDrag,
    required double width,
    required int maxStepSeconds,
  }) {
    final maxStep = maxStepSeconds.toDouble();
    return (horizontalDrag / width * maxStep * 3).clamp(-maxStep, maxStep);
  }

  void _onPanStart(DragStartDetails details) {
    final width = context.size?.width;
    if (width == null) return;
    _panStart = details.localPosition;
    _zone = _zoneFor(details.localPosition.dx, width);
    _horizontalDrag = 0;
    _axisResolved = false;
    _isHorizontal = false;
    _brightnessBaseline = null;
    _volumeBaseline = widget.controller.volume.value;
  }

  Future<void> _onPanUpdate(DragUpdateDetails details) async {
    final size = context.size;
    final start = _panStart;
    if (size == null || start == null) return;

    final delta = details.localPosition - start;
    if (!_axisResolved) {
      if (delta.distance < 12) return;
      _axisResolved = true;
      _isHorizontal = delta.dx.abs() >= delta.dy.abs();
    }

    if (_isHorizontal) {
      _horizontalDrag = delta.dx;
      if (_horizontalDrag.abs() < _seekDragThreshold) {
        setState(() {
          _hudKind = null;
          _hudLabel = null;
        });
        return;
      }
      final seconds = _seekSeconds(
        horizontalDrag: _horizontalDrag,
        width: size.width,
        maxStepSeconds: widget.controller.skipSecondType.value.value,
      );
      final sign = seconds >= 0 ? '+' : '';
      setState(() {
        _hudKind = PlayerHudKind.seek;
        _hudLabel = '$sign${seconds.toStringAsFixed(0)}s';
      });
      return;
    }

    // Vertical
    if (_zone == _GestureZone.center) return;
    final dy = -delta.dy;
    final deltaNorm = (dy / size.height).clamp(-1.0, 1.0);

    if (_zone == _GestureZone.left && !kIsWeb) {
      _brightnessBaseline ??= widget.controller.brightness.value;
      final next = (_brightnessBaseline! + deltaNorm).clamp(0.0, 1.0);
      await widget.controller.setBrightness(next);
      setState(() {
        _hudKind = PlayerHudKind.brightness;
        _hudLabel = '${(next * 100).round()}%';
      });
    } else if (_zone == _GestureZone.right) {
      _volumeBaseline ??= widget.controller.volume.value;
      final next = (_volumeBaseline! + deltaNorm).clamp(0.0, 1.0);
      await widget.controller.setVolume(next);
      setState(() {
        _hudKind = PlayerHudKind.volume;
        _hudLabel = '${(next * 100).round()}%';
      });
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final size = context.size;
    if (_isHorizontal && size != null && _horizontalDrag.abs() >= _seekDragThreshold) {
      final seconds = _seekSeconds(
        horizontalDrag: _horizontalDrag,
        width: size.width,
        maxStepSeconds: widget.controller.skipSecondType.value.value,
      );
      final delta = Duration(milliseconds: (seconds * 1000).round());
      var target = widget.controller.position.value + delta;
      if (target < Duration.zero) target = Duration.zero;
      final total = widget.controller.duration.value;
      if (total > Duration.zero && target > total) target = total;
      await widget.controller.seek(target);
    }
    setState(() {
      _hudKind = null;
      _hudLabel = null;
    });
    _panStart = null;
    _zone = null;
    _axisResolved = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: widget.child,
        ),
        if (_hudKind != null && _hudLabel != null)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.hudBackgroundColor,
                borderRadius: style.hudBorderRadius,
              ),
              child: Padding(
                padding: style.hudPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      switch (_hudKind!) {
                        PlayerHudKind.seek => Icons.fast_forward,
                        PlayerHudKind.brightness => Icons.brightness_6,
                        PlayerHudKind.volume => Icons.volume_up,
                      },
                      color: style.foregroundColor,
                      size: style.hudIconSize,
                    ),
                    SizedBox(width: style.hudIconGap),
                    Text(_hudLabel!, style: style.hudTextStyle),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Desktop-only key handler (used while fullscreen).
KeyEventResult handlePlayerKeyEvent(VideoPlayerController controller, KeyEvent event) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  switch (event.logicalKey) {
    case LogicalKeyboardKey.space:
      controller.playOrPause();
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
    default:
      return KeyEventResult.ignored;
  }
}
