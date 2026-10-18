import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/player/presentation/windows_pip_driver.dart';

void main() {
  group('windowGeometryTarget', () {
    test('a plain window is the size the next launch opens at', () {
      expect(
        windowGeometryTarget(compact: false, minimized: false, maximized: false, fullscreen: false),
        WindowGeometryTarget.normal,
      );
    });

    // Quitting from fullscreen used to leave the screen-sized frame as the
    // remembered size, and the next launch opened that large.
    test('a fullscreen window is never remembered', () {
      expect(
        windowGeometryTarget(compact: false, minimized: false, maximized: false, fullscreen: true),
        WindowGeometryTarget.none,
      );
    });

    test('a maximized or minimized window is never remembered', () {
      expect(
        windowGeometryTarget(compact: false, minimized: false, maximized: true, fullscreen: false),
        WindowGeometryTarget.none,
      );
      expect(
        windowGeometryTarget(compact: false, minimized: true, maximized: false, fullscreen: false),
        WindowGeometryTarget.none,
      );
    });

    test('the compact window goes to its own memory', () {
      expect(
        windowGeometryTarget(compact: true, minimized: false, maximized: false, fullscreen: false),
        WindowGeometryTarget.pip,
      );
    });
  });
}
