import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/resolution_selector/label_menu_offset.dart';
import 'package:pure_live/domains/live/presentation/playback/states/player_state.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

class LineSelector extends StatelessWidget {
  const LineSelector({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    // The height the row allows the button, for where its menu opens.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        return Obx(() {
      final state = controller.state.value;

      if (!state.room.success || !state.player.hasPlaybackSource) {
        return const SizedBox.shrink();
      }

      final currentIndex = state.player.currentLineIndex.clamp(0, state.player.lineCount - 1);
      final switching = controller.playerController.isStreamSwitching.value;

      final currentLineName = i18n("toolbox_line", args: {"index": (currentIndex + 1).toString()});

      return PopupMenuButton<int>(
        key: const ValueKey('room-line-selector'),
        enabled: !switching,
        tooltip: i18n("select_play_line"),
        // Exactly as wide as the entries (see choiceMenuConstraints).
        constraints: choiceMenuConstraints(context, [
          for (var line = 0; line < state.player.lineCount; line++)
            i18n("toolbox_line", args: {"index": (line + 1).toString()}),
        ]),
        offset: labelMenuOffset(context, _labelStyle(context), maxHeight),
        onOpened: () {
          controller.updateUI(isMenuOpen: true);
        },
        onCanceled: () {
          controller.updateUI(isMenuOpen: false);
        },
        position: PopupMenuPosition.under,
        child: ConstrainedBox(
          constraints: PlayerControlDensity.actionConstraints(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (switching) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: Get.theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    currentLineName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Quality and line share one role, the secondary text.
                    style: _labelStyle(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        onSelected: (newLineIndex) async {
          controller.updateUI(isMenuOpen: false);
          await controller.setResolution(ReloadDataType.changeLine, state.player.currentQuality, newLineIndex);
        },
        itemBuilder: (context) {
          final labels = [
            for (var line = 0; line < state.player.lineCount; line++)
              i18n("toolbox_line", args: {"index": (line + 1).toString()}),
          ];
          return [
            for (var index = 0; index < labels.length; index++)
              choiceMenuItem<int>(
                context,
                value: index,
                label: labels[index],
                labels: labels,
                selected: index == currentIndex,
              ),
          ];
        },
      );
        });
      },
    );
  }
}

/// The label's style, shared with the menu's offset.
TextStyle _labelStyle(BuildContext context) =>
    AppText.of(context).secondary.copyWith(color: Get.theme.colorScheme.primary, fontWeight: FontWeight.w700);
