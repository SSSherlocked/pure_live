import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/recorder/domain/models/record_status.dart';
import 'package:pure_live/domains/recorder/domain/models/live_record_task.dart';
import 'package:pure_live/domains/recorder/presentation/pages/recorder/recorder_controller.dart';

/// The room's 录制 actions: the action dialog (start now, record center, add or
/// remove the monitor, stop) and what each choice does. Opened from the room
/// header's menu.
class RecordRoomActions {
  RecordRoomActions({required this.recorderController, required this.onOpenRecordCenter});

  final RecorderController recorderController;
  final Future<void> Function() onOpenRecordCenter;

  bool _busy = false;

  /// The task recording or monitoring [room], if any.
  LiveRecordTask? taskFor(LiveRoom room) => _findTask(room);

  /// Whether [task] is recording right now (including preparing/reconnecting).
  static bool isRunning(LiveRecordTask? task) => _isTaskRunningStatic(task);

  /// Shows the action dialog for [liveroom] and carries out the choice.
  Future<void> open(BuildContext context, LiveRoom liveroom) => _handlePressed(context, liveroom);

  bool _isTaskRunning(LiveRecordTask? task) => _isTaskRunningStatic(task);

  static bool _isTaskRunningStatic(LiveRecordTask? task) {
    if (task == null) {
      return false;
    }

    return task.status == RecordStatus.running ||
        task.status == RecordStatus.reconnecting ||
        task.status == RecordStatus.preparing;
  }

  Future<void> _handlePressed(BuildContext context, LiveRoom liveroom) async {
    if (_busy) return;
    _busy = true;
    try {
      final initialTask = _findTask(liveroom);
      final action = await _showActionDialog(
        context,
        exists: initialTask != null,
        isRunning: _isTaskRunning(initialTask),
      );

      if (!context.mounted || action == null) return;
      final task = _findTask(liveroom);
      final exists = task != null;
      final isRunning = _isTaskRunning(task);

      switch (action) {
        case "start":
          await _startRecording(liveroom: liveroom, task: task, exists: exists, isRunning: isRunning);
          break;

        case "monitor":
          await _addMonitor(liveroom: liveroom, exists: exists);
          break;

        case "stop":
          await _stopRecording(task: task, exists: exists, isRunning: isRunning);
          break;

        case "delete":
          await _removeMonitor(task: task, exists: exists, isRunning: isRunning);
          break;

        case "page":
          await onOpenRecordCenter();
          break;
      }
    } finally {
      _busy = false;
    }
  }

  LiveRecordTask? _findTask(LiveRoom liveroom) => recorderController.tasks.firstWhereOrNull(
    (task) => task.platform == liveroom.platform && task.roomId == liveroom.roomId,
  );

  Future<void> _startRecording({
    required LiveRoom liveroom,
    required LiveRecordTask? task,
    required bool exists,
    required bool isRunning,
  }) async {
    if (isRunning) {
      return;
    }

    // 私有目录就绪检查在录制意图上触发，不在进直播间时自动弹。
    if (!await recorderController.ensureRecordDirUsable()) {
      return;
    }

    if (exists && task != null) {
      await recorderController.forceStartTask(task);
      return;
    }

    // addTask owns the first transition into the scheduler. Starting it again
    // from the button created two competing intents and made first-attempt
    // failures difficult to classify.
    await recorderController.addTask(liveroom: liveroom, startImmediately: true);
  }

  Future<void> _addMonitor({required LiveRoom liveroom, required bool exists}) async {
    if (exists) {
      return;
    }

    if (!await recorderController.ensureRecordDirUsable()) {
      return;
    }

    final task = await recorderController.addTask(liveroom: liveroom, startImmediately: false);
    if (task != null) ToastUtil.show(i18n("record_task_added"));
  }

  Future<void> _stopRecording({required LiveRecordTask? task, required bool exists, required bool isRunning}) async {
    if (!exists || task == null || !isRunning) {
      return;
    }

    await recorderController.stopTask(task);
  }

  Future<void> _removeMonitor({required LiveRecordTask? task, required bool exists, required bool isRunning}) async {
    if (!exists || task == null || isRunning) {
      return;
    }

    await recorderController.unRecorder(task);
  }

  Future<String?> _showActionDialog(BuildContext context, {required bool exists, required bool isRunning}) {
    final theme = Theme.of(context);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final availableHeight =
            mediaQuery.size.height - mediaQuery.padding.vertical - mediaQuery.viewInsets.vertical - 32;
        final stackTitle = mediaQuery.size.width < 360 || mediaQuery.textScaler.scale(22) > 40;
        final titleIcon = AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            isRunning
                ? Remix.record_circle_fill
                : exists
                ? Remix.checkbox_circle_fill
                : Remix.record_circle_line,
            key: ValueKey(
              isRunning
                  ? "running"
                  : exists
                  ? "exists"
                  : "empty",
            ),
            color: isRunning ? Colors.redAccent : theme.colorScheme.primary,
            size: 22,
          ),
        );
        final titleText = Text(
          isRunning
              ? i18n("recording")
              : exists
              ? i18n("record_task")
              : i18n("record"),
          style: theme.textTheme.headlineSmall,
        );
        return Dialog(
          key: const ValueKey('record-action-dialog'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: availableHeight > 0 ? availableHeight : mediaQuery.size.height,
            ),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    key: const ValueKey('record-action-title'),
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                    child: stackTitle
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [titleIcon, const SizedBox(height: 8), titleText],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleIcon,
                              const SizedBox(width: 10),
                              Expanded(child: titleText),
                            ],
                          ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('record-action-scroll'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionTile(
                            icon: Icons.play_arrow_rounded,
                            title: i18n("start_record_now"),
                            color: Colors.green,
                            enabled: !isRunning,
                            onTap: () => Navigator.pop(dialogContext, "start"),
                          ),
                          _ActionTile(
                            icon: Icons.video_library_rounded,
                            title: i18n("go_record_center"),
                            color: theme.colorScheme.primary,
                            enabled: true,
                            onTap: () => Navigator.pop(dialogContext, "page"),
                          ),
                          _ActionTile(
                            icon: Remix.checkbox_circle_line,
                            title: i18n("add_monitor"),
                            color: theme.colorScheme.primary,
                            enabled: !exists,
                            onTap: () => Navigator.pop(dialogContext, "monitor"),
                          ),
                          _ActionTile(
                            icon: Icons.stop_circle_outlined,
                            title: i18n("stop_record"),
                            color: Colors.orange,
                            enabled: isRunning,
                            onTap: () => Navigator.pop(dialogContext, "stop"),
                          ),
                          _ActionTile(
                            icon: Icons.delete_outline_rounded,
                            title: i18n("remove_monitor"),
                            color: Colors.redAccent,
                            enabled: exists && !isRunning,
                            onTap: () => Navigator.pop(dialogContext, "delete"),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  SafeArea(
                    key: const ValueKey('record-action-footer'),
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          key: const ValueKey('record-action-cancel'),
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(i18n('cancel')),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.32);

    final actualColor = enabled ? color : disabledColor;

    final backgroundAlpha = enabled ? 0.10 : 0.045;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1.0 : 0.72,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: actualColor.withValues(alpha: backgroundAlpha),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: actualColor, size: 20),
        ),
        title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: actualColor)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        enabled: enabled,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
