import 'dart:async';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/image_cache_manager.dart';
import 'package:pure_live/core/widgets/common_avatar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/core/platform/share_command_handler.dart';
import 'package:pure_live/core/utils/event_bus.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card_layout.dart';

class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    this.dense = false,
    this.statusPending = false,
    this.statusPendingLabel,
    this.showDelete = false,
    this.onDelete,
    this.deleteTooltip,
    this.settingsViewport,
  });
  final LiveRoom room;
  final bool dense;
  final bool statusPending;
  final String? statusPendingLabel;
  final bool showDelete;
  final VoidCallback? onDelete;
  final String? deleteTooltip;
  final RoomCardViewport? settingsViewport;
  Widget _buildCover(BuildContext context, bool isDark) {
    final coverUrl = normalizeNetworkImageUrl(room.cover);

    if (coverUrl.isEmpty) {
      return _coverFallback(context, isDark);
    }

    // Keep a stable image element and an encoded disk entry. The previous
    // global epoch rebuilt every visible Image.network at once, discarded the
    // old pixels and forced independent network/decode progress callbacks for
    // the full grid. That was the main source of mixed placeholders, flashes
    // and CPU spikes during refresh and tab switching.
    return Obx(() {
      final epoch = SettingsService.to.cache.imageCacheEpoch.value;
      return LayoutBuilder(
        builder: (context, constraints) {
          final logicalWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width / 2;
          final cacheWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(240, 720).toInt();

          return CachedNetworkImage(
            imageUrl: coverUrl,
            cacheKey: epoch == 0 ? coverUrl : '$coverUrl#$epoch',
            httpHeaders: networkImageHeaders(coverUrl),
            cacheManager: AppImageCacheManager.instance,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            memCacheWidth: cacheWidth,
            // maxWidthDiskCache: 720,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            placeholder: (context, _) => _coverPlaceholder(context, isDark),
            errorWidget: (context, _, _) => _coverFallback(context, isDark),
          );
        },
      );
    });
  }

  Widget _coverPlaceholder(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
      child: Center(
        // Do not create one infinite AnimationController per loading card. A
        // page of failed/slow covers used to repaint the complete grid at the
        // monitor refresh rate and could saturate Android CPU during startup.
        child: Icon(Icons.live_tv_rounded, size: 24, color: isDark ? Colors.white24 : Colors.black12),
      ),
    );
  }

  Widget _coverFallback(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
      child: AppStatusView(type: AppStatusType.error, title: "", subtitle: "", isMini: true),
    );
  }

  void onTap(BuildContext context) {
    unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room));
  }

  void onLongPress(BuildContext context) {
    final theme = Theme.of(context);

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(Sites.logoForId(room.normalizedPlatformId), width: 28, height: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  room.nick ?? '',
                  style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              IconButton(
                tooltip: i18n('share'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(RemixIcons.share_forward_line, size: 20, color: theme.colorScheme.primary),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  ShareCommandHandler.instance.onShareRoomPressed(room);
                },
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.04), width: 0.8),
                  ),
                  child: Text(
                    room.title ?? '',
                    style: AppTextStyles.t14.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    i18n('room_id_label', args: {"id": ?room.roomId}),
                    style: AppTextStyles.t11.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FollowButton(room: room),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                i18n('close'),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceMetric({required bool dense, bool inline = false}) {
    return Obx(() {
      final app = SettingsService.to.app;
      final preferReal = app.preferRealOnlineCounts.v;
      final platformEnabled = app.isRealOnlineEnabledFor(room.platform);
      final type = room.audienceType(preferRealOnline: preferReal, platformEnabled: platformEnabled);
      final value = room.audienceValue(preferRealOnline: preferReal, platformEnabled: platformEnabled);
      final labelKey = switch (type) {
        AudienceMetricType.popularity => 'audience_popularity',
        AudienceMetricType.onlineViewers => 'audience_online',
        AudienceMetricType.totalViewers => 'audience_total',
        AudienceMetricType.followers => 'audience_followers',
        AudienceMetricType.unknown => 'audience_count',
      };
      final displayValue = value.isEmpty ? i18n('audience_waiting') : readableCount(value);
      final icon = switch (type) {
        AudienceMetricType.onlineViewers => Icons.people_alt_rounded,
        AudienceMetricType.followers => Icons.favorite_rounded,
        AudienceMetricType.totalViewers => Icons.visibility_rounded,
        _ => Icons.whatshot_rounded,
      };
      if (inline) {
        final color = Colors.orange.shade700;
        return Semantics(
          key: const ValueKey('room-card-audience'),
          label: '${i18n(labelKey)} $displayValue',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: dense ? 12 : 14, color: color),
                const SizedBox(width: 2),
                Text(
                  displayValue,
                  style: (dense ? AppTextStyles.t11 : AppTextStyles.t12).copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return CoverMetricBadge(
        key: const ValueKey('cover-audience-metric'),
        icon: icon,
        value: displayValue,
        semanticLabel: '${i18n(labelKey)} $displayValue',
        dense: dense,
      );
    });
  }

  Widget _buildCoverPlatformBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 8, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        i18n('site_${room.platform ?? ''}'),
        maxLines: 1,
        style: (dense ? AppTextStyles.t11 : AppTextStyles.t12).copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// The platform tag of the compact row, styled like the 关注 panel's tag.
  Widget _buildCompactPlatformBadge(bool isDark) {
    final colors = Get.theme.colorScheme;
    return Container(
      key: const ValueKey('room-card-platform-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outline.withValues(alpha: .2), width: .5),
      ),
      child: Text(
        i18n('site_${room.platform ?? ''}'),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: AppTextStyles.t11.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget? _buildCompactTrailing({
    required RoomCardAppearance config,
    required bool isDark,
    required bool showAutomaticPlatformBadge,
    required double availableWidth,
    required double textScale,
  }) {
    final minimumMetricWidth = showDelete ? 360.0 : (dense ? 260.0 : 300.0);
    final canShowMetrics = availableWidth >= minimumMetricWidth && textScale < 1.8;
    final children = <Widget>[];

    if (canShowMetrics && (config.showPlatformBadge || showAutomaticPlatformBadge)) {
      children.add(_buildCompactPlatformBadge(isDark));
    }
    if (canShowMetrics) {
      if (statusPending) {
        children.add(
          CoverMetricBadge(
            icon: Icons.sync_rounded,
            value: statusPendingLabel ?? i18n('favorite_status_verifying'),
            semanticLabel: statusPendingLabel ?? i18n('favorite_status_verifying'),
            dense: true,
          ),
        );
      } else if (config.showAudience && room.isLiveNow) {
        children.add(_buildAudienceMetric(dense: true, inline: true));
      } else if (config.showReplayBadge && room.isRecord == true) {
        children.add(
          CountChip(icon: Icons.videocam_rounded, count: i18n('replay'), dense: true, color: Get.theme.primaryColor),
        );
      }
    } else if (statusPending) {
      children.add(
        Tooltip(
          message: statusPendingLabel ?? i18n('favorite_status_verifying'),
          child: const Icon(Icons.sync_rounded, size: 18),
        ),
      );
    }

    // Platform tag above, heat below, like the 关注 panel's rows.
    final metrics = List<Widget>.of(children);
    children
      ..clear()
      ..addAll([
        if (metrics.isNotEmpty)
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) const SizedBox(height: 3),
                metrics[index],
              ],
            ],
          ),
      ]);

    if (showDelete) {
      children.add(
        IconButton(
          key: const ValueKey('room-card-delete'),
          tooltip: deleteTooltip ?? i18n('delete'),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(RemixIcons.delete_bin_line, size: dense ? 17 : 19),
        ),
      );
    }
    if (children.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 4),
            children[index],
          ],
        ],
      ),
    );
  }

  Widget _buildCompactLayout({
    required BuildContext context,
    required RoomCardAppearance config,
    required bool isDark,
    required bool showAutomaticPlatformBadge,
    required double availableWidth,
    required double textScale,
  }) {
    final height = RoomCardLayoutMetrics.compactHeight(
      appearance: config,
      dense: dense,
      hasAction: showDelete,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final trailing = _buildCompactTrailing(
      config: config,
      isDark: isDark,
      showAutomaticPlatformBadge: showAutomaticPlatformBadge,
      availableWidth: availableWidth,
      textScale: textScale,
    );

    return SizedBox(
      key: const ValueKey('room-card-compact-layout'),
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 8 : 10),
        child: Row(
          children: [
            if (config.showAvatar) ...[
              KeyedSubtree(
                key: const ValueKey('room-card-avatar'),
                child: CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, dense: dense),
              ),
              SizedBox(width: dense ? 8 : 10),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Like the 关注 panel: streamer first, room title below.
                  if (config.showAnchorName) ...[
                    Text(
                      room.nick ?? '',
                      key: const ValueKey('room-card-anchor-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (dense ? AppTextStyles.t13 : AppTextStyles.t15).copyWith(
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    SizedBox(height: dense ? 2 : 3),
                  ],
                  Text(
                    room.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (config.showAnchorName
                            ? (dense ? AppTextStyles.t12 : AppTextStyles.t13)
                            : (dense ? AppTextStyles.t13 : AppTextStyles.t15))
                        .copyWith(
                          height: 1.2,
                          fontWeight: config.showAnchorName ? FontWeight.w500 : FontWeight.w700,
                          color: config.showAnchorName
                              ? (isDark ? Colors.grey[400] : Colors.grey[700])
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // GridView already inserts a RepaintBoundary around every child. Avoid a
    // second composited layer per card and keep the cover clip lightweight.
    return Obx(() {
      final config = SettingsService.to.roomCard.resolve(viewport: settingsViewport);
      final radius = config.cornerRadius;

      return LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final showAutomaticPlatformBadge =
              config.automaticPlatformBadge && !dense && constraints.maxWidth >= 280 && textScale < 1.8;
          final compact = config.layout == RoomCardLayout.compact;
          final colors = Theme.of(context).colorScheme;
          return Card(
            key: const ValueKey('room-card-surface'),
            margin: EdgeInsets.zero,
            elevation: 0,
            // The compact row matches the 关注 panel: a bordered rounded tile.
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: compact ? BorderSide(color: colors.outlineVariant.withValues(alpha: .55)) : BorderSide.none,
            ),
            color: compact ? colors.surfaceContainerLow : (isDark ? Colors.grey[900] : Colors.white),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: () => onTap(context),
              onLongPress: () => onLongPress(context),
              onSecondaryTap: () => onLongPress(context),
              child: config.layout == RoomCardLayout.compact
                  ? _buildCompactLayout(
                      context: context,
                      config: config,
                      isDark: isDark,
                      showAutomaticPlatformBadge: showAutomaticPlatformBadge,
                      availableWidth: constraints.maxWidth,
                      textScale: textScale,
                    )
                  : Column(
                      key: const ValueKey('room-card-cover-layout'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(radius),
                                child: ColoredBox(
                                  color: isDark ? Colors.grey[850]! : Colors.grey.shade100,
                                  child: _buildCover(context, isDark),
                                ),
                              ),
                            ),
                            // Platform (top-left) and heat (top-right): each on its
                            // own translucent black pill.
                            if (config.showPlatformBadge || showAutomaticPlatformBadge)
                              Positioned(
                                key: const ValueKey('room-card-platform-badge'),
                                left: 8,
                                top: 8,
                                child: _buildCoverPlatformBadge(),
                              ),
                            if (config.showAudience && room.isLiveNow && !statusPending)
                              Positioned(
                                right: showDelete ? (dense ? 44 : 48) : 8,
                                top: 8,
                                child: _buildAudienceMetric(dense: dense),
                              ),
                            if (config.showReplayBadge && room.isRecord == true && !room.isLiveNow)
                              Positioned(
                                key: const ValueKey('room-card-replay-badge'),
                                right: showDelete ? (dense ? 44 : 48) : 8,
                                top: 8,
                                child: CountChip(
                                  icon: Icons.videocam_rounded,
                                  count: i18n("replay"),
                                  dense: dense,
                                  color: Get.theme.primaryColor,
                                ),
                              ),
                            // Title overlaid on the cover over a translucent black band.
                            Positioned(
                              key: const ValueKey('room-card-title-overlay'),
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: ClipRRect(
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
                                  child: Text(
                                    room.title ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: (dense ? AppTextStyles.t12 : AppTextStyles.t14).copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (statusPending)
                              Positioned(
                                left: 8,
                                top: 8,
                                child: CoverMetricBadge(
                                  icon: Icons.sync_rounded,
                                  value: statusPendingLabel ?? i18n('favorite_status_verifying'),
                                  semanticLabel: statusPendingLabel ?? i18n('favorite_status_verifying'),
                                  dense: dense,
                                ),
                              ),
                            if (showDelete)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  key: const ValueKey('room-card-delete'),
                                  tooltip: deleteTooltip ?? i18n('delete'),
                                  onPressed: onDelete,
                                  padding: const EdgeInsets.all(10),
                                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                  icon: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(RemixIcons.delete_bin_line, color: Colors.white, size: dense ? 16 : 18),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Below the cover: avatar and streamer name, with the
                        // platform and audience on the same row.
                        Container(
                          key: const ValueKey('room-card-anchor-row'),
                          height: RoomCardLayoutMetrics.coverCaptionHeight(
                            appearance: config,
                            dense: dense,
                            textScaler: MediaQuery.textScalerOf(context),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
                          alignment: Alignment.center,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (config.showAvatar) ...[
                                KeyedSubtree(
                                  key: const ValueKey('room-card-avatar'),
                                  child: CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, dense: dense),
                                ),
                                SizedBox(width: dense ? 8 : 10),
                              ],
                              Expanded(
                                child: Text(
                                  room.nick ?? '',
                                  key: const ValueKey('room-card-anchor-name'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (dense ? AppTextStyles.t13 : AppTextStyles.t15).copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      );
    });
  }
}

class FollowButton extends StatefulWidget {
  const FollowButton({super.key, required this.room});

  final LiveRoom room;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _busy = false;

  Future<void> _toggleFavorite(bool isFavorite) async {
    if (_busy) return;
    setState(() => _busy = true);

    final favorites = FavoriteRoomController.to;
    try {
      if (!isFavorite) {
        final changed = await favorites.addRoomDurably(widget.room);
        if (changed) EventBus.instance.emit('changeFavorite', true);

        if (mounted && (changed || favorites.isFavorite(widget.room))) {
          Navigator.of(context).pop();
        }
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Text(i18n('unfollow')),
          content: Text(i18n('unfollow_message', args: {'name': widget.room.nick ?? ''})),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(i18n('confirm'))),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;

      final changed = await favorites.removeRoomDurably(widget.room);
      if (changed) EventBus.instance.emit('changeFavorite', true);
      if (!mounted) return;
      if (!favorites.isFavorite(widget.room)) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      debugPrint('Favorite room change failed: $error');
      ToastUtil.show(i18n('favorite_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final favoriteRooms = FavoriteRoomController.to.favoriteRooms.value;
      final isFavorite = favoriteRooms.any((candidate) => candidate.hasSameIdentity(widget.room));

      return FilledButton.tonal(
        onPressed: _busy ? null : () => _toggleFavorite(isFavorite),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: Text(
          isFavorite ? i18n('unfollow') : i18n('follow'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    });
  }
}

class CountChip extends StatelessWidget {
  const CountChip({super.key, required this.icon, required this.count, this.dense = false, required this.color});

  final IconData icon;
  final String count;
  final bool dense;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: const StadiumBorder(),
      color: color,
      shadowColor: Colors.transparent,

      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 4 : 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: dense ? 16 : 18),
            const SizedBox(width: 4),
            Text(
              count,
              style: (dense ? AppTextStyles.t12 : AppTextStyles.t13).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cover metric stays compact and readable without obscuring thumbnails.
/// The full metric name remains available to accessibility and hover users.
class CoverMetricBadge extends StatelessWidget {
  const CoverMetricBadge({
    super.key,
    required this.icon,
    required this.value,
    required this.semanticLabel,
    this.dense = false,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Keep the background mostly neutral so the badge works on both bright
    // and dark cover images. The theme primary color is used as the accent.
    final backgroundColor = theme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.58)
        : Colors.black.withValues(alpha: 0.48);

    final foregroundColor = Colors.white;

    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        label: semanticLabel,
        container: true,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 4 : 5),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(dense ? 10 : 12),
            border: Border.all(color: theme.primaryColor.withValues(alpha: 0.12), width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foregroundColor, size: dense ? 14 : 16),
              SizedBox(width: dense ? 4 : 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: dense ? 11 : 12,
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
