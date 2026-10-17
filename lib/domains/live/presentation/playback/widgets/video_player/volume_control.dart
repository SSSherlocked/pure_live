import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pure_live/core/utils/i18n.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/config/settings_service.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';

/// The room's mute toggle; it follows the room's volume as the wheel, the
/// keyboard, gestures and the global mute change it.
class RoomMuteButton extends StatefulWidget {
  final VideoController controller;
  const RoomMuteButton({super.key, required this.controller});

  @override
  State<RoomMuteButton> createState() => _RoomMuteButtonState();
}

class _RoomMuteButtonState extends State<RoomMuteButton> {
  double _volume = 0.5;
  double _lastVolume = 0.5;
  StreamSubscription? _volumeListener;
  StreamSubscription? _platformVolWorker;
  int _controllerGeneration = 0;
  int _valueRevision = 0;
  StreamSubscription? _controllerVolumeSub;

  VideoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _listenGlobalVolume();
    _bindController();
  }

  @override
  void didUpdateWidget(covariant RoomMuteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, controller)) return;
    _bindController();
  }

  @override
  void dispose() {
    _controllerGeneration++;
    _valueRevision++;
    _volumeListener?.cancel();
    _platformVolWorker?.cancel();
    _controllerVolumeSub?.cancel();
    super.dispose();
  }

  void _listenGlobalVolume() {
    final v = SettingsService.to.vol;
    _volumeListener = v.globalVolumeMute.stream.listen((_) => _updateVolumeFromGlobal());
    _platformVolWorker = v.defaultDesktopVolume.stream.listen((_) => _updateVolumeFromGlobal());
  }

  bool _owns(VideoController owner, int generation) =>
      mounted && generation == _controllerGeneration && identical(controller, owner);

  void _bindController() {
    _controllerVolumeSub?.cancel();
    final owner = controller;
    final generation = ++_controllerGeneration;
    _valueRevision++;
    final initial = owner.currentVolume.value;
    _volume = initial.isFinite ? initial.clamp(0.0, 1.0) : 0.5;
    _lastVolume = _volume > 0 ? _volume : 0.5;
    _controllerVolumeSub = owner.currentVolume.stream.listen((value) {
      if (!_owns(owner, generation) || !value.isFinite) return;
      // Even an equal-valued event supersedes a pending initial query.
      _valueRevision++;
      _displayVolume(value);
    });
    unawaited(initVolume(owner, generation));
  }

  void _displayVolume(double value) {
    final resolved = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _volume = resolved;
      if (resolved > 0) _lastVolume = resolved;
    });
  }

  void _updateVolumeFromGlobal() {
    if (!mounted) return;
    final v = SettingsService.to.vol;
    final platformVolume = v.currentPlatformDefaultVolume;
    _valueRevision++;
    setState(() {
      if (v.globalVolumeMute.v) {
        if (_volume > 0) _lastVolume = _volume;
        _volume = 0.0;
      } else {
        _volume = platformVolume;
        _lastVolume = _volume;
      }
    });

    unawaited(controller.setVolume(_volume));
  }

  Future<void> initVolume(VideoController owner, int generation) async {
    final revision = _valueRevision;
    try {
      final volume = await owner.volume();
      if (!_owns(owner, generation) || revision != _valueRevision || volume == null || !volume.isFinite) return;
      _displayVolume(volume);
    } catch (error) {
      // Keep the bound controller's current value if its optional query fails.
      debugPrint('Volume overlay initial read failed: $error');
    }
  }

  void _handleToggleMute() {
    _valueRevision++;
    setState(() {
      if (_volume > 0) {
        _lastVolume = _volume;
        _volume = 0;
      } else {
        _volume = _lastVolume > 0 ? _lastVolume : 0.5;
      }
    });
    unawaited(controller.setVolume(_volume));
  }

  /// Screen readers step the volume through the button's semantics.
  void _applyVolume(double value) {
    final newVolume = value.clamp(0.0, 1.0).toDouble();
    if (newVolume == _volume) return;
    _valueRevision++;
    setState(() {
      _volume = newVolume;
      if (_volume > 0) _lastVolume = _volume;
    });
    unawaited(controller.setVolume(_volume));
  }

  @override
  Widget build(BuildContext context) {
    IconData icon = _volume == 0 ? Icons.volume_off : (_volume < 0.5 ? Icons.volume_down : Icons.volume_up);
    final percentage = (_volume * 100).round();

    return Semantics(
      label: i18n('room_volume'),
      value: '$percentage%',
      increasedValue: _volume < 1 ? '${((_volume + 0.05).clamp(0.0, 1.0) * 100).round()}%' : null,
      decreasedValue: _volume > 0 ? '${((_volume - 0.05).clamp(0.0, 1.0) * 100).round()}%' : null,
      onIncrease: _volume < 1 ? () => _applyVolume(_volume + 0.05) : null,
      onDecrease: _volume > 0 ? () => _applyVolume(_volume - 0.05) : null,
      child: IconButton(
        onPressed: _handleToggleMute,
        visualDensity: VisualDensity.standard,
        constraints: PlayerControlDensity.actionConstraints(context),
        icon: Icon(icon, color: Colors.white, size: PlayerControlDensity.iconSize(context, 24)),
        tooltip: _volume == 0 ? i18n('cancel_mute') : i18n('mute'),
      ),
    );
  }
}
