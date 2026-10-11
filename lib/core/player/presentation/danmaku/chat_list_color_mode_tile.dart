import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';

/// Picks how the chat list shows each message's danmaku colour: not at all,
/// as a dot before the message, or as the colour of the message text; plus
/// whether the sender's name takes that colour too.
class ChatListColorModeTile extends StatelessWidget {
  const ChatListColorModeTile({super.key, this.horizontalPadding = 16, this.labelColor});

  final double horizontalPadding;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.to.danmaku;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n('chat_list_color_mode'),
            style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600, color: labelColor),
          ),
          const SizedBox(height: 2),
          Text(i18n('chat_list_color_mode_subtitle'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Obx(() {
            final current = settings.resolvedChatListColorMode;
            return Wrap(
              key: const ValueKey('chat-list-color-mode'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ChatListColorMode.values)
                  ChoiceChip(
                    label: Text(i18n('chat_list_color_${mode.name}')),
                    selected: current == mode,
                    onSelected: (_) => settings.chatListColorMode.v = mode.name,
                  ),
              ],
            );
          }),
          const SizedBox(height: 4),
          Obx(
            () => Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const ValueKey('chat-list-color-name'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  i18n('chat_list_color_name'),
                  style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.w600, color: labelColor),
                ),
                subtitle: Text(i18n('chat_list_color_name_subtitle'), style: Theme.of(context).textTheme.bodySmall),
                value: settings.chatListColorName.v,
                onChanged: (value) => settings.chatListColorName.v = value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
