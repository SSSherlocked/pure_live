import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/domains/live/presentation/playback/states/ui_state.dart';
import 'package:pure_live/core/player/core/portrait_stream_support.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/danmaku_tab.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/live_play_video.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/picture_cover.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/live_play_header.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/resolution_selector/resolutions_row.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/portrait_fullscreen_interaction.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';

enum LivePlayNormalLayoutKind { portraitStack, desktopSplit }

/// The room page follows the app layout: stacked in the phone layout,
/// side by side in the wide one.
LivePlayNormalLayoutKind resolveLivePlayNormalLayout(AppLayout layout) {
  return layout.wide ? LivePlayNormalLayoutKind.desktopSplit : LivePlayNormalLayoutKind.portraitStack;
}

/// Stable normal-room composition shared by production and widget tests.
///
/// The video, quality selector and danmaku list must remain simultaneously
/// visible on a phone. Hiding them behind a full-surface flip/drawer makes a
/// normal room indistinguishable from fullscreen and leaves no discoverable
/// interaction surface.
class LivePlayNormalLayout extends StatelessWidget {
  const LivePlayNormalLayout({
    super.key,
    required this.video,
    this.desktopVideo,
    required this.resolution,
    required this.danmaku,
    this.showPanel = true,
    this.isPortraitSource = false,
    this.sourceAspectRatio = 16 / 9,
    this.adaptivePortraitHeight = false,
    this.portraitLayoutMode = PortraitLayoutMode.balanced,
    this.onEnterLandscapeFullscreen,
    this.onEnterPortraitFullscreen,
    this.panelWidth,
    this.onPanelResized,
  });

  final Widget video;

  /// The video for the desktop split, which fills its area; falls back to [video].
  final Widget? desktopVideo;
  final Widget resolution;
  final Widget danmaku;
  final bool showPanel;
  final bool isPortraitSource;
  final double sourceAspectRatio;
  final bool adaptivePortraitHeight;
  final PortraitLayoutMode portraitLayoutMode;
  final VoidCallback? onEnterLandscapeFullscreen;
  final VoidCallback? onEnterPortraitFullscreen;

  /// The side panel's width and where a drag of its edge reports a new one.
  /// Left null, both are the 侧栏宽度 setting.
  final double? panelWidth;
  final ValueChanged<double>? onPanelResized;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!showPanel) {
          return Align(
            key: const ValueKey('live-play-video-only-layout'),
            alignment: Alignment.topCenter,
            child: video,
          );
        }
        if (resolveLivePlayNormalLayout(AppLayout.of(context)) == LivePlayNormalLayoutKind.portraitStack) {
          final useAdaptivePortraitFrame =
              isPortraitSource && adaptivePortraitHeight && portraitLayoutMode != PortraitLayoutMode.compatibility;
          if (useAdaptivePortraitFrame) {
            return PortraitLiveRoomLayout(
              video: video,
              resolution: resolution,
              danmaku: danmaku,
              mode: portraitLayoutMode,
              onEnterLandscapeFullscreen: onEnterLandscapeFullscreen,
              onEnterPortraitFullscreen: onEnterPortraitFullscreen,
            );
          }
          return Column(
            key: const ValueKey('live-play-portrait-stack'),
            children: [
              video,
              resolution,
              const Divider(height: 1),
              Expanded(
                key: const ValueKey('live-play-portrait-danmaku'),
                child: ColoredBox(color: Theme.of(context).colorScheme.surface, child: danmaku),
              ),
            ],
          );
        }

        Widget split(double preferredWidth, {ValueChanged<double>? onResized}) {
          return _LivePlayDesktopSplit(
            preferredWidth: preferredWidth,
            availableWidth: constraints.maxWidth,
            onResized: onResized,
            video: desktopVideo ?? video,
            panel: Column(
              children: [
                resolution,
                const Divider(height: 1),
                Expanded(child: danmaku),
              ],
            ),
          );
        }

        if (panelWidth case final width?) return split(width, onResized: onPanelResized);
        if (!Get.isRegistered<ThemeSettingsController>()) return split(LivePanelWidth.defaultValue);
        // Dragging the panel's edge writes the same setting as 主题 › 侧栏宽度.
        return Obx(
          () => split(
            SettingsService.to.theme.livePanelWidth.v,
            onResized: (width) => SettingsService.to.theme.livePanelWidth.v = width,
          ),
        );
      },
    );
  }
}

/// The wide layout: the video beside the side panel, whose inner edge can be
/// dragged to resize it.
///
/// The width follows the pointer locally while dragging and is written back
/// through [onResized] once, when the drag ends, so a drag is one settings
/// write rather than one per frame.
class _LivePlayDesktopSplit extends StatefulWidget {
  const _LivePlayDesktopSplit({
    required this.preferredWidth,
    required this.availableWidth,
    required this.video,
    required this.panel,
    this.onResized,
  });

  final double preferredWidth;
  final double availableWidth;
  final Widget video;
  final Widget panel;
  final ValueChanged<double>? onResized;

  @override
  State<_LivePlayDesktopSplit> createState() => _LivePlayDesktopSplitState();
}

class _LivePlayDesktopSplitState extends State<_LivePlayDesktopSplit> {
  double? _dragWidth;
  bool _hovered = false;

  double get _width => LivePanelWidth.resolve(_dragWidth ?? widget.preferredWidth, widget.availableWidth);

  void _onDragUpdate(DragUpdateDetails details) {
    // The handle is on the panel's left edge: moving left widens it.
    setState(() => _dragWidth = _width - details.delta.dx);
  }

  void _onDragEnd([DragEndDetails? _]) {
    final dragged = _dragWidth;
    if (dragged == null) return;
    final width = _width.roundToDouble();
    setState(() => _dragWidth = null);
    if (dragged != widget.preferredWidth) widget.onResized?.call(LivePanelWidth.normalize(width));
  }

  @override
  Widget build(BuildContext context) {
    final resizable = widget.onResized != null;
    final colors = Theme.of(context).colorScheme;
    final active = _hovered || _dragWidth != null;
    // Wider for a finger than for a mouse.
    final handleWidth = AppLayout.of(context).touch ? 14.0 : 8.0;
    final split = Row(
      children: [
        // The player fills its area - title and controls follow the window on
        // both axes - while the picture inside keeps its ratio, centred and as
        // large as fits, letterboxed in black or page colour.
        Expanded(key: const ValueKey('live-play-desktop-video'), child: widget.video),
        SizedBox(key: const ValueKey('live-play-desktop-panel'), width: _width, child: widget.panel),
      ],
    );
    if (!resizable) return KeyedSubtree(key: const ValueKey('live-play-desktop-split'), child: split);
    // The handle lies over the seam and takes no width: nothing is drawn
    // there until the pointer is on it or it is being dragged.
    return Stack(
      key: const ValueKey('live-play-desktop-split'),
      children: [
        Positioned.fill(child: split),
        Positioned(
          top: 0,
          bottom: 0,
          right: _width - handleWidth / 2,
          width: handleWidth,
          child: MouseRegion(
            key: const ValueKey('live-play-panel-resize-handle'),
            cursor: SystemMouseCursors.resizeLeftRight,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Semantics(
              label: i18n('live_panel_width'),
              value: '${_width.round()}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragEnd,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: active ? 3 : 0,
                    color: active ? colors.primary : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Portrait programme presentation for a phone room.
///
/// The video owns the full available canvas while a three-stop interaction
/// sheet overlays its lower edge. Users can reveal more danmaku without
/// throwing away the tall video area, and the drag handle is isolated from the
/// list's own scroll recognizer.
class PortraitLiveRoomLayout extends StatefulWidget {
  const PortraitLiveRoomLayout({
    super.key,
    required this.video,
    required this.resolution,
    required this.danmaku,
    required this.mode,
    this.onEnterLandscapeFullscreen,
    this.onEnterPortraitFullscreen,
  });

  final Widget video;
  final Widget resolution;
  final Widget danmaku;
  final PortraitLayoutMode mode;
  final VoidCallback? onEnterLandscapeFullscreen;
  final VoidCallback? onEnterPortraitFullscreen;

  @override
  State<PortraitLiveRoomLayout> createState() => _PortraitLiveRoomLayoutState();
}

class _PortraitLiveRoomLayoutState extends State<PortraitLiveRoomLayout> {
  double? _panelHeight;
  double _dismissOffset = 0;
  bool _settling = false;
  bool _entryPending = false;

  @override
  void didUpdateWidget(covariant PortraitLiveRoomLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        (oldWidget.onEnterPortraitFullscreen != null && widget.onEnterPortraitFullscreen == null)) {
      _panelHeight = null;
      _dismissOffset = 0;
      _entryPending = false;
    }
  }

  void _updatePanelDrag(DragUpdateDetails details, double current, double minimum, double maximum) {
    if (_entryPending) return;
    final delta = details.delta.dy;
    if (delta == 0) return;
    setState(() {
      _settling = false;
      final panelHeight = (_panelHeight ?? current).clamp(minimum, maximum).toDouble();
      if (delta > 0) {
        final collapsible = (panelHeight - minimum).clamp(0.0, double.infinity).toDouble();
        final collapseDelta = delta.clamp(0.0, collapsible).toDouble();
        _panelHeight = panelHeight - collapseDelta;
        final remaining = delta - collapseDelta;
        if (widget.onEnterPortraitFullscreen != null && remaining > 0) {
          // Leave a final animated travel segment for the fullscreen request.
          // If dragging reaches the animation target, AnimatedSlide has no
          // transition to finish and its onEnd callback never fires.
          _dismissOffset = (_dismissOffset + remaining).clamp(0.0, panelHeight).toDouble();
        }
        return;
      }

      var upward = -delta;
      final revealDelta = upward.clamp(0.0, _dismissOffset).toDouble();
      _dismissOffset -= revealDelta;
      upward -= revealDelta;
      if (upward > 0) {
        _panelHeight = (panelHeight + upward).clamp(minimum, maximum).toDouble();
      }
    });
  }

  void _finishPanelDrag(DragEndDetails details, double current, double minimum, double middle, double maximum) {
    if (_entryPending) return;
    final panelHeight = (_panelHeight ?? current).clamp(minimum, maximum).toDouble();
    final disposition = resolvePortraitPanelDragEnd(
      entryEnabled: widget.onEnterPortraitFullscreen != null,
      dismissOffset: _dismissOffset,
      panelHeight: panelHeight,
      velocity: details.primaryVelocity ?? 0,
    );
    if (disposition == PortraitPanelDragDisposition.enterFullscreen) {
      _requestPortraitFullscreen(panelHeight);
      return;
    }

    final dragEndHeight = panelHeight;
    final stops = <double>[minimum, middle, maximum];
    stops.sort((a, b) => (a - dragEndHeight).abs().compareTo((b - dragEndHeight).abs()));
    setState(() {
      _settling = true;
      _dismissOffset = 0;
      _panelHeight = stops.first;
    });
  }

  void _requestPortraitFullscreen(double panelHeight) {
    if (_entryPending || widget.onEnterPortraitFullscreen == null) return;
    setState(() {
      _entryPending = true;
      _settling = true;
      _dismissOffset = panelHeight + 36;
    });
  }

  void _settlePanelHeight(double panelHeight) {
    if (_entryPending) return;
    setState(() {
      _settling = true;
      _dismissOffset = 0;
      _panelHeight = panelHeight;
    });
  }

  void _completePanelAnimation() {
    if (!_entryPending || !mounted) return;
    // The animation, not an independent timer, owns the request. A changed
    // mode/disabled action clears the pending state in didUpdateWidget.
    _entryPending = false;
    try {
      widget.onEnterPortraitFullscreen?.call();
    } finally {
      // The controller may decline entry after its current-source check.
      // If this layout remains mounted, restore a usable sheet. Accepted
      // navigation replaces this layout on the same next build.
      if (mounted) {
        setState(() {
          _settling = true;
          _dismissOffset = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final range = portraitPanelRange(constraints.maxHeight, widget.mode);
        final current = (_panelHeight ?? range.initial).clamp(range.minimum, range.maximum).toDouble();
        return Stack(
          key: const ValueKey('live-play-portrait-stack'),
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ColoredBox(
                key: const ValueKey('live-play-adaptive-video-frame'),
                color: Colors.black,
                child: RepaintBoundary(child: widget.video),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: current,
              child: AnimatedSlide(
                offset: Offset(0, current <= 0 ? 0 : (_dismissOffset / current).clamp(0.0, 1.2).toDouble()),
                duration: _settling ? const Duration(milliseconds: 180) : Duration.zero,
                curve: Curves.easeOutCubic,
                onEnd: _completePanelAnimation,
                child: Material(
                  key: const ValueKey('live-play-portrait-sheet'),
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    key: const ValueKey('live-play-portrait-sheet-scroll'),
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      // Keep controls and the input usable when the keyboard,
                      // split screen or PiP animation reduces the room bounds.
                      // This wrapper stays mounted even when no scrolling is
                      // needed, preserving input focus and the video sibling.
                      height: current.clamp(240.0, double.infinity),
                      child: Column(
                        children: [
                          Semantics(
                            label: i18n('portrait_panel_resize'),
                            value: '${current.round()} px',
                            hint: i18n('portrait_panel_resize_hint'),
                            increasedValue: current < range.maximum
                                ? '${(current < range.middle ? range.middle : range.maximum).round()} px'
                                : null,
                            decreasedValue: current > range.minimum
                                ? '${(current > range.middle ? range.middle : range.minimum).round()} px'
                                : widget.onEnterPortraitFullscreen == null
                                ? null
                                : i18n('portrait_fullscreen_enter_hint'),
                            onTap: widget.onEnterPortraitFullscreen == null
                                ? null
                                : () => _requestPortraitFullscreen(current),
                            onIncrease: current < range.maximum
                                ? () => _settlePanelHeight(current < range.middle ? range.middle : range.maximum)
                                : null,
                            onDecrease: current > range.minimum
                                ? () => _settlePanelHeight(current > range.middle ? range.middle : range.minimum)
                                : widget.onEnterPortraitFullscreen == null
                                ? null
                                : () => _requestPortraitFullscreen(current),
                            child: GestureDetector(
                              key: const ValueKey('live-play-portrait-sheet-handle'),
                              behavior: HitTestBehavior.opaque,
                              dragStartBehavior: DragStartBehavior.down,
                              onTap: widget.onEnterPortraitFullscreen == null
                                  ? null
                                  : () => _requestPortraitFullscreen(current),
                              onVerticalDragUpdate: (details) =>
                                  _updatePanelDrag(details, current, range.minimum, range.maximum),
                              onVerticalDragEnd: (details) =>
                                  _finishPanelDrag(details, current, range.minimum, range.middle, range.maximum),
                              onVerticalDragCancel: () {
                                setState(() {
                                  _settling = true;
                                  _dismissOffset = 0;
                                });
                              },
                              child: SizedBox(
                                height: kMinInteractiveDimension,
                                child: Center(
                                  child: widget.onEnterPortraitFullscreen == null
                                      ? Container(
                                          width: 38,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.30),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 20,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                i18n('portrait_fullscreen_enter_hint'),
                                                key: const ValueKey('portrait-fullscreen-enter-hint'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppText.of(context).secondary.copyWith(color: Theme.of(context).colorScheme.primary,
                                                  fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                          widget.resolution,
                          const Divider(height: 1),
                          Expanded(key: const ValueKey('live-play-portrait-danmaku'), child: widget.danmaku),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onEnterLandscapeFullscreen != null && constraints.maxWidth >= 72 && constraints.maxHeight >= 72)
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _PortraitFullscreenActionLayout(bottom: current + 12 - _dismissOffset),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Tooltip(
                      message: i18nOr('enter_landscape_fullscreen', '横屏全屏'),
                      child: InkWell(
                        key: const ValueKey('portrait-landscape-fullscreen'),
                        onTap: widget.onEnterLandscapeFullscreen,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: kMinInteractiveDimension,
                            minHeight: kMinInteractiveDimension,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 20),
                                if (constraints.maxWidth >= 160) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      i18nOr('enter_landscape_fullscreen', '横屏全屏'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PortraitFullscreenActionLayout extends SingleChildLayoutDelegate {
  const _PortraitFullscreenActionLayout({required this.bottom});

  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size((constraints.maxWidth - 24).clamp(48.0, 180.0), constraints.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width - 12).clamp(0.0, size.width - childSize.width),
    // Anchor using the measured height, not a fixed icon-button estimate: large
    // accessibility text must stay inside the viewport during a PiP resize.
    (size.height - bottom - childSize.height).clamp(0.0, size.height - childSize.height),
  );

  @override
  bool shouldRelayout(_PortraitFullscreenActionLayout oldDelegate) => bottom != oldDelegate.bottom;
}

@visibleForTesting
({double minimum, double middle, double maximum, double initial}) portraitPanelRange(
  double availableHeight,
  PortraitLayoutMode mode,
) {
  final height = availableHeight.isFinite ? availableHeight.clamp(0.0, double.infinity).toDouble() : 0.0;
  final minimum = (height * 0.27).clamp(190.0, 250.0).clamp(0.0, height).toDouble();
  // Preserve 120 dp of video whenever the controls also fit. Transient small
  // bounds must never pass an inverted range to clamp.
  final maximumAllowed = (height - 120).clamp(minimum, height).toDouble();
  final maximum = (height * 0.68).clamp(minimum, maximumAllowed).toDouble();
  final middle = (height * 0.44).clamp(minimum, maximum).toDouble();
  final initial = mode == PortraitLayoutMode.immersive ? minimum : middle;
  return (minimum: minimum, middle: middle, maximum: maximum, initial: initial);
}

class LivePlayContent extends StatelessWidget {
  const LivePlayContent({super.key, required this.controller, required this.isInPip, required this.mode});

  final LivePlayController controller;
  final bool isInPip;
  final VideoMode mode;

  @override
  Widget build(BuildContext context) {
    final manager = GlobalPlayerService.instance.player;

    if (isInPip) {
      return Theme(
        data: ThemeData.dark(),
        child: Container(
          key: const ValueKey('pip'),
          color: Colors.transparent,
          child: manager.buildPiPOverlay(
            pictureCover: Obx(
              () =>
                  pictureCoverFor(
                    audioOnly: manager.isAudioOnlyMode,
                    dummyVideo: manager.isDummyVideo.value,
                    room: controller.state.value.room.detail,
                  ) ??
                  const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    if (mode == VideoMode.normal) {
      return ColoredBox(
        key: const ValueKey('normal'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _buildNormalView(context),
      );
    }

    return Obx(() {
      final settings = SettingsService.to.player;
      manager.videoPresentationRevision.value;
      final isPortrait = manager.isVerticalVideo.value && settings.enablePortraitStreamAdaptation.v;
      Widget presentation;
      if (!isPortrait) {
        presentation = Container(
          key: const ValueKey('fullscreen-standard-video'),
          color: Colors.black,
          child: LivePlayVideo(controller: controller, expandToParent: true),
        );
      } else {
        final detail = controller.state.value.room.detail;
        final fullscreenDisplayMode = mode == VideoMode.portraitFullscreen
            ? settings.portraitFullscreenDisplayMode
            : PortraitFullscreenDisplayMode.ambient;
        final cover = resolvePortraitFullscreenBackgroundUrl(
          detailCover: detail?.cover,
          roomCover: controller.room.cover,
          detailAvatar: detail?.avatar,
          roomAvatar: controller.room.avatar,
        );
        presentation = PortraitFullscreenPresentation(
          coverUrl: cover,
          mode: fullscreenDisplayMode,
          child: LivePlayVideo(
            controller: controller,
            expandToParent: true,
            transparentSurface: true,
            videoViewportAspectRatio: manager.currentPresentationAspectRatio,
            portraitFullscreenDisplayMode: mode == VideoMode.portraitFullscreen ? fullscreenDisplayMode : null,
          ),
        );
      }
      if (mode != VideoMode.portraitFullscreen) return presentation;
      return Stack(
        key: const ValueKey('portrait-panel-fullscreen'),
        fit: StackFit.expand,
        children: [presentation, const PortraitFullscreenEntryHint()],
      );
    });
  }

  Widget _buildNormalView(BuildContext context) {
    final compactHeader = AppLayout.of(context).phone;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: LivePlayHeader(controller: controller, compactHeader: compactHeader),
      body: SafeArea(
        child: Obx(() {
          final manager = GlobalPlayerService.instance.player;
          // Rebuild when the stream's picture size is known or changes, so
          // sourceAspectRatio below stays current.
          manager.videoPresentationRevision.value;
          final settings = SettingsService.to.player;
          final isPortrait = manager.isVerticalVideo.value;
          final useAdaptivePortraitFrame =
              AppLayout.of(context).phone &&
              isPortrait &&
              settings.enablePortraitStreamAdaptation.v &&
              settings.portraitAdaptiveHeight.v &&
              settings.portraitLayoutMode != PortraitLayoutMode.compatibility;
          return LivePlayNormalLayout(
            video: LivePlayVideo(controller: controller, expandToParent: useAdaptivePortraitFrame),
            desktopVideo: LivePlayVideo(
              controller: controller,
              expandToParent: true,
              pageSurface: settings.letterboxPageColor.v,
            ),
            resolution: ResolutionsRow(controller: controller),
            danmaku: _buildDanmaku(),
            showPanel: controller.site != Sites.iptvSite,
            isPortraitSource: isPortrait,
            sourceAspectRatio: manager.currentPresentationAspectRatio,
            adaptivePortraitHeight: settings.enablePortraitStreamAdaptation.v && settings.portraitAdaptiveHeight.v,
            portraitLayoutMode: settings.portraitLayoutMode,
            onEnterLandscapeFullscreen: () {
              final videoController = controller.state.value.player.videoController;
              if (videoController != null) unawaited(videoController.enterLandscapeFullScreen());
            },
            onEnterPortraitFullscreen: PlatformUtils.isAndroid
                ? () {
                    final videoController = controller.state.value.player.videoController;
                    if (videoController != null) unawaited(videoController.enterPortraitFullScreen());
                  }
                : null,
          );
        }),
      ),
    );
  }

  Widget _buildDanmaku() {
    return Obx(() {
      // The side panel sits above the room's loading cycle: switching or
      // reloading a room never removes it (its sections show their own
      // loading state), so 关注 stays usable throughout.
      // Read the observables first: an Obx must always subscribe to one.
      final player = GlobalPlayerService.instance.player;
      final fullscreen = player.isSystemFullscreen.value || player.isWindowFullscreen.value;
      if (fullscreen || controller.site == Sites.iptvSite) {
        return const SizedBox.shrink();
      }
      return const DanmakuTabView(key: ValueKey('live-room-side-panel'));
    });
  }
}

@visibleForTesting
String resolvePortraitFullscreenBackgroundUrl({
  String? detailCover,
  String? roomCover,
  String? detailAvatar,
  String? roomAvatar,
}) {
  for (final value in [detailCover, roomCover, detailAvatar, roomAvatar]) {
    final candidate = value?.trim() ?? '';
    if (candidate.isNotEmpty) return candidate;
  }
  return '';
}

/// Fullscreen presentation for a portrait programme on a landscape display.
/// Controls still own the complete screen, while only the video texture is
/// fitted to its trusted portrait geometry. A dim cached cover replaces harsh
/// empty side columns without duplicating or continuously sampling video.
class PortraitFullscreenPresentation extends StatelessWidget {
  const PortraitFullscreenPresentation({
    super.key,
    required this.coverUrl,
    required this.child,
    this.mode = PortraitFullscreenDisplayMode.ambient,
  });

  final String coverUrl;
  final Widget child;
  final PortraitFullscreenDisplayMode mode;

  @override
  Widget build(BuildContext context) {
    final showAmbient = mode == PortraitFullscreenDisplayMode.ambient || mode == PortraitFullscreenDisplayMode.balanced;
    return ColoredBox(
      key: const ValueKey('fullscreen-portrait-presentation'),
      color: Colors.black,
      child: Stack(
        key: ValueKey('fullscreen-portrait-mode-${mode.name}'),
        fit: StackFit.expand,
        children: [
          if (showAmbient) ...[
            const DecoratedBox(
              key: ValueKey('fullscreen-portrait-ambient-fallback'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF342B3A), Color(0xFF171B27), Color(0xFF2A202B)],
                ),
              ),
            ),
            if (coverUrl.isNotEmpty)
              ImageFiltered(
                key: const ValueKey('fullscreen-portrait-ambient-image'),
                imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.mirror),
                child: Transform.scale(
                  scale: 1.14,
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    filterQuality: FilterQuality.low,
                    placeholder: (_, _) => const SizedBox.expand(),
                    errorWidget: (_, _, _) => const SizedBox.expand(),
                  ),
                ),
              ),
            const ColoredBox(key: ValueKey('fullscreen-portrait-ambient-veil'), color: Color(0x26000000)),
          ],
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}
