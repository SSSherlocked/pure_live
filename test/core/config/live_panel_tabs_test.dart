import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';

void main() {
  test('hidden sections leave the panel, the order of the rest is kept', () {
    final order = LivePanelTab.decode('follow,danmaku_list,super_chat,danmaku_settings');
    final hidden = LivePanelTab.decodeSet('super_chat,danmaku_settings');
    expect(LivePanelTab.visible(order, hidden), [LivePanelTab.follow, LivePanelTab.danmakuList]);
  });

  test('the panel always keeps one section', () {
    final hidden = LivePanelTab.values.toSet();
    expect(LivePanelTab.visible(LivePanelTab.defaultOrder, hidden), [LivePanelTab.danmakuList]);
  });

  test('unknown ids are ignored', () {
    expect(LivePanelTab.decodeSet('nope, follow ,'), {LivePanelTab.follow});
  });
}
