import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller_panel.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

class NotLivingVideoWidget extends StatelessWidget {
  const NotLivingVideoWidget({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(children: [RoomPlaceholderHeader(controller: controller), _buildContent()]),
    );
  }

  Widget _buildContent() {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const ValueKey('offline-room-content-scroll'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (constraints.maxHeight - 16).clamp(0, double.infinity).toDouble()),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // Just 未开播, as large as the old 无法播放直播 line.
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      i18n('offline_room_title'),
                      key: const ValueKey('offline-room-label'),
                      style: AppText.of(context).sectionTitle.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top bar over a room with no player (未开播, 加载失败): the room title,
/// and in fullscreen a back button and the time.
class RoomPlaceholderHeader extends StatelessWidget {
  const RoomPlaceholderHeader({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    final fullscreen = GlobalPlayerService.instance.player.fullscreenUI;
    final titleStyle = AppText.of(context).listPrimary.copyWith(color: Colors.white, decoration: TextDecoration.none);
    final titlePainter = TextPainter(
      text: TextSpan(text: 'Ag', style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final scaledContentHeight = titlePainter.height + 8;
    final headerHeight = scaledContentHeight > 55 ? scaledContentHeight : 55.0;

    return Container(
      key: const ValueKey('offline-room-header'),
      height: headerHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.transparent, Colors.black45],
        ),
      ),
      child: Row(
        children: [
          if (fullscreen)
            IconButton(
              key: const ValueKey('offline-room-exit-fullscreen'),
              tooltip: i18n('exit_fullscreen'),
              visualDensity: VisualDensity.standard,
              constraints: const BoxConstraints(
                minWidth: kMinInteractiveDimension,
                minHeight: kMinInteractiveDimension,
              ),
              onPressed: _exitFullscreen,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                key: const ValueKey('offline-room-title'),
                _offlineRoomTitle(controller.room),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: titleStyle,
              ),
            ),
          ),
          if (fullscreen) const DatetimeInfo(),
        ],
      ),
    );
  }

  void _exitFullscreen() {
    controller.setNormalScreen();
    GlobalPlayerService.instance.player.isSystemFullscreen.value = false;
    GlobalPlayerService.instance.player.isWindowFullscreen.value = false;
  }
}

String _offlineRoomTitle(LiveRoom liveroom) {
  for (final candidate in [liveroom.title, liveroom.nick, liveroom.roomId]) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return i18n('untitled_room');
}
