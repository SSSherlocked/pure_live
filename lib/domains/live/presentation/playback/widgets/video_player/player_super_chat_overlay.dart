import 'dart:async';
import 'dart:math' as math;

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/super_chat_card.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';

/// How long a super chat stays on the picture: as in Simple Live, 15 seconds
/// from when it reaches the room, or less if the super chat itself ends first.
/// The 留言 tab keeps listing it until its own end time.
const Duration playerSuperChatDisplayDuration = Duration(seconds: 15);

/// When a super chat that reached the room at [arrivedAt] leaves the picture.
@visibleForTesting
DateTime playerSuperChatHideAt(LiveSuperChatMessage message, DateTime arrivedAt) {
  final windowEnd = arrivedAt.add(playerSuperChatDisplayDuration);
  return message.endTime.isBefore(windowEnd) ? message.endTime : windowEnd;
}

/// The super chats to draw at [now]: those still inside their window, the one
/// leaving soonest on top (Simple Live's order), and at most [maxVisible] of
/// them — the latest arrivals, so a newly paid message is never the one held
/// back.
@visibleForTesting
List<LiveSuperChatMessage> visiblePlayerSuperChats(
  Map<LiveSuperChatMessage, DateTime> hideAt,
  DateTime now, {
  required int maxVisible,
}) {
  final live = hideAt.entries.where((entry) => entry.value.isAfter(now)).toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final skip = live.length > maxVisible ? live.length - maxVisible : 0;
  return [for (final entry in live.skip(skip)) entry.key];
}

/// 在播放器中显示留言: the room's super chats as small cards at the bottom
/// left of the picture.
///
/// Each one shows for [playerSuperChatDisplayDuration]; the overlay never takes
/// a pointer, so taps, drags and long presses still reach the picture. It is
/// independent of the room's 画面弹幕 switch and hidden in picture-in-picture.
class PlayerSuperChatOverlay extends StatefulWidget {
  const PlayerSuperChatOverlay({
    super.key,
    required this.controller,
    required this.padding,
    required this.compact,
  });

  final VideoController controller;

  /// Space kept clear around the cards: the safe area and the bottom bar.
  final EdgeInsets padding;

  /// The narrow inline player: narrower cards and at most two of them.
  final bool compact;

  @override
  State<PlayerSuperChatOverlay> createState() => _PlayerSuperChatOverlayState();
}

class _PlayerSuperChatOverlayState extends State<PlayerSuperChatOverlay> {
  /// Every super chat the room currently lists, with when it leaves the
  /// picture. One that has left stays here until the room drops it, so a later
  /// list update does not bring it back.
  final Map<LiveSuperChatMessage, DateTime> _hideAt = {};
  Worker? _worker;
  Timer? _ticker;

  RxList<LiveSuperChatMessage> get _superChats => widget.controller.livePlayController.superChats;

  @override
  void initState() {
    super.initState();
    _sync(_superChats);
    _worker = ever<List<LiveSuperChatMessage>>(_superChats, (list) {
      if (!mounted) return;
      setState(() => _sync(list));
    });
  }

  void _sync(List<LiveSuperChatMessage> list) {
    final now = DateTime.now();
    final current = list.toSet();
    _hideAt.removeWhere((message, _) => !current.contains(message));
    for (final message in list) {
      if (_hideAt.containsKey(message)) continue;
      _hideAt[message] = playerSuperChatHideAt(message, now);
    }
    _syncTicker(now);
  }

  /// One 1 s tick drives the countdowns and the removals, and only while
  /// something is on the picture.
  void _syncTicker(DateTime now) {
    final anyVisible = _hideAt.values.any((hideAt) => hideAt.isAfter(now));
    if (!anyVisible) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _syncTicker(DateTime.now()));
      });
    }
  }

  @override
  void dispose() {
    _worker?.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = widget.controller;
      final manager = GlobalPlayerService.instance.player;
      if (!settings.showSuperChatOnPlayer.value || manager.isInPip.value || manager.isPipPreparing.value) {
        return const SizedBox.shrink();
      }
      final opacity = DanmakuSettingsController.normalizeSuperChatOpacity(settings.superChatOpacity.value);
      final fontScale = DanmakuSettingsController.normalizeSuperChatFontScale(settings.superChatFontScale.value);
      final now = DateTime.now();
      final visible = visiblePlayerSuperChats(_hideAt, now, maxVisible: widget.compact ? 2 : 3);
      if (visible.isEmpty) return const SizedBox.shrink();
      return IgnorePointer(
        child: Padding(
          padding: widget.padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Simple Live's 240 px card, held to under half of a small picture.
              final width = math.min(widget.compact ? 200.0 : 240.0, constraints.maxWidth * 0.45);
              return Align(
                alignment: Alignment.bottomLeft,
                child: Opacity(
                  opacity: opacity,
                  child: CompactText(
                    child: SizedBox(
                      width: width,
                      // The oldest card gives way first when the picture is
                      // too short for all of them.
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.bottomLeft,
                          maxHeight: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final message in visible)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _PlayerSuperChatCard(
                                    key: ValueKey<LiveSuperChatMessage>(message),
                                    message: message,
                                    secondsLeft: (_hideAt[message]!.difference(now).inMilliseconds / 1000).ceil(),
                                    fontScale: fontScale,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

/// A compact [SuperChatCard]: the same two colour bands, avatar, name, price
/// and countdown, with the message held to two lines.
class _PlayerSuperChatCard extends StatelessWidget {
  const _PlayerSuperChatCard({
    super.key,
    required this.message,
    required this.secondsLeft,
    required this.fontScale,
  });

  final LiveSuperChatMessage message;
  final int secondsLeft;
  final double fontScale;

  TextStyle _scaled(TextStyle style) {
    final size = style.fontSize;
    return size == null ? style : style.copyWith(fontSize: size * fontScale);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final headerColor = superChatPlatformColor(message.backgroundColor, theme.colorScheme.primaryContainer);
    final messageColor = superChatPlatformColor(
      message.backgroundBottomColor,
      theme.colorScheme.surfaceContainerHighest,
    );
    final headerText = superChatContrastText(headerColor);
    final headerSubText = superChatSecondaryText(headerColor);
    final messageText = superChatContrastText(messageColor);
    final avatarSize = 24 * fontScale;
    final body = superChatDisplayText(message.message);

    // Smooth corners, as the 留言 list's cards.
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: headerColor,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
              child: Row(
                children: [
                  _avatar(avatarSize, headerText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _scaled(text.body).copyWith(color: headerText, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '￥${message.price}',
                    style: _scaled(text.body).copyWith(
                      color: headerText,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$secondsLeft',
                    style: _scaled(text.tag).copyWith(
                      color: headerSubText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (body.isNotEmpty)
            ColoredBox(
              color: messageColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
                child: Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _scaled(text.body).copyWith(color: messageText, height: 1.3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatar(double size, Color fallbackColor) {
    final uri = Uri.tryParse(message.face.trim());
    final hasRemoteAvatar = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    final fallback = ColoredBox(
      color: Colors.black.withValues(alpha: 0.10),
      child: Icon(Remix.user_2_fill, size: size * 0.6, color: fallbackColor),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: hasRemoteAvatar
            ? Image.network(
                message.face,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}
