import 'package:arklores/core/agent/answer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both passes are on by default and round-trip through the setting', () {
    const defaults = AnswerOptions();
    expect(defaults.review, isTrue);
    expect(defaults.digest, isTrue);
    expect(AnswerOptions.decode(null), defaults);
    expect(AnswerOptions.decode(''), defaults);
    const off = AnswerOptions(review: false, digest: false);
    expect(AnswerOptions.decode(off.encode()), off);
    final one = defaults.copyWith(digest: false);
    expect(AnswerOptions.decode(one.encode()), one);
    // 0.13: the wikis, on by default; a setting saved before 0.13 (no
    // wiki key) keeps them on.
    expect(defaults.wiki, isTrue);
    final noWiki = defaults.copyWith(wiki: false);
    expect(AnswerOptions.decode(noWiki.encode()), noWiki);
    expect(AnswerOptions.decode('review=0;digest=1').wiki, isTrue);
  });

  test('an unknown or damaged value keeps the defaults', () {
    expect(AnswerOptions.decode('review=0;later=1'),
        const AnswerOptions(review: false),);
    expect(AnswerOptions.decode('garbage'), const AnswerOptions());
    expect(AnswerOptions.decode('digest=yes'), const AnswerOptions());
  });
}
