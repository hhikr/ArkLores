/// Placeholders the game writes into its texts, filled in when a text is
/// shown (the knowledge base keeps them as they are).
library;

final RegExp _nicknameTag = RegExp(r'\{@nickname\}', caseSensitive: false);

/// `{@nickname}` is the Doctor's name: [nickname] when the reader gave one,
/// else [fallback]. `{@nbs}` is a non-breaking space.
String withPlaceholders(
  String text,
  String nickname, {
  String fallback = '博士',
}) {
  if (!text.contains('{@')) return text;
  final name = nickname.trim().isEmpty ? fallback : nickname.trim();
  return text
      .replaceAll(_nicknameTag, name)
      .replaceAll(RegExp(r'\{@nbs\}', caseSensitive: false), '\u00a0');
}
