import 'package:flutter/material.dart';
import 'package:pure_live/core/theme/app_text.dart';
import 'package:pure_live/core/platform/platform_utils.dart';

/// Which edge of the picture a level indicator stands at.
enum PlayerLevelSide { left, right }

/// The readout of a level being changed on the picture: the level as a bare
/// number on top, a thin vertical white track filled from the bottom, and its
/// icon below. Brightness stands at the left edge and volume at the right,
/// matching the halves a drag changes them on; it fades in only while the
/// level changes.
///
/// It draws in the same white as the volume bar beside the mute button and
/// takes no input.
class PlayerLevelIndicator extends StatelessWidget {
  const PlayerLevelIndicator({
    super.key,
    required this.side,
    required this.visible,
    required this.value,
    required this.icon,
  });

  final PlayerLevelSide side;
  final bool visible;

  /// The level, `0..1`.
  final double value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final level = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    // An upright phone's picture is narrow: the bars hug its edges there.
    final m = !PlatformUtils.isMobile
        ? _LevelMetrics.desktop
        : MediaQuery.orientationOf(context) == Orientation.portrait
        ? _LevelMetrics.touchPortrait
        : _LevelMetrics.touch;
    final text = AppText.of(context);
    final numberStyle = PlatformUtils.isMobile ? text.tag : text.secondary;
    return IgnorePointer(
      child: Align(
        alignment: side == PlayerLevelSide.left ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: m.edgeInset),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A phone's inline picture is barely 200 px tall: the track
                // takes at most half of it so the number and the icon still fit.
                final available = constraints.maxHeight.isFinite ? constraints.maxHeight / 2 : m.maxTrackHeight;
                final trackHeight = available.clamp(40.0, m.maxTrackHeight).toDouble();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // No percent sign: the bar already says it is a share.
                    // Tabular figures keep the column from shifting as it counts.
                    SizedBox(
                      width: m.columnWidth,
                      child: Text(
                        '${(level * 100).round()}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: numberStyle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    SizedBox(height: m.gap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(m.trackWidth / 2),
                      child: SizedBox(
                        width: m.trackWidth,
                        height: trackHeight,
                        child: Stack(
                          children: [
                            const Positioned.fill(child: ColoredBox(color: Colors.white30)),
                            // Pinned to the bottom edge: a bare FractionallySizedBox
                            // in a Stack shrinks to its child and sits at the top,
                            // which drew the level growing downward.
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: trackHeight * level,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: m.gap),
                    Icon(icon, size: m.iconSize, color: Colors.white),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Sizes of [PlayerLevelIndicator]: a desktop's picture is read from further
/// away than a phone's, so its readout is a step larger.
class _LevelMetrics {
  const _LevelMetrics({
    required this.trackWidth,
    required this.maxTrackHeight,
    required this.edgeInset,
    required this.columnWidth,
    required this.iconSize,
    required this.gap,
  });

  static const touch = _LevelMetrics(
    trackWidth: 4,
    maxTrackHeight: 140,
    edgeInset: 40,
    columnWidth: 32,
    iconSize: 18,
    gap: 10,
  );

  // The track's centre 38 px from the edge, where the first version (28 px
  // inset, no fixed column) put it on a phone's inline picture.
  static const touchPortrait = _LevelMetrics(
    trackWidth: 4,
    maxTrackHeight: 140,
    edgeInset: 22,
    columnWidth: 32,
    iconSize: 18,
    gap: 10,
  );

  static const desktop = _LevelMetrics(
    trackWidth: 5,
    maxTrackHeight: 180,
    edgeInset: 48,
    columnWidth: 40,
    iconSize: 22,
    gap: 12,
  );

  final double trackWidth;
  final double maxTrackHeight;

  /// From the picture's edge to the readout column.
  final double edgeInset;

  /// Wide enough for "100": the column keeps one width, so the track does not
  /// move when the number gains or loses a digit.
  final double columnWidth;
  final double iconSize;

  /// Between the number, the track and the icon.
  final double gap;
}

/// The volume icon for [value]: muted, low or high.
IconData playerVolumeIcon(double value) {
  if (value <= 0) return Icons.volume_off_rounded;
  return value < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded;
}
