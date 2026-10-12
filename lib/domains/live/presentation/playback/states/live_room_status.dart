import 'package:flutter/widgets.dart';
import 'package:pure_live/core/utils/i18n.dart';
import 'package:pure_live/core/utils/live_quality_label.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

/// What the room is playing right now, read in one place.
///
/// The quality chip, the quality row and 视频详情 used to assemble this each
/// from the room state, the player and the danmaku session on their own.
/// Reading it here keeps their labels identical. Built from observable room
/// state, so an `Obx` reading it rebuilds when quality or line change.
@immutable
class LiveRoomStatus {
  const LiveRoomStatus({
    required this.hasStream,
    required this.qualityLabel,
    required this.lineIndex,
    required this.lineCount,
    required this.engine,
    required this.streamHost,
    required this.danmakuConnected,
  });

  factory LiveRoomStatus.of(LivePlayController controller) {
    final player = controller.state.value.player;
    final snapshot = GlobalPlayerService.instance.player.handle?.combinedSnapshot;
    return LiveRoomStatus(
      hasStream: player.qualites.isNotEmpty && player.hasPlaybackSource,
      qualityLabel: player.qualites.isEmpty ? '—' : player.qualitySafe.playbackLabel,
      lineIndex: player.currentLineIndex,
      lineCount: player.lineCount,
      engine: snapshot?.backendId ?? '—',
      // The host only: the full address carries access tokens.
      streamHost: snapshot?.source?.uri.host ?? '',
      danmakuConnected: controller.danmakuController.isSessionConnected,
    );
  }

  final bool hasStream;
  final String qualityLabel;
  final int lineIndex;
  final int lineCount;
  final String engine;
  final String streamHost;
  final bool danmakuConnected;

  String get lineLabel => i18n('toolbox_line', args: {'index': '${lineIndex + 1}'});

  /// "原画 · 线路1", the quality chip's label.
  String get qualityAndLine => '$qualityLabel · $lineLabel';
}
