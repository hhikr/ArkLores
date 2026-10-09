import 'package:arklores/core/agent/answer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults: digest and wiki on, review and sub-agents off; the setting '
      'round-trips', () {
    const defaults = AnswerOptions();
    // 0.14: the reader's review and sub-agents are off by default.
    expect(defaults.review, isFalse);
    expect(defaults.delegate, isFalse);
    expect(defaults.digest, isTrue);
    expect(defaults.wiki, isTrue);
    expect(AnswerOptions.decode(null), defaults);
    expect(AnswerOptions.decode(''), defaults);
    const all = AnswerOptions(review: true, delegate: true);
    expect(AnswerOptions.decode(all.encode()), all);
    const off = AnswerOptions(digest: false, wiki: false);
    expect(AnswerOptions.decode(off.encode()), off);
  });

  test('a setting saved before 0.14 keeps digest and wiki, review starts off',
      () {
    expect(
      AnswerOptions.decode('review=1;digest=0;wiki=0'),
      const AnswerOptions(digest: false, wiki: false),
    );
    // 0.13: a setting saved before 0.13 (no wiki key) keeps the wikis on.
    expect(AnswerOptions.decode('review=0;digest=1').wiki, isTrue);
  });

  test('an unknown or damaged value keeps the defaults', () {
    expect(AnswerOptions.decode('v=2;review=1;later=1'),
        const AnswerOptions(review: true),);
    expect(AnswerOptions.decode('garbage'), const AnswerOptions());
    expect(AnswerOptions.decode('digest=yes'), const AnswerOptions());
  });
}
