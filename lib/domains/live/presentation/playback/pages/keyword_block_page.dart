import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/setting_value_format.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/domain/danmaku_block_filter.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/widgets/thumb_only_slider.dart';

class KeywordBlockPage extends StatefulWidget {
  const KeywordBlockPage({super.key, this.asSection = false});

  /// Render as a section inside another scrolling page (the end of the room
  /// panel's 弹幕设置) instead of a standalone scrolling page.
  final bool asSection;

  @override
  State<KeywordBlockPage> createState() => _KeywordBlockPageState();
}

class _KeywordBlockPageState extends State<KeywordBlockPage> {
  final TextEditingController textEditingController = TextEditingController();

  final FocusNode _focusNode = FocusNode();
  final RxBool _isFocused = false.obs;

  late final ScrollController _scrollController;

  SettingsService get settingsService => SettingsService.to;

  @override
  void initState() {
    super.initState();

    _scrollController = createPureLiveScrollController();

    _focusNode.addListener(() {
      _isFocused.value = _focusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    textEditingController.dispose();
    _isFocused.close();
    super.dispose();
  }

  void addKeyword() {
    final keyword = textEditingController.text.trim();

    if (keyword.isEmpty) {
      ToastUtil.show(i18n('please_enter_keyword'));
      return;
    }

    // A `/…/` keyword is a regular expression; one that is broken or could
    // stall the chat is refused here rather than silently ignored later.
    final problem = DanmakuBlockFilter.validate(keyword);
    if (problem != null) {
      ToastUtil.show(i18n(problem));
      return;
    }

    FavoriteRoomController.to.addShieldList(keyword);

    textEditingController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurface;
    final dm = settingsService.danmaku;

    final sections = <Widget>[
      // Repeated, similar and keyword filtering share one group and card.
      context.buildGroupTitle(i18n('danmaku_filter_group')),
      Obx(
        () => context.buildModernCard([
          _switch(
            theme,
            title: i18n('collapse_repeated_danmaku'),
            subtitle: i18n('collapse_repeated_danmaku_desc'),
            value: dm.collapseRepeatedDanmaku.v,
            onChanged: (value) => dm.collapseRepeatedDanmaku.v = value,
            labelColor: labelColor,
          ),
          if (dm.collapseRepeatedDanmaku.v)
            _slider(
              title: i18n('repeated_danmaku_window'),
              value: dm.repeatedDanmakuWindowSeconds.v.toDouble(),
              min: 1,
              max: 30,
              stepSize: 1,
              display: formatSeconds(dm.repeatedDanmakuWindowSeconds.v),
              semanticValueBuilder: (value) =>
                  formatSeconds(value.round()),
              onChanged: (value) => dm.repeatedDanmakuWindowSeconds.v = value.round(),
              labelColor: labelColor,
            ),
          _switch(
            theme,
            title: i18n('danmaku_similarity_filter_enable'),
            value: dm.enableDanmakuSimilarityFilter.v,
            onChanged: (value) => dm.enableDanmakuSimilarityFilter.v = value,
            labelColor: labelColor,
          ),
          if (dm.enableDanmakuSimilarityFilter.v) ...[
            _slider(
              title: i18n('danmaku_similarity_threshold'),
              value: dm.danmakuSimilarityThreshold.v.toDouble(),
              min: 50,
              max: 100,
              stepSize: 1,
              display: '${dm.danmakuSimilarityThreshold.v}%',
              semanticValueBuilder: (value) => '${value.round()}%',
              onChanged: (value) => dm.danmakuSimilarityThreshold.v = value.round(),
              labelColor: labelColor,
            ),
            _slider(
              title: i18n('danmaku_similarity_cache_duration'),
              value: dm.danmakuSimilarityCacheDuration.v.toDouble(),
              min: 1,
              max: 60,
              stepSize: 1,
              display: formatSeconds(dm.danmakuSimilarityCacheDuration.v),
              semanticValueBuilder: (value) =>
                  formatSeconds(value.round()),
              onChanged: (value) => dm.danmakuSimilarityCacheDuration.v = value.round(),
              labelColor: labelColor,
            ),
            _slider(
              title: i18n('danmaku_similarity_max_cache_size'),
              value: dm.danmakuSimilarityMaxCacheSize.v.toDouble(),
              min: 20,
              max: 1000,
              stepSize: 10,
              display: '${dm.danmakuSimilarityMaxCacheSize.v}',
              semanticValueBuilder: (value) => '${value.round()}',
              onChanged: (value) => dm.danmakuSimilarityMaxCacheSize.v = value.round(),
              labelColor: labelColor,
            ),
          ],
          _buildInput(theme, labelColor),
        ]),
      ),
      const SizedBox(height: 20),
    ];
    // After the blocked keyword and user lists.
    final platformSection = <Widget>[
      context.buildGroupTitle(i18n('platform_danmaku_filter')),
      Obx(
        () => context.buildModernCard([
          _switch(
            theme,
            title: i18n('douyu_suspected_automated_filter'),
            subtitle: i18n('douyu_suspected_automated_filter_desc'),
            value: dm.filterDouyuSuspectedAutomatedMessages.v,
            onChanged: (value) => dm.filterDouyuSuspectedAutomatedMessages.v = value,
            labelColor: labelColor,
          ),
        ]),
      ),
      const SizedBox(height: 20),
    ];

    if (widget.asSection) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sections,
          Obx(() => _buildBlockedSummary(theme, users: false)),
          Obx(() => _buildBlockedSummary(theme, users: true)),
          ...platformSection,
        ],
      );
    }

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        physics: const PureLiveScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList.list(children: sections),
          ),
          Obx(() => _buildBlockedSliver(theme, users: false)),
          Obx(() => _buildBlockedSliver(theme, users: true)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.list(children: platformSection),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  String _blockedTitle(bool users, int count) => users
      ? i18n('blocked_danmaku_users', args: {'count': '$count'})
      : i18n('keyword_added_count', args: {'count': '$count'});

  /// In the room's settings tab the blocked keywords (or users) fold into one
  /// row with their count; the list opens in a dialog instead of laying every
  /// entry out on the page.
  Widget _buildBlockedSummary(ThemeData theme, {required bool users}) {
    final count = (users ? FavoriteRoomController.to.blockedDanmakuUsers : FavoriteRoomController.to.shieldList).length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: context.buildModernCard([
        context.buildTile(
          icon: users ? Icons.person_off_rounded : Icons.filter_alt_off_rounded,
          title: _blockedTitle(users, count),
          onTap: () => _showBlocked(users),
        ),
      ]),
    );
  }

  void _showBlocked(bool users) {
    final theme = Theme.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Obx(() {
          final values = List<String>.from(
            users ? FavoriteRoomController.to.blockedDanmakuUsers : FavoriteRoomController.to.shieldList,
          );
          return AlertDialog(
            title: Text(_blockedTitle(users, values.length)),
            content: SizedBox(
              width: 400,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final value in values)
                    _buildItem(
                      theme,
                      text: value,
                      icon: users ? Icons.person_off_rounded : Icons.filter_alt_off_rounded,
                      onRemove: () => _remove(users, value),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(i18n('close'))),
            ],
          );
        }),
      ),
    );
  }

  void _remove(bool users, String value) {
    final favorites = FavoriteRoomController.to;
    // Resolve the rendered value against current preferences, not a stale index.
    final current = users ? favorites.blockedDanmakuUsers : favorites.shieldList;
    final index = current.indexOf(value);
    if (index < 0) return;
    if (users) {
      favorites.removeBlockedDanmakuUser(index);
    } else {
      favorites.removeShieldList(index);
    }
  }

  Widget _buildBlockedSliver(ThemeData theme, {required bool users}) {
    final values = List<String>.from(
      users ? FavoriteRoomController.to.blockedDanmakuUsers : FavoriteRoomController.to.shieldList,
    );
    if (values.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final title = users
        ? i18n('blocked_danmaku_users', args: {'count': '${values.length}'})
        : i18n('keyword_added_count', args: {'count': '${values.length}'});
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _buildSectionTitle(theme, title)),
          SliverList.builder(
            itemCount: values.length,
            itemBuilder: (context, index) => _buildItem(
              theme,
              text: values[index],
              icon: users ? Icons.person_off_rounded : Icons.filter_alt_off_rounded,
              onRemove: () {
                final favorites = FavoriteRoomController.to;
                // Resolve the rendered value against current preferences, not a stale index.
                final current = users ? favorites.blockedDanmakuUsers : favorites.shieldList;
                final currentIndex = current.indexOf(values[index]);
                if (users) {
                  favorites.removeBlockedDanmakuUser(currentIndex);
                } else {
                  favorites.removeShieldList(currentIndex);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // Input
  // ================================================================

  Widget _buildInput(ThemeData theme, Color labelColor) {
    final isFocused = _isFocused.value;

    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        controller: textEditingController,
        focusNode: _focusNode,
        maxLength: FavoriteRoomController.maxShieldKeywordLength,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => addKeyword(),
        decoration: InputDecoration(
          hintText: i18n('please_enter_keyword'),
          helperText: i18n('keyword_regex_hint'),
          helperMaxLines: 2,
          filled: true,
          fillColor: isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.04)
              : theme.colorScheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          suffixIcon: IconButton(tooltip: i18n('add'), onPressed: addKeyword, icon: const Icon(Remix.add_circle_line)),
        ),
      ),
    );
  }

  // ================================================================
  // Section title
  // ================================================================

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        title,
        style: AppText.of(context).sectionTitle.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  // ================================================================
  // Block item
  // ================================================================

  Widget _buildItem(ThemeData theme, {required String text, required IconData icon, required VoidCallback onRemove}) {
    final removeLabel = '${i18n('click_to_remove')}: $text';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: RepaintBoundary(
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            dense: true,
            leading: Icon(icon, size: 19, color: theme.colorScheme.primary),
            title: Text(text),
            trailing: Semantics(
              container: true,
              button: true,
              label: removeLabel,
              child: ExcludeSemantics(
                child: IconButton(
                  tooltip: removeLabel,
                  icon: const Icon(Remix.close_line, size: 18),
                  onPressed: onRemove,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // Slider
  // ================================================================

  Widget _slider({
    required String title,
    required double value,
    required double min,
    required double max,
    required String display,
    required String Function(double value) semanticValueBuilder,
    required ValueChanged<double> onChanged,
    required Color labelColor,
    double? stepSize,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  title,
                  style: AppText.of(context).sectionTitle.copyWith(color: labelColor),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SliderPalette.of(context).badge,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    display,
                    style: AppText.of(context).secondary.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SliderPalette.of(context).badgeText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          SizedBox(
            width: double.infinity,
            child: ThumbOnlySlider(
              min: min,
              max: max,
              value: value,
              stepSize: stepSize,
              semanticFormatterCallback: (semanticValue) =>
                '$title, ${semanticValueBuilder(semanticValue)}',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // Switch
  // ================================================================

  Widget _switch(
    ThemeData theme, {
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color labelColor,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        title,
        style: AppText.of(context).sectionTitle.copyWith(color: labelColor),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: AppText.of(context).secondary.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      value: value,
      activeThumbColor: theme.colorScheme.primary,
      onChanged: onChanged,
    );
  }
}
