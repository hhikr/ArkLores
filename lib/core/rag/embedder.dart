import '../../core/llm/llm_client.dart';

/// Wraps the [LLMClient]'s embedding methods with error handling
/// and validation specific to the indexing pipeline.
class Embedder {
  final LLMClient _client;

  Embedder(this._client);

  /// Embeds a single text string into a 1536-dimensional vector.
  ///
  /// Returns a zero vector for empty or whitespace-only input.
  Future<List<double>> embed(String text) async {
    if (text.trim().isEmpty) {
      return List.filled(1536, 0.0);
    }

    try {
      return await _client.embed(text);
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

    // Filter out empty texts.
    final validTexts = <String>[];
    final validIndices = <int>[];
    final results = <List<double>?> List.filled(texts.length, null);

    for (var i = 0; i < texts.length; i++) {
      if (texts[i].trim().isEmpty) {
        results[i] = List.filled(1536, 0.0);
      } else {
        validIndices.add(i);
        validTexts.add(texts[i]);
      }
    }

    if (validTexts.isEmpty) {
      return EmbeddingResult(
        vectors: results.whereType<List<double>>().toList(),
        failedIndices: [],
      );
    }

    try {
      final embeddings = await _client.embedBatch(validTexts);
      for (var j = 0; j < embeddings.length; j++) {
        results[validIndices[j]] = embeddings[j];
      }
    } catch (e) {
      // Mark all valid texts as failed.
      throw EmbedderException('Batch embedding failed: $e');
    }

    final failedIndices = <int>[];
    for (var i = 0; i < results.length; i++) {
      if (results[i] == null) {
        failedIndices.add(i);
      }
    }

    return EmbeddingResult(
      vectors: results.whereType<List<double>>().toList(),
      failedIndices: failedIndices,
    );
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
