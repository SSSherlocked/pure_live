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
  const VideoPlayer({
    super.key,
    required this.controller,
    this.surfaceColor = Colors.black,
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

      return PlaybackFailureOverlay(
        hasError: hasError,
        // Set when a reconnect finds the broadcast over (see
        // LivePlayController's reconnect ladder).
        offline: !controller.livePlayController.state.value.room.isLiving,
        onRetry: controller.refresh,
        child: player.getVideoWidgetCompat(
          SettingsService.to.player.videoFitIndex.v,
          fitList: SettingsService.to.player.videoFitArray,
          trackPipSource: true,
          pictureCover: pictureCoverFor(
            audioOnly: controller.audioOnlyState.value,
            dummyVideo: player.isDummyVideo.value,
            room: controller.room,
            onExitAudioOnly: _exitAudioOnly,
          ),
          controls: _withAudioOnlyForeground(VideoControllerPanel(controller: controller)),
          surfaceColor: widget.surfaceColor,
          videoViewportAspectRatio: widget.videoViewportAspectRatio,
          portraitFullscreenDisplayMode: widget.portraitFullscreenDisplayMode,
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
