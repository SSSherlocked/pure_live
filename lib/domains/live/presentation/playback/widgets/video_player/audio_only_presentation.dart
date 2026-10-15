import 'dart:math' as math;

import 'package:remixicon/remixicon.dart';

import 'package:pure_live/core/index.dart';

/// What covers the picture in 纯音频: the room's avatar, title and streamer
/// on black.
///
/// It takes no pointer, so gestures reach the player controls on top of it.
/// The room player instead draws it in two layers: [AudioOnlyPresentation.backdrop]
/// (the black, under the controls) and [AudioOnlyPresentation.foreground]
/// (the information, over them), so that the 纯音频 badge can be tapped to
/// bring the picture back. Everything else in the foreground lets pointers
/// through.
class AudioOnlyPresentation extends StatelessWidget {
  const AudioOnlyPresentation({super.key, required this.room}) : onExit = null, _layer = _Layer.whole;

  const AudioOnlyPresentation.backdrop({super.key, required this.room}) : onExit = null, _layer = _Layer.backdrop;

  const AudioOnlyPresentation.foreground({super.key, required this.room, required VoidCallback this.onExit})
    : _layer = _Layer.foreground;

  final LiveRoom room;

  /// Leaves 纯音频 (the foreground's badge).
  final VoidCallback? onExit;

  final _Layer _layer;

  @override
  Widget build(BuildContext context) {
    if (_layer == _Layer.backdrop) {
      return const IgnorePointer(
        child: ColoredBox(key: ValueKey('audio-only-presentation'), color: Colors.black),
      );
    }
    if (_layer == _Layer.foreground) return _buildForeground(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final maxWidth = constraints.maxWidth;
        final compact = maxHeight < 500;
        final avatarRadius = compact ? (maxHeight * 0.11).clamp(25.0, 38.0) : 50.0;

        return IgnorePointer(
          child: ColoredBox(
            key: const ValueKey('audio-only-presentation'),
            color: Colors.black,
            child: Center(
              child: SingleChildScrollView(
                physics: compact ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24, vertical: compact ? 4 : 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? maxWidth : 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Avatar(radius: avatarRadius, url: room.avatar, name: room.nick),
                      SizedBox(height: compact ? 10 : 24),
                      Text(
                        key: const ValueKey('audio-only-title'),
                        _title(room),
                        textAlign: TextAlign.center,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: (compact ? AppText.of(context).listPrimary : AppText.of(context).sectionTitle).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Badge(compact: compact, text: _nick(room)),
                      SizedBox(height: compact ? 8 : 16),
                      _Badge(compact: compact, icon: Remix.headphone_line, text: i18n('audio_only_mode')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The information over the controls. No scroll view (it would take the
  /// player's drags): a short area scales the column down instead. Only the
  /// badge takes a pointer.
  Widget _buildForeground(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final maxWidth = constraints.maxWidth;
        final compact = maxHeight < 500;
        final avatarRadius = compact ? (maxHeight * 0.11).clamp(25.0, 38.0) : 50.0;
        final horizontal = compact ? 16.0 : 24.0;

        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: compact ? 4 : 24),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? math.max(0, maxWidth - horizontal * 2) : 460),
                child: Column(
                  key: const ValueKey('audio-only-foreground'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Avatar(radius: avatarRadius, url: room.avatar, name: room.nick),
                          SizedBox(height: compact ? 10 : 24),
                          Text(
                            key: const ValueKey('audio-only-title'),
                            _title(room),
                            textAlign: TextAlign.center,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: (compact ? AppText.of(context).listPrimary : AppText.of(context).sectionTitle)
                                .copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.25),
                          ),
                          const SizedBox(height: 8),
                          _Badge(compact: compact, text: _nick(room)),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 16),
                    _ExitBadge(compact: compact, onTap: onExit!),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _Layer { whole, backdrop, foreground }

/// The 纯音频 badge that leaves 纯音频: the theme colour, lifted until it
/// reads on the black cover.
class _ExitBadge extends StatelessWidget {
  const _ExitBadge({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = readablePrimary(Theme.of(context).colorScheme.primary, Colors.black);
    final radius = BorderRadius.circular(30);
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('audio-only-exit'),
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 3 : 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: radius,
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Remix.headphone_line, color: color, size: compact ? 12 : 16),
                SizedBox(width: compact ? 4 : 8),
                Flexible(
                  child: Text(
                    i18n('audio_only_mode'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.of(context).secondary.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.radius, required this.url, required this.name});

  final double radius;
  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeNetworkImageUrl(url);
    final size = radius * 2;
    final placeholder = Icon(Remix.user_3_line, color: Colors.white24, size: radius);

    return Container(
      key: const ValueKey('audio-only-avatar'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
      ),
      child: ClipOval(
        child: normalized.isEmpty
            ? ColoredBox(color: Colors.white12, child: Center(child: placeholder))
            : Image.network(
                normalized,
                width: size,
                height: size,
                fit: BoxFit.cover,
                headers: networkImageHeaders(normalized),
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(color: Colors.white12, child: Center(child: placeholder)),
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.compact, required this.text, this.icon});

  final bool compact;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 3 : 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: compact ? 12 : 16),
            SizedBox(width: compact ? 4 : 8),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.of(context).secondary.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _title(LiveRoom room) {
  final value = room.title?.trim() ?? '';
  return value.isEmpty ? _nick(room) : value;
}

String _nick(LiveRoom room) {
  final value = room.nick?.trim() ?? '';
  if (value.isNotEmpty) return value;
  final fallback = room.title?.trim() ?? '';
  return fallback.isEmpty ? i18n('untitled_room') : fallback;
}
