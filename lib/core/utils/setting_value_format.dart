import 'package:pure_live/core/utils/i18n.dart';

/// How settings show their values, one form per kind of quantity:
/// lengths in `px`, multiples (of a text line, a font size, a scale) as `×`,
/// shares (opacity, area, volume) as `%`, and times in 秒 / 分钟 / 小时.

/// A length in logical pixels: whole numbers without a decimal.
String formatPixels(num value) {
  final v = value.toDouble();
  return v == v.roundToDouble() ? '${v.round()} px' : '${v.toStringAsFixed(1)} px';
}

/// A multiple, with [digits] decimals (the setting's step).
String formatTimes(num value, {int digits = 2}) => '${value.toDouble().toStringAsFixed(digits)}×';

/// A share of 0-1 as a whole percentage.
String formatPercent(num share) => '${(share * 100).round()}%';

String formatSeconds(num seconds) => i18n('value_seconds', args: {'n': '$seconds'});

String formatMinutes(num minutes) => i18n('value_minutes', args: {'n': _trim(minutes)});

String formatHours(num hours) => i18n('value_hours', args: {'n': _trim(hours)});

/// [seconds] in the largest unit it reaches (秒, 分钟 or 小时), with one
/// decimal when it is not whole.
String formatDurationSeconds(int seconds) {
  if (seconds < 60) return formatSeconds(seconds);
  if (seconds < 3600) return formatMinutes(seconds / 60);
  return formatHours(seconds / 3600);
}

String _trim(num value) {
  final v = value.toDouble();
  return v == v.truncateToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
}
