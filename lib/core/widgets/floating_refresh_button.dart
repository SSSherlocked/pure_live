import 'package:pure_live/core/index.dart';

/// The refresh button of a list page in the desktop layout
/// ([AppLayout.pagedLists]), where pulling the list down is not the natural
/// way to reload it. It sits in the page's floating action button slot.
class FloatingRefreshButton extends StatelessWidget {
  const FloatingRefreshButton({super.key, required this.onPressed, this.loading = false});

  /// Bottom offset that puts a list's scroll buttons (see `BasePageView`)
  /// clear above this button: the scaffold's 16 px margin, the 56 px button
  /// and a 16 px gap.
  static const double clearance = 88;

  final VoidCallback onPressed;

  /// Shows a spinner and disables the button while the list reloads.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FloatingActionButton(
      // A page may carry other floating buttons; this one never flies between
      // routes.
      heroTag: null,
      tooltip: i18n('refresh'),
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      onPressed: loading ? null : onPressed,
      child: loading
          ? SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
            )
          : const Icon(Icons.refresh_rounded),
    );
  }
}
