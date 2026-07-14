import 'package:arklores/core/rag/local_embedding/wordpiece_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WordPieceTokenizer encodes mixed Chinese and English text', () {
    final tokenizer = WordPieceTokenizer(
      maxSequenceLength: 8,
      vocab: {
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 3,
        'amiya': 4,
        '博': 5,
        '士': 6,
        '!': 7,
      },
    );

    final encoded = tokenizer.encode('Amiya 博士!');

    expect(encoded.inputIds, [2, 4, 5, 6, 7, 3, 0, 0]);
    expect(encoded.attentionMask, [1, 1, 1, 1, 1, 1, 0, 0]);
    expect(encoded.tokenTypeIds, List<int>.filled(8, 0));
  });

  test('WordPieceTokenizer falls back to unknown token', () {
    final tokenizer = WordPieceTokenizer(
      maxSequenceLength: 5,
      vocab: {
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 3,
      },
    );

    final encoded = tokenizer.encode('missing');

    expect(encoded.inputIds, [2, 1, 3, 0, 0]);
    expect(encoded.attentionMask, [1, 1, 1, 0, 0]);
  });
}
