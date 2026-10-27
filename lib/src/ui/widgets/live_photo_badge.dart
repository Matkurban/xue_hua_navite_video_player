import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../style/player_icon_catalog.dart';
import '../style/video_player_theme.dart';
import 'player_glass_surface.dart';

/// 动态照片角标组件（`LIVE` / `实况`），自动适配 Material 与 Cupertino 视觉风格及桌面鼠标悬停。
///
/// Displays the signature `LIVE` badge with concentric Live Photo rings,
/// playback activity state, desktop hover callbacks, and an optional mute toggle button.
class LivePhotoBadge extends StatelessWidget {
  const LivePhotoBadge({
    super.key,
    this.label = 'LIVE',
    this.isPlaying = false,
    this.isLoading = false,
    this.showMuteButton = false,
    this.isMuted = false,
    this.onTap,
    this.onHoverStart,
    this.onHoverEnd,
    this.onToggleMute,
    this.compact = false,
  });

  /// 徽标文字，默认 `'LIVE'`（可自定义为 `'实况'` 等）。
  final String label;

  /// 当前是否正在播放动态照片视频。
  final bool isPlaying;

  /// 当前是否正在加载动态照片视频。
  final bool isLoading;

  /// 是否在徽标旁显示静音切换按钮。
  final bool showMuteButton;

  /// 当前是否已静音。
  final bool isMuted;

  /// 点击 LIVE 徽标时的回调（通常用于触发播放/停止）。
  final VoidCallback? onTap;

  /// 桌面端鼠标移入 LIVE 徽标时的回调（仿 macOS Photos 悬停徽标即播放）。
  final VoidCallback? onHoverStart;

  /// 桌面端鼠标移出 LIVE 徽标时的回调。
  final VoidCallback? onHoverEnd;

  /// 点击静音按钮时的回调。
  final VoidCallback? onToggleMute;

  /// 是否使用紧凑尺寸（用于播放器顶栏内嵌展示）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = VideoPlayerTheme.of(context);
    final isCupertino = theme.isCupertinoFor(context);
    final fg = theme.foregroundColor;

    final badgeContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LivePhotoConcentricIcon(
          size: compact ? 14 : 16,
          color: isPlaying ? const Color(0xFFFFD60A) : fg,
          isPlaying: isPlaying,
        ),
        if (label.isNotEmpty) ...<Widget>[
          SizedBox(width: compact ? 4 : 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              height: 1.0,
            ),
          ),
        ],
      ],
    );

    final pillPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 5);
    const pillRadius = BorderRadius.all(Radius.circular(999));

    final Widget badgePill = MouseRegion(
      cursor: (onTap != null || onHoverStart != null)
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: onHoverStart != null ? (_) => onHoverStart!() : null,
      onExit: onHoverEnd != null ? (_) => onHoverEnd!() : null,
      child: GestureDetector(
        key: const ValueKey<String>('live_photo_badge'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: isCupertino
            ? PlayerGlassSurface(
                backgroundColor: theme.barBackgroundColor,
                borderRadius: pillRadius,
                blurSigma: theme.backdropBlurSigma > 0 ? theme.backdropBlurSigma : 16.0,
                padding: pillPadding,
                child: badgeContent,
              )
            : Container(
                padding: pillPadding,
                decoration: const BoxDecoration(
                  color: Color(0x991C1C1E),
                  borderRadius: pillRadius,
                ),
                child: badgeContent,
              ),
      ),
    );

    if (!showMuteButton) {
      return badgePill;
    }

    final muteButton = MouseRegion(
      cursor: onToggleMute != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        key: const ValueKey<String>('live_photo_mute_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggleMute,
        child: isCupertino
            ? PlayerGlassSurface(
                backgroundColor: theme.barBackgroundColor,
                borderRadius: pillRadius,
                blurSigma: theme.backdropBlurSigma > 0 ? theme.backdropBlurSigma : 16.0,
                padding: const EdgeInsets.all(5),
                child: Icon(
                  PlayerIconCatalog.volume(isCupertino: true, muted: isMuted),
                  size: compact ? 13 : 15,
                  color: fg,
                ),
              )
            : Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Color(0x991C1C1E),
                  borderRadius: pillRadius,
                ),
                child: Icon(
                  PlayerIconCatalog.volume(isCupertino: false, muted: isMuted),
                  size: compact ? 13 : 15,
                  color: fg,
                ),
              ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        badgePill,
        const SizedBox(width: 6),
        muteButton,
      ],
    );
  }
}

class _LivePhotoConcentricIcon extends StatelessWidget {
  const _LivePhotoConcentricIcon({
    required this.size,
    required this.color,
    required this.isPlaying,
  });

  final double size;
  final Color color;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LivePhotoRingsPainter(
          color: color,
          isPlaying: isPlaying,
        ),
      ),
    );
  }
}

class _LivePhotoRingsPainter extends CustomPainter {
  const _LivePhotoRingsPainter({
    required this.color,
    required this.isPlaying,
  });

  final Color color;
  final bool isPlaying;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.shortestSide / 2;

    // 1. Solid center dot
    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, outerRadius * (isPlaying ? 0.34 : 0.28), centerPaint);

    // 2. Middle continuous ring
    final midRingPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.09
      ..isAntiAlias = true;
    canvas.drawCircle(center, outerRadius * 0.58, midRingPaint);

    // 3. Outer dotted ring (signature Live Photo rays/dots)
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    const dotCount = 12;
    final dotRadius = size.shortestSide * 0.055;
    final ringRadius = outerRadius * 0.90;
    for (var i = 0; i < dotCount; i++) {
      final angle = (2 * math.pi * i) / dotCount;
      final dx = center.dx + ringRadius * math.cos(angle);
      final dy = center.dy + ringRadius * math.sin(angle);
      canvas.drawCircle(Offset(dx, dy), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LivePhotoRingsPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isPlaying != isPlaying;
  }
}
