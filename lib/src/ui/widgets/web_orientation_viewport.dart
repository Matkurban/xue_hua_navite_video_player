import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../orientation/player_orientation_controller.dart';
import '../../pigeon/orientation_api.g.dart';

/// Web 端（专治 iOS Safari 无法调用 `screen.orientation.lock()`）CSS 降级旋转全屏容器。
///
/// 当运行在不支持原生屏幕方向锁定的 iOS Safari 移动端浏览器中且播放器进入全屏横屏时，
/// 该组件自动将子视图宽高互换并以 `90°`（`landscapeLeft`）或 `-90°`（`landscapeRight`）
/// 顺滑旋转铺满视口，使 iOS 网页端播放器的“全屏横屏”与“解锁后反向旋转”体验与原生端一致；
/// 在 Android / iOS 原生及支持 Screen Orientation API 的浏览器上则零开销透传 [child]。
///
/// CSS transform fallback fullscreen viewport for iOS Safari where
/// `screen.orientation.lock()` is unsupported. Pass-through on all other platforms.
class WebOrientationViewport extends StatelessWidget {
  /// 创建 [WebOrientationViewport]。
  ///
  /// Creates a [WebOrientationViewport] bound to [controller].
  const WebOrientationViewport({
    super.key,
    required this.controller,
    required this.child,
    this.animationDuration = const Duration(milliseconds: 220),
    this.animationCurve = Curves.easeOutCubic,
  });

  /// 驱动旋转角度与全屏状态的方向控制器。
  ///
  /// [PlayerOrientationController] driving fullscreen and fallback rotation state.
  final PlayerOrientationController controller;

  /// 被包裹的播放器内容组件。
  ///
  /// Player content child widget.
  final Widget child;

  /// CSS 降级旋转切换时的补间动画时长。
  ///
  /// Animation duration when rotating between orientations.
  final Duration animationDuration;

  /// CSS 降级旋转切换时的动画曲线。
  ///
  /// Animation curve when rotating between orientations.
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (BuildContext context) {
        final bool useFallback =
            controller.usesCssFallbackRotation && controller.isFullscreen.value;
        final DevicePhysicalOrientation orientation = controller.currentOrientation.value;
        final bool isRotatedLandscape =
            useFallback &&
            (orientation == DevicePhysicalOrientation.landscapeLeft ||
                orientation == DevicePhysicalOrientation.landscapeRight);

        if (!isRotatedLandscape) {
          return child;
        }

        final double targetTurns = orientation == DevicePhysicalOrientation.landscapeLeft
            ? 0.25
            : -0.25;
        final double targetAngle = targetTurns * 2.0 * math.pi;

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size mediaSize = MediaQuery.sizeOf(context);
            final double viewportW = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : mediaSize.width;
            final double viewportH = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : mediaSize.height;

            return SizedBox(
              width: viewportW,
              height: viewportH,
              child: ClipRect(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: targetAngle),
                    duration: animationDuration,
                    curve: animationCurve,
                    builder: (BuildContext context, double angle, Widget? innerChild) {
                      return Transform.rotate(
                        angle: angle,
                        child: OverflowBox(
                          minWidth: viewportH,
                          maxWidth: viewportH,
                          minHeight: viewportW,
                          maxHeight: viewportW,
                          child: SizedBox(
                            width: viewportH,
                            height: viewportW,
                            child: innerChild,
                          ),
                        ),
                      );
                    },
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
