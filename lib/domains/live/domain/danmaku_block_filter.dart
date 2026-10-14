import 'package:pure_live/core/models/live_message.dart';

/// The 屏蔽管理 lists (blocked users and keywords) compiled once for
/// matching. The room and the multi-view tiles both filter through this, so
/// a keyword blocks the same messages everywhere.
///
/// A keyword written `/like this/` is a regular expression, matched without
/// regard to case; any other keyword is matched as plain text, also without
/// regard to case. Users are matched by their whole name, case-insensitive.
class DanmakuBlockFilter {
  DanmakuBlockFilter({required Iterable<String> users, required Iterable<String> keywords}) {
    for (final raw in users) {
      final user = raw.trim().toLowerCase();
      if (user.isNotEmpty && !_maskedName.hasMatch(user)) _users.add(user);
    }
    for (final raw in keywords) {
      final keyword = raw.trim();
      if (keyword.isEmpty) continue;
      final pattern = regexBody(keyword);
      if (pattern == null) {
        _texts.add(keyword.toLowerCase());
      } else if (validate(keyword) == null) {
        _patterns.add(RegExp(pattern, caseSensitive: false, unicode: true));
      }
    }
  }

  /// Blocks nothing.
  static final DanmakuBlockFilter none = DanmakuBlockFilter(users: const <String>[], keywords: const <String>[]);

  final Set<String> _users = <String>{};
  final List<String> _texts = <String>[];
  final List<RegExp> _patterns = <RegExp>[];

  /// Names a platform masks (`张**`): many viewers share one, so blocking it
  /// would block them all.
  static final RegExp _maskedName = RegExp(r'\*{2,}|＊{2,}');

  /// Whether [message] is from a blocked user or contains a blocked keyword.
  bool blocks(LiveMessage message) {
    final user = message.userName.trim().toLowerCase();
    if (user.isNotEmpty && !_maskedName.hasMatch(user) && _users.contains(user)) return true;
    final text = message.message;
    if (_texts.isNotEmpty) {
      final lower = text.toLowerCase();
      if (_texts.any(lower.contains)) return true;
    }
    return _patterns.any((pattern) => pattern.hasMatch(text));
  }

  /// The pattern inside a `/…/` keyword, or null for a plain keyword.
  static String? regexBody(String keyword) {
    final text = keyword.trim();
    if (text.length < 3 || !text.startsWith('/') || !text.endsWith('/')) return null;
    return text.substring(1, text.length - 1);
  }

  // A quantified group that itself repeats - (a+)+, (.*)*, (\w+){2,} - can
  // take exponential time on a near-miss. Every message runs through every
  // pattern on the UI isolate, and a Dart RegExp cannot be interrupted, so
  // such patterns are refused when added.
  static final RegExp _nestedQuantifier = RegExp(r'\([^()]*[+*][^()]*\)\s*[+*{]');

  /// Why [keyword] cannot be used, or null when it can: a `/…/` keyword
  /// must be a valid pattern without nested quantifiers. Returns a
  /// translation key.
  static String? validate(String keyword) {
    final pattern = regexBody(keyword);
    if (pattern == null) return null;
    if (_nestedQuantifier.hasMatch(pattern)) return 'keyword_regex_slow';
    try {
      RegExp(pattern, unicode: true);
    } on FormatException {
      return 'keyword_regex_invalid';
    }
    return null;
  }
}
