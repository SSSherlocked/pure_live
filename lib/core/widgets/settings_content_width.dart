import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Holds a settings page body at a fixed content width.
///
/// Settings rows read badly when a wide desktop window stretches them edge to
/// edge, so the body keeps [width] and sits centred; narrower windows still
/// shrink it to fit. The margins beside it scroll the page's list: the mouse
/// wheel, and touch, stylus or trackpad drags (with fling) on tablets.
class SettingsContentWidth extends StatefulWidget {
  const SettingsContentWidth({super.key, required this.child});

  static const double width = 720;

  final Widget child;

  @override
  State<SettingsContentWidth> createState() => _SettingsContentWidthState();
}

class _SettingsContentWidthState extends State<SettingsContentWidth> {
  final GlobalKey _contentKey = GlobalKey();
  Drag? _drag;

  static const Set<PointerDeviceKind> _dragDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };

  /// The first vertical scroll view inside the content: the page's list.
  ScrollableState? _verticalScrollable() {
    final context = _contentKey.currentContext;
    if (context == null) return null;
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

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final scrollable = _verticalScrollable();
    if (scrollable == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final position = scrollable.position;
      final delta = (resolved as PointerScrollEvent).scrollDelta.dy;
      final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      if (target != position.pixels) position.jumpTo(target);
    });
  }

  void _onDragStart(DragStartDetails details) {
    _drag?.cancel();
    _drag = _verticalScrollable()?.position.drag(details, () => _drag = null);
  }

  void _onDragUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _onDragEnd(DragEndDetails details) {
    _drag?.end(details);
    _drag = null;
  }

  void _onDragCancel() {
    _drag?.cancel();
    _drag = null;
  }

  @override
  void dispose() {
    _drag?.cancel();
    super.dispose();
  }

  Widget _margin() {
    return Expanded(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _onPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          supportedDevices: _dragDevices,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onVerticalDragCancel: _onDragCancel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= SettingsContentWidth.width) return content;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _margin(),
            SizedBox(width: SettingsContentWidth.width, child: content),
            _margin(),
          ],
        );
      },
    );
  }
}
