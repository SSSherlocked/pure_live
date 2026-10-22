import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/super_chat_card.dart';

class SuperChatPage extends StatelessWidget {
  final List<LiveSuperChatMessage> messages;

  static const double _listPadding = 15;

  const SuperChatPage({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      // Only the one-line hint, in the middle of the tab: no icon or
      // headline for an empty tab.
      return CustomScrollView(
        key: const ValueKey('super-chat-empty-state'),
        primary: false,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  i18n('super_chat_empty_subtitle'),
                  textAlign: TextAlign.center,
                  style: AppText.of(context).body.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final list = <LiveSuperChatMessage>{...messages}.toList(growable: false);

    return ListView.builder(
      primary: false,
      physics: const ClampingScrollPhysics(),
      // One margin on every side, the first card's top included; the cards
      // keep the panel lists' gap between them.
      padding: const EdgeInsets.all(_listPadding),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final message = list[index];

        return Padding(
          padding: EdgeInsets.only(bottom: index == list.length - 1 ? 0 : LivePanelTab.listPadding),
          child: SuperChatCard(message, key: ValueKey<LiveSuperChatMessage>(message)),
        );
      },
    );
  }
}
