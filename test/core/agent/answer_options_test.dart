import 'package:arklores/core/agent/answer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults: the wikis on, sub-agents off; the setting round-trips', () {
    const defaults = AnswerOptions();
    expect(defaults.wiki, isTrue);
    expect(defaults.delegate, isFalse);
    expect(AnswerOptions.decode(null), defaults);
    expect(AnswerOptions.decode(''), defaults);
    const all = AnswerOptions(delegate: true);
    expect(AnswerOptions.decode(all.encode()), all);
    const off = AnswerOptions(wiki: false);
    expect(AnswerOptions.decode(off.encode()), off);
  });

  // 0.14: the digest and the review are asked for under an answer; what an
  // earlier version saved for them is not read.
  test('a setting saved by an earlier version keeps wiki and sub-agents',
      () {
    expect(
      AnswerOptions.decode('review=1;digest=0;wiki=0'),
      const AnswerOptions(wiki: false),
    );
    expect(
      AnswerOptions.decode('v=2;review=1;digest=1;wiki=1;delegate=1'),
      const AnswerOptions(delegate: true),
    );
    expect(AnswerOptions.decode('review=0;digest=1').wiki, isTrue);
  });

  test('unknown keys and broken values keep the defaults', () {
    expect(AnswerOptions.decode('v=3;delegate=1;later=1'),
        const AnswerOptions(delegate: true),);
    expect(AnswerOptions.decode('garbage'), const AnswerOptions());
    expect(AnswerOptions.decode('wiki=yes'), const AnswerOptions());
  });
}
