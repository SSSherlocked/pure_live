import 'dart:async';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/widgets/qr_code_widget.dart';
import 'package:pure_live/features/backup/backup_controller.dart';
import 'package:pure_live/features/backup/backup_section_picker.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_device.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_protocol.dart';

class RemoteSyncPage extends StatefulWidget {
  const RemoteSyncPage({super.key});

  @override
  State<RemoteSyncPage> createState() => _RemoteSyncPageState();
}

class _RemoteSyncPageState extends State<RemoteSyncPage> {
  final RemoteSyncService service = Get.find<RemoteSyncService>();

  final TextEditingController addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    service.confirmRequest = _confirmIncoming;
  }

  @override
  void dispose() {
    if (identical(service.confirmRequest, _confirmIncoming)) service.confirmRequest = null;
    addressController.dispose();
    super.dispose();
  }

  /// Another device asks to read or overwrite this device's settings.
  ///
  /// The pairing code is the check against someone in between: the requesting
  /// device shows the same six digits.
  Future<bool> _confirmIncoming(String action, String remoteAddress, String pairingCode) async {
    if (!mounted) return false;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('remote_sync')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n(
                action == 'import' ? 'remote_sync_incoming_import' : 'remote_sync_incoming_export',
                args: {'address': remoteAddress},
              ),
            ),
            const SizedBox(height: 16),
            _PairingCode(code: pairingCode),
            const SizedBox(height: 8),
            Text(i18n('remote_sync_pairing_code_owner_hint'), style: Theme.of(dialogContext).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(i18n('confirm'))),
        ],
      ),
      barrierDismissible: false,
    );
    return allowed == true;
  }

  bool _pairingDialogOpen = false;

  /// Shows the session's pairing code while the other device decides.
  void _showPairingCode(String code) {
    if (!mounted) return;
    _pairingDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(i18n('remote_sync_pairing_code')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PairingCode(code: code),
              const SizedBox(height: 12),
              Text(i18n('remote_sync_pairing_code_waiting'), textAlign: TextAlign.center),
            ],
          ),
        ),
      ).whenComplete(() => _pairingDialogOpen = false),
    );
  }

  void _closePairingCode() {
    if (!_pairingDialogOpen || !mounted) return;
    _pairingDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  String _failureMessage(String fallbackKey) => i18n(service.lastFailureKey ?? fallbackKey);

  Future<void> _sendToDevice(String ip, int port, {String? fingerprint}) async {
    final sections = await pickBackupSections(
      direction: BackupSectionDirection.export,
      available: service.exportSectionNames(),
    );
    if (sections == null) return;

    final success = await service.syncToAddress(
      ip,
      port,
      sections: sections,
      fingerprint: fingerprint,
      onPairingCode: _showPairingCode,
    );
    _closePairingCode();
    if (!mounted) return;
    ToastUtil.show(success ? i18n('remote_sync_send_success') : _failureMessage('remote_sync_send_failed'));
  }

  Future<void> _receiveFromDevice(String ip, int port, {String? fingerprint}) async {
    final settings = await service.getRemoteSettings(
      ip,
      port,
      fingerprint: fingerprint,
      onPairingCode: _showPairingCode,
    );
    _closePairingCode();
    if (settings == null) {
      ToastUtil.show(_failureMessage('remote_sync_receive_failed'));
      return;
    }

    final available = BackupController.presentSections(settings);
    List<String>? sections;
    if (available.isNotEmpty) {
      sections = await pickBackupSections(direction: BackupSectionDirection.import, available: available);
      if (sections == null) return;
    }

    final success = await service.applyRemoteSettings(settings, sections: sections);
    if (!mounted) return;
    ToastUtil.show(success ? i18n('remote_sync_receive_success') : i18n('remote_sync_receive_failed'));
  }

  ({String ip, int port})? _manualAddress() {
    final value = addressController.text.trim();
    if (value.isEmpty) {
      ToastUtil.show(i18n('remote_sync_enter_address'));
      return null;
    }
    final parsed = RemoteSyncProtocol.parseHttpAddress(value);
    if (parsed == null) ToastUtil.show(i18n('remote_sync_invalid_address'));
    return parsed;
  }

  Future<void> _scanQr() async {
    if (PlatformUtils.isDesktop) return;
    final result = await Get.to<String>(() => const _RemoteSyncScannerPage());
    if (!mounted || result == null || result.trim().isEmpty) return;

    final parsed = RemoteSyncProtocol.parseQr(result);
    if (parsed == null) {
      ToastUtil.show(i18n('remote_sync_invalid_qr'));
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('remote_sync_select_action')),
        content: Text('${parsed.ip}:${parsed.port}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('receive'),
            child: Text(i18n('remote_sync_receive')),
          ),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop('send'), child: Text(i18n('remote_sync_send'))),
        ],
      ),
    );

    // The QR's key fingerprint lets this device check the other one by itself.
    if (action == 'send') {
      await _sendToDevice(parsed.ip, parsed.port, fingerprint: parsed.fingerprint);
    } else if (action == 'receive') {
      await _receiveFromDevice(parsed.ip, parsed.port, fingerprint: parsed.fingerprint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('remote_sync')),
        actions: [
          if (!PlatformUtils.isDesktop) IconButton(onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner)),
          Obx(
            () => IconButton(
              onPressed: service.isDiscovering.value ? service.stop : service.start,
              icon: Icon(service.isDiscovering.value ? Remix.stop_circle_line : Remix.play_circle_line),
              tooltip: service.isDiscovering.value ? i18n('stop') : i18n('start'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SettingsContentWidth(child: Obx(
        () => ListView(
          physics: const PureLiveScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildLocalDevice(),
            const SizedBox(height: 16),
            _buildDiscoveredDevices(),
            const SizedBox(height: 16),
            _buildManualAddress(),
          ],
        ),
      )),
    );
  }

  Widget _buildLocalDevice() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(i18n('remote_sync_my_device'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (service.qrData.isNotEmpty)
              QrCodeWidget(data: service.qrData, size: 180, padding: const EdgeInsets.all(12)),
            const SizedBox(height: 12),
            SelectableText(
              service.address.isEmpty ? i18n('remote_sync_no_address') : service.address,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(i18n('remote_sync_scan_hint'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(service.isServerRunning.value ? Icons.check_circle : Icons.error, size: 18),
                const SizedBox(width: 6),
                Text(service.isServerRunning.value ? i18n('remote_sync_running') : i18n('remote_sync_not_running')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredDevices() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    i18n('remote_sync_devices'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (service.isDiscovering.value)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            if (service.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(i18n('remote_sync_no_devices'))),
              )
            else
              ...service.devices.map(_buildDevice),
          ],
        ),
      ),
    );
  }

  Widget _buildDevice(RemoteSyncDevice device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.devices),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(device.address),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: service.isSyncing.value ? null : () => _receiveFromDevice(device.ip, device.port),
                    icon: const Icon(Icons.download),
                    label: Text(i18n('remote_sync_receive')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: service.isSyncing.value ? null : () => _sendToDevice(device.ip, device.port),
                    icon: const Icon(Icons.upload),
                    label: Text(i18n('remote_sync_send')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualAddress() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n('remote_sync_manual'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: '192.168.1.100:39888',
                prefixIcon: Icon(Icons.lan),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: service.isSyncing.value
                    ? null
                    : () async {
                        final parsed = _manualAddress();
                        if (parsed != null) await _sendToDevice(parsed.ip, parsed.port);
                      },
                icon: const Icon(Icons.upload),
                label: Text(i18n('remote_sync_send')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: service.isSyncing.value
                    ? null
                    : () async {
                        final parsed = _manualAddress();
                        if (parsed != null) await _receiveFromDevice(parsed.ip, parsed.port);
                      },
                icon: const Icon(Icons.download),
                label: Text(i18n('remote_sync_receive')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteSyncScannerPage extends StatefulWidget {
  const _RemoteSyncScannerPage();

  @override
  State<_RemoteSyncScannerPage> createState() => _RemoteSyncScannerPageState();
}

class _RemoteSyncScannerPageState extends State<_RemoteSyncScannerPage> {
  final MobileScannerController controller = MobileScannerController();

  bool found = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('remote_sync_scan_qr'))),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (found) {
            return;
          }

          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue?.trim();

            if (value == null || value.isEmpty) {
              continue;
            }

            if (RemoteSyncProtocol.parseQr(value) == null) {
              continue;
            }

            found = true;
            Navigator.of(context).pop(value);
            break;
          }
        },
      ),
    );
  }
}

/// Six digits, spaced for reading aloud and comparing across two screens.
class _PairingCode extends StatelessWidget {
  const _PairingCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
    return Center(
      child: Text(
        spaced,
        key: const ValueKey('remote-sync-pairing-code'),
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
          color: theme.colorScheme.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
