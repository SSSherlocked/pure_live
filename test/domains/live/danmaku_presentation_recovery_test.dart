import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/danmaku_presentation_recovery.dart';

void main() {
  test('a blocked recovery is retried and runs once the transition finishes', () async {
    var blocked = true;
    var recovered = 0;
    final recovery = DanmakuPresentationRecovery(
      isBlocked: () => blocked,
      canRecover: () => true,
      recover: () async {
        recovered++;
      },
      settleDelay: Duration.zero,
      retryDelay: const Duration(milliseconds: 1),
    );
    recovery.request();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recovered, 0);
    blocked = false;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recovered, 1);
    recovery.dispose();
  });

  test('a recovery that stays blocked gives up after its attempt budget', () async {
    var blocked = true;
    var attempts = 0;
    var recovered = 0;
    final recovery = DanmakuPresentationRecovery(
      isBlocked: () {
        attempts++;
        return blocked;
      },
      canRecover: () => true,
      recover: () async {
        recovered++;
      },
      settleDelay: Duration.zero,
      retryDelay: const Duration(milliseconds: 1),
      maxBlockedAttempts: 3,
    );
    recovery.request();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 3);
    expect(recovered, 0);

    // The given-up request is not replayed once the block lifts...
    blocked = false;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recovered, 0);

    // ...but a new request starts with a fresh budget.
    recovery.request();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recovered, 1);
    recovery.dispose();
  });
}
