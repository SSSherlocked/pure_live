import 'dart:io';

/// Per-engine, per-platform-group output settings.
///
/// One segment holds everything an engine needs to build its output:
/// hardware acceleration, manual vo/hwdec picks and the audio output.
/// Segments are stored separately for each engine and each platform
/// group, so an Android pick never leaks onto Windows.
class PlayerEngineOutput {
  const PlayerEngineOutput({
    this.enableCodec = true,
    this.customPlayerOutput = false,
    this.videoOutputDriver = 'auto',
    this.videoHardwareDecoder = 'auto-safe',
    this.audioOutputDriver = 'auto',
    this.videoSync = 'audio',
    this.interpolation = 'no',
    this.scale = 'lanczos',
    this.deinterlace = 'auto',
    this.hwdecCodecs = 'all',
    this.audioExclusive = 'no',
  });

  /// Whether hardware decoding is allowed at all.
  final bool enableCodec;

  /// Whether the manual vo/hwdec picks below are applied.
  final bool customPlayerOutput;

  /// Manual video output driver (mpv `vo`), engine-spelled.
  final String videoOutputDriver;

  /// Manual hardware decoder (mpv `hwdec`), engine-spelled.
  final String videoHardwareDecoder;

  /// Manual audio output driver (mpv `ao`), engine-spelled.
  final String audioOutputDriver;

  /// mpv `video-sync` mode.
  final String videoSync;

  /// mpv `interpolation`.
  final String interpolation;

  /// mpv `scale` (upscale kernel).
  final String scale;

  /// mpv `deinterlace`.
  final String deinterlace;

  /// mpv `hwdec-codecs`.
  final String hwdecCodecs;

  /// mpv `audio-exclusive` (Windows).
  final String audioExclusive;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enableCodec': enableCodec,
      'customPlayerOutput': customPlayerOutput,
      'videoOutputDriver': videoOutputDriver,
      'videoHardwareDecoder': videoHardwareDecoder,
      'audioOutputDriver': audioOutputDriver,
      'videoSync': videoSync,
      'interpolation': interpolation,
      'scale': scale,
      'deinterlace': deinterlace,
      'hwdecCodecs': hwdecCodecs,
      'audioExclusive': audioExclusive,
    };
  }

  static PlayerEngineOutput fromJson(Object? json) {
    if (json is! Map) return const PlayerEngineOutput();

    return PlayerEngineOutput(
      enableCodec: json['enableCodec'] is bool ? json['enableCodec'] as bool : true,
      customPlayerOutput: json['customPlayerOutput'] is bool ? json['customPlayerOutput'] as bool : false,
      videoOutputDriver: json['videoOutputDriver'] is String ? json['videoOutputDriver'] as String : 'auto',
      videoHardwareDecoder: json['videoHardwareDecoder'] is String ? json['videoHardwareDecoder'] as String : 'auto-safe',
      audioOutputDriver: json['audioOutputDriver'] is String ? json['audioOutputDriver'] as String : 'auto',
      videoSync: json['videoSync'] is String ? json['videoSync'] as String : 'audio',
      interpolation: json['interpolation'] is String ? json['interpolation'] as String : 'no',
      scale: json['scale'] is String ? json['scale'] as String : 'lanczos',
      deinterlace: json['deinterlace'] is String ? json['deinterlace'] as String : 'auto',
      hwdecCodecs: json['hwdecCodecs'] is String ? json['hwdecCodecs'] as String : 'all',
      audioExclusive: json['audioExclusive'] is String ? json['audioExclusive'] as String : 'no',
    );
  }
}

/// Platform groups a settings segment can be stored under.
String platformGroupName() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'other';
}
