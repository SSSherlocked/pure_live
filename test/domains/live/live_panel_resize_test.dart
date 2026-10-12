import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/live_play_content.dart';

void main() {
  test('the panel width range leaves the video most of the window', () {
    expect(LivePanelWidth.resolve(LivePanelWidth.max, 2000), LivePanelWidth.max);
    expect(LivePanelWidth.resolve(LivePanelWidth.max, 1000), 600);
    expect(LivePanelWidth.resolve(100, 2000), LivePanelWidth.min);
    expect(LivePanelWidth.normalize(double.nan), LivePanelWidth.defaultValue);
  });

  testWidgets('dragging the panel edge resizes it and reports the width once', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reported = <double>[];
    var preferred = 300.0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLayoutScope(
          layout: const AppLayout(wide: true, pointer: true),
          child: StatefulBuilder(
            builder: (context, setState) => LivePlayNormalLayout(
              video: const SizedBox.expand(),
              resolution: const SizedBox(height: 40),
              danmaku: const SizedBox.expand(),
              panelWidth: preferred,
              onPanelResized: (width) => setState(() {
                reported.add(width);
                preferred = width;
              }),
            ),
          ),
        ),
      ),
    );

    double panelWidth() => tester.getSize(find.byKey(const ValueKey('live-play-desktop-panel'))).width;
    expect(panelWidth(), 300);

    final handle = find.byKey(const ValueKey('live-play-panel-resize-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
    }
    expect(reported, isEmpty, reason: 'nothing is written while dragging');
    await gesture.up();
    await tester.pump();

    expect(reported, hasLength(1));
    expect(reported.single, closeTo(400, 20));
    expect(panelWidth(), reported.single);
  });
}
