import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/utils/setting_value_format.dart';

void main() {
  test('lengths in px, whole numbers without a decimal', () {
    expect(formatPixels(14), '14 px');
    expect(formatPixels(16.0), '16 px');
    expect(formatPixels(1.5), '1.5 px');
  });

  test('multiples as ×, shares as %', () {
    expect(formatTimes(0.4), '0.40×');
    expect(formatTimes(1.8, digits: 1), '1.8×');
    expect(formatPercent(0.995), '100%');
    expect(formatPercent(0.15), '15%');
  });
}
