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
  });

  test('an unknown or damaged value keeps the defaults', () {
    expect(AnswerOptions.decode('review=0;later=1'),
        const AnswerOptions(review: false),);
    expect(AnswerOptions.decode('garbage'), const AnswerOptions());
    expect(AnswerOptions.decode('digest=yes'), const AnswerOptions());
  });
}
