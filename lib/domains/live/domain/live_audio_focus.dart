import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

/// Audio focus for a live room on phones and tablets.
///
/// - A call (or another app taking audio for a while) pauses the room; when it
///   ends the room resumes, but only if this pause was ours and the user did
///   not start playback again in the meantime.
/// - Ducking requests (navigation prompts) are left to the system, which
///   lowers media volume by itself.
/// - Unplugging headphones pauses the room and does not resume it.
///
/// Modelled on wzgrx/pure_live G05.1.
class LiveAudioFocus {
  LiveAudioFocus._();

  static final LiveAudioFocus instance = LiveAudioFocus._();

  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;
  AudioSession? _session;
  bool _pausedByInterruption = false;
  bool _attached = false;

  /// Bumped by every attach and detach, so an attach still awaiting the session
  /// can tell that it was detached (or superseded) in the meantime.
  int _generation = 0;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  bool _stale(int generation) => generation != _generation || !_attached;

  /// Takes audio focus and starts following interruptions.
  Future<void> attach() async {
    if (!_supported || _attached) return;
    _attached = true;
    final generation = ++_generation;
    try {
      final session = await AudioSession.instance;
      if (_stale(generation)) return;
      _session = session;
      await session.configure(const AudioSessionConfiguration.music());
      if (_stale(generation)) return;
      await session.setActive(true);
      if (_stale(generation)) {
        // Detached while activating: nothing else will give the focus back.
        await _deactivate(session);
        return;
      }
      _interruptions = session.interruptionEventStream.listen(_onInterruption);
      _noisy = session.becomingNoisyEventStream.listen((_) {
        _pausedByInterruption = false;
        final player = GlobalPlayerService.instance.player;
        if (player.isPlayingNow) unawaited(player.pause());
      });
    } catch (_) {
      // Audio focus is a courtesy; playback must not depend on it.
      if (generation == _generation) _attached = false;
    }
  }

  Future<void> _deactivate(AudioSession session) async {
    try {
      await session.setActive(false);
    } catch (_) {}
  }

  void _onInterruption(AudioInterruptionEvent event) {
    final player = GlobalPlayerService.instance.player;
    if (event.begin) {
      if (event.type == AudioInterruptionType.duck) return;
      if (player.isPlayingNow) {
        _pausedByInterruption = true;
        unawaited(player.pause());
      }
      return;
    }
    final resume = _pausedByInterruption && event.type == AudioInterruptionType.pause;
    _pausedByInterruption = false;
    if (resume && !player.isPlayingNow) unawaited(player.resume());
  }

  /// Releases audio focus when the room closes.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    _generation++;
    _pausedByInterruption = false;
    await _interruptions?.cancel();
    await _noisy?.cancel();
    _interruptions = null;
    _noisy = null;
    final session = _session;
    if (session != null) await _deactivate(session);
  }
}
