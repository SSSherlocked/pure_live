import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/theme/app_text.dart';

void main() {
  test('every role is one pixel larger', () {
    const theme = TextTheme(
      titleMedium: TextStyle(fontSize: 15),
      bodyLarge: TextStyle(fontSize: 14),
      bodySmall: TextStyle(fontSize: 12),
      labelSmall: TextStyle(fontSize: 11),
    );
    final larger = largerTextTheme(theme);
    expect(larger.titleMedium?.fontSize, 16);
    expect(larger.bodyLarge?.fontSize, 15);
    expect(larger.bodySmall?.fontSize, 13);
    expect(larger.labelSmall?.fontSize, 12);
    expect(larger.titleLarge, isNull);
  });

  testWidgets('nested LargerText grows once', (tester) async {
    double? size;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(textTheme: const TextTheme(titleMedium: TextStyle(fontSize: 15))),
        home: LargerText(
          child: LargerText(
            child: Builder(
              builder: (context) {
                size = AppText.of(context).sectionTitle.fontSize;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(size, 16);
  });
}
