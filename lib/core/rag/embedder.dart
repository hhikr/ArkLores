import 'embedding_client.dart';

/// Wraps the [LLMClient]'s embedding methods with error handling
/// and validation specific to the indexing pipeline.
///
/// Automatically detects the embedding vector dimension from the
/// first successful API response, so it works with any model
/// (OpenAI 1536-dim, DeepSeek 2048-dim, etc.).
class Embedder {
  final EmbeddingClient _client;

  /// Cached embedding dimension, detected from first API response.
  /// 0 means "not yet determined".
  int _dimension = 0;

  /// Default fallback dimension before first API call completes.
  static const int _defaultDimension = 1536;

  Embedder(this._client);

  /// Returns the detected embedding dimension.
  /// 0 if no embedding has been performed yet.
  int get detectedDimension => _dimension > 0 ? _dimension : _client.dimension;

  String get providerId => _client.providerId;

  /// Embeds a single text string.
  ///
  /// Returns a zero vector for empty or whitespace-only input,
  /// using the detected embedding dimension.
  Future<List<double>> embed(String text) async {
    if (text.trim().isEmpty) {
      return List.filled(
        detectedDimension > 0 ? detectedDimension : _defaultDimension,
        0.0,
      );
    }

    try {
      final result = await _client.embed(text);
      _detectDimension(result);
      return result;
    } catch (e) {
      throw EmbedderException('Embedding failed: $e');
    }
  }

  /// Embeds a list of texts in batches.
  ///
  /// Empty texts are skipped (assigned zero vectors) to avoid
  /// wasting API quota.
  Future<EmbeddingResult> embedBatch(List<String> texts) async {
    if (texts.isEmpty) {
      return EmbeddingResult(vectors: [], failedIndices: []);
    }

    // Separate empty texts (skip embedding, assign zero vectors).
    final validTexts = <String>[];
    final validIndices = <int>[];
    final results = <List<double>>[];

    for (var i = 0; i < texts.length; i++) {
      if (texts[i].trim().isEmpty) {
        results.add(List.filled(
          detectedDimension > 0 ? detectedDimension : _defaultDimension,
          0.0,
        ));
      } else {
        validIndices.add(i);
        validTexts.add(texts[i]);
        // Placeholder — will be filled after batch embedding.
        results.add(List.filled(
          detectedDimension > 0 ? detectedDimension : _defaultDimension,
          0.0,
        ));
      }
    }

    if (validTexts.isEmpty) {
      return EmbeddingResult(vectors: results, failedIndices: []);
    }

    try {
      final embeddings = await _client.embedBatch(validTexts);

      // Detect dimension from the first result if not yet known.
      if (embeddings.isNotEmpty && _dimension == 0) {
        _dimension = embeddings.first.length;
      }

      for (var j = 0; j < embeddings.length; j++) {
        results[validIndices[j]] = embeddings[j];
      }
    } catch (e) {
      throw EmbedderException('Batch embedding failed: $e');
    }

    return EmbeddingResult(vectors: results, failedIndices: []);
  }

  /// Detects and caches the embedding dimension from a vector.
  void _detectDimension(List<double> vector) {
    if (_dimension == 0 && vector.isNotEmpty) {
      _dimension = vector.length;
    }
  }
}

/// Result of a batch embedding operation.
class EmbeddingResult {
  /// Successfully embedded vectors (in the same order as input texts).
  final List<List<double>> vectors;

  /// Indices of texts that failed to embed.
  final List<int> failedIndices;

  const EmbeddingResult({
    required this.vectors,
    this.failedIndices = const [],
  });

  bool get allSucceeded => failedIndices.isEmpty;
}

/// Exception thrown by [Embedder].
class EmbedderException implements Exception {
  final String message;
  const EmbedderException(this.message);

  @override
  String toString() => 'EmbedderException: $message';
}
