import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_auto_refresh.dart';

void main() {
  group('followed rooms auto refresh interval', () {
    test('off when neither setting is on', () {
      expect(favoriteAutoRefreshInterval(homeEnabled: false, homeMinutes: 30, roomPanelMinutes: 0), isNull);
    });

    test('the home setting alone', () {
      expect(
        favoriteAutoRefreshInterval(homeEnabled: true, homeMinutes: 30, roomPanelMinutes: 0),
        const Duration(minutes: 30),
      );
    });

    test('the room 关注 interval alone, with the home switch off', () {
      expect(
        favoriteAutoRefreshInterval(homeEnabled: false, homeMinutes: 30, roomPanelMinutes: 3),
        const Duration(minutes: 3),
      );
    });

    test('both on: the shorter one', () {
      expect(
        favoriteAutoRefreshInterval(homeEnabled: true, homeMinutes: 5, roomPanelMinutes: 10),
        const Duration(minutes: 5),
      );
      expect(
        favoriteAutoRefreshInterval(homeEnabled: true, homeMinutes: 30, roomPanelMinutes: 10),
        const Duration(minutes: 10),
      );
    });
  });

  group('followed rooms auto refresh delay', () {
    final now = DateTime(2026, 10, 22, 12);
    const interval = Duration(minutes: 10);

    test('before the first full refresh, a whole interval', () {
      expect(favoriteAutoRefreshDelay(interval: interval, lastRefreshAt: null, now: now), interval);
    });

    test('counts from the last full refresh', () {
      final last = now.subtract(const Duration(minutes: 4));
      expect(favoriteAutoRefreshDelay(interval: interval, lastRefreshAt: last, now: now), const Duration(minutes: 6));
    });

    test('due at once when the interval has passed, e.g. after it was shortened', () {
      final last = now.subtract(const Duration(minutes: 4));
      expect(
        favoriteAutoRefreshDelay(interval: const Duration(minutes: 3), lastRefreshAt: last, now: now),
        Duration.zero,
      );
    });
  });
}
