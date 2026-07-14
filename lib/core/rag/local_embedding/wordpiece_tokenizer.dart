import 'package:flutter/services.dart' show rootBundle;

/// Encoded input expected by BERT/E5-style TFLite embedding models.
class TokenizedText {
  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> tokenTypeIds;

  const TokenizedText({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
  });
}

/// Minimal WordPiece tokenizer for the fixed built-in embedding model.
///
/// This intentionally supports only the vocabulary contract used by the fixed
/// model. It is not a general tokenizer registry.
class WordPieceTokenizer {
  final Map<String, int> _vocab;
  final int maxSequenceLength;

  late final int _padId = _tokenId('[PAD]');
  late final int _unkId = _tokenId('[UNK]');
  late final int _clsId = _tokenId('[CLS]');
  late final int _sepId = _tokenId('[SEP]');

  WordPieceTokenizer({
    required Map<String, int> vocab,
    required this.maxSequenceLength,
  }) : _vocab = vocab;

  static Future<WordPieceTokenizer> fromAsset({
    required String vocabAsset,
    required int maxSequenceLength,
  }) async {
    final raw = await rootBundle.loadString(vocabAsset);
    return WordPieceTokenizer(
      vocab: parseVocab(raw),
      maxSequenceLength: maxSequenceLength,
    );
  }

  static Map<String, int> parseVocab(String raw) {
    final vocab = <String, int>{};
    final lines = raw.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) vocab[token] = i;
    }
    return vocab;
  }

  TokenizedText encode(String text) {
    if (maxSequenceLength < 2) {
      throw ArgumentError('maxSequenceLength must be at least 2');
    }

    final ids = <int>[_clsId];
    for (final token in _basicTokenize(text)) {
      ids.addAll(_wordPiece(token));
      if (ids.length >= maxSequenceLength - 1) break;
    }
    ids.add(_sepId);

    final truncated = ids.take(maxSequenceLength).toList();
    if (truncated.last != _sepId) {
      truncated[maxSequenceLength - 1] = _sepId;
    }

    final attentionMask = List<int>.filled(maxSequenceLength, 0);
    final inputIds = List<int>.filled(maxSequenceLength, _padId);
    for (var i = 0; i < truncated.length; i++) {
      inputIds[i] = truncated[i];
      attentionMask[i] = 1;
    }

    return TokenizedText(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: List<int>.filled(maxSequenceLength, 0),
    );
  }

  int _tokenId(String token) {
    final id = _vocab[token];
    if (id == null) {
      throw StateError('Vocabulary is missing required token: $token');
    }
    return id;
  }

  Iterable<String> _basicTokenize(String text) sync* {
    final normalized = text.toLowerCase().trim();
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      final token = buffer.toString();
      buffer.clear();
      if (token.isNotEmpty) {
        // Yielding from a nested function is not supported; handled below.
      }
    }

    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      if (_isWhitespace(char)) {
        if (buffer.isNotEmpty) {
          yield buffer.toString();
          buffer.clear();
        }
      } else if (_isCjk(rune) || _isPunctuation(char)) {
        if (buffer.isNotEmpty) {
          yield buffer.toString();
          buffer.clear();
        }
        yield char;
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) yield buffer.toString();
    flush();
  }

  List<int> _wordPiece(String token) {
    if (_vocab.containsKey(token)) return [_vocab[token]!];

    final pieces = <int>[];
    var start = 0;
    while (start < token.length) {
      var end = token.length;
      int? current;
      while (start < end) {
        final sub = token.substring(start, end);
        final candidate = start == 0 ? sub : '##$sub';
        current = _vocab[candidate];
        if (current != null) break;
        end--;
      }
      if (current == null) return [_unkId];
      pieces.add(current);
      start = end;
    }
    return pieces;
  }

  bool _isWhitespace(String char) => char.trim().isEmpty;

  bool _isPunctuation(String char) =>
      RegExp(r'^[\p{P}\p{S}]$', unicode: true).hasMatch(char);

  bool _isCjk(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x20000 && rune <= 0x2A6DF) ||
      (rune >= 0x2A700 && rune <= 0x2B73F) ||
      (rune >= 0x2B740 && rune <= 0x2B81F) ||
      (rune >= 0x2B820 && rune <= 0x2CEAF);
}
