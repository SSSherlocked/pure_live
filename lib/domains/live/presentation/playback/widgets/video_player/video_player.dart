import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/core/portrait_stream_support.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/picture_cover.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller_panel.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/playback_failure_overlay.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

class VideoPlayer extends StatefulWidget {
  final VideoController controller;
  final Color surfaceColor;
  final double? videoViewportAspectRatio;
  final PortraitFullscreenDisplayMode? portraitFullscreenDisplayMode;

  /// Sizes the video to the picture when it is fitted whole (适应), so the
  /// area around it shows what lies behind the player. The engine's surface
  /// paints its own letterbox in black whatever [surfaceColor] says; only
  /// leaving that area out of the surface keeps the page colour there. The
  /// controls still cover the whole area.
  final bool boxToPicture;
  const VideoPlayer({
    super.key,
    required this.controller,
    this.surfaceColor = Colors.black,
    this.boxToPicture = false,
    this.videoViewportAspectRatio,
    this.portraitFullscreenDisplayMode,
  });

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  VideoController get controller => widget.controller;
  Widget _buildVideo() {
    return Obx(() {
      final player = GlobalPlayerService.instance.player;
      final hasError = controller.hasPlaybackError;
      final fitIndex = SettingsService.to.player.videoFitIndex.v;
      final fitList = SettingsService.to.player.videoFitArray;
      final pictureCover = pictureCoverFor(
        audioOnly: controller.audioOnlyState.value,
        dummyVideo: player.isDummyVideo.value,
        room: controller.room,
        onExitAudioOnly: _exitAudioOnly,
      );
      // Rebuild when the stream's picture size is known or changes.
      player.videoPresentationRevision.value;
      final fit = fitList.isEmpty ? BoxFit.contain : fitList[fitIndex.clamp(0, fitList.length - 1)];
      final pictureRatio = widget.boxToPicture && pictureCover == null && fit == BoxFit.contain
          ? player.currentPresentationAspectRatio
          : null;

      return PlaybackFailureOverlay(
        hasError: hasError,
        // Set when a reconnect finds the broadcast over (see
        // LivePlayController's reconnect ladder).
        offline: !controller.livePlayController.state.value.room.isLiving,
        onRetry: controller.refresh,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PictureBox(
              aspectRatio: pictureRatio,
              child: player.getVideoWidgetCompat(
                fitIndex,
                fitList: fitList,
                trackPipSource: true,
                pictureCover: pictureCover,
                surfaceColor: widget.surfaceColor,
                videoViewportAspectRatio: widget.videoViewportAspectRatio,
                portraitFullscreenDisplayMode: widget.portraitFullscreenDisplayMode,
              ),
            ),
            _withAudioOnlyForeground(VideoControllerPanel(controller: controller)),
          ],
        ),
      );
    });
  }

  /// The 纯音频 badge brings the picture back, as the ⋯ menu's switch does.
  void _exitAudioOnly() {
    if (controller.isAudioOnly) unawaited(controller.toggleAudioOnly());
  }

  /// The controls, with the 纯音频 information over them so its badge can
  /// be tapped; the rest of it lets the controls' gestures through.
  Widget _withAudioOnlyForeground(Widget controls) {
    final foreground = audioOnlyForegroundFor(
      audioOnly: controller.audioOnlyState.value,
      room: controller.room,
      onExit: _exitAudioOnly,
    );
    if (foreground == null) return controls;
    return Stack(fit: StackFit.expand, children: [controls, foreground]);
  }

  @override
  Widget build(BuildContext context) {
    return _buildVideo();
  }
}

/// Centres [child] at the largest size of [aspectRatio] that fits, or lets it
/// fill the area when [aspectRatio] is null. The widget tree is the same
/// either way, so switching never remounts the video.
class _PictureBox extends StatelessWidget {
  const _PictureBox({required this.aspectRatio, required this.child});

  final double? aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double? width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        double? height = constraints.hasBoundedHeight ? constraints.maxHeight : null;
        final ratio = aspectRatio;
        if (ratio != null && ratio > 0 && width != null && height != null && width > 0 && height > 0) {
          if (width / height > ratio) {
            width = height * ratio;
          } else {
            height = width / ratio;
          }
        }
        return Center(
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }
}
