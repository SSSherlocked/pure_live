import 'package:flutter/material.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/widgets/thumb_only_slider.dart';
import 'package:pure_live/core/theme/app_text.dart';

/// The width every settings row gives its leading icon, and the gap from
/// there to its text: switch, slider and plain rows alike, so the texts of a
/// card start on one line.
const double kSettingsIconSlot = 24;
const double kSettingsIconGap = 12;

/// Row metrics shared by every row of a settings card: the same side
/// padding, the same space above and below the text and the same minimum
/// height, whether the row is a plain, switch, slider or hand-built one.
/// [AppLayoutFactory.buildModernCard] hands them to its rows through the
/// list tile theme, so a row only sets what differs (a switch's end edge).
const double kSettingsRowSidePadding = 16;
const double kSettingsRowVerticalPadding = 14;
const double kSettingsRowMinHeight = 64;

/// A switch row's padding: the switch carries its own margin at the end.
const EdgeInsetsDirectional kSettingsSwitchRowPadding = EdgeInsetsDirectional.only(
  start: kSettingsRowSidePadding,
  end: 8,
);

/// The leading icon of a settings row: theme colour, 22 px, as every shared
/// settings tile draws it. Rows built by hand use this so their icons match.
class SettingsRowIcon extends StatelessWidget {
  const SettingsRowIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary);
}

extension AppLayoutFactory on BuildContext {
  Widget buildGroupTitle(String text) {
    final theme = Theme.of(this);
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        text,
        style: AppText.of(this).secondary.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary.withValues(alpha: 0.65),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget buildModernCard(List<Widget> children) {
    final theme = Theme.of(this);
    final List<Widget> autoShapedChildren = [];

    final validChildren = children.where((w) => w is! SizedBox).toList();

    for (int i = 0; i < validChildren.length; i++) {
      final child = validChildren[i];

      String typeString = child.runtimeType.toString();

      final bool isTileElement =
          child is ListTile ||
          child is StreamBuilder ||
          typeString.contains('ListTile') ||
          typeString.contains('SwitchListTile') ||
          typeString.contains('Obx');

      if (isTileElement) {
        ShapeBorder effectiveShape;

        if (validChildren.length == 1) {
          effectiveShape = const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)));
        } else if (i == 0) {
          effectiveShape = const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20)));
        } else if (i == validChildren.length - 1) {
          effectiveShape = const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          );
        } else {
          effectiveShape = const LinearBorder();
        }

        autoShapedChildren.add(ListTileTheme.merge(shape: effectiveShape, child: child));
      } else {
        autoShapedChildren.add(child);
      }

      if (i < validChildren.length - 1 && isTileElement) {
        final nextChild = validChildren[i + 1];
        String nextTypeString = nextChild.runtimeType.toString();

        final bool isNextTile =
            nextChild is ListTile ||
            nextChild is StreamBuilder ||
            nextTypeString.contains('ListTile') ||
            nextTypeString.contains('SwitchListTile') ||
            nextTypeString.contains('Obx');

        if (isNextTile) {
          autoShapedChildren.add(
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: theme.dividerColor.withValues(alpha: 0.05),
            ),
          );
        }
      }
    }

    return Material(
      clipBehavior: Clip.antiAlias,
      // The theme's card colour when it has one, else a light wash.
      color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.05), width: 0.5),
      ),
      child: ListTileTheme.merge(
        contentPadding: const EdgeInsets.symmetric(horizontal: kSettingsRowSidePadding),
        minVerticalPadding: kSettingsRowVerticalPadding,
        minTileHeight: kSettingsRowMinHeight,
        horizontalTitleGap: kSettingsIconGap,
        minLeadingWidth: kSettingsIconSlot,
        child: Column(children: autoShapedChildren),
      ),
    );
  }

  Widget buildSwitchTile({
    required String title,
    required RxBool value,
    IconData? icon,
    String? subtitle,
    Color? iconColor,
    Color? subtitleColor,
    bool enabled = true,
    bool autoCommit = true,
    ValueChanged<bool>? onChanged,
  }) {
    final theme = Theme.of(this);
    return Obx(
      () => SwitchListTile(
        secondary: icon != null ? Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 22) : null,
        title: Text(title, style: AppText.of(this).sectionTitle),
        subtitle: subtitle != null && subtitle.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: AppText.of(this).secondary.copyWith(color: subtitleColor ?? theme.colorScheme.onSurfaceVariant),
                ),
              )
            : null,
        value: value.value,
        onChanged: enabled
            ? (val) {
                if (autoCommit) value.value = val;
                onChanged?.call(val);
              }
            : null,
        contentPadding: kSettingsSwitchRowPadding,
      ),
    );
  }

  Widget buildTile({
    required String title,
    IconData? icon,
    Widget? iconWidget,
    String? subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Color? subtitleColor,
    Widget? trailing,
    bool stackTrailingOnNarrow = false,
    bool showNavigationChevronWhenStacked = true,
    bool destructive = false,
  }) {
    final theme = Theme.of(this);
    // A destructive action (clearing files, a cache) is not a way into
    // another page: its icon is red and it has no navigation chevron.
    if (destructive) {
      iconColor ??= theme.colorScheme.error;
      showNavigationChevronWhenStacked = false;
    }

    Widget? leadingWidget;
    if (iconWidget != null) {
      leadingWidget = Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: IconTheme(
              data: IconThemeData(color: iconColor ?? theme.colorScheme.primary, size: 22),
              child: iconWidget,
            ),
          ),
        ],
      );
    } else if (icon != null) {
      leadingWidget = Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 22),
          ),
        ],
      );
    }

    final titleWidget = Text(title, style: AppText.of(this).sectionTitle);
    final subtitleWidget = subtitle != null && subtitle.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: AppText.of(this).secondary.copyWith(color: subtitleColor ?? theme.colorScheme.onSurfaceVariant),
            ),
          )
        : null;

    Widget standardTile() => ListTile(
      leading: leadingWidget,
      title: titleWidget,
      subtitle: subtitleWidget,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child:
                trailing ??
                (onTap != null && !destructive
                    ? Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20)
                    : null),
          ),
        ],
      ),
      onTap: onTap,
    );

    if (!stackTrailingOnNarrow || trailing == null) return standardTile();
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth >= 360 && textScale <= 1.5) return standardTile();
        return ListTile(
          leading: leadingWidget,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleWidget, ?subtitleWidget, const SizedBox(height: 8), trailing],
          ),
          trailing: onTap != null && showNavigationChevronWhenStacked
              ? Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20)
              : null,
          onTap: onTap,
        );
      },
    );
  }

  Widget buildMenuTile<T>({
    required String title,
    required T value,
    required Map<T, String> valueMap,
    required Function(T) onChanged,
    IconData? icon,
    String? subtitle,
    Color? iconColor,
    Color? subtitleColor,
  }) {
    final theme = Theme.of(this);
    final rawValueString = valueMap[value] ?? "$value";
    final displayValue = rawValueString.tr;

    return buildTile(
      title: title,
      icon: icon,
      subtitle: subtitle,
      iconColor: iconColor,
      subtitleColor: subtitleColor,
      stackTrailingOnNarrow: true,
      showNavigationChevronWhenStacked: false,
      trailing: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            displayValue,
            style: AppText.of(this).listPrimary.copyWith(
              color: theme.hintColor.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20),
        ],
      ),
      onTap: () => _openMenuDialog<T>(title: title, value: value, valueMap: valueMap, onChanged: onChanged),
    );
  }

  void _openMenuDialog<T>({
    required String title,
    required T value,
    required Map<T, String> valueMap,
    required Function(T) onChanged,
  }) {
    showDialog(
      context: this,
      builder: (BuildContext dialogContext) {
        final innerTheme = Theme.of(dialogContext);

        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Text(title, style: AppText.of(this).pageTitle),
          content: RadioGroup<T>(
            groupValue: value,
            onChanged: (T? newValue) {
              if (newValue != null) {
                Navigator.of(dialogContext).pop();
                onChanged.call(newValue);
              }
            },
            child: buildModernCard(
              valueMap.entries.map<Widget>((entry) {
                final itemDisplayText = (entry.value).tr;
                final isSelected = entry.key == value;
                return RadioListTile<T>(
                  value: entry.key,
                  activeColor: innerTheme.colorScheme.primary,
                  title: Text(
                    itemDisplayText,
                    style: AppText.of(this).sectionTitle.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? innerTheme.colorScheme.primary : innerTheme.textTheme.bodyLarge?.color,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget buildSliderTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kSettingsRowSidePadding,
        vertical: kSettingsRowVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(width: kSettingsIconSlot, child: SettingsRowIcon(icon)),
          ),
          const SizedBox(width: kSettingsIconGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final titleStyle = AppText.of(this).sectionTitle;
                    final valueStyle = AppText.of(this).body.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    );
                    final scaler = MediaQuery.textScalerOf(context);
                    final titlePainter = TextPainter(
                      text: TextSpan(text: title, style: titleStyle),
                      textDirection: Directionality.of(context),
                      textScaler: scaler,
                      maxLines: 1,
                    )..layout();
                    final valuePainter = TextPainter(
                      text: TextSpan(text: displayValue, style: valueStyle),
                      textDirection: Directionality.of(context),
                      textScaler: scaler,
                      maxLines: 1,
                    )..layout();
                    final valueBadge = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(displayValue, style: valueStyle),
                    );
                    final useRow = titlePainter.width + valuePainter.width + 28 <= constraints.maxWidth;
                    if (useRow) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(title, style: titleStyle)),
                          const SizedBox(width: 12),
                          valueBadge,
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: titleStyle),
                        const SizedBox(height: 6),
                        valueBadge,
                      ],
                    );
                  },
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppText.of(this).secondary.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 2),
                Transform.translate(
                  offset: const Offset(-4, 0),
                  child: SizedBox(
                    width: double.infinity,
                    // Only a drag of the thumb changes it: a tap on the
                    // track, or a finger scrolling the page past it, does not.
                    child: ThumbOnlySlider(
                      min: min,
                      max: max,
                      value: value,
                      activeColor: theme.colorScheme.primary,
                      inactiveColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
