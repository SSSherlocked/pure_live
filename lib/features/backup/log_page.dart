import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:remixicon/remixicon.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/logging/app_log.dart';

/// This run's log, in the app: the in-memory buffer every `Log` call and
/// `debugPrint` feeds, newest at the bottom, with copy, share and clear.
/// It needs no file, no directory and no switch, so it works on every
/// platform the moment something goes wrong.
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // The buffer is not observable; a once-a-second rebuild keeps the page
    // current while it is open.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _refresh = null;
    super.dispose();
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: Log.exportText()));
    ToastUtil.show(i18n('copied_to_clipboard'));
  }

  Future<void> _share() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}pure_live_${Log.fileTimestamp(DateTime.now())}.log');
      await file.writeAsString(Log.exportText(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      ToastUtil.show(i18n('log_share_failed'));
    }
  }

  void _clear() {
    Log.clearDebugLogs();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final logs = Log.allLogs;
    final colors = Theme.of(context).colorScheme;
    final style = AppText.of(context).secondary;
    return Scaffold(
      appBar: AppBar(
        title: Text('${i18n('log_page_title')} (${logs.length})'),
        actions: [
          IconButton(
            tooltip: i18n('copy'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: logs.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: i18n('share'),
            icon: const Icon(RemixIcons.share_forward_line),
            onPressed: logs.isEmpty ? null : _share,
          ),
          IconButton(
            tooltip: i18n('clear'),
            icon: const Icon(RemixIcons.delete_bin_line),
            onPressed: logs.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: SettingsContentWidth(
        child: logs.isEmpty
            ? Center(child: Text(i18n('log_empty'), style: style.copyWith(color: colors.onSurfaceVariant)))
            : ListView.builder(
                // Newest at the bottom, and the list opens there.
                reverse: true,
                physics: const PureLiveScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final entry = logs[logs.length - 1 - index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${Log.formatLogTime(entry.datetime)}  ${entry.content}',
                      style: style.copyWith(color: entry.color ?? colors.onSurface),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
