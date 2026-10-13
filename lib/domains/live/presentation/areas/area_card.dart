import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/areas/category_artwork.dart';
import 'package:pure_live/core/network/image_cache_manager.dart';
import 'package:pure_live/domains/live/presentation/areas/area_pic_mapper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/shared/platforms/cc/cc_catalog.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';

/// Side of a category icon, like Simple Live's directory.
const double areaIconSize = 40;

/// The category grid: as many cells as fit, each at most 84 px wide, an icon
/// above a one-line name. The row grows with the text scale.
SliverGridDelegate areaCardGridDelegate(BuildContext context) {
  final style = AppText.of(context).secondary;
  final line = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 12) * (style.height ?? 1.3);
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 84,
    mainAxisSpacing: 4,
    crossAxisSpacing: 4,
    mainAxisExtent: 8 + areaIconSize + 6 + line + 8,
  );
}

class AreaCard extends StatefulWidget {
  const AreaCard({super.key, required this.category});
  final LiveArea category;

  @override
  State<AreaCard> createState() => _AreaCardState();
}

class _AreaCardState extends State<AreaCard> {
  String _getFinalUrl() {
    if (widget.category.areaPic != null && widget.category.areaPic!.isNotEmpty) {
      return widget.category.areaPic!;
    }
    return AreaPicMapper.getPic(widget.category.areaName);
  }

  Widget _fallbackIcon(BuildContext context) =>
      Icon(Icons.live_tv_rounded, size: 24, color: Theme.of(context).colorScheme.onSurfaceVariant);

  Widget _buildNetworkImage(String imageUrl) {
    return Obx(() {
      final epoch = SettingsService.to.cache.imageCacheEpoch.value;
      return Builder(
        builder: (context) {
          final cacheWidth = (areaIconSize * MediaQuery.devicePixelRatioOf(context)).round();
          return CachedNetworkImage(
            cacheKey: epoch == 0 ? imageUrl : '$imageUrl#$epoch',
            imageUrl: imageUrl,
            httpHeaders: networkImageHeaders(imageUrl),
            cacheManager: AppImageCacheManager.instance,
            fit: BoxFit.cover,
            alignment: categoryArtworkAlignment(imageUrl),
            filterQuality: FilterQuality.low,
            memCacheWidth: cacheWidth,
            // maxWidthDiskCache: 512,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            placeholder: (context, url) => _fallbackIcon(context),
            errorWidget: (context, url, error) => _fallbackIcon(context),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayImageUrl = normalizeNetworkImageUrl(_getFinalUrl());
    final officialEntry = CCCatalog.isOfficialEntry(widget.category);
    final rawName = widget.category.areaName?.trim() ?? '';
    final displayName = rawName.isEmpty ? i18n('unnamed_area') : rawName;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (widget.category.platform == Sites.iptvSite) {
          var roomItem = LiveRoom(
            roomId: widget.category.areaId,
            title: widget.category.typeName,
            cover: '',
            nick: widget.category.areaName,
            watching: '',
            avatar: 'https://img95.699pic.com/xsj/0q/x6/7p.jpg%21/fw/700/watermark/url/L3hzai93YXRlcl9kZXRhaWwyLnBuZw/align/southeast',
            area: '',
            liveStatus: LiveStatus.live,
            status: true,
            platform: 'iptv',
          );
          AppNavigator.toLiveRoomDetail(liveRoom: roomItem);
        } else {
          AppNavigator.toCategoryDetail(site: Sites.of(widget.category.platform!), category: widget.category);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: areaIconSize,
                child: displayImageUrl.isNotEmpty ? _buildNetworkImage(displayImageUrl) : _fallbackIcon(context),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppText.of(context).secondary,
                  ),
                ),
                // Opens the platform's page in the browser, not a room list.
                if (officialEntry) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.open_in_new_rounded, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
