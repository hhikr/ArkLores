/// The optional parts of an Ask answer (R18 passes after the main agent's
/// draft; 0.13 the wikis; 0.14 sub-agents), chosen in the composer's options
/// menu and saved between launches.
class AnswerOptions {
  const AnswerOptions({
    this.review = false,
    this.digest = true,
    this.wiki = true,
    this.delegate = false,
  });

  /// "复核": a second model reads the draft as a reader and raises questions
  /// the main agent checks in the text before answering again. 0.14: off by
  /// default (it rarely raised a question and costs a rewrite when it does).
  final bool review;

  /// "提要": a long answer is reorganised into a few paragraphs, the
  /// detailed answer folded below.
  final bool digest;

  /// "Wiki": the agent searches and reads the games' wikis (online) along
  /// with the knowledge base, and cites them as wiki text.
  final bool wiki;

  /// 0.14 "子助手": the agent may hand parts of a wide question to
  /// sub-agents (at most two). Off by default.
  final bool delegate;

  AnswerOptions copyWith({
    bool? review,
    bool? digest,
    bool? wiki,
    bool? delegate,
  }) =>
      AnswerOptions(
        review: review ?? this.review,
        digest: digest ?? this.digest,
        wiki: wiki ?? this.wiki,
        delegate: delegate ?? this.delegate,
      );

  /// Saved form version: options saved before 0.14 (no `v`) keep their
  /// digest and wiki choices; review starts off again.
  static const int _version = 2;

  /// `v=2;review=1;digest=0;wiki=1;delegate=0`; unknown or missing keys
  /// keep their defaults.
  String encode() => 'v=$_version;review=${review ? 1 : 0};'
      'digest=${digest ? 1 : 0};wiki=${wiki ? 1 : 0};'
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
    final current = values['v'] == '$_version';
    bool flag(String key, bool fallback) => switch (values[key]) {
          '1' => true,
          '0' => false,
          _ => fallback,
        };
    return AnswerOptions(
      review: current ? flag('review', defaults.review) : defaults.review,
      digest: flag('digest', defaults.digest),
      wiki: flag('wiki', defaults.wiki),
      delegate: flag('delegate', defaults.delegate),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnswerOptions &&
      other.review == review &&
      other.digest == digest &&
      other.wiki == wiki &&
      other.delegate == delegate;

  @override
  int get hashCode => Object.hash(review, digest, wiki, delegate);
}
