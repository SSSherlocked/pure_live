import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/theme/app_text.dart';
import 'package:pure_live/core/utils/i18n.dart';
import 'package:pure_live/core/widgets/widget_extensions.dart';

/// A settings group folded into one row: the group's name, a one-line
/// summary of its current values and a chevron. Tapping the row opens the
/// group's own settings under it, in the same card.
///
/// Every group starts folded and its open state lives only as long as the
/// page: nothing is stored, so there is nothing to back up. Several groups
/// may be open at once; opening one never folds another.
class CollapsibleSettingsGroup extends StatefulWidget {
  const CollapsibleSettingsGroup({
    super.key,
    required this.title,
    required this.summary,
    required this.children,
    this.icon,
    this.dense = false,
    this.reactive = true,
  });

  final String title;

  /// The summary under the title, read inside an [Obx] so it follows the
  /// settings. Null when everything in the group is off: the row then shows
  /// a muted 未开启.
  final String? Function() summary;

  /// The group's settings, built only while it is open: inside an [Obx]
  /// when [reactive], so they follow the settings they read.
  final List<Widget> Function() children;

  /// False when [children] read no observable themselves (a widget that
  /// watches its own state); an [Obx] that reads none throws.
  final bool reactive;

  final IconData? icon;

  /// The in-room panels' tighter rows.
  final bool dense;

  @override
  State<CollapsibleSettingsGroup> createState() => _CollapsibleSettingsGroupState();
}

class _CollapsibleSettingsGroupState extends State<CollapsibleSettingsGroup> {
  static const Duration _duration = Duration(milliseconds: 200);

  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) Future<void>.delayed(_duration, _revealBody);
  }

  /// Once the group has opened, scrolls just far enough to show all of it,
  /// but never past its own row: a group taller than the view stops with
  /// its row at the top.
  void _revealBody() {
    if (!mounted || !_open) return;
    final box = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box == null || !box.attached || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final toShowEnd = viewport.getOffsetToReveal(box, 1.0).offset;
    final toTop = viewport.getOffsetToReveal(box, 0.0).offset;
    final target = math
        .min(toShowEnd, toTop)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target <= position.pixels) return;
    position.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  Widget _body() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Semantics(
      expanded: _open,
      child: ListTile(
        visualDensity: widget.dense ? const VisualDensity(vertical: -2) : null,
        leading: widget.icon == null ? null : SettingsRowIcon(widget.icon!),
        title: Text(widget.title, style: AppText.of(context).sectionTitle),
        subtitle: Obx(() {
          final summary = widget.summary();
          return Text(
            summary ?? i18n('disabled'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.of(context).secondary.copyWith(
              color: summary == null ? theme.hintColor : theme.colorScheme.onSurfaceVariant,
            ),
          );
        }),
        trailing: AnimatedRotation(
          turns: _open ? 0.5 : 0,
          duration: _duration,
          curve: Curves.easeOutCubic,
          child: Icon(Icons.expand_more_rounded, color: theme.hintColor, size: 22),
        ),
        onTap: _toggle,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        AnimatedSize(
          duration: _duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    // A shade off the card in either theme marks the second
                    // level without indenting it: sliders keep the full width.
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08), width: 0.5)),
                  ),
                  child: widget.reactive ? Obx(_body) : _body(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The card the folded groups of one page share: the settings card on a
/// settings page, the in-room panels' own card when [embedded], with a thin
/// line between groups.
class CollapsibleSettingsCard extends StatelessWidget {
  const CollapsibleSettingsCard({super.key, required this.groups, this.embedded = false});

  final List<Widget> groups;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: theme.dividerColor.withValues(alpha: 0.05),
          ),
        groups[i],
      ],
    ];
    if (!embedded) return context.buildModernCard(children);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(kSettingsCardInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(type: MaterialType.transparency, child: Column(children: children)),
    );
  }
}

/// A folded group's summary from the parts that apply, joined with ' · ';
/// null (shown as a muted 未开启) when none does.
String? joinSettingsSummary(List<String> parts) => parts.isEmpty ? null : parts.join(' · ');
