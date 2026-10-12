import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/core/index.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

/// One row of the 视频详情 window.
typedef VideoDetail = ({String labelKey, String value});

/// mpv properties the window reads; each is optional (a live stream may have no
/// audio, an engine may not know its bitrate yet).
const List<String> videoDetailMpvProperties = <String>[
  'video-codec',
  'video-format',
  'estimated-vf-fps',
  'container-fps',
  'hwdec-current',
  'video-bitrate',
  'audio-codec-name',
  'audio-params/samplerate',
  'audio-params/channel-count',
  'audio-bitrate',
  'file-format',
  'demuxer-cache-duration',
  'frame-drop-count',
  'decoder-frame-drop-count',
];

/// Formats bits per second as kbps or Mbps; null when there is no number.
@visibleForTesting
String? formatBitrate(String? raw) {
  final bits = double.tryParse(raw?.trim() ?? '');
  if (bits == null || bits <= 0) return null;
  if (bits >= 1000000) return '${(bits / 1000000).toStringAsFixed(2)} Mbps';
  return '${(bits / 1000).round()} kbps';
}

/// The window's rows from what the engine reported. [mpv] is null for engines
/// other than media_kit, which do not report codecs or bitrates.
@visibleForTesting
List<VideoDetail> buildVideoDetails({
  required String quality,
  required String line,
  required String engine,
  required String host,
  required int? width,
  required int? height,
  required Map<String, String>? mpv,
}) {
  String? read(String key) {
    final value = mpv?[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? number(String key, {int digits = 2, String suffix = ''}) {
    final value = double.tryParse(read(key) ?? '');
    if (value == null || value <= 0) return null;
    return '${value.toStringAsFixed(digits)}$suffix';
  }

  final rows = <VideoDetail>[
    (labelKey: 'video_details_quality', value: quality),
    (labelKey: 'video_details_line', value: line),
    (labelKey: 'video_details_engine', value: engine),
    if (host.isNotEmpty) (labelKey: 'video_details_host', value: host),
    if (width != null && height != null && width > 0 && height > 0)
      (labelKey: 'video_details_resolution', value: '$width × $height'),
  ];
  if (mpv == null) return rows;

  final codec = read('video-codec') ?? read('video-format');
  final fps = number('estimated-vf-fps') ?? number('container-fps');
  final hwdec = read('hwdec-current');
  final sampleRate = read('audio-params/samplerate');
  final channels = read('audio-params/channel-count');
  final dropped = [
    read('frame-drop-count'),
    read('decoder-frame-drop-count'),
  ].map((value) => int.tryParse(value ?? '') ?? 0).fold<int>(0, (sum, value) => sum + value);

  return [
    ...rows,
    if (codec != null) (labelKey: 'video_details_video_codec', value: codec),
    if (fps != null) (labelKey: 'video_details_frame_rate', value: '$fps fps'),
    if (hwdec != null)
      (labelKey: 'video_details_hwdec', value: hwdec == 'no' ? i18n('video_details_hwdec_off') : hwdec),
    if (formatBitrate(read('video-bitrate')) case final bitrate?)
      (labelKey: 'video_details_video_bitrate', value: bitrate),
    if (read('audio-codec-name') case final audio?) (labelKey: 'video_details_audio_codec', value: audio),
    if (sampleRate != null)
      (
        labelKey: 'video_details_audio_format',
        value: channels == null
            ? '$sampleRate Hz'
            : '$sampleRate Hz · ${i18n('video_details_channels', args: {'count': channels})}',
      ),
    if (formatBitrate(read('audio-bitrate')) case final bitrate?)
      (labelKey: 'video_details_audio_bitrate', value: bitrate),
    if (read('file-format') case final format?) (labelKey: 'video_details_container', value: format),
    if (number('demuxer-cache-duration', digits: 1, suffix: ' s') case final cache?)
      (labelKey: 'video_details_cache', value: cache),
    (labelKey: 'video_details_dropped', value: '$dropped'),
  ];
}

/// 视频详情: what is actually playing, refreshed every second while open.
///
/// A floating window over the room so the picture stays visible behind it.
class VideoDetailsDialog extends StatefulWidget {
  const VideoDetailsDialog({super.key, required this.controller});

  final LivePlayController controller;

  static Future<void> show(BuildContext context, LivePlayController controller) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => VideoDetailsDialog(controller: controller),
    );
  }

  @override
  State<VideoDetailsDialog> createState() => _VideoDetailsDialogState();
}

class _VideoDetailsDialogState extends State<VideoDetailsDialog> {
  Timer? _timer;
  List<VideoDetail> _rows = const <VideoDetail>[];
  bool _engineLimited = false;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final player = GlobalPlayerService.instance.player;
      final handle = player.handle;
      final snapshot = handle?.combinedSnapshot;
      final size = snapshot?.geometry.videoSize;
      final state = widget.controller.state.value.player;

      Map<String, String>? mpv;
      final adapter = handle?.adapter;
      if (adapter is MediaKitPlayerAdapter) {
        final platform = adapter.player.platform;
        if (platform is NativePlayer) {
          mpv = <String, String>{};
          for (final property in videoDetailMpvProperties) {
            try {
              // Never wait for initialization: a stalled stream must not
              // freeze the window.
              mpv[property] = await platform.getProperty(property, waitForInitialization: false);
            } catch (_) {
              // Not available for this stream; the row is left out.
            }
          }
        }
      }

      final rows = buildVideoDetails(
        quality: state.qualites.isEmpty ? '—' : state.qualitySafe.playbackLabel,
        line: i18n('toolbox_line', args: {'index': '${state.currentLineIndex + 1}'}),
        engine: snapshot?.backendId ?? '—',
        // The host only: the full address carries access tokens.
        host: snapshot?.source?.uri.host ?? '',
        width: size?.width.round(),
        height: size?.height.round(),
        mpv: mpv,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _engineLimited = mpv == null;
      });
    } catch (_) {
      // Playback torn down mid-read; keep the last rows.
    } finally {
      _reading = false;
    }
  }

  Future<void> _copy() async {
    final text = _rows.map((row) => '${i18n(row.labelKey)}: ${row.value}').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    ToastUtil.show(i18n('video_details_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final value = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return AlertDialog(
      key: const ValueKey('video-details-dialog'),
      scrollable: true,
      title: Text(i18n('video_details')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_rows.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else
              for (final row in _rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 96, child: Text(i18n(row.labelKey), style: label)),
                      const SizedBox(width: 12),
                      Expanded(child: SelectableText(row.value, style: value)),
                    ],
                  ),
                ),
            if (_engineLimited) ...[
              const SizedBox(height: 8),
              Text(i18n('video_details_engine_limited'), style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _rows.isEmpty ? null : _copy, child: Text(i18n('copy'))),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close'))),
      ],
    );
  }
}
