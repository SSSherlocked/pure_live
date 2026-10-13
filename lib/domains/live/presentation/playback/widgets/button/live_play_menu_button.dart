import 'dart:io';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';
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
    // The same menu as the home page's: MenuAnchor entries sized to their
    // content (a popup menu rounds its width up to 56 px steps, which left a
    // wide empty band on the right).
    return MenuAnchor(
      style: homeMenuStyle,
      alignmentOffset: const Offset(0, 4),
      onOpen: () => controller.updateUI(isMenuOpen: true),
      onClose: () => controller.updateUI(isMenuOpen: false),
      menuChildren: _buildItems(context),
      builder: (context, menu, _) => homeMenuToggle(menu, icon: Icons.menu_rounded, tooltip: i18n('menu')),
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

  List<Widget> _buildItems(BuildContext context) {
    Widget item(int value, IconData icon, String text, {Color? iconColor}) => homeMenuItem(
      context,
      icon: icon,
      text: text,
      iconColor: iconColor,
      onPressed: () => _handleSelected(context, value),
    );
    final detail = controller.state.value.room.detail;
    final record = detail == null ? null : _recordState(_recordActions, detail);
    return [
      if (record != null)
        item(1, record.icon, i18n(record.labelKey), iconColor: record.running ? Colors.redAccent : null),
      item(2, Remix.tv_2_line, i18n('cast_screen')),
      Obx(() {
        final videoController = controller.state.value.player.videoController;
        if (videoController == null) return const SizedBox.shrink();
        return homeMenuItem(
          context,
          icon: videoController.isAudioOnly ? Icons.check_rounded : Icons.headphones_rounded,
          text: i18n('audio_only_mode'),
          onPressed: () {
            unawaited(videoController.toggleAudioOnly());
            controller.updateUI(isMenuOpen: false);
          },
        );
      }),
      item(5, Remix.link_m, i18n('toolbox_get_direct_link')),
      item(0, Icons.open_in_new_rounded, i18n('open_live_room')),
      item(3, Remix.time_line, i18n('sleep_timer')),
      item(6, RemixIcons.share_forward_line, i18n('share')),
      if (Platform.isWindows) item(8, Icons.open_in_new_rounded, i18n('open_room_in_new_window')),
      // Always last.
      item(9, Remix.information_line, i18n('video_details')),
    ];
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
                  child: Text(i18n(labelKey), style: playerMenuLabelStyle),
                );
              },
            ),
        ],
        child: Text(i18n(state.labelKey), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: playerMenuLabelStyle),
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
