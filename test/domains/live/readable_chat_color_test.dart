import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/danmaku_list_view.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const white = Colors.white;
  final yellow = HSLColor.fromColor(const Color(0xFFFFFF00)).withLightness(0.52).toColor();

  test('a light colour is darkened to 3:1 on a light panel', () {
    final readable = readableChatColor(yellow, background: white, isDark: false);
    expect(_contrast(readable, white), greaterThanOrEqualTo(3.0));
    expect(HSLColor.fromColor(readable).hue, closeTo(HSLColor.fromColor(yellow).hue, 1));
  });

  test('a colour that already contrasts stays as it is', () {
    const blue = Color(0xFF1565C0);
    expect(readableChatColor(blue, background: white, isDark: false), blue);
  });

  test('the dark theme is left alone', () {
    expect(readableChatColor(yellow, background: Colors.black, isDark: true), yellow);
  });
}
