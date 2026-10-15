import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/resolution_selector/label_menu_offset.dart';
import 'package:pure_live/domains/live/presentation/playback/states/player_state.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/states/live_room_status.dart';

class ResolutionSelector extends StatelessWidget {
  const ResolutionSelector({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    // The height the row allows the button, for where its menu opens.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        return Obx(() {
      final state = controller.state.value;

      if (!state.room.success || state.player.qualites.isEmpty) {
        return const SizedBox.shrink();
      }

      final currentIndex = state.player.currentQuality.clamp(0, state.player.qualites.length - 1);
      final currentQualityName = LiveRoomStatus.of(controller).qualityLabel;
      final switching = controller.playerController.isStreamSwitching.value;

      return PopupMenuButton<int>(
        key: const ValueKey('room-quality-selector'),
        enabled: !switching,
        tooltip: i18n('toolbox_select_quality'),
        // Exactly as wide as the entries (see choiceMenuConstraints).
        constraints: choiceMenuConstraints(context, [for (final quality in state.player.qualites) quality.quality]),
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
                    currentQualityName,
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
        onSelected: (newQualityIndex) async {
          controller.updateUI(isMenuOpen: false);
          await controller.setResolution(ReloadDataType.changeQuality, newQualityIndex, state.player.currentLineIndex);
        },
        itemBuilder: (context) {
          final labels = [for (final quality in state.player.qualites) quality.quality];
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
