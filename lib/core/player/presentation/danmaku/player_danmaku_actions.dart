import 'dart:async';

import 'package:flutter_svg/svg.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/player/presentation/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/core/player/presentation/danmaku/danmaku_surface_settings.dart';

/// The danmaku, danmaku-settings and video-fit actions every player surface
/// shows.
///
/// These three are the controls a viewer reaches for while watching, and they
/// were the room's own until now: the recording player had a text chip for
/// danmaku, no way into the danmaku settings, and its own private idea of "fit".
/// Keeping them in Core is what makes the two pages the same product — the same
/// SVG glyphs, the same panel, the same six fit modes and the same stored
/// setting — without Core knowing anything about rooms or files.
///
/// Responsibilities:
///
/// - render the danmaku toggle, the settings entry and the fit cycle
/// - open the shared danmaku panel
///
/// It does not:
///
/// - decide what a surface's danmaku look is (the settings source does)
/// - own playback or presentation
/// - draw the picture

/// Danmaku on/off, using the player's own glyphs.
///
/// A room toggles its own switch (`VideoController`), a recording the global
/// one; both arrive here through [DanmakuSettingsSource.danmakuHidden], so the
/// button is the same control either way.
class PlayerDanmakuButton extends StatelessWidget {
  const PlayerDanmakuButton({super.key, required this.controller, this.iconColor = Colors.white});

  final DanmakuSettingsSource controller;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => IconButton(
        key: const ValueKey('player-danmaku-action'),
        tooltip: i18n('danmaku'),
        visualDensity: VisualDensity.standard,
        constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
        onPressed: () => controller.danmakuHidden.toggle(),
        icon: SizedBox.square(
          dimension: 24,
          child: SvgPicture.asset(
            controller.danmakuHidden.value ? 'assets/images/video/danmu_close.svg' : 'assets/images/video/danmu_open.svg',
            // ignore: deprecated_member_use
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

/// Opens the shared danmaku panel: the same surface the room's danmaku tab
/// embeds, so a recording and a room offer identical controls and presets.
class PlayerDanmakuSettingsButton extends StatelessWidget {
  const PlayerDanmakuSettingsButton({
    super.key,
    required this.controller,
    this.iconColor = Colors.white,
    this.onOpenChanged,
    this.includePipSettings = false,
  });

  final DanmakuSettingsSource controller;
  final Color iconColor;

  /// Called with true while the panel is up and false once it closes.
  ///
  /// A room uses this to pin its control bar open: the bars auto-hide on a
  /// timer, and a bar that disappears behind an open dialog is a bar the viewer
  /// has to re-summon to close it.
  final ValueChanged<bool>? onOpenChanged;

  /// Picture-in-picture has its own settings page; the fullscreen sheet leaves
  /// it out so the live picture stays visible.
  final bool includePipSettings;

  Future<void> _open(BuildContext context) async {
    onOpenChanged?.call(true);
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.58),
        useSafeArea: true,
        builder: (_) => DanmakuSettingsDialog(controller: controller, includePipSettings: includePipSettings),
      );
    } finally {
      onOpenChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('player-danmaku-settings-action'),
      tooltip: i18n('settings_danmaku_title'),
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
      onPressed: () => unawaited(_open(context)),
      icon: SizedBox.square(
        dimension: 24,
        child: SvgPicture.asset(
          'assets/images/video/danmu_setting.svg',
          // ignore: deprecated_member_use
          color: iconColor,
        ),
      ),
    );
  }
}

/// The danmaku panel as a dialog, sized for both orientations.
class DanmakuSettingsDialog extends StatelessWidget {
  const DanmakuSettingsDialog({super.key, required this.controller, this.includePipSettings = false});

  final DanmakuSettingsSource controller;

  /// Picture-in-picture has its own settings page; keeping it out of the short
  /// landscape sheet leaves the picture visible.
  final bool includePipSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final compactLandscape = isLandscape && size.height < 620;
    final targetWidth = isLandscape
        ? (size.width * (compactLandscape ? 0.44 : 0.38)).clamp(340.0, compactLandscape ? 460.0 : 540.0).toDouble()
        : (size.width * 0.92).clamp(300.0, 560.0).toDouble();
    final targetHeight = isLandscape ? size.height - (compactLandscape ? 12 : 24) : size.height * 0.84;

    return Dialog(
      alignment: isLandscape ? Alignment.centerRight : Alignment.center,
      backgroundColor: Colors.transparent,
      shadowColor: theme.shadowColor.withValues(alpha: 0.45),
      elevation: 24,
      insetPadding: EdgeInsets.symmetric(horizontal: isLandscape ? 6 : 12, vertical: isLandscape ? 6 : 12),
      child: Container(
        key: const ValueKey('fullscreen-danmaku-settings-panel'),
        width: targetWidth,
        height: targetHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: isLandscape
              ? const BorderRadius.horizontal(left: Radius.circular(18), right: Radius.circular(8))
              : BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, compactLandscape ? 6 : 10, 6, compactLandscape ? 6 : 10),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 18,
                    decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n('settings_danmaku_title'),
                          style: AppTextStyles.t16Bold.copyWith(color: colorScheme.onSurface),
                        ),
                        Text(
                          i18n('danmaku_realtime_hint'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.t12.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('fullscreen-danmaku-settings-close'),
                    tooltip: i18n('close'),
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: kMinInteractiveDimension,
                      minHeight: kMinInteractiveDimension,
                    ),
                    color: colorScheme.onSurfaceVariant,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.7), height: 1, thickness: 0.8),
            Expanded(
              child: DanmakuSettingsContent(
                controller: controller,
                embedded: true,
                includePipSettings: includePipSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "⋯" button at the top-left of the player.
///
/// Opens a menu whose 画面比例 entry expands a submenu with every video-fit
/// mode; the current one is checked. The room and a recording share the
/// stored index (`SettingsService.to.player.videoFitIndex`).
class PlayerMoreMenuButton extends StatelessWidget {
  const PlayerMoreMenuButton({super.key, this.iconColor = Colors.white, this.isAudioOnly, this.onToggleAudioOnly});

  final Color iconColor;

  /// Reads the room's audio-only state (an observable); with
  /// [onToggleAudioOnly] it adds the 纯音频 entry.
  final ValueGetter<bool>? isAudioOnly;
  final VoidCallback? onToggleAudioOnly;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          key: const ValueKey('player-more-video-fit'),
          leadingIcon: const Icon(Icons.aspect_ratio_rounded, size: 18),
          menuChildren: [
            for (final (index, option) in AppConsts().videoFitType.indexed)
              Obx(
                () => MenuItemButton(
                  key: ValueKey('player-video-fit-$index'),
                  leadingIcon: SizedBox(
                    width: 18,
                    child: SettingsService.to.player.resolvedVideoFitIndex == index
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                  ),
                  onPressed: () => SettingsService.to.player.videoFitIndex.v = index,
                  child: Text(i18n(option['desc'] as String)),
                ),
              ),
          ],
          child: Text(i18n('video_fit')),
        ),
        if (isAudioOnly != null && onToggleAudioOnly != null)
          Obx(
            () => MenuItemButton(
              key: const ValueKey('player-more-audio-only'),
              leadingIcon: Icon(isAudioOnly!() ? Icons.check_rounded : Icons.headphones_rounded, size: 18),
              onPressed: onToggleAudioOnly,
              child: Text(i18n('audio_only_mode')),
            ),
          ),
      ],
      builder: (context, menu, child) => IconButton(
        key: const ValueKey('player-more-menu'),
        visualDensity: VisualDensity.standard,
        constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
        color: iconColor,
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () {
          if (menu.isOpen) {
            menu.close();
          } else {
            menu.open();
          }
        },
      ),
    );
  }
}

