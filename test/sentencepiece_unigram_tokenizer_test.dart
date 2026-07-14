import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arklores/core/rag/local_embedding/sentencepiece_unigram_tokenizer.dart';

void main() {
  test('SentencePieceUnigramTokenizer encodes with special tokens and padding',
      () {
    final tokenizer = SentencePieceUnigramTokenizer(
      pieces: SentencePieceUnigramTokenizer.parseTokenizerJson(jsonEncode({
        'model': {
          'type': 'Unigram',
          'vocab': [
            ['<s>', 0],
            ['<pad>', 0],
            ['</s>', 0],
            ['<unk>', 0],
            ['▁hello', -1],
            ['▁world', -1],
          ],
        },
      })),
      maxSequenceLength: 6,
    );

    final encoded = tokenizer.encode('hello world');

    expect(encoded.inputIds, [0, 4, 5, 2, 1, 1]);
    expect(encoded.attentionMask, [1, 1, 1, 1, 0, 0]);
    expect(encoded.tokenTypeIds, [0, 0, 0, 0, 0, 0]);
  });

  test('SentencePieceUnigramTokenizer falls back to unknown token', () {
    final tokenizer = SentencePieceUnigramTokenizer(
      pieces: SentencePieceUnigramTokenizer.parseTokenizerJson(jsonEncode({
        'model': {
          'type': 'Unigram',
          'vocab': [
            ['<s>', 0],
            ['<pad>', 0],
            ['</s>', 0],
            ['<unk>', 0],
          ],
        },
      })),
      maxSequenceLength: 4,
    );

    final encoded = tokenizer.encode('missing');

    expect(encoded.inputIds, [0, 3, 3, 2]);
    expect(encoded.attentionMask, [1, 1, 1, 1]);
  });
}
