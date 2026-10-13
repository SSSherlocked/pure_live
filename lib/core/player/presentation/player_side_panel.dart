import 'dart:math' as math;

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';

/// Opens the [PlayerSidePanel] that [builder] returns: it slides in from the
/// right edge and back out, over the undimmed picture. Like [showDialog], it
/// keeps the caller's themes and stays inside the safe area.
Future<T?> showPlayerSidePanel<T>(BuildContext context, {required WidgetBuilder builder}) {
  final themes = InheritedTheme.capture(from: context, to: Navigator.of(context).context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => themes.wrap(SafeArea(child: Builder(builder: builder))),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
      ),
      child: child,
    ),
  );
}

/// Opens the [PlayerSidePanel] that [builder] returns as a bottom sheet: the
/// narrow inline player has no room for a right-edge panel, so there the same
/// panel (header, close button, content) rises from the bottom instead.
Future<T?> showPlayerBottomPanel<T>(BuildContext context, {required WidgetBuilder builder}) {
  final height = MediaQuery.sizeOf(context).height * 0.7;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    clipBehavior: Clip.antiAlias,
    builder: (context) => _PlayerPanelInSheet(height: height, child: Builder(builder: builder)),
  );
}

/// Opens a player panel the way the layout wants it: from the bottom on the
/// narrow inline player ([asBottomSheet]), sliding in from the right
/// everywhere else.
Future<T?> showPlayerPanel<T>(BuildContext context, {required WidgetBuilder builder, required bool asBottomSheet}) {
  return asBottomSheet
      ? showPlayerBottomPanel<T>(context, builder: builder)
      : showPlayerSidePanel<T>(context, builder: builder);
}

/// Marks a [PlayerSidePanel] shown by [showPlayerBottomPanel].
class _PlayerPanelInSheet extends InheritedWidget {
  const _PlayerPanelInSheet({required this.height, required super.child});

  final double height;

  @override
  bool updateShouldNotify(_PlayerPanelInSheet oldWidget) => oldWidget.height != height;
}

/// The fullscreen player's menu panel: a full-height column docked to the right
/// edge, top and bottom flush with the screen, with a width of its own.
///
/// Every fullscreen menu (关注, 画质与线路, 弹幕设置) uses this one shape, so
/// they open in the same place and leave the same part of the picture visible.
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.headerHeight,
    this.closeKey,
  });

  final IconData icon;
  final String title;
  final Widget child;

  /// Whether [context] is inside a panel opened by [showPlayerBottomPanel].
  static bool inBottomSheet(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PlayerPanelInSheet>() != null;

  /// Overrides the header height a caller has already measured.
  final double? headerHeight;
  final Key? closeKey;

  /// The panel width for [screen]: the fullscreen panel width, at least 320
  /// and never more than 90% of the screen.
  static double widthFor(Size screen, {double? preferred}) {
    final preferredWidth =
        preferred ??
        (Get.isRegistered<ThemeSettingsController>()
            ? SettingsService.to.theme.fullscreenPanelWidth.v
            : LivePanelWidth.defaultValue);
    return math.min(math.max(LivePanelWidth.normalize(preferredWidth), 320.0), screen.width * 0.9);
  }

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

/// The panel's left edge resizes it like the room side panel's: the width
/// follows the drag and is saved once, when the drag ends. Fullscreen panels
/// keep their own width, apart from the room's side panel.
class _PlayerSidePanelState extends State<PlayerSidePanel> {
  double? _dragWidth;
  bool _hovered = false;

  void _onDragUpdate(DragUpdateDetails details, Size screen) {
    // The handle is on the panel's left edge: moving left widens it.
    final current = _dragWidth ?? PlayerSidePanel.widthFor(screen);
    setState(() => _dragWidth = PlayerSidePanel.widthFor(screen, preferred: current - details.delta.dx));
  }

  void _onDragEnd([DragEndDetails? _]) {
    final dragged = _dragWidth;
    if (dragged == null) return;
    setState(() => _dragWidth = null);
    if (Get.isRegistered<ThemeSettingsController>()) {
      SettingsService.to.theme.fullscreenPanelWidth.v = LivePanelWidth.normalize(dragged.roundToDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    final title = widget.title;
    final child = widget.child;
    final headerHeight = widget.headerHeight;
    final closeKey = widget.closeKey;
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final titleLine = MediaQuery.textScalerOf(context).scale(
      (titleStyle?.fontSize ?? 14) * (titleStyle?.height ?? 1.25),
    );
    final resolvedHeaderHeight = headerHeight ?? math.max(kMinInteractiveDimension, titleLine + 16);

    final header = SizedBox(
      height: resolvedHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 2),
        child: Row(
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle)),
            IconButton(
              key: closeKey,
              tooltip: i18n('close'),
              visualDensity: VisualDensity.standard,
              constraints: const BoxConstraints.tightFor(width: kMinInteractiveDimension, height: kMinInteractiveDimension),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );

    // From the bottom (narrow inline player): the same header and content,
    // full width, no resize edge.
    final sheet = context.dependOnInheritedWidgetOfExactType<_PlayerPanelInSheet>();
    if (sheet != null) {
      return SizedBox(
        height: sheet.height,
        child: Column(children: [header, Expanded(child: child)]),
      );
    }

    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(16))),
      child: SizedBox(
        width: _dragWidth ?? PlayerSidePanel.widthFor(screen),
        height: screen.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                left: false,
                child: Column(children: [header, Expanded(child: child)]),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              // Wider for a finger than for a mouse.
              width: AppLayout.of(context).touch ? 14.0 : 8.0,
              child: MouseRegion(
                key: const ValueKey('player-side-panel-resize-handle'),
                cursor: SystemMouseCursors.resizeLeftRight,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => _onDragUpdate(details, screen),
                  onHorizontalDragEnd: _onDragEnd,
                  onHorizontalDragCancel: _onDragEnd,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _hovered || _dragWidth != null ? 3 : 0,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
