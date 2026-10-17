import 'package:flutter/material.dart';
import 'package:pure_live/core/platform/platform_utils.dart';

/// Width of the volume bar beside a player's mute button.
const double playerVolumeBarWidth = 84;

/// The thin horizontal volume readout that sits right of a player's mute
/// button, in the button's white.
///
/// A desktop sets the volume with it: a click jumps to the clicked level and a
/// held drag follows the pointer. On a phone or tablet it only shows the level;
/// the surface drags change the volume there, and the mute button beside it
/// still mutes.
///
/// It does not decide where it appears: each player bar shows it next to its
/// mute button under the bar's own rules.
class PlayerVolumeBar extends StatelessWidget {
  const PlayerVolumeBar({super.key, required this.value, required this.onChanged, this.onInteract});

  /// The current level, `0..1`.
  final double value;

  /// Applies a level the viewer picked (desktops only).
  final ValueChanged<double> onChanged;

  /// Called on any pointer contact, so a bar can keep its controls up.
  final VoidCallback? onInteract;

  static const double _trackHeight = 4;
  static const double _hitHeight = 24;

  bool get _interactive => !PlatformUtils.isMobile;

  void _pick(Offset local) {
    onInteract?.call();
    onChanged((local.dx / playerVolumeBarWidth).clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final level = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    final bar = SizedBox(
      width: playerVolumeBarWidth,
      height: _hitHeight,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_trackHeight / 2),
          child: SizedBox(
            width: playerVolumeBarWidth,
            height: _trackHeight,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.white30)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: level,
                  heightFactor: 1,
                  child: const ColoredBox(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final percent = (level * 100).round();
    if (!_interactive) {
      return Semantics(value: '$percent%', child: ExcludeSemantics(child: bar));
    }
    return Semantics(
      slider: true,
      value: '$percent%',
      increasedValue: '${((level + 0.05).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue: '${((level - 0.05).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: () => onChanged((level + 0.05).clamp(0.0, 1.0).toDouble()),
      onDecrease: () => onChanged((level - 0.05).clamp(0.0, 1.0).toDouble()),
      child: ExcludeSemantics(
        child: Tooltip(
          message: '$percent%',
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _pick(details.localPosition),
              onHorizontalDragStart: (details) => _pick(details.localPosition),
              onHorizontalDragUpdate: (details) => _pick(details.localPosition),
              child: bar,
            ),
          ),
        ),
      ),
    );
  }
}
