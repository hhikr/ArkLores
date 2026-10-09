/// The optional parts of an Ask answer (R18 passes after the main agent's
/// draft; 0.13 the wikis), chosen in the composer's options menu and saved
/// between launches.
class AnswerOptions {
  const AnswerOptions({this.review = true, this.digest = true, this.wiki = true});

  /// "复核": a second model reads the draft as a reader and raises questions
  /// the main agent checks in the text before answering again.
  final bool review;

  /// "提要": a long answer is reorganised into a few paragraphs, the
  /// detailed answer folded below.
  final bool digest;

  /// "Wiki": the agent may search and read the games' wikis (online) and
  /// cite them as a secondary source.
  final bool wiki;

  AnswerOptions copyWith({bool? review, bool? digest, bool? wiki}) =>
      AnswerOptions(
        review: review ?? this.review,
        digest: digest ?? this.digest,
        wiki: wiki ?? this.wiki,
      );

  /// `review=1;digest=0;wiki=1`; unknown or missing keys keep their
  /// defaults.
  String encode() =>
      'review=${review ? 1 : 0};digest=${digest ? 1 : 0};wiki=${wiki ? 1 : 0}';

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
      review: flag('review', defaults.review),
      digest: flag('digest', defaults.digest),
      wiki: flag('wiki', defaults.wiki),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnswerOptions &&
      other.review == review &&
      other.digest == digest &&
      other.wiki == wiki;

  @override
  int get hashCode => Object.hash(review, digest, wiki);
}
