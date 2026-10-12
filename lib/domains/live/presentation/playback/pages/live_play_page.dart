import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/core/player/presentation/player_back_scope.dart';
import 'package:pure_live/domains/live/presentation/playback/states/ui_state.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/keyboard/video_keyboard.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/live_play_content.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

class LivePlayPage extends GetView<LivePlayController> {
  const LivePlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final manager = GlobalPlayerService.instance.player;
      final isInPip = manager.isInPip.value || manager.isPipPreparing.value;

      final state = controller.state.value;
      final mode = state.ui.screenMode;
      final videoController = state.player.videoController;
      final player = GlobalPlayerService.instance.player;
      final presentationActive =
          !isInPip && (mode != VideoMode.normal || player.isSystemFullscreen.value || player.isWindowFullscreen.value);

      final content = LivePlayContent(controller: controller, isInPip: isInPip, mode: mode);

      // Keep desktop route shortcuts mounted even when metadata loading ends
      // in an offline/error placeholder before a VideoController exists.
      // Otherwise the visible back button works while Escape silently does
      // nothing on exactly those failure states.
      final page = VideoKeyboardShortcuts(
        controller: videoController,
        child: Container(color: Colors.black, width: double.infinity, height: double.infinity, child: content),
      );

      return PlayerBackScope(
        presentationActive: presentationActive,
        onExitPresentation: controller.exitPresentationForSystemBack,
        child: page,
      );
    });
  }
}
