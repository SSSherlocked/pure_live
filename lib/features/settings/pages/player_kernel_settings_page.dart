import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:remixicon/remixicon.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/player_settings_controller.dart';
import 'package:pure_live/core/network/proxy_routing.dart';
import 'package:pure_live/core/player/models/player_engine.dart';
import 'package:pure_live/core/player/kernel/mpv_option_labels.dart';
import 'package:pure_live/core/player/kernel/player_consts.dart';
import 'package:pure_live/core/player/super_resolution.dart';
import 'package:pure_live/features/settings/widgets/player_guide_section.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

class PlayerKernelSettingsPage extends GetView<SettingsService> {
  const PlayerKernelSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availablePlayerKeys = availableVideoPlayerKeysForPlatform(defaultTargetPlatform);
    final canSwitchPlayer = availablePlayerKeys.length > 1;

    return Scaffold(
      appBar: AppBar(title: Text(i18n("player_kernel_settings"))),
      body: SettingsContentWidth(child: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("core_kernel_settings")),
          // One Obx for the engine: the kernel name, the proxy row and the
          // mpv-only group all key off the same value.
          Obx(() {
            final activeKey = _activePlayerKey();
            final engine = PlayerConsts.engines[activeKey];
            return context.buildModernCard([
              context.buildTile(
                icon: Remix.toggle_line,
                title: i18n("kernel_switch"),
                subtitle: i18n(canSwitchPlayer ? "kernel_switch_subtitle" : "kernel_fixed_subtitle"),
                onTap: canSwitchPlayer ? () => showVideoSetDialog(context) : null,
                trailing: Text(
                  i18n(PlayerConsts.names[activeKey] ?? PlayerConsts.names[PlayerConsts.defaultKey]!),
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                ),
                stackTrailingOnNarrow: true,
              ),
              if (engine != PlayerEngine.exo) _proxyTile(context, theme),
              context.buildSwitchTile(
                icon: Remix.speed_up_line,
                title: i18n('enable_codec'),
                subtitle: i18n("gpu_decode"),
                value: SettingsService.to.player.enableCodec,
              ),
              context.buildSwitchTile(
                icon: Remix.shut_down_line,
                title: i18n('force_destroy_player'),
                subtitle: i18n('force_destroy_player_subtitle'),
                value: SettingsService.to.player.useHardStopOnExit,
              ),
              if (engine == PlayerEngine.mediaKit && PlayerConsts.hlsSystemPlayerAvailable(defaultTargetPlatform))
                context.buildSwitchTile(
                  icon: Remix.play_circle_line,
                  title: i18n('hls_system_player'),
                  subtitle: i18n(
                    defaultTargetPlatform == TargetPlatform.android
                        ? 'hls_system_player_subtitle_android'
                        : 'hls_system_player_subtitle_apple',
                  ),
                  value: SettingsService.to.player.hlsSystemPlayer,
                ),
            ]);
          }),
          Obx(() {
            if (PlayerConsts.engines[_activePlayerKey()] != PlayerEngine.mediaKit) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (Platform.isWindows) ...[
                  const SizedBox(height: 20),
                  _buildSuperResolutionSection(context, theme),
                ],
                _buildMpvSettings(context),
                const SizedBox(height: 20),
                // The manual, every chapter collapsed.
                const PlayerGuideSection(),
              ],
            );
          }),
          const SizedBox(height: 32),
        ],
      )),
    );
  }

  String _activePlayerKey() =>
      normalizeVideoPlayerKeyForPlatform(SettingsService.to.player.videoPlayerKey.v, defaultTargetPlatform);

  /// Anime4K super-resolution: off / efficiency / quality, one row each.
  ///
  /// Only desktop GPUs can hold the CNN chain in realtime; the property
  /// itself only mounts on Windows (see
  /// MediaKitLiveProperties.superResolutionAvailable).
  Widget _buildSuperResolutionSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        context.buildGroupTitle(i18n('super_resolution_section')),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            i18n('super_resolution_hint'),
            style: AppText.of(context).secondary.copyWith(color: theme.hintColor),
          ),
        ),
        context.buildModernCard([
          for (final mode in SuperResolutionMode.values)
            ListTile(
              key: ValueKey('super-resolution-${mode.name}'),
              title: Text(i18n(mode.labelKey), style: AppText.of(context).sectionTitle),
              subtitle: Text(i18n(mode.descriptionKey), style: AppText.of(context).secondary),
              trailing: Obx(() {
                final active = SuperResolutionMode.fromName(SettingsService.to.player.superResolutionMode.v) == mode;
                return active
                    ? Icon(Remix.checkbox_circle_fill, color: theme.colorScheme.primary)
                    : const Icon(Remix.checkbox_blank_circle_line);
              }),
              onTap: () => SettingsService.to.player.superResolutionMode.v = mode.name,
            ),
        ]),
      ],
    );
  }

  /// The proxy state is read inside its own Obx so toggling it does not rebuild
  /// the whole kernel card.
  Widget _proxyTile(BuildContext context, ThemeData theme) {
    return Obx(
      () => context.buildTile(
        icon: Remix.global_line,
        title: i18n("network_proxy"),
        subtitle: i18n("network_proxy_subtitle"),
        onTap: () => showProxySettingsDialog(context),
        trailing: Text(
          SettingsService.to.proxy.enableProxy.v ? i18n("enabled") : i18n("disabled"),
          style: AppText.of(context).body.copyWith(
            color: SettingsService.to.proxy.enableProxy.v ? theme.colorScheme.primary : theme.hintColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        stackTrailingOnNarrow: true,
      ),
    );
  }

  Widget _buildMpvSettings(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMpvSectionHeader(context, theme),
        Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 6), child: _buildMpvNotice(context, theme)),
        context.buildModernCard([
          context.buildSwitchTile(
            icon: Remix.code_box_line,
            title: i18n("custom_output_hwdec"),
            value: SettingsService.to.player.customPlayerOutput,
          ),
          Obx(() {
            final player = SettingsService.to.player;
            // Manual output picks only take effect while the custom-output
            // switch is armed — hiding them mirrors that honestly, the same
            // way the decoder pick disappears with hardware acceleration off.
            if (!player.customPlayerOutput.v) return const SizedBox.shrink();

            return _optionTile(
              context,
              kind: MpvOptionKind.videoOutput,
              title: i18n("video_output_driver"),
              icon: Remix.movie_line,
              value: player.videoOutputDriver,
            );
          }),
          Obx(() {
            final player = SettingsService.to.player;
            if (!player.customPlayerOutput.v) return const SizedBox.shrink();

            return _optionTile(
              context,
              kind: MpvOptionKind.audioOutput,
              title: i18n("audio_output_driver"),
              icon: Remix.volume_up_line,
              value: player.audioOutputDriver,
            );
          }),
          Obx(() {
            final player = SettingsService.to.player;
            // The decoder pick exists only while hardware acceleration is on:
            // turning the switch off IS the "no hardware decoder" state, so a
            // separate disabled entry would duplicate it.
            if (!player.enableCodec.v) return const SizedBox.shrink();

            return _optionTile(
              context,
              kind: MpvOptionKind.hardwareDecoder,
              title: i18n("hardware_decoder"),
              icon: Remix.cpu_line,
              value: player.videoHardwareDecoder,
            );
          }),

          // Platform-gated advanced tuning: interpolation and the richer
          // scale menu are desktop-GPU features; audio-exclusive is a
          // Windows WASAPI switch.
          if (!Platform.isAndroid && !Platform.isIOS)
            _optionTile(
              context,
              kind: MpvOptionKind.videoSync,
              title: i18n("video_sync"),
              icon: Remix.timer_flash_line,
              value: SettingsService.to.player.videoSync,
            ),
          if (!Platform.isAndroid && !Platform.isIOS)
            context.buildSwitchTile(
              icon: Remix.artboard_line,
              title: i18n('interpolation'),
              subtitle: i18n('interpolation_hint'),
              value: SettingsService.to.player.interpolation,
            ),
          _optionTile(
            context,
            kind: MpvOptionKind.scale,
            title: i18n("scale_kernel"),
            icon: Remix.layout_masonry_line,
            value: SettingsService.to.player.scale,
          ),
          _optionTile(
            context,
            kind: MpvOptionKind.deinterlace,
            title: i18n("deinterlace"),
            icon: Remix.layout_grid_line,
            value: SettingsService.to.player.deinterlace,
          ),
          if (Platform.isAndroid || Platform.isWindows)
            Obx(() {
              final player = SettingsService.to.player;
              if (!player.enableCodec.v) return const SizedBox.shrink();

              return _optionTile(
                context,
                kind: MpvOptionKind.hwdecCodecs,
                title: i18n("hwdec_codecs"),
                icon: Remix.file_list_3_line,
                value: player.hwdecCodecs,
              );
            }),
          if (Platform.isWindows)
            context.buildSwitchTile(
              icon: Remix.headphone_line,
              title: i18n('audio_exclusive'),
              subtitle: i18n('audio_exclusive_hint'),
              value: SettingsService.to.player.audioExclusive,
            ),
        ]),
      ],
    );
  }

  Widget _buildMpvSectionHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(child: context.buildGroupTitle(i18n("mpv_advanced_settings"))),
          TextButton.icon(
            onPressed: () => _confirmResetMpvSettings(context),
            icon: const Icon(Remix.refresh_line, size: 16),
            label: Text(i18n("reset"), style: const TextStyle(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetMpvSettings(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('mpv_settings_reset')),
        content: Text(i18n('mpv_settings_reset_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(i18n('reset'))),
        ],
      ),
    );
    if (confirmed == true) SettingsService.to.player.resetMpvPlayerSettings();
  }

  Widget _buildMpvNotice(BuildContext context, ThemeData theme) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: 2,
      children: [
        Text(
          i18n("mpv_warning_text"),
          style: AppText.of(context).secondary.copyWith(color: theme.hintColor.withValues(alpha: 0.85)),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => launchUrlString("https://mpv.io/manual/", mode: LaunchMode.externalApplication),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  i18n("mpv_official_docs"),
                  style: AppText.of(context).secondary.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
    BuildContext context, {
    required MpvOptionKind kind,
    required String title,
    required IconData icon,
    required RxString value,
  }) {
    return Obx(
      () => context.buildTile(
        icon: icon,
        title: title,
        subtitle: mpvOptionLabel(kind, normalizedMpvOption(kind, value.value, defaultTargetPlatform)),
        trailing: const Icon(Remix.arrow_right_s_line),
        onTap: () => _showMpvOptionDialog(context, kind: kind, title: title, value: value),
      ),
    );
  }

  /// Picks one mpv output/decoder option; choosing closes the dialog.
  void _showMpvOptionDialog(
    BuildContext context, {
    required MpvOptionKind kind,
    required String title,
    required RxString value,
  }) {
    final platform = defaultTargetPlatform;
    final options = mpvOptionsForPlatform(kind, platform);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          Obx(
            () => RadioGroup<String>(
              groupValue: normalizedMpvOption(kind, value.value, platform),
              onChanged: (key) {
                if (key == null) return;
                value.value = key;
                Navigator.of(dialogContext).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    RadioListTile<String>(
                      value: option.key,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(option.label, style: AppText.of(dialogContext).listPrimary),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showVideoSetDialog(BuildContext pageContext) {
    final playerKeys = availableVideoPlayerKeysForPlatform(defaultTargetPlatform);
    if (playerKeys.length <= 1) return;

    showDialog<void>(
      context: pageContext,
      builder: (dialogContext) {
        void select(String? key) {
          final engine = PlayerConsts.engines[key];
          if (engine == null) return;
          SettingsService.to.player.videoPlayerKey.v = key!;
          GlobalPlayerService.instance.player.switchEngine(engine, isManual: true);
          Navigator.of(dialogContext).pop();
        }

        return SimpleDialog(
          title: Text(i18n("change_player")),
          children: [
            Obx(
              () => RadioGroup<String>(
                groupValue: _activePlayerKey(),
                onChanged: select,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final itemKey in playerKeys)
                      RadioListTile<String>(
                        value: itemKey,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(i18n(PlayerConsts.names[itemKey]!), style: AppText.of(pageContext).sectionTitle),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void showProxySettingsDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const _PlayerProxySettingsDialog());
  }
}

final TextInputFormatter _playerProxyHostInputFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
  final normalized = normalizeProxyHost(newValue.text);
  if (normalized == newValue.text) return newValue;
  return TextEditingValue(
    text: normalized,
    selection: TextSelection.collapsed(offset: normalized.length),
    composing: TextRange.empty,
  );
});

class _PlayerProxySettingsDialog extends StatefulWidget {
  const _PlayerProxySettingsDialog();

  @override
  State<_PlayerProxySettingsDialog> createState() => _PlayerProxySettingsDialogState();
}

class _PlayerProxySettingsDialogState extends State<_PlayerProxySettingsDialog> {
  final proxy = SettingsService.to.proxy;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  bool _portInvalid = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: proxy.proxyHost.v);
    _portController = TextEditingController(text: proxy.proxyPort.v.toString());
    _portInvalid = parseProxyPortInput(_portController.text) == null;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _updatePort(String rawValue) {
    final port = parseProxyPortInput(rawValue);
    final invalid = port == null;
    if (_portInvalid != invalid) setState(() => _portInvalid = invalid);
    if (port != null) proxy.proxyPort.v = port;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(i18n("proxy_settings")),
      content: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            context.buildSwitchTile(
              icon: Remix.shield_keyhole_line,
              title: i18n("enable_player_proxy"),
              value: proxy.enableProxy,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('player-proxy-dialog-host'),
              controller: _hostController,
              enabled: proxy.enableProxy.v,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [_playerProxyHostInputFormatter],
              decoration: InputDecoration(
                labelText: i18n("proxy_host"),
                prefixIcon: const Icon(Remix.global_line, size: 20),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: (value) => proxy.proxyHost.v = normalizeProxyHost(value),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('player-proxy-dialog-port'),
              controller: _portController,
              enabled: proxy.enableProxy.v,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: i18n("proxy_port"),
                prefixIcon: const Icon(Remix.links_line, size: 20),
                errorText: _portInvalid ? i18n('proxy_port_invalid') : null,
                errorMaxLines: 3,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: _updatePort,
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n("confirm")))],
    );
  }
}
