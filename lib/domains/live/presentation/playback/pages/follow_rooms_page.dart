import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/play_other.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

/// "关注" tab of the room panel: followed rooms (已开播 / 录播 / 观看记录),
/// one tap away from replacing the room being watched.
class FollowRoomsPage extends StatelessWidget {
  const FollowRoomsPage({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    return FollowRoomSwitcher(key: const ValueKey('live-follow-rooms-list'), controller: controller);
  }
}
