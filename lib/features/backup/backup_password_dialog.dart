import 'dart:convert';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/security/settings_crypto.dart';
import 'package:pure_live/features/backup/backup_controller.dart';

/// Sections that hold credentials: account cookies and the WebDAV password.
const Set<String> sensitiveBackupSections = <String>{'cookie', 'webdav'};

/// Whether a backup of [sections] would carry credentials.
bool backupIncludesSensitiveSections(Iterable<String>? sections) =>
    sections == null || sections.any(sensitiveBackupSections.contains);

/// The viewer's choice for a backup that would carry credentials.
sealed class BackupPasswordChoice {
  const BackupPasswordChoice();
}

/// Encrypt the whole backup with this password.
final class EncryptBackup extends BackupPasswordChoice {
  const EncryptBackup(this.password);
  final String password;
}

/// No password: back up without the credential sections.
final class SkipSensitiveSections extends BackupPasswordChoice {
  const SkipSensitiveSections();
}

/// Minimum backup password length; the key derivation is slow on purpose, but a
/// very short password is still guessable.
const int minimumBackupPasswordLength = 6;

/// Asks for a password to encrypt a backup with. Null means the backup was
/// cancelled.
Future<BackupPasswordChoice?> askBackupEncryptionPassword(BuildContext context) {
  return showDialog<BackupPasswordChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _EncryptionPasswordDialog(),
  );
}

/// Asks for the password of an encrypted backup. Null means cancelled.
Future<String?> askBackupDecryptionPassword(BuildContext context, {bool retry = false}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DecryptionPasswordDialog(retry: retry),
  );
}

/// Thrown when the viewer cancels the password prompt of an encrypted backup.
class BackupDecryptionCancelled implements Exception {
  const BackupDecryptionCancelled();
}

/// Reads backup [content], asking for the password when it is encrypted.
///
/// A plain backup (every backup made before encryption existed) is read as it
/// always was. A wrong password asks again, up to [attempts] times, then throws
/// [BackupPasswordException]; cancelling throws [BackupDecryptionCancelled].
Future<Map<String, dynamic>> openBackupContent(
  String content, {
  required Future<String?> Function({required bool retry}) askPassword,
  int attempts = 3,
}) async {
  var json = content;
  if (BackupCipher.isEncrypted(content)) {
    String? decrypted;
    for (var attempt = 0; attempt < attempts && decrypted == null; attempt++) {
      final password = await askPassword(retry: attempt > 0);
      if (password == null) throw const BackupDecryptionCancelled();
      try {
        decrypted = await BackupCipher.decrypt(content, password);
      } on BackupPasswordException {
        if (attempt == attempts - 1) rethrow;
      }
    }
    json = decrypted!;
  }
  final data = jsonDecode(json);
  if (data is! Map) throw const FormatException('Backup is not a settings object');
  return Map<String, dynamic>.from(data);
}

/// Serializes [data] for a backup file: encrypted when [password] is given.
Future<String> sealBackupContent(Map<String, dynamic> data, {String? password}) {
  final json = const JsonEncoder.withIndent('  ').convert(data);
  if (password == null || password.isEmpty) return Future.value(json);
  return BackupCipher.encrypt(json, password);
}

/// The export for a backup of [sections]: credentials only when the backup is
/// going to be encrypted.
Map<String, dynamic> exportForBackup({Iterable<String>? sections, String? password}) {
  return BackupController.to.exportAllSettings(
    includeSensitiveData: password != null && password.isNotEmpty,
    sections: sections,
  );
}

class _EncryptionPasswordDialog extends StatefulWidget {
  const _EncryptionPasswordDialog();

  @override
  State<_EncryptionPasswordDialog> createState() => _EncryptionPasswordDialogState();
}

class _EncryptionPasswordDialogState extends State<_EncryptionPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (password.length < minimumBackupPasswordLength) {
      setState(() => _error = i18n('backup_password_too_short', args: {'count': '$minimumBackupPasswordLength'}));
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = i18n('backup_password_mismatch'));
      return;
    }
    Navigator.of(context).pop(EncryptBackup(password));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(i18n('backup_password_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n('backup_password_explain'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('backup-password'),
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: i18n('backup_password'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('backup-password-confirm'),
              controller: _confirm,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: i18n('backup_password_confirm'),
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              i18n('backup_password_forget_warning'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        TextButton(
          key: const ValueKey('backup-password-skip'),
          onPressed: () => Navigator.of(context).pop(const SkipSensitiveSections()),
          child: Text(i18n('backup_password_skip')),
        ),
        FilledButton(
          key: const ValueKey('backup-password-encrypt'),
          onPressed: _submit,
          child: Text(i18n('backup_password_encrypt')),
        ),
      ],
    );
  }
}

class _DecryptionPasswordDialog extends StatefulWidget {
  const _DecryptionPasswordDialog({required this.retry});

  final bool retry;

  @override
  State<_DecryptionPasswordDialog> createState() => _DecryptionPasswordDialogState();
}

class _DecryptionPasswordDialogState extends State<_DecryptionPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(i18n('backup_password_enter_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TextField(
          key: const ValueKey('backup-password-unlock'),
          controller: _password,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (value) => Navigator.of(context).pop(value),
          decoration: InputDecoration(
            labelText: i18n('backup_password'),
            border: const OutlineInputBorder(),
            errorText: widget.retry ? i18n('backup_password_wrong') : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        FilledButton(onPressed: () => Navigator.of(context).pop(_password.text), child: Text(i18n('confirm'))),
      ],
    );
  }
}
