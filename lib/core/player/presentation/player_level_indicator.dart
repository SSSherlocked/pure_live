import 'package:flutter/material.dart';
import 'package:pure_live/core/theme/app_text.dart';

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

  static const double _trackWidth = 4;
  static const double _maxTrackHeight = 140;
  static const double _edgeInset = 28;
  static const double _iconSize = 18;
  static const double _iconGap = 10;

  @override
  Widget build(BuildContext context) {
    final level = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    return IgnorePointer(
      child: Align(
        alignment: side == PlayerLevelSide.left ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _edgeInset),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A phone's inline picture is barely 200 px tall: the track
                // takes at most half of it so the number and the icon still fit.
                final available = constraints.maxHeight.isFinite ? constraints.maxHeight / 2 : _maxTrackHeight;
                final trackHeight = available.clamp(40.0, _maxTrackHeight).toDouble();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // No percent sign: the bar already says it is a share.
                    // Tabular figures keep the column from shifting as it counts.
                    Text(
                      '${(level * 100).round()}',
                      style: AppText.of(context).tag.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: _iconGap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(_trackWidth / 2),
                      child: SizedBox(
                        width: _trackWidth,
                        height: trackHeight,
                        child: Stack(
                          children: [
                            const Positioned.fill(child: ColoredBox(color: Colors.white30)),
                            FractionallySizedBox(
                              alignment: Alignment.bottomCenter,
                              widthFactor: 1,
                              heightFactor: level,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: _iconGap),
                    Icon(icon, size: _iconSize, color: Colors.white),
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

/// The volume icon for [value]: muted, low or high.
IconData playerVolumeIcon(double value) {
  if (value <= 0) return Icons.volume_off_rounded;
  return value < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded;
}
