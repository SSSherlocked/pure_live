import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/common_avatar.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/button/live_play_menu_button.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/button/favorite_floating_button.dart';

class LivePlayHeader extends StatelessWidget implements PreferredSizeWidget {
  const LivePlayHeader({super.key, required this.controller, this.compactHeader = false});
  final LivePlayController controller;
  final bool compactHeader;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 0,
      title: _buildTitle(context),
      actions: [
        _buildFavoriteButton(),
        // 录制 lives in this menu, second entry.
        LivePlayMenuButton(controller: controller),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Row(
      children: [
        Obx(() {
          final detail = controller.state.value.room.detail;
          return CommonAvatar(avatarUrl: detail?.avatar, radius: 16, fallbackName: detail?.nick);
        }),
        const SizedBox(width: 8),
        Expanded(
          child: Obx(() {
            final detail = controller.state.value.room.detail;
            if (detail == null) {
              return const SizedBox.shrink();
            }
            final platform = detail.platform ?? '';
            final theme = Theme.of(context);
            final colors = theme.colorScheme;
            // One line beside the avatar: the streamer's name, then the
            // platform as a small filled tag. The name gives way first when
            // space runs out; the category is left out.
            return Row(
              children: [
                Flexible(
                  child: Text(
                    detail.nick ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The app's title style as is: 字体设置's title size and
                    // the theme's title weight.
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (platform.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      child: Text(
                        i18n('site_$platform'),
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFavoriteButton() {
    return Obx(() {
      final roomState = controller.state.value.room;
      final detail = roomState.detail;
      if (detail == null) {
        return const SizedBox.shrink();
      }
      final awaitingCanonicalIdentity =
          roomState.isLoading && (detail.nick?.trim().isEmpty ?? true) && (detail.title?.trim().isEmpty ?? true);
      if (awaitingCanonicalIdentity) {
        return const SizedBox(
          width: 47,
          child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(left: 2, right: 5),
        child: FavoriteFloatingButton(
          key: ValueKey('${detail.platform}:${detail.roomId}'),
          room: detail,
          compact: compactHeader,
        ),
      );
    });
  }
}
