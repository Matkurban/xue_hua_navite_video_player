import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/enums/aspect_ratio_mode.dart';
import '../../data/enums/cast_state.dart';
import '../style/player_icon_catalog.dart';
import '../video_player_slot_context.dart';
import 'live_photo_badge.dart';
import 'player_glass_surface.dart';
import 'player_icon_button.dart';
import 'player_loading_indicator.dart';
import 'player_menu_button.dart';

/// Default top bar of [VideoPlayer], adapting to Material and Cupertino styles.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.slot,
    required this.leading,
    required this.title,
    required this.actions,
    required this.topBarActions,
    required this.showCastButton,
    required this.showAspectRatioMenu,
    required this.onClose,
    required this.onShowControls,
  });

  final VideoPlayerSlotContext slot;
  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final List<Widget> topBarActions;
  final bool showCastButton;
  final bool showAspectRatioMenu;
  final VoidCallback onClose;
  final VoidCallback onShowControls;

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;
    final isCupertino = style.isCupertinoFor(context);

    return SignalBuilder(
      builder: (context) {
        final castState = controller.castState.value;
        final castSupported = controller.isCastSupported.value;
        final isFullscreen = controller.isFullscreen.value;
        final isLivePhoto = controller.isLivePhoto.value;
        final isPlaying = controller.isPlaying.value;

        final trailing = <Widget>[
          if (isLivePhoto)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: LivePhotoBadge(
                compact: true,
                isPlaying: isPlaying,
                onTap: () {
                  controller.playOrPause();
                  onShowControls();
                },
              ),
            ),
          ...actions,
          ...topBarActions,
          if (showCastButton && castSupported)
            _TopBarCastButton(slot: slot, castState: castState, onShowControls: onShowControls),
          if (showAspectRatioMenu)
            _TopBarAspectRatioMenu(slot: slot, onShowControls: onShowControls),
        ];

        final closeButton =
            leading ??
            PlayerIconButton(
              key: const ValueKey<String>('video_player_close_button'),
              compact: isCupertino,
              onPressed: onClose,
              color: style.foregroundColor,
              icon: Icon(
                PlayerIconCatalog.close(isCupertino: isCupertino, isFullscreen: isFullscreen),
                size: style.chromeIconSize,
              ),
            );

        final wrappedLeading = isCupertino && leading == null
            ? PlayerGlassSurface(
                backgroundColor: style.barBackgroundColor,
                borderRadius: style.barBorderRadius,
                blurSigma: style.backdropBlurSigma,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: closeButton,
              )
            : closeButton;

        final trailingRow = trailing.isEmpty
            ? const SizedBox.shrink()
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: isCupertino
                    ? PlayerGlassSurface(
                        backgroundColor: style.barBackgroundColor,
                        borderRadius: style.barBorderRadius,
                        blurSigma: style.backdropBlurSigma,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
                      )
                    : Row(mainAxisSize: MainAxisSize.min, children: trailing),
              );

        return Padding(
          padding: style.topBarPadding,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: wrappedLeading),
              ),
              Expanded(flex: 2, child: Center(child: title ?? const SizedBox.shrink())),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: trailingRow),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBarCastButton extends StatelessWidget {
  const _TopBarCastButton({
    required this.slot,
    required this.castState,
    required this.onShowControls,
  });

  final VideoPlayerSlotContext slot;
  final CastState castState;
  final VoidCallback onShowControls;

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;
    final isCupertino = style.isCupertinoFor(context);
    final isBusy = castState == CastState.connecting || castState == CastState.disconnecting;

    return PlayerIconButton(
      key: const ValueKey<String>('video_player_cast_button'),
      compact: isCupertino,
      tooltip: castState == CastState.connected ? '正在投屏' : '投屏',
      color: style.foregroundColor,
      onPressed: () {
        controller.showCastPicker();
        onShowControls();
      },
      icon: isBusy
          ? PlayerLoadingIndicator(size: style.chromeIconSize, color: style.foregroundColor)
          : Icon(
              PlayerIconCatalog.cast(isCupertino: isCupertino, state: castState),
              size: style.chromeIconSize,
            ),
    );
  }
}

class _TopBarAspectRatioMenu extends StatelessWidget {
  const _TopBarAspectRatioMenu({required this.slot, required this.onShowControls});

  final VideoPlayerSlotContext slot;
  final VoidCallback onShowControls;

  static String _aspectLabel(AspectRatioMode mode) => switch (mode) {
    AspectRatioMode.fit => '适应',
    AspectRatioMode.fill => '铺满',
    AspectRatioMode.stretch => '拉伸',
  };

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;
    final isCupertino = style.isCupertinoFor(context);
    const modes = AspectRatioMode.values;

    return PlayerMenuButton(
      compact: isCupertino,
      icon: PlayerIconCatalog.aspectRatio(isCupertino: isCupertino),
      color: style.foregroundColor,
      tooltip: '画面模式',
      menuBuilder: (context, hideMenu) {
        return SignalBuilder(
          builder: (context) {
            final current = controller.aspectRatioMode.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < modes.length; i++)
                  PlayerMenuOptionTile(
                    label: _aspectLabel(modes[i]),
                    selected: current == modes[i],
                    showDivider: i < modes.length - 1,
                    onTap: () {
                      controller.setAspectRatioMode(modes[i]);
                      hideMenu();
                      onShowControls();
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
