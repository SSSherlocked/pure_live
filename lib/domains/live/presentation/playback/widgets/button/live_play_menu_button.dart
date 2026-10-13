import 'dart:io';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/share_command_handler.dart';
import 'package:pure_live/core/platform/windows_multi_instance_launcher.dart';
import 'package:pure_live/core/player/presentation/left_submenu_button.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/room_timer_dialog.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/known_room_link_dialog.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/video_details_dialog.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/recorder/presentation/widgets/record_room_actions.dart';

class LivePlayMenuButton extends StatefulWidget {
  const LivePlayMenuButton({super.key, required this.controller});

  final LivePlayController controller;

  @override
  State<LivePlayMenuButton> createState() => _LivePlayMenuButtonState();
}

class _LivePlayMenuButtonState extends State<LivePlayMenuButton> {
  LivePlayController get controller => widget.controller;

  late final RecordRoomActions _recordActions = RecordRoomActions(
    recorderController: controller.recorderController,
    onOpenRecordCenter: controller.openRecordCenter,
  );

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: i18n('menu'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(12, 0),
      position: PopupMenuPosition.under,
      onOpened: () {
        controller.updateUI(isMenuOpen: true);
      },
      onCanceled: () {
        controller.updateUI(isMenuOpen: false);
      },
      onSelected: (index) {
        _handleSelected(context, index);
      },
      itemBuilder: _buildItems,
      child: const SizedBox.square(dimension: kMinInteractiveDimension, child: Icon(Icons.menu_rounded)),
    );
  }

  void _handleSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        _openLiveRoom();
        break;

      case 1:
        _openRecordActions(context);
        break;

      case 2:
        _castScreen(context);
        break;

      case 3:
        _showTimer(context);
        break;

      case 5:
        _getDirectLink(context);
        break;

      case 6:
        _shareRoom();
        break;

      case 8:
        _openNewWindow();
        break;

      case 9:
        unawaited(VideoDetailsDialog.show(context, controller));
        break;
    }

    controller.updateUI(isMenuOpen: false);
  }

  void _openLiveRoom() {
    controller.openNaviteAPP();
  }

  void _openRecordActions(BuildContext context) {
    final detail = controller.state.value.room.detail;
    if (detail == null) return;
    unawaited(_recordActions.open(context, detail));
  }

  void _castScreen(BuildContext context) {
    final detail = controller.state.value.room.detail;

    KnownRoomLinkDialog.castPlayUrlByRoomId(
      context: context,
      liveroom: detail ?? LiveRoom(roomId: '', platform: ''),
      isCurrentRoom: () =>
          !controller.isClosed &&
          detail != null &&
          (controller.state.value.room.detail?.hasSameIdentity(detail) ?? false),
    );
  }

  void _showTimer(BuildContext context) {
    RoomTimerDialog.show(context: context, controller: controller);
  }

  void _getDirectLink(BuildContext context) {
    final detail = controller.state.value.room.detail;

    if (detail == null) {
      return;
    }

    KnownRoomLinkDialog.getPlayUrlByRoomId(
      context: context,
      liveroom: detail,
      isCurrentRoom: () =>
          !controller.isClosed && (controller.state.value.room.detail?.hasSameIdentity(detail) ?? false),
    );
  }

  void _shareRoom() {
    final detail = controller.state.value.room.detail;

    if (detail == null) {
      return;
    }

    ShareCommandHandler.instance.onShareRoomPressed(detail);
  }

  void _openNewWindow() {
    final detail = controller.state.value.room.detail;

    if (detail == null) {
      return;
    }

    WindowsMultiInstanceLauncher.launch(liveroom: detail).catchError((Object error, StackTrace stackTrace) {
      developer.log(
        'Open live room in a new Windows instance failed',
        name: 'LivePlayPage',
        error: error,
        stackTrace: stackTrace,
      );

      ToastUtil.show(i18n('open_new_window_failed'));
    });
  }

  List<PopupMenuEntry<int>> _buildItems(BuildContext context) {
    return [
      _item(value: 0, icon: Icons.open_in_new_rounded, text: i18n('open_live_room')),

      ?_recordItem(),

      _item(value: 2, icon: Remix.tv_2_line, text: i18n('cast_screen')),

      _item(value: 3, icon: Remix.time_line, text: i18n('sleep_timer')),

      _item(value: 5, icon: Remix.link_m, text: i18n('toolbox_get_direct_link')),

      _item(value: 6, icon: RemixIcons.share_forward_line, text: i18n('share')),

      if (Platform.isWindows) _item(value: 8, icon: Icons.open_in_new_rounded, text: i18n('open_room_in_new_window')),

      // Always last.
      _item(value: 9, icon: Remix.information_line, text: i18n('video_details')),
    ];
  }

  /// 录制, labelled with the room's current recording state.
  PopupMenuItem<int>? _recordItem() {
    final detail = controller.state.value.room.detail;
    if (detail == null) return null;
    final state = _recordState(_recordActions, detail);
    return _item(
      value: 1,
      icon: state.icon,
      iconColor: state.running ? Colors.redAccent : null,
      text: i18n(state.labelKey),
    );
  }

  PopupMenuItem<int> _item({required int value, required IconData icon, required String text, Color? iconColor}) {
    return PopupMenuItem<int>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MenuListTile(leading: Icon(icon, size: 20, color: iconColor), text: text),
    );
  }
}

/// The room's 录制 state as an icon and a label: recording, monitored or not.
({IconData icon, String labelKey, bool running}) _recordState(RecordRoomActions actions, LiveRoom room) {
  final task = actions.taskFor(room);
  final running = RecordRoomActions.isRunning(task);
  return (
    icon: running
        ? Remix.record_circle_fill
        : task != null
        ? Remix.checkbox_circle_fill
        : Remix.record_circle_line,
    labelKey: running
        ? 'recording'
        : task != null
        ? 'monitored'
        : 'record',
    running: running,
  );
}

/// 录制 in the fullscreen ⋯ menu: a left-opening submenu with the record
/// dialog's actions, each enabled or not as the room's task changes.
class LiveRoomRecordMenuEntry extends StatefulWidget {
  const LiveRoomRecordMenuEntry({super.key, required this.controller});

  final LivePlayController controller;

  @override
  State<LiveRoomRecordMenuEntry> createState() => _LiveRoomRecordMenuEntryState();
}

class _LiveRoomRecordMenuEntryState extends State<LiveRoomRecordMenuEntry> {
  late final RecordRoomActions _actions = RecordRoomActions(
    recorderController: widget.controller.recorderController,
    onOpenRecordCenter: widget.controller.openRecordCenter,
  );

  static const _entries = <(RecordRoomAction, IconData, String, Color?)>[
    (RecordRoomAction.start, Icons.play_arrow_rounded, 'start_record_now', Colors.green),
    (RecordRoomAction.page, Icons.video_library_rounded, 'go_record_center', null),
    (RecordRoomAction.monitor, Remix.checkbox_circle_line, 'add_monitor', null),
    (RecordRoomAction.stop, Icons.stop_circle_outlined, 'stop_record', Colors.orange),
    (RecordRoomAction.delete, Icons.delete_outline_rounded, 'remove_monitor', Colors.redAccent),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Obx(() {
      final room = widget.controller.state.value.room.detail;
      if (room == null) return const SizedBox.shrink();
      // Reads the recorder's task list, so the entries follow its changes.
      final state = _recordState(_actions, room);
      return LeftSubmenuButton(
        key: const ValueKey('player-more-record'),
        leadingIcon: Icon(state.icon, size: 18, color: state.running ? Colors.redAccent : null),
        labels: [for (final entry in _entries) i18n(entry.$3)],
        // The entries' icon and its gap.
        entryLeadingWidth: 18 + 12,
        menuChildren: [
          for (final (action, icon, labelKey, color) in _entries)
            Builder(
              builder: (context) {
                final enabled = _actions.isEnabled(action, room);
                return MenuItemButton(
                  key: ValueKey('player-more-record-${action.name}'),
                  leadingIcon: Icon(icon, size: 18, color: enabled ? (color ?? primary) : null),
                  onPressed: enabled ? () => unawaited(_actions.perform(action, room)) : null,
                  child: Text(i18n(labelKey)),
                );
              },
            ),
        ],
        child: Text(i18n(state.labelKey)),
      );
    });
  }
}

/// A red 录制中 button beside the fullscreen ⋯, the same size, while the room
/// is being recorded; it opens the record dialog.
class LiveRoomRecordingIndicator extends StatefulWidget {
  const LiveRoomRecordingIndicator({super.key, required this.controller});

  final LivePlayController controller;

  @override
  State<LiveRoomRecordingIndicator> createState() => _LiveRoomRecordingIndicatorState();
}

class _LiveRoomRecordingIndicatorState extends State<LiveRoomRecordingIndicator> {
  late final RecordRoomActions _actions = RecordRoomActions(
    recorderController: widget.controller.recorderController,
    onOpenRecordCenter: widget.controller.openRecordCenter,
  );

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final room = widget.controller.state.value.room.detail;
      if (room == null || !_recordState(_actions, room).running) return const SizedBox.shrink();
      return IconButton(
        key: const ValueKey('player-recording-indicator'),
        tooltip: i18n('recording'),
        visualDensity: VisualDensity.standard,
        constraints: PlayerControlDensity.actionConstraints(context),
        color: Colors.redAccent,
        icon: const Icon(Remix.record_circle_fill),
        onPressed: () => unawaited(_actions.open(context, room)),
      );
    });
  }
}
