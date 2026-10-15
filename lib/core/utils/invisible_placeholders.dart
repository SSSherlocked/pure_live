library;

final RegExp _invisiblePlaceholders = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F￹-￼￾￿]');

String stripInvisiblePlaceholders(String text) =>
    _invisiblePlaceholders.hasMatch(text) ? text.replaceAll(_invisiblePlaceholders, '') : text;

String? stripInvisiblePlaceholdersOrNull(String? text) => text == null ? null : stripInvisiblePlaceholders(text);

/// Combining marks (accents, Zalgo, the lines of drawn text art).
const String _combiningMarks = r'̀-ͯ҃-҉᪰-᫿᷀-᷿⃐-⃿︠-︯';
final RegExp _stackedMarks = RegExp('([$_combiningMarks]{2})[$_combiningMarks]+');

/// Keeps at most two combining marks on one character.
///
/// Chat art such as the 钓鱼 emoticon stacks dozens of marks on one
/// character to draw a line that hangs down the screen: in a list it ran
/// across the rows below, and the row itself looked blank. Real text never
/// needs more than two marks from these blocks on one letter.
String limitStackedMarks(String text) =>
    _stackedMarks.hasMatch(text) ? text.replaceAllMapped(_stackedMarks, (match) => match[1]!) : text;
