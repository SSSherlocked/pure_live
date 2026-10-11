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

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  /// Takes audio focus and starts following interruptions.
  Future<void> attach() async {
    if (!_supported || _attached) return;
    _attached = true;
    try {
      final session = await AudioSession.instance;
      _session = session;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
      _interruptions = session.interruptionEventStream.listen(_onInterruption);
      _noisy = session.becomingNoisyEventStream.listen((_) {
        _pausedByInterruption = false;
        final player = GlobalPlayerService.instance.player;
        if (player.isPlayingNow) unawaited(player.pause());
      });
    } catch (_) {
      // Audio focus is a courtesy; playback must not depend on it.
      _attached = false;
    }
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
    _pausedByInterruption = false;
    await _interruptions?.cancel();
    await _noisy?.cancel();
    _interruptions = null;
    _noisy = null;
    try {
      await _session?.setActive(false);
    } catch (_) {}
  }
}
