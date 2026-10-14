import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';

void main() {
  group('退出全屏恢复方向', () {
    Future<List<String>> run(
      FullscreenOrientationRestoreState state, {
      required bool autoRotate,
      void Function()? duringSettle,
    }) async {
      final calls = <String>[];
      await exitFullscreenWithOrientationRestore(
        state: state,
        exitFullscreen: () async => calls.add('exit'),
        restorePortrait: () async {
          calls.add('portrait');
          duringSettle?.call();
        },
        releaseOrientation: () async => calls.add('release'),
        isAutoRotateOn: () async => autoRotate,
        portraitSettleDelay: const Duration(milliseconds: 1),
        lockedSettleDelay: const Duration(milliseconds: 30),
      );
      return calls;
    }

    test('自动旋转开着：竖直后很快放开', () async {
      final state = FullscreenOrientationRestoreState()..begin(restorePortraitOnExit: true);
      final clock = Stopwatch()..start();
      expect(await run(state, autoRotate: true), ['exit', 'portrait', 'release']);
      expect(clock.elapsedMilliseconds, lessThan(30));
    });

    test('自动旋转关着：竖直保持一段时间再放开', () async {
      final state = FullscreenOrientationRestoreState()..begin(restorePortraitOnExit: true);
      final clock = Stopwatch()..start();
      expect(await run(state, autoRotate: false), ['exit', 'portrait', 'release']);
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(30));
    });

    test('等待期间又进了全屏：不再放开方向', () async {
      final state = FullscreenOrientationRestoreState()..begin(restorePortraitOnExit: true);
      final calls = await run(
        state,
        autoRotate: false,
        duringSettle: () => state.begin(restorePortraitOnExit: true),
      );
      expect(calls, ['exit', 'portrait']);
    });

    test('不需要恢复竖屏时只退出全屏', () async {
      final state = FullscreenOrientationRestoreState()..begin(restorePortraitOnExit: false);
      expect(await run(state, autoRotate: false), ['exit']);
    });
  });
}
