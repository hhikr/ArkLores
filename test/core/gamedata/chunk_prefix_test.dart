import 'package:flutter_test/flutter_test.dart';

import '../../support/chunk_prefix.dart';

void main() {
  test('only the chunks asked about are kept, spaces in keys ignored', () {
    expect(
      parseChunkPrefixes(
        '好的：{"0-11": "甲地，乙与丙谈话。", "8 - 19": "甲地，丙离开。", '
        '"30-41": "多出来的", "16-27": " "}',
        [(0, 11), (8, 19), (16, 27)],
      ),
      {'0-11': '甲地，乙与丙谈话。', '8-19': '甲地，丙离开。'},
    );
    expect(parseChunkPrefixes('没有 JSON', [(0, 11)]), isEmpty);
  });

  test('the chunk text is built as the chunker builds it', () {
    final lines = [
      (line: 0, speaker: '甲', content: '你好'),
      (line: 1, speaker: '', content: '旁白'),
      (line: 2, speaker: '乙', content: '  '),
      (line: 3, speaker: '乙', content: '再见'),
    ];
    expect(chunkText(lines, 0, 2), '甲：你好\n旁白');
    expect(
      prefixedChunkText('集 · 篇', '甲地，甲与乙道别。', chunkText(lines, 3, 3)),
      '《集 · 篇》甲地，甲与乙道别。\n乙：再见',
    );
  });

  test('the prompt names no story, person or place', () {
    expect(chunkPrefixPrompt, isNot(matches(RegExp(r'[《》]'))));
    expect(chunkPrefixPrompt, contains('<谁>'));
  });
}
