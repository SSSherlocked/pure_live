import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/areas/category_artwork.dart';
import 'package:pure_live/domains/live/presentation/area_rooms/area_rooms_controller.dart';
import 'package:pure_live/core/network/image_cache_manager.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/core/widgets/keep_alive_wrapper.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card_rows.dart';

class AreasRoomPage extends StatefulWidget {
  final Site site;
  final LiveArea subCategory;

  const AreasRoomPage({super.key, required this.site, required this.subCategory});

  @override
  State<AreasRoomPage> createState() => _AreasRoomPageState();
}

class _AreasRoomPageState extends State<AreasRoomPage> {
  BasePageScrollAndStateBone<LiveRoom> get controller =>
      Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: areaRoomsControllerTag(widget.site, widget.subCategory));

  @override
  void initState() {
    super.initState();
    controller.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final rawAreaName = widget.subCategory.areaName?.trim() ?? '';
    final areaName = rawAreaName.isEmpty ? i18n('unnamed_area') : rawAreaName;
    final refreshByButton = AppLayout.of(context).refreshByButton;
    return KeepAliveWrapper(
      child: Scaffold(
        appBar: AppBar(title: Text(areaName)),
        body: BasePageView<BasePageScrollAndStateBone<LiveRoom>, LiveRoom>(
          controller: controller,
          enableRefresh: true,
          enableLoadMore: true,
          // Clears the follow-area pill (48 px tall over its own 24 px bottom
          // padding in the wide layout) and, on desktop, the refresh button
          // under it.
          wideBottomPadding: refreshByButton ? FloatingRefreshButton.clearance + 24 + 48 : 110,
          narrowBottomPadding: 85,
          emptyBuilder: (context) => EmptyView(icon: Icons.live_tv_rounded, title: i18n('no_data'), subtitle: ''),
          // The rooms in the layout chosen for 分区; the bottom stays clear
          // of the follow-area pill.
          contentBuilder: (context, list, scrollController) => LayoutBuilder(
            builder: (context, constraint) => CustomScrollView(
              controller: scrollController,
              scrollCacheExtent: ScrollCacheExtent.pixels(constraint.maxWidth > 680 ? 480 : 320),
              semanticChildCount: list.length,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [RoomCardRows(page: RoomListPage.areaRooms, width: constraint.maxWidth, rooms: list, bottomPadding: 80)],
            ),
          ),
        ),
        floatingActionButton: refreshByButton
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The pill's own bottom padding spaces it from the refresh.
                  FavoriteAreaFloatingButton(area: widget.subCategory),
                  // Desktop has no pull-to-refresh. The page's reload spinner
                  // shows the refresh; the button does not spin as well.
                  FloatingRefreshButton(
                    key: const ValueKey('area-rooms-refresh'),
                    onPressed: controller.refreshData,
                  ),
                ],
              )
            : FavoriteAreaFloatingButton(area: widget.subCategory),
      ),
    );
  }
}

class FavoriteAreaFloatingButton extends StatefulWidget {
  const FavoriteAreaFloatingButton({super.key, required this.area});

  final LiveArea area;

  @override
  State<FavoriteAreaFloatingButton> createState() => _FavoriteAreaFloatingButtonState();
}

class _FavoriteAreaFloatingButtonState extends State<FavoriteAreaFloatingButton> {
  bool _busy = false;

  LiveArea get area => widget.area;

  Future<void> _toggleFavorite({required LiveArea target, required bool isFavorite}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final favorites = FavoriteRoomController.to;
    try {
      if (!isFavorite) {
        await favorites.addAreaDurably(target);
        return;
      }

      final displayName = target.areaName?.trim().isNotEmpty == true ? target.areaName!.trim() : i18n('unnamed_area');
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(i18n('unfollow')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(i18n('unfollow_message', args: {'name': displayName})),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(i18n('cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(i18n('confirm')),
            ),
          ],
        ),
      );
      if (confirmed == true) await favorites.removeAreaDurably(target);
    } catch (error) {
      debugPrint('Favorite area change failed: $error');
      ToastUtil.show(i18n('favorite_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final rawAreaName = area.areaName?.trim() ?? '';
    final displayName = rawAreaName.isEmpty ? i18n('unnamed_area') : rawAreaName;
    final firstChar = String.fromCharCode(displayName.runes.first);
    final pictureUrl = normalizeNetworkImageUrl(area.areaPic);
    final bool hasPic = pictureUrl.isNotEmpty;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primaryContainer),
      child: ClipOval(
        child: hasPic
            ? CachedNetworkImage(
                imageUrl: pictureUrl,
                cacheKey: pictureUrl,
                cacheManager: AppImageCacheManager.instance,
                httpHeaders: networkImageHeaders(pictureUrl),
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                alignment: categoryArtworkAlignment(pictureUrl),
                memCacheWidth: 64,
                // maxWidthDiskCache: 128,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (context, _, _) {
                  return Center(
                    child: Text(
                      firstChar,
                      style: AppText.of(context).secondary.copyWith(fontWeight: FontWeight.w700).copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  firstChar,
                  style: AppText.of(context).secondary.copyWith(fontWeight: FontWeight.w700).copyWith(color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isFavorite = FavoriteRoomController.to.isFavoriteArea(area);
      final rawAreaName = area.areaName?.trim() ?? '';
      final displayName = rawAreaName.isEmpty ? i18n('unnamed_area') : rawAreaName;

      return Padding(
        padding: EdgeInsets.only(
          bottom: AppLayout.of(context).wide
              ? 24
              : (MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 12),
          right: 0,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(isFavorite ? 24 : 16),
            border: Border.all(
              color: isFavorite
                  ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isFavorite ? 24 : 16),
            child: ColoredBox(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(isFavorite ? 24 : 16),
                onTap: _busy ? null : () => _toggleFavorite(target: area, isFavorite: isFavorite),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAvatar(context),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOutCubic,
                        child: isFavorite
                            ? const SizedBox.shrink()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        i18n("follow"),
                                        style: Theme.of(context).textTheme.bodySmall
                                            ?.copyWith(color: Theme.of(context).hintColor, height: 1.1),
                                      ),
                                      const SizedBox(height: 1),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: AppLayout.of(context).wide ? 120 : 80),
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.of(context).secondary.copyWith(fontWeight: FontWeight.w700).copyWith(
                                            color: Theme.of(context).colorScheme.primary,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
