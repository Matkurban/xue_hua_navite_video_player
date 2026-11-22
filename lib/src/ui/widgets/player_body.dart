import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/enums/fullscreen_gesture_side_mapping.dart';
import '../../data/enums/player_lock_button_position.dart';
import '../../player/video_player_controller.dart';
import '../core_player.dart';
import '../style/video_player_theme.dart';
import '../video_player_slot_context.dart';
import 'player_bottom_scrubber.dart';
import 'player_casting_overlay.dart';
import 'player_center_controls.dart';
import 'player_gesture_layer.dart';
import 'player_lock_button.dart';
import 'player_top_bar.dart';

/// `VideoPlayer` 在内联态与全屏 [OverlayPortal] 中共用的播放器主体布局组件。
///
/// Shared player body used both inline and inside the fullscreen [OverlayPortal].
class PlayerBody extends StatelessWidget {
  /// 创建播放器主体布局组件。
  ///
  /// Creates a [PlayerBody].
  const PlayerBody({
    super.key,
    required this.slot,
    required this.controller,
    required this.surfaceKey,
    required this.aspectRatio,
    required this.fill,
    required this.fadeDuration,
    required this.visible,
    required this.isDesktop,
    required this.focusNode,
    required this.leading,
    required this.title,
    required this.actions,
    required this.topBarActions,
    required this.showCastButton,
    required this.showAspectRatioMenu,
    required this.enableFullscreen,
    required this.enableFullscreenVerticalGestures,
    required this.verticalGestureMapping,
    required this.verticalGestureLeftWidthRatio,
    required this.verticalGestureRightWidthRatio,
    required this.verticalGestureHeightRatio,
    required this.showLockButton,
    required this.lockButtonPosition,
    required this.errorBuilder,
    required this.loadingBuilder,
    required this.topBarBuilder,
    required this.centerControlsBuilder,
    required this.bottomScrubberBuilder,
    required this.castingOverlayBuilder,
    required this.extraOverlayBuilder,
    required this.gestureHudBuilder,
    required this.lockButtonBuilder,
    required this.onClose,
    required this.onToggleControls,
    required this.onShowControls,
    required this.onHideControls,
    required this.onCancelHideTimer,
    required this.onScheduleAutoHide,
  });

  /// 当前播放器槽位上下文。
  ///
  /// Active player slot context.
  final VideoPlayerSlotContext slot;

  /// 绑定的播放器控制器。
  ///
  /// Bound [VideoPlayerController].
  final VideoPlayerController controller;

  /// 绑定到 [CorePlayer] 的跨子树 [GlobalKey]，确保进出全屏时同帧迁移不重建原生视图。
  ///
  /// [GlobalKey] attached to [CorePlayer] for same-frame fullscreen reparenting.
  final Key surfaceKey;

  /// 非全屏且非铺满模式下的宽高比配置。
  ///
  /// Optional inline aspect ratio.
  final double? aspectRatio;

  /// 是否铺满父容器。
  ///
  /// Whether to fill available parent bounds.
  final bool fill;

  /// 控件层显隐淡入淡出时长。
  ///
  /// Chrome fade animation duration.
  final Duration fadeDuration;

  /// 控件层当前可见性信号。
  ///
  /// Reactive visibility signal for player controls.
  final FlutterSignal<bool> visible;

  /// 是否为桌面或 Web 平台（决定是否挂载键盘快捷键监听）。
  ///
  /// Whether running on desktop or Web (enables keyboard shortcut focus handling).
  final bool isDesktop;

  /// 桌面/Web 键盘快捷键焦点节点。
  ///
  /// Focus node capturing desktop/Web keyboard shortcuts.
  final FocusNode focusNode;

  /// 顶栏左侧组件。
  ///
  /// Optional top-bar leading widget.
  final Widget? leading;

  /// 顶栏居中标题组件。
  ///
  /// Optional top-bar centered title widget.
  final Widget? title;

  /// 顶栏右侧操作组件列表。
  ///
  /// Trailing top-bar actions.
  final List<Widget> actions;

  /// 遗留额外顶栏右侧操作组件列表。
  ///
  /// Legacy extra trailing top-bar actions.
  final List<Widget> topBarActions;

  /// 是否显示顶栏投屏按钮。
  ///
  /// Whether to show the cast button when supported.
  final bool showCastButton;

  /// 是否显示顶栏画面模式菜单。
  ///
  /// Whether to show the aspect-ratio menu.
  final bool showAspectRatioMenu;

  /// 是否显示底栏全屏切换按钮。
  ///
  /// Whether to show the fullscreen button.
  final bool enableFullscreen;

  /// 全屏横屏下是否启用垂直亮度/音量手势。
  ///
  /// Enables fullscreen landscape vertical brightness/volume swipe gestures.
  final bool enableFullscreenVerticalGestures;

  /// 左右区域亮度/音量映射模式。
  ///
  /// Side mapping between brightness and volume.
  final FullscreenGestureSideMapping verticalGestureMapping;

  /// 左侧垂直手势热区宽度比例（`0.0..1.0`）。
  ///
  /// Left vertical gesture zone width ratio (`0.0..1.0`).
  final double verticalGestureLeftWidthRatio;

  /// 右侧垂直手势热区宽度比例（`0.0..1.0`）。
  ///
  /// Right vertical gesture zone width ratio (`0.0..1.0`).
  final double verticalGestureRightWidthRatio;

  /// 居中垂直手势热区高度比例（`0.0..1.0`）。
  ///
  /// Centered vertical gesture band height ratio (`0.0..1.0`).
  final double verticalGestureHeightRatio;

  /// 全屏下是否显示锁屏按钮。
  ///
  /// Whether to show the fullscreen lock/unlock button.
  final bool showLockButton;

  /// 锁屏按钮在左侧或右侧的摆放位置。
  ///
  /// Left/right edge placement for the fullscreen lock button.
  final PlayerLockButtonPosition lockButtonPosition;

  /// 自定义错误界面构建器。
  ///
  /// Custom error builder.
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;

  /// 自定义加载指示器构建器。
  ///
  /// Custom loading builder.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// 自定义顶栏构建器。
  ///
  /// Custom top bar builder.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;

  /// 自定义居中传输控制区构建器。
  ///
  /// Custom center controls builder.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;

  /// 自定义底部进度条栏构建器。
  ///
  /// Custom bottom scrubber builder.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;

  /// 自定义投屏状态遮罩构建器。
  ///
  /// Custom casting overlay builder.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? castingOverlayBuilder;

  /// 额外叠加层构建器。
  ///
  /// Optional extra full-bleed overlay builder.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;

  /// 自定义全屏手势中心指示器构建器。
  ///
  /// Custom fullscreen gesture HUD builder.
  final Widget Function(BuildContext context, PlayerGestureHudContext hud)? gestureHudBuilder;

  /// 自定义全屏锁屏/解锁按钮构建器。
  ///
  /// Custom fullscreen lock/unlock button builder.
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot, bool isLocked)?
  lockButtonBuilder;

  /// 关闭或退出全屏回调。
  ///
  /// Callback invoked on close button press.
  final VoidCallback onClose;

  /// 切换控件层显隐回调。
  ///
  /// Callback toggling chrome visibility.
  final VoidCallback onToggleControls;

  /// 显示控件层回调。
  ///
  /// Callback showing controls and rescheduling auto-hide.
  final VoidCallback onShowControls;

  /// 隐藏控件层回调。
  ///
  /// Callback hiding controls immediately.
  final VoidCallback onHideControls;

  /// 取消自动隐藏计时器回调。
  ///
  /// Callback cancelling the auto-hide timer.
  final VoidCallback onCancelHideTimer;

  /// 重新调度自动隐藏计时器回调。
  ///
  /// Callback rescheduling the auto-hide timer.
  final VoidCallback onScheduleAutoHide;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerTheme style = slot.theme;

    return SignalBuilder(
      builder: (BuildContext context) {
        final bool isFullscreen = controller.isFullscreen.value;
        final bool isLocked = controller.isLocked.value;

        Widget stack = ColoredBox(
          color: style.backgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fill(
                child: CorePlayer(
                  key: surfaceKey,
                  controller: controller,
                  aspectRatio: aspectRatio,
                  backgroundColor: style.backgroundColor,
                  errorBuilder: errorBuilder,
                  loadingBuilder: loadingBuilder,
                ),
              ),
              // Hide frozen local video frames while casting to a remote device.
              Positioned.fill(
                child: SignalBuilder(
                  builder: (BuildContext context) {
                    if (!controller.isCasting.value) {
                      return const SizedBox.shrink();
                    }
                    return ColoredBox(color: style.backgroundColor);
                  },
                ),
              ),
              Positioned.fill(
                child: isFullscreen
                    ? PlayerGestureLayer(
                        controller: controller,
                        isLocked: isLocked,
                        enableVerticalGestures: enableFullscreenVerticalGestures,
                        verticalGestureMapping: verticalGestureMapping,
                        verticalGestureLeftWidthRatio: verticalGestureLeftWidthRatio,
                        verticalGestureRightWidthRatio: verticalGestureRightWidthRatio,
                        verticalGestureHeightRatio: verticalGestureHeightRatio,
                        gestureHudBuilder: gestureHudBuilder,
                        onTap: () {
                          if (isDesktop) {
                            focusNode.requestFocus();
                          }
                          onToggleControls();
                        },
                        child: const SizedBox.expand(),
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (isDesktop) {
                            focusNode.requestFocus();
                          }
                          onToggleControls();
                        },
                        child: const SizedBox.expand(),
                      ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: SignalBuilder(
                    builder: (BuildContext context) {
                      final bool isVisible = visible.value;
                      return AnimatedSwitcher(
                        duration: fadeDuration,
                        child: !isVisible
                            ? const SizedBox.shrink(key: ValueKey<String>('controls_hidden'))
                            : (isFullscreen && isLocked)
                            ? (showLockButton
                                  ? _PositionedLockButton(
                                      key: const ValueKey<String>('controls_locked'),
                                      slot: slot,
                                      position: lockButtonPosition,
                                      isLocked: true,
                                      lockButtonBuilder: lockButtonBuilder,
                                      onToggle: () {
                                        controller.toggleLocked();
                                        onShowControls();
                                      },
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey<String>('controls_locked_empty'),
                                    ))
                            : Stack(
                                key: const ValueKey<String>('controls_visible'),
                                fit: StackFit.expand,
                                children: <Widget>[
                                  Column(
                                    mainAxisSize: MainAxisSize.max,
                                    children: <Widget>[
                                      topBarBuilder?.call(context, slot) ??
                                          PlayerTopBar(
                                            slot: slot,
                                            leading: leading,
                                            title: title,
                                            actions: actions,
                                            topBarActions: topBarActions,
                                            showCastButton: showCastButton,
                                            showAspectRatioMenu: showAspectRatioMenu,
                                            onClose: onClose,
                                            onShowControls: onShowControls,
                                          ),
                                      Expanded(
                                        child: Center(
                                          child:
                                              centerControlsBuilder?.call(context, slot) ??
                                              PlayerCenterControls(
                                                slot: slot,
                                                onInteract: onShowControls,
                                              ),
                                        ),
                                      ),
                                      bottomScrubberBuilder?.call(context, slot) ??
                                          PlayerBottomScrubber(
                                            slot: slot,
                                            enableFullscreen: enableFullscreen,
                                            onInteractStart: onCancelHideTimer,
                                            onInteractEnd: onScheduleAutoHide,
                                            onInteract: onShowControls,
                                          ),
                                    ],
                                  ),
                                  if (isFullscreen && showLockButton)
                                    _PositionedLockButton(
                                      slot: slot,
                                      position: lockButtonPosition,
                                      isLocked: false,
                                      lockButtonBuilder: lockButtonBuilder,
                                      onToggle: () {
                                        controller.toggleLocked();
                                        onShowControls();
                                      },
                                    ),
                                ],
                              ),
                      );
                    },
                  ),
                ),
              ),
              // Interactive casting status & quick actions ("切换设备" / "退出投屏").
              Positioned.fill(
                child: SignalBuilder(
                  builder: (BuildContext context) {
                    if (!controller.isCasting.value || isLocked) {
                      return const SizedBox.shrink();
                    }
                    return castingOverlayBuilder?.call(context, slot) ??
                        PlayerCastingOverlay(slot: slot, onInteract: onShowControls);
                  },
                ),
              ),
              if (extraOverlayBuilder != null && !isLocked)
                Positioned.fill(child: extraOverlayBuilder!(context, slot)),
            ],
          ),
        );

        if (isDesktop) {
          stack = Focus(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              final KeyEventResult result = handlePlayerKeyEvent(controller, event);
              if (result == KeyEventResult.handled) {
                onHideControls();
              }
              return result;
            },
            child: stack,
          );
        }

        if (fill || isFullscreen) {
          return stack;
        }

        final double effectiveAspectRatio;
        if (aspectRatio != null) {
          effectiveAspectRatio = aspectRatio!;
        } else {
          final double reported = controller.videoAspectRatio.value;
          const double minInlineAspect = 16 / 9;
          if (reported > 0) {
            effectiveAspectRatio = reported >= minInlineAspect ? reported : minInlineAspect;
          } else {
            effectiveAspectRatio = minInlineAspect;
          }
        }
        return AspectRatio(aspectRatio: effectiveAspectRatio, child: stack);
      },
    );
  }
}

class _PositionedLockButton extends StatelessWidget {
  const _PositionedLockButton({
    super.key,
    required this.slot,
    required this.position,
    required this.isLocked,
    required this.lockButtonBuilder,
    required this.onToggle,
  });

  final VideoPlayerSlotContext slot;
  final PlayerLockButtonPosition position;
  final bool isLocked;
  final Widget Function(BuildContext context, VideoPlayerSlotContext slot, bool isLocked)?
  lockButtonBuilder;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Alignment alignment = position == PlayerLockButtonPosition.left
        ? Alignment.centerLeft
        : Alignment.centerRight;

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child:
            lockButtonBuilder?.call(context, slot, isLocked) ??
            PlayerLockButton(slot: slot, isLocked: isLocked, onToggle: onToggle),
      ),
    );
  }
}
