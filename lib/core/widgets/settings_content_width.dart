import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Holds a settings page body at a fixed content width.
///
/// Settings rows read badly when a wide desktop window stretches them edge to
/// edge, so the body keeps [width] and sits centred; narrower windows still
/// shrink it to fit. The margins beside it forward the mouse wheel to the
/// page's list, so the whole window scrolls the page.
class SettingsContentWidth extends StatefulWidget {
  const SettingsContentWidth({super.key, required this.child});

  static const double width = 720;

  final Widget child;

  @override
  State<SettingsContentWidth> createState() => _SettingsContentWidthState();
}

class _SettingsContentWidthState extends State<SettingsContentWidth> {
  final GlobalKey _contentKey = GlobalKey();

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final contentContext = _contentKey.currentContext;
    final box = contentContext?.findRenderObject();
    if (contentContext == null || box is! RenderBox || !box.hasSize) return;
    // Inside the content the list already handles the wheel itself.
    if ((Offset.zero & box.size).contains(box.globalToLocal(event.position))) return;
    final scrollable = _verticalScrollable(contentContext);
    if (scrollable == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final position = scrollable.position;
      final delta = (resolved as PointerScrollEvent).scrollDelta.dy;
      final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      if (target != position.pixels) position.jumpTo(target);
    });
  }

  /// The first vertical scroll view inside the content: the page's list.
  static ScrollableState? _verticalScrollable(BuildContext context) {
    ScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState && state.position.axis == Axis.vertical) {
          found = state;
          return;
        }
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onPointerSignal,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: _contentKey,
          constraints: const BoxConstraints(maxWidth: SettingsContentWidth.width),
          child: widget.child,
        ),
      ),
    );
  }
}
