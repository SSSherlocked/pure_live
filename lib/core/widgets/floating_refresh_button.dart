import 'package:pure_live/core/index.dart';

/// The refresh button of a list page in the desktop layout
/// ([AppLayout.refreshByButton]), where pulling the list down is not the natural
/// way to reload it. It sits in the page's floating action button slot.
class FloatingRefreshButton extends StatelessWidget {
  const FloatingRefreshButton({super.key, required this.onPressed});

  /// Bottom offset that puts a list's scroll buttons (see `BasePageView`)
  /// clear above this button: the scaffold's 16 px margin, the 56 px button
  /// and a 16 px gap.
  static const double clearance = 88;

  final VoidCallback onPressed;

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
      // The page's reload spinner shows a refresh in progress; a press
      // meanwhile joins it (see BasePageScrollAndStateBone.runningRefresh).
      onPressed: onPressed,
      child: const Icon(Icons.refresh_rounded),
    );
  }
}
