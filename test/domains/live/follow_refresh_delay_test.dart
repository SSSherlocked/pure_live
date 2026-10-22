import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/play_other.dart';

void main() {
  group('room 关注 list auto refresh delay', () {
    final now = DateTime(2026, 10, 22, 12);

    test('an interval of zero turns it off', () {
      expect(followRefreshDelay(minutes: 0, lastRefreshAt: null, now: now), isNull);
      expect(followRefreshDelay(minutes: 0, lastRefreshAt: now, now: now), isNull);
    });

    test('with no refresh yet the list refreshes at once', () {
      expect(followRefreshDelay(minutes: 5, lastRefreshAt: null, now: now), Duration.zero);
    });

    test('the interval counts from the last refresh, not from when the list is shown', () {
      final lastRefreshAt = now.subtract(const Duration(minutes: 3));

      expect(followRefreshDelay(minutes: 5, lastRefreshAt: lastRefreshAt, now: now), const Duration(minutes: 2));
    });

    test('a list shown after the interval has passed refreshes at once', () {
      final lastRefreshAt = now.subtract(const Duration(minutes: 12));

      expect(followRefreshDelay(minutes: 10, lastRefreshAt: lastRefreshAt, now: now), Duration.zero);
    });

    test('a shorter interval takes effect from the same last refresh', () {
      final lastRefreshAt = now.subtract(const Duration(minutes: 4));

      expect(followRefreshDelay(minutes: 30, lastRefreshAt: lastRefreshAt, now: now), const Duration(minutes: 26));
      expect(followRefreshDelay(minutes: 3, lastRefreshAt: lastRefreshAt, now: now), Duration.zero);
    });
  });
}
