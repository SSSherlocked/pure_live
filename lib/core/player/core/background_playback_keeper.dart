import 'dart:async';

import 'package:flutter/foundation.dart';

// Background play robustness, ported from wzgrx/pure_live O01.3 and C01.5.
//
// Away from the app a room keeps the media notification's foreground service
// (and the CPU/Wi-Fi locks) while it plays, reconnects after a stream drop,
// waits for an offline streamer or for a call. Android 12 and later refuse to
// start that service again from the background, so it must not drop in
// between. A room that was not playing when the app left does not start by
// itself there; it waits for the user to come back.

/// Why a room away from the app keeps its foreground service.
enum BackgroundHold {
  /// Nothing to keep: in front of the app, paused by the user, given up, or
  /// not playing when the app left.
  none,

  /// Opening, buffering or playing.
  playing,

  /// The stream failed and the room is reconnecting.
  recovering,

  /// The broadcast stopped (offline) or the player sits between two opens;
  /// the room may start again by itself.
  waiting,

  /// A call or another app took the sound and will give it back.
  interrupted,
}

/// What the player is doing, as far as the keeper cares.
enum BackgroundPlayerPhase {
  /// Producing sound and picture.
  playing,

  /// Opening or buffering: may still fail.
  starting,

  /// Paused (by a call, a reconnect, or the user).
  paused,

  /// Failed (every line tried).
  failed,

  /// Idle, stopped or ended.
  idle,
}

/// The room's state as the keeper reads it.
@immutable
class BackgroundKeeperInput {
  const BackgroundKeeperInput({
    required this.away,
    required this.phase,
    this.reconnecting = false,
    this.roomOffline = false,
    this.interrupted = false,
  });

  /// The app is out of sight (not picture-in-picture) and the room may play
  /// there (background play on, or a sleep session).
  final bool away;

  final BackgroundPlayerPhase phase;

  /// The room's reconnect ladder is running.
  final bool reconnecting;

  /// The room is not broadcasting.
  final bool roomOffline;

  /// The audio focus paused the room and resumes it when the interruption
  /// ends.
  final bool interrupted;

  bool get active => phase == BackgroundPlayerPhase.playing || phase == BackgroundPlayerPhase.starting;

  @override
  bool operator ==(Object other) =>
      other is BackgroundKeeperInput &&
      other.away == away &&
      other.phase == phase &&
      other.reconnecting == reconnecting &&
      other.roomOffline == roomOffline &&
      other.interrupted == interrupted;

  @override
  int get hashCode => Object.hash(away, phase, reconnecting, roomOffline, interrupted);

  @override
  String toString() =>
      'BackgroundKeeperInput(away: $away, phase: ${phase.name}, reconnecting: $reconnecting, '
      'roomOffline: $roomOffline, interrupted: $interrupted)';
}

/// Schedules [callback] after [delay] (tests pass a fake).
typedef KeeperTimerFactory = Timer Function(Duration delay, void Function() callback);

/// Decides what a room away from the app keeps ([hold]) and whether it may
/// start playing by itself ([mayStartPlayback]):
///
/// - playing, opening or buffering: kept;
/// - reconnecting or failed: kept for at most [recoverBudget];
/// - offline, or between two opens: kept for at most [waitBudget];
/// - paused by a call: kept for at most [recoverBudget];
/// - paused by the user ([markUserPause]): nothing kept until it plays again.
///
/// Only a room that was playing when the app left (or played since) is kept
/// (C01.5). When a budget runs out the keeper gives up: nothing is kept and
/// the room no longer starts by itself until the app comes back.
/// [onChanged] runs when a budget timer changed [hold] without an [update].
class BackgroundPlaybackKeeper {
  BackgroundPlaybackKeeper({
    this.onChanged,
    DateTime Function()? now,
    KeeperTimerFactory? timer,
    this.recoverBudget = const Duration(minutes: 30),
    this.waitBudget = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now,
       _timer = timer ?? Timer.new;

  final void Function()? onChanged;

  /// How long a reconnect or a call keeps the service.
  final Duration recoverBudget;

  /// How long an offline broadcast keeps the service.
  final Duration waitBudget;

  final DateTime Function() _now;
  final KeeperTimerFactory _timer;

  BackgroundKeeperInput? _input;
  BackgroundHold _hold = BackgroundHold.none;
  bool _played = false;
  bool _userPaused = false;
  bool _gaveUp = false;
  DateTime? _troubleSince;
  Timer? _budgetTimer;
  bool _disposed = false;

  /// What is kept now.
  BackgroundHold get hold => _hold;

  /// Whether the room may (re)start playback by itself: always in front of
  /// the app; away from it only while something is kept, so a room that was
  /// not playing when the app left, or that was given up, waits for the
  /// user.
  bool get mayStartPlayback {
    final input = _input;
    if (_disposed || input == null || !input.away) return true;
    return _hold != BackgroundHold.none;
  }

  /// Takes the room's state; returns [hold].
  BackgroundHold update(BackgroundKeeperInput input) {
    if (_disposed) return _hold = BackgroundHold.none;
    final previous = _input;
    _input = input;
    if (!input.away) {
      _reset();
      return _hold = BackgroundHold.none;
    }
    if (previous == null || !previous.away) {
      // The app just left: only what plays now may be kept.
      _played = input.active;
      _userPaused = false;
      _gaveUp = false;
      _troubleSince = null;
    }
    return _hold = _decide(input);
  }

  BackgroundHold _decide(BackgroundKeeperInput input) {
    if (input.active) {
      _played = true;
      _userPaused = false;
      _gaveUp = false;
      _cancelBudget();
      // Opening may still fail: the budget starts again only once it plays.
      if (input.phase == BackgroundPlayerPhase.playing) _troubleSince = null;
      return BackgroundHold.playing;
    }
    if (!_played || _userPaused || _gaveUp) {
      _cancelBudget();
      return BackgroundHold.none;
    }
    final BackgroundHold trouble;
    final Duration budget;
    if (input.phase == BackgroundPlayerPhase.paused && input.interrupted) {
      trouble = BackgroundHold.interrupted;
      budget = recoverBudget;
    } else if (input.roomOffline) {
      trouble = BackgroundHold.waiting;
      budget = waitBudget;
    } else if (input.reconnecting || input.phase == BackgroundPlayerPhase.failed) {
      trouble = BackgroundHold.recovering;
      budget = recoverBudget;
    } else {
      // Idle, stopped, or paused for no reason the room knows (a refresh
      // between two opens pauses the old player first).
      trouble = BackgroundHold.waiting;
      budget = waitBudget;
    }
    final since = _troubleSince ??= _now();
    final left = budget - _now().difference(since);
    if (left <= Duration.zero) {
      _gaveUp = true;
      _cancelBudget();
      return BackgroundHold.none;
    }
    _budgetTimer?.cancel();
    _budgetTimer = _timer(left, _onBudget);
    return trouble;
  }

  void _onBudget() {
    _budgetTimer = null;
    final input = _input;
    if (_disposed || input == null || !input.away || input.active) return;
    final before = _hold;
    _hold = _decide(input);
    if (_hold != before) onChanged?.call();
  }

  /// The user paused or stopped (notification, lock screen, headset, a
  /// timer): nothing is kept or started until the room plays again.
  void markUserPause() {
    if (_disposed) return;
    _userPaused = true;
    _cancelBudget();
    final input = _input;
    if (input != null && !input.active) _hold = BackgroundHold.none;
  }

  void _cancelBudget() {
    _budgetTimer?.cancel();
    _budgetTimer = null;
  }

  void _reset() {
    _cancelBudget();
    _played = false;
    _userPaused = false;
    _gaveUp = false;
    _troubleSince = null;
  }

  /// Stops the budget timer; [hold] stays [BackgroundHold.none].
  void dispose() {
    _disposed = true;
    _reset();
    _hold = BackgroundHold.none;
  }
}

/// When the room's reconnect ladder tries again: after [delays] (the last
/// one repeats), for at most [window] since the first failure.
@immutable
class ReconnectSchedule {
  const ReconnectSchedule({
    this.delays = const [
      Duration(seconds: 2),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
      Duration(seconds: 60),
    ],
    this.window = const Duration(minutes: 30),
  });

  /// The pauses before each attempt. wzgrx/pure_live starts at 5 s; the
  /// first step here is 2 s so a short drop in front of the app recovers
  /// sooner (commit aa81fb054).
  final List<Duration> delays;

  /// How long the ladder keeps trying.
  final Duration window;

  /// The pause before attempt number [attempt] (0-based).
  Duration delayBefore(int attempt) {
    if (attempt <= 0) return delays.first;
    return attempt < delays.length ? delays[attempt] : delays.last;
  }

  /// Whether the ladder has run out of time [elapsed] after the first failure.
  bool isExhausted(Duration elapsed) => elapsed > window;
}
