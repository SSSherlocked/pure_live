import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/background_guide.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';

/// 后台播放设置 (Android, ported from wzgrx/pure_live O01.3): the phone, the
/// states Android lets an app read (notifications, battery optimisation,
/// background restriction, Data Saver, battery saver) and the vendor's own
/// switches, each opening the system page where it is changed. Read again
/// whenever the app comes back from a system page.
class BackgroundPlaySettingsPage extends StatefulWidget {
  const BackgroundPlaySettingsPage({super.key, this.channel = const BackgroundGuideChannel()});

  final BackgroundGuideChannel channel;

  @override
  State<BackgroundPlaySettingsPage> createState() => _BackgroundPlaySettingsPageState();
}

class _BackgroundPlaySettingsPageState extends State<BackgroundPlaySettingsPage> {
  AppLifecycleListener? _lifecycle;
  BackgroundStatus? _status;
  bool _loading = true;
  String? _opening;
  int _readRevision = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_read()));
    unawaited(_read());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final revision = ++_readRevision;
    final status = await widget.channel.status();
    if (!mounted || revision != _readRevision) return;
    setState(() {
      // A failed read again keeps showing the last one.
      _status = status ?? _status;
      _loading = false;
    });
  }

  Future<void> _run(GuideStep step) async {
    if (_opening != null) return;
    setState(() => _opening = step.id);
    try {
      await _act(step);
    } finally {
      if (mounted) {
        setState(() => _opening = null);
        unawaited(_read());
      }
    }
  }

  Future<void> _act(GuideStep step) async {
    switch (step.action) {
      case GuideAction.notifications:
        // The system dialog while it can still ask, else the settings page.
        if (await Permission.notification.status == PermissionStatus.denied) {
          await Permission.notification.request();
          return;
        }
        await _open(step);
      case GuideAction.battery:
        // The system's "允许后台运行" dialog; builds that removed it get the
        // list of apps, then the app's details. Already exempt: the list, to
        // look or to change it back.
        if (step.check == GuideCheck.todo) {
          if (await Permission.ignoreBatteryOptimizations.request() == PermissionStatus.granted) return;
        }
        await _open(step);
      case GuideAction.pages:
        await _open(step);
      case GuideAction.none:
        break;
    }
  }

  Future<void> _open(GuideStep step) async {
    final opened = await widget.channel.open(step.pages);
    if (opened < 0) {
      ToastUtil.show(i18n('background_guide_open_failed'));
    } else if (step.pages[opened].isAppDetails && step.pages.length > 1) {
      // The vendor's own page is missing on this build.
      ToastUtil.show(i18n('background_guide_opened_details', args: {'name': i18n(step.titleKey)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('background_play_settings'))),
      body: SettingsContentWidth(
        child: ListView(
          physics: const PureLiveScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _note(context, i18n('background_guide_intro')),
            const SizedBox(height: 12),
            if (status == null)
              context.buildModernCard([
                context.buildTile(
                  icon: Icons.smartphone_rounded,
                  title: i18n('background_guide_group'),
                  subtitle: _loading ? null : i18n('background_guide_unavailable'),
                  trailing: _loading
                      ? const AppLoadingIndicator(size: 18)
                      : null,
                ),
              ])
            else
              ..._sections(context, status),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, BackgroundStatus status) {
    final rom = status.rom;
    final steps = guideSteps(status);
    final system = steps.where((step) => !step.isVendor).toList();
    final vendor = steps.where((step) => step.isVendor).toList();
    final device = [rom.manufacturer, rom.model].where((part) => part.isNotEmpty).join(' ');
    final build = [
      if (rom.romName.isNotEmpty) rom.romLabel,
      if (rom.androidVersion.isNotEmpty) 'Android ${rom.androidVersion}',
    ].join(' · ');
    return [
      context.buildGroupTitle(i18n('background_guide_group')),
      context.buildModernCard([
        context.buildTile(
          icon: Icons.smartphone_rounded,
          title: device.isEmpty ? i18n('background_guide_group') : device,
          subtitle: build.isEmpty ? null : build,
        ),
      ]),
      if (status.powerSave) ...[const SizedBox(height: 8), _note(context, i18n('background_guide_power_save'))],
      const SizedBox(height: 20),
      context.buildGroupTitle(i18n('background_guide_system_group')),
      context.buildModernCard([for (final step in system) _stepTile(context, step)]),
      if (vendor.isNotEmpty) ...[
        const SizedBox(height: 20),
        context.buildGroupTitle(i18n('background_guide_vendor_group', args: {'rom': rom.romLabel})),
        _note(context, i18n('background_guide_manual_note', args: {'rom': rom.romLabel})),
        const SizedBox(height: 8),
        context.buildModernCard([for (final step in vendor) _stepTile(context, step)]),
      ],
    ];
  }

  Widget _stepTile(BuildContext context, GuideStep step) {
    final colors = Theme.of(context).colorScheme;
    final todo = step.check == GuideCheck.todo;
    final tappable = step.action != GuideAction.none;
    final (stateKey, stateColor) = switch (step.check) {
      GuideCheck.ok => ('background_guide_state_ok', colors.primary),
      GuideCheck.todo => ('background_guide_state_todo', colors.error),
      GuideCheck.manual => ('background_guide_state_manual', colors.onSurfaceVariant),
    };
    return context.buildTile(
      icon: _stepIcon(step),
      title: i18n(step.titleKey),
      subtitle: i18n(todo ? step.problemKey ?? step.howKey : step.howKey),
      subtitleColor: todo ? colors.error : null,
      onTap: !tappable || _opening != null ? null : () => unawaited(_run(step)),
      trailing: !tappable
          ? const SizedBox.shrink()
          : _opening == step.id
          ? const AppLoadingIndicator(size: 18)
          : Text(i18n(stateKey), style: AppText.of(context).secondary.copyWith(color: stateColor)),
    );
  }

  Widget _note(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: AppText.of(context).secondary.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  static IconData _stepIcon(GuideStep step) => switch (step.id) {
    'notifications' => Icons.notifications_active_outlined,
    'battery' => Icons.battery_charging_full_rounded,
    'restricted' => Icons.block_rounded,
    'data_saver' => Icons.data_saver_on_rounded,
    'lock_recents' => Icons.lock_outline_rounded,
    'xiaomi_autostart' ||
    'oppo_autostart' ||
    'vivo_autostart' ||
    'huawei_launch' ||
    'honor_launch' => Icons.rocket_launch_outlined,
    _ => Icons.energy_savings_leaf_outlined,
  };
}

/// After background play was turned on: once, on a vendor build that clears
/// apps away, says that the system needs a few more switches and offers the
/// page that has them. Remembered on this device only (not backed up).
Future<void> offerBackgroundPlayGuide(
  BuildContext context, {
  BackgroundGuideChannel channel = const BackgroundGuideChannel(),
}) async {
  const offeredKey = 'backgroundGuideOffered';
  if (!channel.applies || HivePrefUtil.getBool(offeredKey) == true) return;
  final status = await channel.status();
  if (status == null || !hasVendorSteps(status.rom.family) || !context.mounted) return;
  await HivePrefUtil.setBool(offeredKey, true);
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(i18n('background_guide_offer_title')),
      content: Text(i18n('background_guide_offer_content', args: {'rom': status.rom.romLabel})),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('permission_cancel'))),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(i18n('background_guide_offer_go')),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Get.to(() => const BackgroundPlaySettingsPage());
  }
}
