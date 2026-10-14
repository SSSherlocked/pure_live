import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:remixicon/remixicon.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pure_live/core/index.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pure_live/core/logging/app_log.dart';
import 'package:pure_live/core/platform/file_utils.dart';
import 'package:pure_live/features/backup/backup_recovery_service.dart';
import 'package:pure_live/core/config/log_controller.dart';
import 'package:pure_live/features/backup/backup_controller.dart';

/// The backup, restore and log groups shown at the top of 数据管理与备份.
class BackupSettingsSections extends StatefulWidget {
  const BackupSettingsSections({super.key});

  @override
  State<BackupSettingsSections> createState() => _BackupSettingsSectionsState();
}

enum _BackupAction { create, restore, directory }

class _LogFileEntry {
  const _LogFileEntry(this.path, this.size, this.modified);

  final String path;
  final int size;
  final DateTime modified;

  String get name => p.basename(path);
}

class _BackupSettingsSectionsState extends State<BackupSettingsSections> {
  /// Height of the embedded log file list, as in Simple Live.
  static const double _logListHeight = 300;

  final LogController logController = LogController.to;
  String get backupDirectory => BackupController.to.backupDirectory.v;
  _BackupAction? _backupAction;
  List<_LogFileEntry> _logFiles = const [];
  Worker? _logStatusWorker;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogFiles());
    // Switching the log on creates a file; list it once the switch settles.
    _logStatusWorker = ever<bool>(logController.isApplyingLogStatus, (applying) {
      if (!applying) unawaited(_loadLogFiles());
    });
  }

  @override
  void dispose() {
    _logStatusWorker?.dispose();
    _logStatusWorker = null;
    super.dispose();
  }

  Future<void> _runBackupAction(
    _BackupAction action,
    String failureMessageKey,
    Future<void> Function() operation,
  ) async {
    if (_backupAction != null) return;
    setState(() => _backupAction = action);
    try {
      await operation();
    } catch (error, stackTrace) {
      debugPrint('Backup action $action failed: $error\n$stackTrace');
      if (mounted) ToastUtil.show(i18n(failureMessageKey));
    } finally {
      if (mounted) setState(() => _backupAction = null);
    }
  }

  Widget? _backupActionIndicator(_BackupAction action) {
    if (_backupAction != action) return null;
    return SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: i18n('refresh_loading')),
    );
  }

  Future<void> _openLogDirectory() async {
    try {
      final logDir = await LogFileWriter.resolveLogDirectory();
      if (!await logDir.exists()) {
        ToastUtil.show(i18n('log_dir_not_exist'));
        return;
      }
      await FileUtils.openFolder(logDir.path);
    } catch (_) {
      ToastUtil.show(i18n('open_log_dir_failed'));
    }
  }

  /// The saved log files, newest first.
  Future<void> _loadLogFiles() async {
    try {
      await Log.flush();
      final logDir = await LogFileWriter.resolveLogDirectory();
      final entries = <_LogFileEntry>[];
      if (await logDir.exists()) {
        await for (final entity in logDir.list()) {
          if (entity is! File || !entity.path.endsWith('.log')) continue;
          final stat = await entity.stat();
          entries.add(_LogFileEntry(entity.path, stat.size, stat.modified));
        }
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));
      if (mounted) setState(() => _logFiles = entries);
    } catch (error) {
      debugPrint('Loading log files failed: $error');
    }
  }

  /// Deletes every log file except the one being written.
  Future<void> _clearLogFiles() async {
    final active = Log.activeLogFilePath;
    var failed = false;
    for (final entry in _logFiles) {
      if (entry.path == active) continue;
      try {
        await File(entry.path).delete();
      } catch (_) {
        failed = true;
      }
    }
    if (failed) ToastUtil.show(i18n('clear_log_files_failed'));
    await _loadLogFiles();
  }

  Future<void> _shareLogFile(_LogFileEntry entry) async {
    try {
      await Log.flush();
      await SharePlus.instance.share(ShareParams(files: [XFile(entry.path)]));
    } catch (_) {
      ToastUtil.show(i18n('log_share_failed'));
    }
  }

  Future<void> _saveLogFile(_LogFileEntry entry) async {
    try {
      await Log.flush();
      final bytes = await File(entry.path).readAsBytes();
      final saved = await FilePicker.saveFile(fileName: entry.name, bytes: bytes);
      if (saved != null) ToastUtil.show(i18n('log_file_saved'));
    } catch (_) {
      ToastUtil.show(i18n('log_file_save_failed'));
    }
  }

  String _formatFileSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} ${i18n('unit_mb')}';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} ${i18n('unit_kb')}';
    return '$bytes ${i18n('unit_b')}';
  }

  Widget _buildLogFileList(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final active = Log.activeLogFilePath;
    // Not a SizedBox: buildModernCard drops those as spacers.
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(height: _logListHeight),
      child: _logFiles.isEmpty
          ? Center(
              child: Text(
                i18n('log_file_not_found'),
                style: text.secondary.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              physics: const PureLiveScrollPhysics(),
              itemCount: _logFiles.length,
              separatorBuilder: (context, index) => Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: theme.dividerColor.withValues(alpha: 0.05),
              ),
              itemBuilder: (context, index) {
                final entry = _logFiles[index];
                final size = _formatFileSize(entry.size);
                return ListTile(
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.only(left: 16, right: 4),
                  title: Text(entry.name, style: text.listPrimary),
                  subtitle: Text(
                    entry.path == active ? '$size · ${i18n('log_file_in_use')}' : size,
                    style: text.secondary.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // share_plus cannot share files on Linux.
                      if (!Platform.isLinux)
                        IconButton(
                          tooltip: i18n('share'),
                          icon: const Icon(RemixIcons.share_forward_line),
                          onPressed: () => _shareLogFile(entry),
                        ),
                      IconButton(
                        tooltip: i18n('save'),
                        icon: const Icon(Remix.download_2_line),
                        onPressed: () => _saveLogFile(entry),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        context.buildGroupTitle(i18n("cloud_backup")),
        context.buildModernCard([
          context.buildTile(
            icon: Remix.cloud_line,
            title: i18n("webdav"),
            subtitle: i18n("backup_to_webdav"),
            onTap: () => Get.toNamed(RoutePath.kWebDavPage),
          ),
          context.buildTile(
            icon: Remix.qr_scan_2_line,
            title: i18n('remote_sync'),
            subtitle: i18n('remote_sync_subtitle'),
            onTap: () => Get.toNamed(RoutePath.kRemoteSync),
          ),
        ]),
        const SizedBox(height: 20),
        context.buildGroupTitle(i18n("local_backup")),
        context.buildModernCard([
          context.buildTile(
            icon: Remix.file_download_line,
            title: i18n("create_backup"),
            subtitle: i18n("create_backup_subtitle"),
            trailing: _backupActionIndicator(_BackupAction.create),
            onTap: _backupAction == null
                ? () => unawaited(
                    _runBackupAction(_BackupAction.create, 'create_backup_failed', () async {
                      // The export flow chooses a directory and remembers the first
                      // successful choice; no separate first-run settings step.
                      await BackupRecoveryService().createAppSettingsBackup(backupDirectory);
                    }),
                  )
                : null,
          ),
          context.buildTile(
            icon: Remix.file_upload_line,
            title: i18n("recover_backup"),
            subtitle: i18n("recover_backup_subtitle"),
            trailing: _backupActionIndicator(_BackupAction.restore),
            onTap: _backupAction == null
                ? () => unawaited(
                    _runBackupAction(
                      _BackupAction.restore,
                      'recover_backup_failed',
                      BackupRecoveryService().recoverSettingsFromFile,
                    ),
                  )
                : null,
          ),
          context.buildTile(
            icon: Remix.folder_open_line,
            title: i18n("backup_directory"),
            subtitle: backupDirectory.isEmpty ? i18n('please_set_backup_directory') : backupDirectory,
            trailing: _backupActionIndicator(_BackupAction.directory),
            onTap: _backupAction == null
                ? () => unawaited(
                    _runBackupAction(_BackupAction.directory, 'backup_directory_update_failed', () async {
                      await BackupRecoveryService().updateBackupDirectory();
                    }),
                  )
                : null,
          ),
        ]),
        const SizedBox(height: 20),
        context.buildGroupTitle(i18n("log_manage")),
        context.buildModernCard([
          Obx(() {
            final applying = logController.isApplyingLogStatus.v;
            final statusKey = logController.logStatusKey.v;
            final subtitleKey = applying
                ? 'local_log_applying'
                : statusKey.isNotEmpty
                ? statusKey
                : 'enable_local_log_desc';
            return context.buildTile(
              icon: Remix.file_text_line,
              title: i18n("enable_local_log"),
              subtitle: i18n(subtitleKey),
              subtitleColor: statusKey.isNotEmpty && !applying ? Theme.of(context).colorScheme.error : null,
              stackTrailingOnNarrow: true,
              showNavigationChevronWhenStacked: false,
              trailing: Switch(
                key: const ValueKey('local-log-switch'),
                value: logController.storedEnableLog.v,
                onChanged: applying ? null : (value) => unawaited(logController.setLoggingEnabled(value)),
              ),
              onTap: applying
                  ? null
                  : () => unawaited(logController.setLoggingEnabled(!logController.storedEnableLog.v)),
            );
          }),
          context.buildTile(
            icon: Remix.file_list_3_line,
            title: i18n("view_logs_in_app"),
            subtitle: i18n("view_logs_in_app_desc"),
            onTap: () => Get.toNamed(RoutePath.kLogs),
          ),
          // Android keeps the logs in the app's own external directory, which
          // the system file manager cannot browse; the list below shares them.
          if (!Platform.isAndroid)
            context.buildTile(
              icon: Remix.folder_open_line,
              title: i18n("open_log_dir"),
              subtitle: i18n("open_log_dir_desc"),
              onTap: _openLogDirectory,
            ),
        ]),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: context.buildGroupTitle(i18n('log_files'))),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: _logFiles.isEmpty ? null : _clearLogFiles,
                icon: const Icon(Icons.clear_all),
                label: Text(i18n('clear_log_files')),
              ),
            ),
          ],
        ),
        context.buildModernCard([_buildLogFileList(context)]),
      ],
    );
  }
}
