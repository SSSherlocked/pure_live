import 'package:flutter/widgets.dart';
import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/audio_only_presentation.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/dummy_video_cover.dart';

/// What covers the picture. With [onExitAudioOnly] the 纯音频 cover is only
/// its black backdrop: the caller draws [audioOnlyForegroundFor] over its
/// controls, whose badge calls it.
Widget? pictureCoverFor({
  required bool audioOnly,
  required bool dummyVideo,
  required LiveRoom? room,
  VoidCallback? onExitAudioOnly,
}) {
  if (room == null) return null;
  if (audioOnly) {
    return onExitAudioOnly == null ? AudioOnlyPresentation(room: room) : AudioOnlyPresentation.backdrop(room: room);
  }
  if (dummyVideo) return DummyVideoCover(room: room);
  return null;
}

/// The 纯音频 information drawn over the player controls, or null when not
/// in 纯音频.
Widget? audioOnlyForegroundFor({required bool audioOnly, required LiveRoom? room, required VoidCallback onExit}) {
  if (!audioOnly || room == null) return null;
  return AudioOnlyPresentation.foreground(room: room, onExit: onExit);
}
