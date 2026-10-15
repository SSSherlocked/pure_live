import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/playback/states/room_state.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_player.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_loading.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/placeholder/not_living_video_widget.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/play_other.dart';
import 'package:pure_live/core/player/core/portrait_stream_support.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

class LivePlayVideo extends StatelessWidget {
  const LivePlayVideo({
    super.key,
    required this.controller,
    this.expandToParent = false,
    this.transparentSurface = false,
    this.pageSurface = false,
    this.videoViewportAspectRatio,
    this.portraitFullscreenDisplayMode,
  });

  final LivePlayController controller;
  final bool expandToParent;
  final bool transparentSurface;

  /// The picture sits on the page background instead of black: the frame
  /// fills its area and the video is letterboxed in page colour. Placeholders
  /// (loading, offline, failed) keep their black backdrop - they are drawn
  /// for one.
  final bool pageSurface;
  final double? videoViewportAspectRatio;
  final PortraitFullscreenDisplayMode? portraitFullscreenDisplayMode;

  @override
  Widget build(BuildContext context) {
    return LivePlayVideoFrame(
      expandToParent: expandToParent,
      child: ColoredBox(
        color: transparentSurface || pageSurface ? Colors.transparent : Colors.black,
        child: Obx(() {
          final state = controller.state.value;
          final videoController = state.player.videoController;
          if (videoController == null) {
            final kind = livePlayPlaceholderFor(state.room);
            Widget placeholder = switch (kind) {
              LivePlayPlaceholder.loading => const VideoLoading(),
              LivePlayPlaceholder.loadFailed => RoomLoadFailedWidget(controller: controller),
              LivePlayPlaceholder.notLiving => NotLivingVideoWidget(controller: controller),
            };
            // A long press shows 关注 here too, as it does on the picture, so
            // a room that cannot play is never a dead end.
            if (kind != LivePlayPlaceholder.loading) {
              placeholder = Builder(
                builder: (context) => GestureDetector(
                  key: const ValueKey('room-placeholder-long-press'),
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => showFollowPanel(context, controller),
                  child: placeholder,
                ),
              );
            }
            return pageSurface ? ColoredBox(color: Colors.black, child: placeholder) : placeholder;
          }
          final reloading = state.room.isLoading;
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: transparentSurface || pageSurface ? Colors.transparent : Colors.black,
                child: VideoPlayer(
                  controller: videoController,
                  surfaceColor: transparentSurface || pageSurface ? Colors.transparent : Colors.black,
                  videoViewportAspectRatio: videoViewportAspectRatio,
                  portraitFullscreenDisplayMode: portraitFullscreenDisplayMode,
                ),
              ),
              // A spinner in the middle of the picture while the stream is not
              // playing yet (opening, 刷新, a line change, buffering) or while
              // it stalls mid-play, so a black or frozen picture never leaves
              // its state unknown. It takes no pointer; the controls stay
              // usable over it.
              ListenableBuilder(
                listenable: videoController,
                builder: (context, _) => Obx(() {
                  final status = videoController.status;
                  final stalled = GlobalPlayerService.instance.player.isStalled.value;
                  final waiting =
                      reloading ||
                      stalled ||
                      status == PlayerStatus.idle ||
                      status == PlayerStatus.loading ||
                      status == PlayerStatus.disposed;
                  if (!waiting) return const SizedBox.shrink();
                  return const IgnorePointer(
                    key: ValueKey('player-loading-spinner'),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 48,
                        child: AppStatusView(
                          type: AppStatusType.loading,
                          title: '',
                          subtitle: '',
                          iconColor: Colors.white,
                          isMini: true,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        }),
      ),
    );
  }
}

enum LivePlayPlaceholder { loading, loadFailed, notLiving }

/// What the video area shows before a player exists. A finished load that
/// recorded an error must not keep spinning: `isLiving` defaults to true, so
/// a failed room request previously left an endless spinner with no retry.
@visibleForTesting
LivePlayPlaceholder livePlayPlaceholderFor(RoomState room) {
  if (room.isLoading) return LivePlayPlaceholder.loading;
  if (room.loadError != null) return LivePlayPlaceholder.loadFailed;
  return room.isLiving ? LivePlayPlaceholder.loading : LivePlayPlaceholder.notLiving;
}

/// Leaving a room only floats a player that is actually presenting video.
/// A failed or never-opened room would otherwise leave an empty black window.
bool shouldFloatAfterLivePlayExit(RoomState room, {required bool hasVideo}) => hasVideo && room.loadError == null;

class RoomLoadFailedWidget extends StatelessWidget {
  const RoomLoadFailedWidget({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    // Fullscreen has no other way out of a failed room: it gets the 未开播
    // page's top bar (back, title, time).
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          if (GlobalPlayerService.instance.player.fullscreenUI) RoomPlaceholderHeader(controller: controller),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 36),
            const SizedBox(height: 8),
            Text(
              i18n('get_room_info_failed_retry'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('room-load-retry'),
              onPressed: () => unawaited(controller.onInitPlayerState()),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(i18n('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the legacy 16:9 contract for every ordinary landscape room.
///
/// Only a caller that already owns an explicit adaptive portrait/fullscreen
/// frame may opt into expansion. Making the generic video widget expand by
/// default lets an unrelated parent constraint change every playback mode at
/// once, which caused the v3.0.1 landscape/PiP regression.
@visibleForTesting
class LivePlayVideoFrame extends StatelessWidget {
  const LivePlayVideoFrame({super.key, required this.child, required this.expandToParent});

  final Widget child;
  final bool expandToParent;

  @override
  Widget build(BuildContext context) {
    if (expandToParent) return SizedBox.expand(child: child);
    return AspectRatio(aspectRatio: 16 / 9, child: child);
  }
}
