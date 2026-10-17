import 'dart:io';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/storage/hive_rx.dart';

class VolumeSettingsController extends GetxController {
  final RxDouble defaultDesktopVolume = hiveDouble('defaultDesktopVolume', 1.0);
  final RxBool globalVolumeMute = hiveBool('globalVolumeMute', false);

  @override
  void onInit() {
    super.onInit();
    final desktop = normalizeVolume(defaultDesktopVolume.v, fallback: 1.0);
    if (!defaultDesktopVolume.v.isFinite || defaultDesktopVolume.v != desktop) defaultDesktopVolume.v = desktop;
  }

  /// The player's own level when nothing else asks for one. Android/iOS keep
  /// the player at full gain and leave loudness to the system media volume,
  /// so only desktops have a default to apply.
  double get currentPlatformDefaultVolume {
    return Platform.isAndroid || Platform.isIOS ? 1.0 : normalizeVolume(defaultDesktopVolume.v, fallback: 1.0);
  }

  /// The level every room opens at: silent under 默认静音, otherwise the
  /// default. A level changed inside a room lasts for that viewing only.
  double get roomOpenVolume => globalVolumeMute.v ? 0.0 : currentPlatformDefaultVolume;

  Map<String, dynamic> toJson() {
    return {'defaultDesktopVolume': defaultDesktopVolume.v, 'globalVolumeMute': globalVolumeMute.v};
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    defaultDesktopVolume.v = parsed.desktop;
    globalVolumeMute.v = parsed.mute;
  }

  static ({double desktop, bool mute}) parseConfig(Map<String, dynamic> json) {
    final desktop = _parseVolume(json['defaultDesktopVolume'], fallback: 1.0);
    final mute = json['globalVolumeMute'] as bool? ?? false;
    return (desktop: desktop, mute: mute);
  }

  static double normalizeVolume(double value, {required double fallback}) {
    if (!value.isFinite) return fallback;
    return value.clamp(0.0, 1.0).toDouble();
  }

  static double _parseVolume(dynamic value, {required double fallback}) {
    if (value == null) return fallback;
    if (value is! num) throw const FormatException('Invalid default volume');
    final parsed = value.toDouble();
    if (!parsed.isFinite) throw const FormatException('Invalid default volume');
    return parsed.clamp(0.0, 1.0).toDouble();
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final volume = rootConfig?['volume'] as Map<String, dynamic>? ?? {};
    return {
      'defaultDesktopVolume': (volume['defaultDesktopVolume'] ?? 1.0).toDouble(),
      'globalVolumeMute': volume['globalVolumeMute'] ?? false,
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final volume = Map<String, dynamic>.from(rootConfig['volume'] ?? {});
    updateFields.forEach((k, v) => volume[k] = v);
    rootConfig['volume'] = volume;
    return rootConfig;
  }
}
