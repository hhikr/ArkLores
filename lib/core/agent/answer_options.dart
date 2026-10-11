/// How an Ask question is answered (0.13 the wikis; 0.14 sub-agents), chosen
/// in the composer's options menu and saved between launches.
///
/// 0.14: the digest ("提要") and the reader's review ("复核") are no longer
/// options of the question: they are asked for under a finished answer.
class AnswerOptions {
  const AnswerOptions({
    this.wiki = true,
    this.delegate = false,
  });

  /// "Wiki": the agent searches and reads the games' wikis (online) along
  /// with the knowledge base, and cites them as wiki text.
  final bool wiki;

  /// 0.14 "子助手": the agent may hand parts of a wide question to
  /// sub-agents (at most two). Off by default.
  final bool delegate;

  AnswerOptions copyWith({bool? wiki, bool? delegate}) => AnswerOptions(
        wiki: wiki ?? this.wiki,
        delegate: delegate ?? this.delegate,
      );

  static const int _version = 3;

  /// `v=3;wiki=1;delegate=0`; unknown or missing keys keep their defaults
  /// (the `review` and `digest` keys of earlier versions are not read).
  String encode() => 'v=$_version;wiki=${wiki ? 1 : 0};'
      'delegate=${delegate ? 1 : 0}';

  static AnswerOptions decode(String? text) {
    const defaults = AnswerOptions();
    if (text == null || text.isEmpty) return defaults;
    final values = {
      for (final part in text.split(';'))
        if (part.contains('='))
          part.substring(0, part.indexOf('=')).trim():
              part.substring(part.indexOf('=') + 1).trim(),
    };
    bool flag(String key, bool fallback) => switch (values[key]) {
          '1' => true,
          '0' => false,
          _ => fallback,
        };
    return AnswerOptions(
      wiki: flag('wiki', defaults.wiki),
      delegate: flag('delegate', defaults.delegate),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnswerOptions &&
      other.wiki == wiki &&
      other.delegate == delegate;

  @override
  int get hashCode => Object.hash(wiki, delegate);
}
