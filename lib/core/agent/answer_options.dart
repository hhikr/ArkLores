/// The optional passes of an Ask answer after the main agent's draft (R18),
/// chosen in the composer's options menu and saved between launches.
class AnswerOptions {
  const AnswerOptions({this.review = true, this.digest = true});

  /// "复核": a second model reads the draft as a reader and raises questions
  /// the main agent checks in the text before answering again.
  final bool review;

  /// "提要": a long answer is reorganised into a few paragraphs, the
  /// detailed answer folded below.
  final bool digest;

  AnswerOptions copyWith({bool? review, bool? digest}) => AnswerOptions(
        review: review ?? this.review,
        digest: digest ?? this.digest,
      );

  /// `review=1;digest=0`; unknown or missing keys keep their defaults.
  String encode() => 'review=${review ? 1 : 0};digest=${digest ? 1 : 0}';

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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnswerOptions && other.review == review && other.digest == digest;

  @override
  int get hashCode => Object.hash(review, digest);
}
