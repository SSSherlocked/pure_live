import 'dart:async';
import 'package:pure_live/core/theme/app_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/config/settings_service.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/utils/i18n.dart';
import 'package:pure_live/core/widgets/toast_util.dart';
import 'package:pure_live/core/models/live_message.dart';

/// A platform's super chat colour (`#RRGGBB`, `RRGGBB` or `AARRGGBB`), or
/// [fallback] when it sends something else.
Color superChatPlatformColor(String source, Color fallback) {
  final value = source.trim();
  final normalized = value.startsWith('#') ? value.substring(1) : value;
  if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(normalized)) return fallback;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return fallback;
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}

/// Text colour readable on a super chat's [background].
Color superChatContrastText(Color background) {
  return background.computeLuminance() > 0.55 ? const Color(0xFF18181A) : Colors.white;
}

/// Secondary text colour readable on a super chat's [background].
Color superChatSecondaryText(Color background) {
  return background.computeLuminance() > 0.55 ? const Color(0x8A18181A) : Colors.white.withValues(alpha: 0.70);
}

/// The message as shown. The raw text can end in a line break (or an
/// invisible zero-width character) that a web page hides but a Flutter
/// text widget draws as one more, empty line at the bottom of the card.
String superChatDisplayText(String raw) => raw.replaceAll(_edgeInvisibles, '');

final RegExp _edgeInvisibles = RegExp(r'^[\s\u200B-\u200D\u2060\uFEFF]+|[\s\u200B-\u200D\u2060\uFEFF]+$');

class SuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;

  const SuperChatCard(this.message, {super.key});

  @override
  State<SuperChatCard> createState() => _SuperChatCardState();
}

class _SuperChatCardState extends State<SuperChatCard> {
  Timer? _timer;

  int _remainSeconds = 0;

  @override
  void initState() {
    super.initState();

    _initTimer();
  }

  @override
  void didUpdateWidget(covariant SuperChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.message.startTime != widget.message.startTime ||
        oldWidget.message.endTime != widget.message.endTime) {
      _timer?.cancel();
      _timer = null;

      _initTimer();
    }
  }

  void _initTimer() {
    _updateRemainSeconds();

    if (_remainSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemainSeconds());
    }
  }

  void _updateRemainSeconds() {
    final duration = widget.message.endTime.difference(DateTime.now());

    final remain = duration.inMilliseconds <= 0 ? 0 : (duration.inMilliseconds / 1000).ceil().clamp(0, 7200);

    if (!mounted) {
      return;
    }

    setState(() {
      _remainSeconds = remain;
    });

    if (remain <= 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  String get _remainText {
    final minutes = _remainSeconds ~/ 60;
    final seconds = _remainSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Color _overlay(Color background, double opacity) {
    return superChatContrastText(background).withValues(alpha: opacity);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = Theme.of(context);

    final headerColor = superChatPlatformColor(message.backgroundColor, theme.colorScheme.primaryContainer);
    final messageColor = superChatPlatformColor(
      message.backgroundBottomColor,
      theme.colorScheme.surfaceContainerHighest,
    );

    final headerText = superChatContrastText(headerColor);
    final headerSubText = superChatSecondaryText(headerColor);
    final messageText = superChatContrastText(messageColor);

    // Smooth (superellipse) corners, and the hairline outline drawn over the
    // header and message colours: drawn under them, as before, the coloured
    // halves were clipped straight at the corner arc and hid the outline,
    // which left a hard, plain-circle edge.
    const radius = BorderRadius.all(Radius.circular(12));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: const RoundedSuperellipseBorder(borderRadius: radius),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      foregroundDecoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: radius,
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08), width: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(
            message: message,
            backgroundColor: headerColor,
            primaryText: headerText,
            secondaryText: headerSubText,
          ),
          _buildMessageBody(message: message, backgroundColor: messageColor, textColor: messageText),
        ],
      ),
    );
  }

  /// Avatar and name on the left with the countdown under the name; price and
  /// the SC tag in the top-right corner. Only a large text scale stacks them.
  Widget _buildHeader({
    required LiveSuperChatMessage message,
    required Color backgroundColor,
    required Color primaryText,
    required Color secondaryText,
  }) {
    final userName = Text(
      message.userName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppText.of(context).listPrimary.copyWith(color: primaryText, height: 1.2, fontWeight: FontWeight.w600),
    );
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAvatar(message.face, primaryText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [userName, const SizedBox(height: 4), _buildCountdown(primaryText, secondaryText)],
          ),
        ),
      ],
    );
    final value = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildPrice(message, primaryText),
        const SizedBox(height: 5),
        _buildScTag(backgroundColor, secondaryText),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(color: backgroundColor),
      child: MediaQuery.textScalerOf(context).scale(14) > 24
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerEnd, child: value),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: identity),
                const SizedBox(width: 8),
                value,
              ],
            ),
    );
  }

  Widget _buildPrice(LiveSuperChatMessage message, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Remix.money_cny_circle_fill, size: 16, color: Color(0xFFFFC107)),
        const SizedBox(width: 3),
        Text(
          '￥${message.price}',
          style: AppText.of(context).sectionTitle.copyWith(color: textColor,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }

  Widget _buildAvatar(String url, Color borderColor) {
    final uri = Uri.tryParse(url.trim());
    final hasRemoteAvatar = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    final fallback = Container(
      color: Colors.black.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Icon(Remix.user_2_fill, size: 20, color: borderColor),
    );
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(1.8),
      decoration: BoxDecoration(color: borderColor.withValues(alpha: 0.9), shape: BoxShape.circle),
      child: ClipOval(
        child: hasRemoteAvatar
            ? Image.network(
                url,
                width: 40.4,
                height: 40.4,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }

  Widget _buildScTag(Color backgroundColor, Color secondaryText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: _overlay(backgroundColor, 0.10), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Remix.vip_diamond_fill, size: 11, color: Color(0xFFFFC107)),
          const SizedBox(width: 3),
          Text(
            'SC',
            style: AppText.of(context).secondary.copyWith(color: secondaryText,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdown(Color primaryText, Color secondaryText) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Remix.time_line, size: 13, color: secondaryText),
        const SizedBox(width: 3),
        Text(
          _remainText,
          style: AppText.of(context).secondary.copyWith(color: primaryText,
            height: 1,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }

  Future<void> clipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    ToastUtil.show(i18n('copied_to_clipboard'));
  }

  Widget _buildMessageBody({
    required LiveSuperChatMessage message,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      decoration: BoxDecoration(color: backgroundColor),
      child: GestureDetector(
        onDoubleTap: () => clipboard(superChatDisplayText(message.message)),
        // 留言字体粗细 applies at once, while the card is on screen.
        child: Obx(
          () => SelectableText(
            superChatDisplayText(message.message),
            style: AppText.of(context).listPrimary.copyWith(
              color: textColor,
              height: 1.5,
              fontWeight: FontWeight(SettingsService.to.danmaku.superChatFontWeight.v),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
