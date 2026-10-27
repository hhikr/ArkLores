import 'package:arklores/shared/widgets/search_marks.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mark = TextStyle(fontWeight: FontWeight.w700);

  List<(String, bool)> parts(String text, String query) => [
        for (final s in searchSpans(text, searchWords(query), mark))
          ((s as TextSpan).text!, s.style == mark),
      ];

  test('every word of the query is marked, ignoring case', () {
    expect(parts('Rhodes Island 黑色博士坠落', 'island 博士'), [
      ('Rhodes ', false),
      ('Island', true),
      (' 黑色', false),
      ('博士', true),
      ('坠落', false),
    ]);
  });

  test('overlapping and repeated hits are one run each', () {
    expect(parts('博士博士生日', '博士 士生'), [('博士博士生', true), ('日', false)]);
  });

  test('no words or no hit: the text as it is', () {
    expect(parts('博士', ''), [('博士', false)]);
    expect(parts('博士', '阿米娅'), [('博士', false)]);
  });
}
