import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import 'wordpiece_tokenizer.dart' show TokenizedText;

class SentencePieceUnigramTokenizer {
  final Map<String, _Piece> _pieces;
  final int maxSequenceLength;
  final int _maxPieceLength;

  static const int _bosId = 0;
  static const int _padId = 1;
  static const int _eosId = 2;
  static const int _unkId = 3;
  static const double _unkScore = -100.0;

  SentencePieceUnigramTokenizer({
    required Map<String, _Piece> pieces,
    required this.maxSequenceLength,
  })  : _pieces = pieces,
        _maxPieceLength = pieces.keys.fold<int>(
          1,
          (maxLength, piece) => max(maxLength, piece.length),
        );

  static Future<SentencePieceUnigramTokenizer> fromAsset({
    required String tokenizerAsset,
    required int maxSequenceLength,
  }) async {
    final raw = await rootBundle.loadString(tokenizerAsset);
    return SentencePieceUnigramTokenizer(
      pieces: parseTokenizerJson(raw),
      maxSequenceLength: maxSequenceLength,
    );
  }

  static Map<String, _Piece> parseTokenizerJson(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final model = data['model'] as Map<String, dynamic>;
    if (model['type'] != 'Unigram') {
      throw const FormatException('Expected a SentencePiece Unigram tokenizer');
    }
    final vocab = model['vocab'] as List<dynamic>;
    final pieces = <String, _Piece>{};
    for (var i = 0; i < vocab.length; i++) {
      final entry = vocab[i] as List<dynamic>;
      pieces[entry[0] as String] = _Piece(
        id: i,
        score: (entry[1] as num).toDouble(),
      );
    }
    return pieces;
  }

  TokenizedText encode(String text) {
    if (maxSequenceLength < 2) {
      throw ArgumentError('maxSequenceLength must be at least 2');
    }

    final bodyIds = _encodePieces(text).take(maxSequenceLength - 2).toList();
    final ids = <int>[_bosId, ...bodyIds, _eosId];
    final inputIds = List<int>.filled(maxSequenceLength, _padId);
    final attentionMask = List<int>.filled(maxSequenceLength, 0);
    for (var i = 0; i < ids.length; i++) {
      inputIds[i] = ids[i];
      attentionMask[i] = 1;
    }

    return TokenizedText(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: List<int>.filled(maxSequenceLength, 0),
    );
  }

  List<int> _encodePieces(String text) {
    final normalized = _metaspace(text);
    if (normalized.isEmpty) return const [];

    final bestScore =
        List<double>.filled(normalized.length + 1, -double.infinity);
    final bestStart = List<int>.filled(normalized.length + 1, -1);
    final bestId = List<int>.filled(normalized.length + 1, _unkId);
    bestScore[0] = 0;

    for (var start = 0; start < normalized.length; start++) {
      if (bestScore[start] == -double.infinity) continue;
      final endLimit = min(normalized.length, start + _maxPieceLength);
      var matched = false;
      for (var end = start + 1; end <= endLimit; end++) {
        final piece = _pieces[normalized.substring(start, end)];
        if (piece == null) continue;
        matched = true;
        final score = bestScore[start] + piece.score;
        if (score > bestScore[end]) {
          bestScore[end] = score;
          bestStart[end] = start;
          bestId[end] = piece.id;
        }
      }
      if (!matched && bestScore[start] + _unkScore > bestScore[start + 1]) {
        bestScore[start + 1] = bestScore[start] + _unkScore;
        bestStart[start + 1] = start;
        bestId[start + 1] = _unkId;
      }
    }

    if (bestStart[normalized.length] < 0) return const [_unkId];

    final ids = <int>[];
    var cursor = normalized.length;
    while (cursor > 0) {
      ids.add(bestId[cursor]);
      cursor = bestStart[cursor];
      if (cursor < 0) return const [_unkId];
    }
    return ids.reversed.toList(growable: false);
  }

  String _metaspace(String text) {
    final compact = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return '';
    return '▁${compact.replaceAll(' ', '▁')}';
  }
}

class _Piece {
  final int id;
  final double score;

  const _Piece({required this.id, required this.score});
}
