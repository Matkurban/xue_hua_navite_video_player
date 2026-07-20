import 'package:flutter/material.dart';

import '../style/video_player_theme.dart';

/// 播放器底部使用的极纤细滑动条。
/// 支持播放进度以及拖动时的"小白点"滑块。
///
/// Ultra-thin scrubber used at the bottom of the player.
/// Renders a playback progress bar and a tiny white thumb that scales up
/// while the user is scrubbing.
class PlayerScrubberSlider extends StatefulWidget {
  /// 当前播放进度（0.0 – 1.0）。
  /// Current playback progress (0.0 – 1.0).
  final double value;

  /// 已缓冲进度（0.0 – 1.0）。小于 [value] 时会被抬升到 [value]。
  /// Buffered progress (0.0 – 1.0). Clamped to be ≥ [value].
  final double bufferedValue;

  /// 滑动过程中的实时回调（尚未提交）。
  /// Called continuously while the user drags.
  final ValueChanged<double>? onChanged;

  /// 开始拖动时回调。
  /// Called when the user begins scrubbing.
  final ValueChanged<double>? onChangeStart;

  /// 结束拖动时回调（应在此处 commit seek）。
  /// Called when the user ends scrubbing – commit the final seek here.
  final ValueChanged<double>? onChangeEnd;

  /// 轨道厚度（静止状态）。未传时从 [VideoPlayerTheme] 读取。
  final double? trackHeight;

  /// 拖动时轨道加厚的目标厚度。未传时从 [VideoPlayerTheme] 读取。
  final double? activeTrackHeight;

  /// 已播放部分颜色。未传时从 [VideoPlayerTheme] 读取。
  final Color? activeColor;

  /// 已缓冲部分颜色。未传时从 [VideoPlayerTheme] 读取。
  final Color? bufferedColor;

  /// 未播放部分颜色。未传时从 [VideoPlayerTheme] 读取。
  final Color? inactiveColor;

  /// 拖动滑块颜色。未传时从 [VideoPlayerTheme] 读取。
  final Color? thumbColor;

  /// Soft shadow under the thumb. 未传时从 [VideoPlayerTheme] 读取。
  final Color? thumbShadowColor;

  /// 滑块半径（静止）。未传时从 [VideoPlayerTheme] 读取。
  final double? thumbRadius;

  /// 滑块半径（拖动时放大）。未传时从 [VideoPlayerTheme] 读取。
  final double? activeThumbRadius;

  /// 是否显示滑块。
  /// Whether to render the thumb dot.
  final bool showThumb;

  const PlayerScrubberSlider({
    super.key,
    required this.value,
    this.bufferedValue = 0.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.trackHeight,
    this.activeTrackHeight,
    this.activeColor,
    this.bufferedColor,
    this.inactiveColor,
    this.thumbColor,
    this.thumbShadowColor,
    this.thumbRadius,
    this.activeThumbRadius,
    this.showThumb = true,
  });

  @override
  State<PlayerScrubberSlider> createState() => _PlayerScrubberSliderState();
}

class _PlayerScrubberSliderState extends State<PlayerScrubberSlider> {
  bool _dragging = false;
  bool _moved = false;
  double? _dragValue;

  double _clamp(double v) => v.isNaN ? 0.0 : v.clamp(0.0, 1.0);

  double _valueFromDx(double dx, double width) {
    if (width <= 0) return 0.0;
    return _clamp(dx / width);
  }

  /// Press-down: only enlarge the track, do NOT move the thumb yet.
  /// The actual seek happens when the user drags horizontally and releases.
  void _handlePressDown() {
    setState(() {
      _dragging = true;
      _moved = false;
      _dragValue = widget.value;
    });
    widget.onChangeStart?.call(widget.value);
  }

  void _handleDragUpdate(double dx, double width) {
    final v = _valueFromDx(dx, width);
    setState(() {
      _moved = true;
      _dragValue = v;
    });
    widget.onChanged?.call(v);
  }

  void _handleEnd() {
    // Only commit when the user actually moved the thumb; a plain press
    // without drag just releases the enlarged state and keeps playback.
    final shouldCommit = _moved && _dragValue != null;
    final v = shouldCommit ? _dragValue! : widget.value;
    setState(() {
      _dragging = false;
      _moved = false;
      _dragValue = null;
    });
    if (shouldCommit) {
      widget.onChangeEnd?.call(_clamp(v));
    } else {
      // Surface a "cancel" so callers can resume auto-hide, etc.
      widget.onChangeEnd?.call(_clamp(widget.value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    final trackHeight = widget.trackHeight ?? style.scrubberTrackHeight;
    final activeTrackHeight = widget.activeTrackHeight ?? style.scrubberActiveTrackHeight;
    final activeColor = widget.activeColor ?? style.scrubberActiveColor;
    final bufferedColor = widget.bufferedColor ?? style.scrubberBufferedColor;
    final inactiveColor = widget.inactiveColor ?? style.scrubberInactiveColor;
    final thumbColor = widget.thumbColor ?? style.scrubberThumbColor;
    final thumbShadowColor = widget.thumbShadowColor ?? style.scrubberThumbShadowColor;
    final thumbRadius = widget.thumbRadius ?? style.scrubberThumbRadius;
    final activeThumbRadius = widget.activeThumbRadius ?? style.scrubberActiveThumbRadius;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final effectiveValue = _clamp(_dragValue ?? widget.value);
        final effectiveBuffered = _clamp(
          widget.bufferedValue,
        ).clamp(effectiveValue, 1.0).toDouble();
        final paintedTrackHeight = _dragging ? activeTrackHeight : trackHeight;
        final paintedThumbRadius = _dragging ? activeThumbRadius : thumbRadius;

        final rowHeight =
            (paintedThumbRadius * 2).clamp(paintedTrackHeight, activeThumbRadius * 2 + 6) + 16;

        return SizedBox(
          height: rowHeight,
          width: double.infinity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              if (!_dragging) _handlePressDown();
            },
            onHorizontalDragUpdate: (details) => _handleDragUpdate(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _handleEnd(),
            onHorizontalDragCancel: _handleEnd,
            onTapDown: (_) => _handlePressDown(),
            onTapUp: (_) => _handleEnd(),
            onTapCancel: _handleEnd,
            child: CustomPaint(
              painter: _ScrubberPainter(
                value: effectiveValue,
                bufferedValue: effectiveBuffered,
                trackHeight: paintedTrackHeight,
                activeColor: activeColor,
                bufferedColor: bufferedColor,
                inactiveColor: inactiveColor,
                thumbColor: thumbColor,
                thumbShadowColor: thumbShadowColor,
                thumbRadius: paintedThumbRadius,
                showThumb: widget.showThumb,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  final double value;
  final double bufferedValue;
  final double trackHeight;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;
  final Color thumbColor;
  final Color thumbShadowColor;
  final double thumbRadius;
  final bool showThumb;

  _ScrubberPainter({
    required this.value,
    required this.bufferedValue,
    required this.trackHeight,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.thumbShadowColor,
    required this.thumbRadius,
    required this.showThumb,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final left = 0.0;
    final right = size.width;
    final radius = Radius.circular(trackHeight);

    // Inactive / background track
    final bgRect = RRect.fromLTRBR(left, cy - trackHeight / 2, right, cy + trackHeight / 2, radius);
    canvas.drawRRect(bgRect, Paint()..color = inactiveColor);

    // Buffered overlay
    if (bufferedValue > 0) {
      final bufRect = RRect.fromLTRBR(
        left,
        cy - trackHeight / 2,
        left + right * bufferedValue,
        cy + trackHeight / 2,
        radius,
      );
      canvas.drawRRect(bufRect, Paint()..color = bufferedColor);
    }

    // Active (played) fill
    if (value > 0) {
      final activeRect = RRect.fromLTRBR(
        left,
        cy - trackHeight / 2,
        left + right * value,
        cy + trackHeight / 2,
        radius,
      );
      canvas.drawRRect(activeRect, Paint()..color = activeColor);
    }

    // Thumb dot
    if (showThumb) {
      final cx = right * value;
      // Soft outer glow so the dot stands out on bright frames.
      canvas.drawCircle(Offset(cx, cy), thumbRadius + 2, Paint()..color = thumbShadowColor);
      canvas.drawCircle(Offset(cx, cy), thumbRadius, Paint()..color = thumbColor);
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) {
    return old.value != value ||
        old.bufferedValue != bufferedValue ||
        old.trackHeight != trackHeight ||
        old.activeColor != activeColor ||
        old.bufferedColor != bufferedColor ||
        old.inactiveColor != inactiveColor ||
        old.thumbColor != thumbColor ||
        old.thumbShadowColor != thumbShadowColor ||
        old.thumbRadius != thumbRadius ||
        old.showThumb != showThumb;
  }
}
