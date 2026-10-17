import 'package:flutter/material.dart';

/// A [MenuAnchor] whose open menu is closed by Back.
///
/// A menu is an overlay, not a route, so on its own Back went past it and
/// left the page (or the app) with the menu still up. While the menu is open
/// the route is held (`PopScope.canPop` false), so Back only closes the menu;
/// closed, the route pops as before.
class AppMenuAnchor extends StatefulWidget {
  const AppMenuAnchor({
    super.key,
    this.controller,
    this.style,
    this.alignmentOffset,
    this.onOpen,
    this.onClose,
    required this.menuChildren,
    this.builder,
    this.child,
  });

  final MenuController? controller;
  final MenuStyle? style;
  final Offset? alignmentOffset;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder? builder;
  final Widget? child;

  @override
  State<AppMenuAnchor> createState() => _AppMenuAnchorState();
}

class _AppMenuAnchorState extends State<AppMenuAnchor> {
  final MenuController _ownController = MenuController();
  final ValueNotifier<bool> _open = ValueNotifier(false);

  MenuController get _controller => widget.controller ?? _ownController;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _open,
      builder: (context, open, child) => PopScope<Object?>(
        canPop: !open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _controller.isOpen) _controller.close();
        },
        child: child!,
      ),
      child: MenuAnchor(
        controller: _controller,
        style: widget.style,
        alignmentOffset: widget.alignmentOffset,
        onOpen: () {
          _open.value = true;
          widget.onOpen?.call();
        },
        onClose: () {
          _open.value = false;
          widget.onClose?.call();
        },
        menuChildren: widget.menuChildren,
        builder: widget.builder,
        child: widget.child,
      ),
    );
  }
}
