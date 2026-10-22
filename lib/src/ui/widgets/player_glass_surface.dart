import 'dart:ui';

import 'package:material_ui/material_ui.dart';

/// Frosted glass container used by Cupertino chrome overlays and HUDs, or
/// plain decorated container when [blurSigma] is 0.
class PlayerGlassSurface extends StatelessWidget {
  const PlayerGlassSurface({
    super.key,
    required this.child,
    required this.backgroundColor,
    required this.borderRadius,
    this.blurSigma = 0.0,
    this.padding,
    this.border,
  });

  final Widget child;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final content = padding != null ? Padding(padding: padding!, child: child) : child;
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: border,
      ),
      child: content,
    );

    if (blurSigma <= 0) {
      return decorated;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: decorated,
      ),
    );
  }
}
