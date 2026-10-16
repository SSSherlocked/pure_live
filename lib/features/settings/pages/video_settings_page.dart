import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/features/settings/pages/player_kernel_settings_page.dart';
import 'package:pure_live/core/player/kernel/player_consts.dart';
import 'package:pure_live/core/player/presentation/windows_pip_driver.dart';
import 'package:pure_live/core/player/core/live_audio_service.dart';
import 'package:pure_live/core/config/app_settings_controller.dart';
import 'package:pure_live/core/config/player_settings_controller.dart';
import 'package:pure_live/features/settings/pages/background_play_settings_page.dart';
import 'package:pure_live/features/settings/pages/portrait_live_settings_page.dart';

typedef SleepPermissionRequester = Future<bool> Function();
typedef BackgroundPlaybackConfigurator = Future<void> Function({required bool enabled});
typedef PipAlwaysOnTopSetter = Future<void> Function(bool enabled);

class VideoSettingsPage extends StatefulWidget {
  const VideoSettingsPage({
    super.key,
    this.platformOverride,
    this.sleepPermissionRequesterOverride,
    this.backgroundPlaybackConfiguratorOverride,
    this.backgroundPlaybackTaskObserver,
    this.pipAlwaysOnTopSetterOverride,
  });

  @visibleForTesting
  final TargetPlatform? platformOverride;

  @visibleForTesting
  final SleepPermissionRequester? sleepPermissionRequesterOverride;

  @visibleForTesting
  final BackgroundPlaybackConfigurator? backgroundPlaybackConfiguratorOverride;

  @visibleForTesting
  final ValueChanged<Future<void>>? backgroundPlaybackTaskObserver;

  @visibleForTesting
  final PipAlwaysOnTopSetter? pipAlwaysOnTopSetterOverride;

  @override
  State<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

enum _ResolutionPreferenceTarget { wifi, cellular }

class _VideoSettingsPageState extends State<VideoSettingsPage> {
  bool _resolutionDialogBusy = false;
  bool _backgroundPlayBusy = false;
  String? _backgroundPlayErrorText;
  bool _pipAlwaysOnTopBusy = false;
  String? _pipAlwaysOnTopErrorText;

  TargetPlatform get _platform => widget.platformOverride ?? defaultTargetPlatform;
  bool get _isAndroid => _platform == TargetPlatform.android;
  /// The app's own compact picture-in-picture window (Windows, macOS), whose
  /// size and layer are set here; Android's system window has none of these.
  bool get _hasDesktopPip => _platform == TargetPlatform.windows || _platform == TargetPlatform.macOS;
  bool get _isMobile => _platform == TargetPlatform.android || _platform == TargetPlatform.iOS;
  bool get _isDesktop => !_isMobile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(i18n("video_settings"))),
      body: SettingsContentWidth(child: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 播放器内核 is part of 视频, reached from here.
          context.buildGroupTitle(i18n("kernel_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Remix.cpu_line,
              title: i18n("player_kernel"),
              subtitle: i18n("player_kernel_desc"),
              onTap: () => Get.to(() => const PlayerKernelSettingsPage()),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("audio_settings")),
          context.buildModernCard([
            Obx(
              () => context.buildSwitchTile(
                title: i18n("global_mute"),
                subtitle: i18n("global_mute_subtitle"),
                value: SettingsService.to.vol.globalVolumeMute,
                icon: SettingsService.to.vol.globalVolumeMute.v ? Remix.volume_mute_line : Remix.volume_up_line,
              ),
            ),
            if (_isMobile)
              Obx(
                () => _mutedAware(
                  context.buildSliderTile(
                    context,
                    icon: Remix.phone_line,
                    title: i18n("mobile_default_volume"),
                    value: SettingsService.to.vol.defaultMobileVolume.v * 100,
                    min: 0.0,
                    max: 100.0,
                    displayValue: "${(SettingsService.to.vol.defaultMobileVolume.v * 100).toStringAsFixed(0)}%",
                    onChanged: (val) =>
                        SettingsService.to.vol.defaultMobileVolume.v = double.parse((val / 100).toStringAsFixed(2)),
                  ),
                ),
              ),
            if (_isDesktop)
              Obx(
                () => _mutedAware(
                  context.buildSliderTile(
                    context,
                    icon: Remix.computer_line,
                    title: i18n("desktop_default_volume"),
                    value: SettingsService.to.vol.defaultDesktopVolume.v * 100,
                    min: 0.0,
                    max: 100.0,
                    displayValue: "${(SettingsService.to.vol.defaultDesktopVolume.v * 100).toStringAsFixed(0)}%",
                    onChanged: (val) {
                      SettingsService.to.vol.defaultDesktopVolume.v = double.parse((val / 100).toStringAsFixed(2));
                    },
                  ),
                ),
              ),
          ]),

          const SizedBox(height: 20),

          context.buildGroupTitle(i18n("video_quality_settings")),
          context.buildModernCard([
            Obx(
              () => context.buildTile(
                icon: Remix.hd_line,
                title: i18n("prefer_resolution"),
                subtitle: i18n("prefer_resolution_subtitle"),
                onTap: _resolutionDialogBusy
                    ? null
                    : () => _showPreferredResolutionSelectorDialog(_ResolutionPreferenceTarget.wifi),
                trailing: Text(
                  _preferredResolutionLabel(SettingsService.to.player.resolvedPreferResolution),
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                ),
                stackTrailingOnNarrow: true,
              ),
            ),
            Obx(
              () => context.buildTile(
                icon: Remix.signal_tower_line,
                title: i18n("mobile_quality"),
                subtitle: i18n("mobile_quality_subtitle"),
                onTap: _resolutionDialogBusy
                    ? null
                    : () => _showPreferredResolutionSelectorDialog(_ResolutionPreferenceTarget.cellular),
                trailing: Text(
                  _preferredResolutionLabel(SettingsService.to.player.resolvedPreferResolutionCellular),
                  style: AppText.of(context).body.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                ),
                stackTrailingOnNarrow: true,
              ),
            ),
          ]),

          const SizedBox(height: 20),

          context.buildGroupTitle(i18n("playback_behavior_settings")),
          context.buildModernCard([
            context.buildTile(
              icon: Icons.stay_current_portrait_rounded,
              title: i18n('portrait_live_settings'),
              subtitle: i18n('portrait_live_settings_desc'),
              onTap: () => Get.to(() => const PortraitLiveSettingsPage()),
            ),
            if (_isAndroid)
              context.buildSwitchTile(
                icon: Remix.music_2_line,
                title: i18n("enable_background_play"),
                subtitle: _backgroundPlayErrorText ?? i18n("enable_background_play_subtitle"),
                subtitleColor: _backgroundPlayErrorText == null ? null : theme.colorScheme.error,
                value: SettingsService.to.app.enableBackgroundPlay,
                enabled: !_backgroundPlayBusy,
                autoCommit: false,
                onChanged: (enabled) {
                  final task = _changeBackgroundPlayback(enabled);
                  widget.backgroundPlaybackTaskObserver?.call(task);
                },
              ),
            if (_isAndroid)
              context.buildTile(
                icon: Icons.tune_rounded,
                title: i18n('background_play_settings'),
                subtitle: i18n('background_play_settings_desc'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.to(() => const BackgroundPlaySettingsPage()),
              ),
            if (_isAndroid)
              context.buildSwitchTile(
                icon: Icons.headphones_rounded,
                title: i18n('background_audio_only'),
                subtitle: i18n('background_audio_only_desc'),
                value: SettingsService.to.app.backgroundAudioOnly,
              ),
            if (_isAndroid)
              context.buildSwitchTile(
                icon: Icons.speaker_notes_off_rounded,
                title: i18n('background_pause_danmaku'),
                subtitle: i18n('background_pause_danmaku_desc'),
                value: SettingsService.to.app.backgroundPauseDanmaku,
              ),
            if (_isAndroid)
              context.buildSwitchTile(
                icon: Icons.picture_in_picture_alt_rounded,
                title: i18n('pause_on_pip_close'),
                subtitle: i18n('pause_on_pip_close_desc'),
                value: SettingsService.to.app.pauseOnPipClose,
              ),
            if (_hasDesktopPip)
              context.buildSwitchTile(
                title: i18n('windows_pip_always_on_top'),
                subtitle: _pipAlwaysOnTopErrorText ?? i18n('windows_pip_always_on_top_subtitle'),
                subtitleColor: _pipAlwaysOnTopErrorText == null ? null : theme.colorScheme.error,
                value: SettingsService.to.player.windowsPipAlwaysOnTop,
                icon: Remix.pushpin_line,
                enabled: !_pipAlwaysOnTopBusy,
                autoCommit: false,
                onChanged: _changePipAlwaysOnTop,
              ),
            if (_hasDesktopPip)
              context.buildSwitchTile(
                title: i18n('windows_pip_remember_position'),
                subtitle: i18n('windows_pip_remember_position_subtitle'),
                value: SettingsService.to.window.rememberPipPosition,
                icon: Remix.terminal_window_fill,
                onChanged: (value) {
                  SettingsService.to.window.rememberPipPosition.v = value;
                },
              ),
            if (_hasDesktopPip) ...[
              Obx(
                () => context.buildSliderTile(
                  context,
                  icon: Remix.aspect_ratio_line,
                  title: i18n('windows_pip_base_size'),
                  value: SettingsService.to.player.windowsPipBaseSize.v,
                  min: 200.0,
                  max: 720.0,
                  displayValue: '${SettingsService.to.player.windowsPipBaseSize.v.round()} px',
                  onChanged: (val) {
                    SettingsService.to.player.windowsPipBaseSize.v = double.parse(val.toStringAsFixed(0));
                    _syncPipConfig();
                  },
                ),
              ),
              Obx(
                () => context.buildSliderTile(
                  context,
                  icon: Remix.arrow_down_double_line,
                  title: i18n('windows_pip_min_width'),
                  value: SettingsService.to.player.windowsPipMinWidth.v,
                  min: 100.0,
                  max: 320.0,
                  displayValue: '${SettingsService.to.player.windowsPipMinWidth.v.round()} px',
                  onChanged: (val) {
                    SettingsService.to.player.windowsPipMinWidth.v = double.parse(val.toStringAsFixed(0));
                    _syncPipConfig();
                  },
                ),
              ),
              Obx(
                () => context.buildSliderTile(
                  context,
                  icon: Remix.arrow_up_double_line,
                  title: i18n('windows_pip_min_height'),
                  value: SettingsService.to.player.windowsPipMinHeight.v,
                  min: 60.0,
                  max: 240.0,
                  displayValue: '${SettingsService.to.player.windowsPipMinHeight.v.round()} px',
                  onChanged: (val) {
                    SettingsService.to.player.windowsPipMinHeight.v = double.parse(val.toStringAsFixed(0));
                    _syncPipConfig();
                  },
                ),
              ),
            ],
            if (_hasDesktopPip)
              context.buildSwitchTile(
                title: i18n('windows_pip_free_aspect'),
                subtitle: i18n('windows_pip_free_aspect_subtitle'),
                value: SettingsService.to.player.windowsPipFreeAspect,
                icon: Remix.aspect_ratio_line,
                onChanged: (value) {
                  SettingsService.to.player.windowsPipFreeAspect.v = value;
                  _syncPipConfig();
                },
              ),
            if (_hasDesktopPip) const _WindowsPipResetTile(),

            context.buildSwitchTile(
              title: i18n('enable_fullscreen_default'),
              subtitle: i18n('enable_fullscreen_default_subtitle'),
              value: SettingsService.to.app.enableFullScreenDefault,
              icon: Remix.fullscreen_line,
            ),
            if (_isAndroid)
              Obx(
                () => context.buildSwitchTile(
                  icon: Icons.screen_rotation_rounded,
                  title: i18n('fullscreen_auto_rotate'),
                  subtitle: i18n(
                    'fullscreen_auto_rotate_desc',
                    args: {'profile': i18n('display_mode_${SettingsService.to.player.profile.value.name}')},
                  ),
                  value: SettingsService.to.player.fullscreenAutoRotate,
                ),
              ),
            if (_isAndroid)
              context.buildSwitchTile(
                title: i18n('enable_screen_keep_on'),
                subtitle: i18n('enable_screen_keep_on_subtitle'),
                value: SettingsService.to.app.enableScreenKeepOn,
                icon: Remix.lightbulb_line,
              ),
            context.buildSwitchTile(
              title: i18n('letterbox_page_color'),
              subtitle: i18n('letterbox_page_color_subtitle'),
              value: SettingsService.to.player.letterboxPageColor,
              icon: Remix.aspect_ratio_line,
            ),
          ]),

          const SizedBox(height: 32),
        ],
      )),
    );
  }

  Future<void> _changeBackgroundPlayback(bool enabled) async {
    if (_backgroundPlayBusy || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final app = SettingsService.to.app;
    if (app.isClosed || app.enableBackgroundPlay.v == enabled) return;
    final previous = app.enableBackgroundPlay.v;
    final requestPermission = widget.sleepPermissionRequesterOverride ?? LiveAudioService.requestPlatformPermissions;
    final configure = widget.backgroundPlaybackConfiguratorOverride ?? LiveAudioService.configureBackgroundPlayback;
    setState(() {
      _backgroundPlayBusy = true;
      _backgroundPlayErrorText = null;
    });
    try {
      if (enabled) {
        final granted = await requestPermission();
        if (!_canCommitBackgroundPlayback(app) || !granted) return;
      }
      await configure(enabled: enabled);
      if (!_canCommitBackgroundPlayback(app)) {
        try {
          await configure(enabled: previous);
        } catch (_) {}
        return;
      }
      app.enableBackgroundPlay.v = enabled;
      // Once, on a vendor build that clears apps away: point at the system
      // switches background play also needs.
      if (enabled && mounted) unawaited(offerBackgroundPlayGuide(context));
    } catch (_) {
      if (_canCommitBackgroundPlayback(app)) {
        setState(() => _backgroundPlayErrorText = i18n('background_play_apply_failed'));
      }
    } finally {
      if (mounted) setState(() => _backgroundPlayBusy = false);
    }
  }

  bool _canCommitBackgroundPlayback(AppSettingsController app) {
    return mounted && !app.isClosed && ModalRoute.of(context)?.isActive == true;
  }

  /// Pushes size-policy changes into the pip driver live: the next compact
  /// window uses the new base size and floors without leaving settings.
  void _syncPipConfig() {
    windowsPipDriver.updateConfig(pipConfigFromSettings());
  }

  Future<void> _changePipAlwaysOnTop(bool enabled) async {
    if (_pipAlwaysOnTopBusy || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final player = SettingsService.to.player;
    if (player.isClosed || player.windowsPipAlwaysOnTop.v == enabled) return;
    final previous = player.windowsPipAlwaysOnTop.v;
    final setAlwaysOnTop = widget.pipAlwaysOnTopSetterOverride ?? setWindowsPipAlwaysOnTop;
    setState(() {
      _pipAlwaysOnTopBusy = true;
      _pipAlwaysOnTopErrorText = null;
    });
    try {
      await setAlwaysOnTop(enabled);
      if (!_canCommitPipAlwaysOnTop(player)) {
        try {
          await setAlwaysOnTop(previous);
        } catch (_) {}
        return;
      }
      player.windowsPipAlwaysOnTop.v = enabled;
    } catch (_) {
      try {
        await setAlwaysOnTop(previous);
      } catch (_) {}
      if (_canCommitPipAlwaysOnTop(player)) {
        setState(() => _pipAlwaysOnTopErrorText = i18n('windows_pip_always_on_top_apply_failed'));
      }
    } finally {
      if (mounted) setState(() => _pipAlwaysOnTopBusy = false);
    }
  }

  bool _canCommitPipAlwaysOnTop(PlayerSettingsController player) {
    return mounted && !player.isClosed && ModalRoute.of(context)?.isActive == true;
  }

  Future<void> _showPreferredResolutionSelectorDialog(_ResolutionPreferenceTarget target) async {
    if (_resolutionDialogBusy || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final player = SettingsService.to.player;
    final title = i18n(target == _ResolutionPreferenceTarget.wifi ? 'prefer_resolution' : 'prefer_resolution_cellular');
    final selected = target == _ResolutionPreferenceTarget.wifi
        ? player.resolvedPreferResolution
        : player.resolvedPreferResolutionCellular;
    setState(() => _resolutionDialogBusy = true);
    try {
      final result = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) {
          void select(String value) => Navigator.of(dialogContext, rootNavigator: true).pop(value);

          return AlertDialog(
            key: const ValueKey('resolution-preference-dialog'),
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            title: Text(title, style: AppText.of(context).sectionTitle),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: RadioGroup<String>(
                groupValue: selected,
                onChanged: (value) {
                  if (value != null) select(value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: PlayerConsts.resolutions
                      .map(
                        (value) => SimpleDialogOption(
                          onPressed: () => select(value),
                          child: Row(
                            children: [
                              Radio<String>(value: value, activeColor: Theme.of(dialogContext).colorScheme.primary),
                              const SizedBox(width: 4),
                              Expanded(child: Text(_preferredResolutionLabel(value))),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 8,
            actions: [
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
                child: Text(i18n('cancel'), style: AppText.of(context).listPrimary.copyWith(color: Theme.of(context).hintColor)),
              ),
            ],
          );
        },
      );
      if (result == null || !mounted || player.isClosed || ModalRoute.of(context)?.isCurrent != true) return;
      if (target == _ResolutionPreferenceTarget.wifi) {
        player.changePreferResolution(result);
      } else {
        player.changePreferResolutionCellular(result);
      }
    } finally {
      if (mounted) setState(() => _resolutionDialogBusy = false);
    }
  }

  String _preferredResolutionLabel(String value) {
    final key = PlayerConsts.resolutionLabelKey(value);
    return key == null ? value : i18n(key);
  }
}

class _WindowsPipResetTile extends StatefulWidget {
  const _WindowsPipResetTile();

  @override
  State<_WindowsPipResetTile> createState() => _WindowsPipResetTileState();
}

class _WindowsPipResetTileState extends State<_WindowsPipResetTile> {
  bool _resetBusy = false;

  Future<void> _confirmReset() async {
    if (_resetBusy || !mounted) return;
    final window = SettingsService.to.window;
    setState(() => _resetBusy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('windows-pip-reset-dialog'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(i18n('windows_pip_reset_position'), style: AppText.of(context).sectionTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(i18n('windows_pip_reset_position_confirm'), style: AppText.of(context).listPrimary),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false),
              child: Text(i18n('cancel'), style: AppText.of(context).listPrimary.copyWith(color: Theme.of(context).hintColor)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
              child: Text(i18n('reset')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || window.isClosed) return;
      window.clearWindowsPipGeometry();
      SettingsService.to.player.floatWindowGeometry.value = '';
      ToastUtil.show(i18n('windows_pip_reset_position_success'));
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return context.buildTile(
      icon: Remix.reserved_line,
      title: i18n('windows_pip_reset_position'),
      subtitle: i18n('windows_pip_reset_position_subtitle'),
      onTap: _resetBusy ? null : _confirmReset,
    );
  }
}

/// While 默认静音 is on rooms start silent, so the default-volume slider has
/// no effect: show it greyed out and ignore input.
Widget _mutedAware(Widget slider) {
  final muted = SettingsService.to.vol.globalVolumeMute.v;
  return IgnorePointer(ignoring: muted, child: Opacity(opacity: muted ? 0.4 : 1, child: slider));
}
