import 'package:flutter/material.dart';

/// A slider that only changes when its thumb is dragged.
///
/// Tapping or brushing the track does nothing, so a finger passing over the
/// player panels cannot jump a setting to a new value.
class ThumbOnlySlider extends StatelessWidget {
  const ThumbOnlySlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.stepSize,
    this.activeColor,
    this.inactiveColor,
    this.semanticFormatterCallback,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final double? stepSize;
  final Color? activeColor;
  final Color? inactiveColor;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  Widget build(BuildContext context) {
    final step = stepSize;
    final divisions = step != null && step > 0 ? ((max - min) / step).round() : null;
    return Slider(
      value: value.clamp(min, max).toDouble(),
      min: min,
      max: max,
      divisions: divisions != null && divisions > 0 ? divisions : null,
      allowedInteraction: SliderInteraction.slideThumb,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      semanticFormatterCallback: semanticFormatterCallback,
      onChanged: onChanged,
    );
  }
}
