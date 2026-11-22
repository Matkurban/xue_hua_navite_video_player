import 'dart:ui';

import 'package:material_ui/material_ui.dart';

/// 毛玻璃半透明容器组件，供 Cupertino 控件浮层与 HUD 使用；当 [blurSigma] 为 `0` 时退化为普通圆角容器。
///
/// Frosted glass container used by Cupertino chrome overlays and HUDs, falling
/// back to a plain decorated container when [blurSigma] is `0`.
class PlayerGlassSurface extends StatelessWidget {
  /// 创建毛玻璃或纯色圆角浮层容器。
  ///
  /// Creates a [PlayerGlassSurface].
  const PlayerGlassSurface({
    super.key,
    required this.child,
    required this.backgroundColor,
    required this.borderRadius,
    this.blurSigma = 0.0,
    this.padding,
    this.border,
  });

  /// 容器内部渲染的子组件。
  ///
  /// Child widget displayed inside this surface.
  final Widget child;

  /// 容器背景填充色。
  ///
  /// Background fill color of the surface.
  final Color backgroundColor;

  /// 容器圆角半径。
  ///
  /// Corner radius applied to decoration and blur clipping.
  final BorderRadius borderRadius;

  /// 高斯模糊半径（`<= 0` 时不启用 [BackdropFilter]）。
  ///
  /// Gaussian blur sigma (`<= 0` disables [BackdropFilter]).
  final double blurSigma;

  /// 可选内边距。
  ///
  /// Optional inner padding around [child].
  final EdgeInsetsGeometry? padding;

  /// 可选边框样式。
  ///
  /// Optional border drawn around the container.
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final content = padding != null ? Padding(padding: padding!, child: child) : child;
    final decorated = DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor, borderRadius: borderRadius, border: border),
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
