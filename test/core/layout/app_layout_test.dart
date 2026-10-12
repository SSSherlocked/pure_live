import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/layout/app_layout.dart';

void main() {
  test('automatic mode follows the width for layout and the device for interaction', () {
    final phone = AppLayout.resolve(mode: DisplayMode.auto, width: 400, mobilePlatform: true);
    expect(phone.wide, isFalse);
    expect(phone.touch, isTrue);

    final tablet = AppLayout.resolve(mode: DisplayMode.auto, width: 900, mobilePlatform: true);
    expect(tablet.wide, isTrue);
    expect(tablet.touch, isTrue);
    expect(tablet.pagedLists, isFalse);

    final desktop = AppLayout.resolve(mode: DisplayMode.auto, width: 1280, mobilePlatform: false);
    expect(desktop.pagedLists, isTrue);

    final narrowWindow = AppLayout.resolve(mode: DisplayMode.auto, width: 500, mobilePlatform: false);
    expect(narrowWindow.wide, isFalse);
    expect(narrowWindow.pointer, isTrue);
  });

  test('a chosen mode overrides both, whatever the screen', () {
    expect(
      AppLayout.resolve(mode: DisplayMode.phone, width: 1920, mobilePlatform: false),
      const AppLayout(wide: false, pointer: false),
    );
    expect(
      AppLayout.resolve(mode: DisplayMode.tablet, width: 360, mobilePlatform: true),
      const AppLayout(wide: true, pointer: false),
    );
    expect(
      AppLayout.resolve(mode: DisplayMode.desktop, width: 360, mobilePlatform: true),
      const AppLayout(wide: true, pointer: true),
    );
  });

  test('an unknown stored value reads as automatic', () {
    expect(DisplayMode.parse('desktop'), DisplayMode.desktop);
    expect(DisplayMode.parse('laptop'), DisplayMode.auto);
    expect(DisplayMode.parse(null), DisplayMode.auto);
  });
}
