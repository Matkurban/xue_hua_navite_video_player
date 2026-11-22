import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../style/video_player_theme.dart';
import 'player_glass_surface.dart';

/// 主题自适应的播放器图标按钮组件，供顶栏、底栏、居中控制与锁屏按钮使用。
///
/// - Material 模式：渲染带水波纹反馈的 [IconButton]；
/// - Cupertino 模式：渲染带按压透明度渐变与可选圆形毛玻璃底衬的 [CupertinoButton]。
///
/// Theme-adaptive icon button for player chrome and transport controls.
class PlayerIconButton extends StatelessWidget {
  /// 创建主题自适应图标按钮。
  ///
  /// Creates a [PlayerIconButton].
  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.tooltip,
    this.compact = false,
    this.circularGlassInCupertino = false,
    this.padding,
    this.minSize = 36.0,
  });

  /// 按钮内部图标组件。
  ///
  /// Icon widget rendered inside the button.
  final Widget icon;

  /// 点击回调；为 `null` 时按钮处于禁用态。
  ///
  /// Tap callback; disables the button when `null`.
  final VoidCallback? onPressed;

  /// 图标前景色，默认读取 `VideoPlayerTheme.foregroundColor`。
  ///
  /// Foreground color of the icon.
  final Color? color;

  /// 可选圆形按钮背景色。
  ///
  /// Optional circular button background color.
  final Color? backgroundColor;

  /// 可选悬停/长按提示文本。
  ///
  /// Optional tooltip message.
  final String? tooltip;

  /// 是否启用紧凑视觉密度与内边距。
  ///
  /// Whether to use compact density and padding.
  final bool compact;

  /// Cupertino 模式下当设置了 [backgroundColor] 时是否启用高斯模糊毛玻璃底衬。
  ///
  /// Enables frosted glass blur backing in Cupertino mode when [backgroundColor] is set.
  final bool circularGlassInCupertino;

  /// 自定义内边距覆盖。
  ///
  /// Optional explicit button padding.
  final EdgeInsetsGeometry? padding;

  /// 按钮最小可点击热区尺寸，默认 `36.0`。
  ///
  /// Minimum interactive tap target dimension (defaults to `36.0`).
  final double minSize;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);
    final foreground = color ?? style.foregroundColor;

    if (style.isCupertinoFor(context)) {
      final buttonPadding =
          padding ??
          (circularGlassInCupertino
              ? const EdgeInsets.all(12)
              : (compact ? const EdgeInsets.all(6) : const EdgeInsets.all(8)));

      Widget button = CupertinoButton(
        padding: buttonPadding,
        minimumSize: Size(minSize, minSize),
        pressedOpacity: 0.55,
        onPressed: onPressed,
        child: IconTheme(
          data: IconThemeData(color: foreground),
          child: icon,
        ),
      );

      if (backgroundColor != null) {
        button = PlayerGlassSurface(
          backgroundColor: backgroundColor!,
          borderRadius: BorderRadius.circular(999),
          blurSigma: circularGlassInCupertino ? style.backdropBlurSigma : 0.0,
          child: button,
        );
      }

      if (tooltip != null && tooltip!.isNotEmpty) {
        return Tooltip(message: tooltip!, child: button);
      }
      return button;
    }

    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      padding: padding ?? (compact ? EdgeInsets.zero : null),
      constraints: compact ? BoxConstraints(minWidth: minSize, minHeight: minSize) : null,
      tooltip: tooltip,
      color: foreground,
      style: backgroundColor != null
          ? IconButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foreground,
              disabledBackgroundColor: backgroundColor!.withValues(alpha: 0.25),
              disabledForegroundColor: foreground.withValues(alpha: 0.45),
            )
          : null,
      onPressed: onPressed,
      icon: icon,
    );
  }
}

/// 主题自适应的图标+文字胶囊按钮组件（用于投屏遮罩的快捷操作）。
///
/// Theme-adaptive labeled action pill button (used for casting quick actions).
class PlayerActionPillButton extends StatelessWidget {
  /// 创建图标+文字胶囊按钮。
  ///
  /// Creates a [PlayerActionPillButton].
  const PlayerActionPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  /// 胶囊按钮前置图标。
  ///
  /// Leading icon displayed before [label].
  final IconData icon;

  /// 胶囊按钮文本标签。
  ///
  /// Text label displayed inside the pill.
  final String label;

  /// 点击回调。
  ///
  /// Callback invoked when pressed.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = VideoPlayerTheme.of(context);

    if (style.isCupertinoFor(context)) {
      return PlayerGlassSurface(
        backgroundColor: style.barBackgroundColor,
        borderRadius: BorderRadius.circular(999),
        blurSigma: style.backdropBlurSigma,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: Size.zero,
          pressedOpacity: 0.55,
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: style.menuIconSize, color: style.foregroundColor),
              const SizedBox(width: 6),
              Text(label, style: style.menuItemTextStyle),
            ],
          ),
        ),
      );
    }

    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: style.foregroundColor,
        backgroundColor: style.centerButtonBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: style.menuIconSize, color: style.foregroundColor),
      label: Text(label, style: style.menuItemTextStyle),
    );
  }
}
