import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../rag/embedder.dart';
import '../../rag/vector_store.dart';
import 'agent_tool.dart';

/// Tool to perform semantic search on the knowledge base.
class SearchWikiTool extends AgentTool {
  static String? _previousDiagnosticQuery;
  static List<double>? _previousDiagnosticVector;

  final Embedder _embedder;
  final VectorStore _vectorStore;
  final String? _profileId;

  SearchWikiTool({
    required Embedder embedder,
    required VectorStore vectorStore,
    String? profileId,
  })  : _embedder = embedder,
        _vectorStore = vectorStore,
        _profileId = profileId;

  @override
  String get name => 'search_wiki';

  @override
  String get description =>
      'Search the Arknights and Endfield knowledge base (Wikis and imported books) '
      'using semantic search. Returns relevant text chunks along with metadata '
      'such as source type, page title, section, source url, and chunk id.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'The query text to search for (e.g., character name, event, faction, or lore topic).',
          },
          'top_k': {
            'type': 'integer',
            'description':
                'Number of search results to return. Default is 5, max is 10.',
            'default': 5,
          },
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final query = arguments['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return 'Error: query parameter is empty';
    }

    final topK = (arguments['top_k'] as num?)?.toInt() ?? 5;
    final cleanTopK = topK.clamp(1, 10);

    try {
      final queryVariants = _buildQueryVariants(query);

      final keywordResults = await _vectorStore.keywordSearch(
        queryVariants,
        topK: cleanTopK,
        profileId: _profileId,
      );

      // 1. Generate query embedding
      final queryVector = await _embedder.embed(query);
      final queryDiagnostics =
          _logQueryEmbeddingDiagnostics(query, queryVector);

      // 2. Perform search in VectorStore
      final searchResults = await _vectorStore.search(
        queryVector,
        topK: cleanTopK * 2,
        profileId: _profileId,
        filterLowInformation: true,
      );

      final mergedResults = _mergeHybridResults(
        keywordResults: keywordResults,
        vectorResults: searchResults,
        topK: cleanTopK,
      );

      if (mergedResults.isEmpty) {
        return ToolExecutionResult(
          observation: 'No matching records found in the database.',
          debugLog: queryDiagnostics,
        );
      }
      final scoreDiagnostics = _logSearchScoreDiagnostics(
        query,
        keywordResults: keywordResults,
        vectorResults: searchResults,
        mergedResults: mergedResults,
      );

      // 3. Format results as a readable block for LLM
      final buffer = StringBuffer();
      for (var i = 0; i < mergedResults.length; i++) {
        final res = mergedResults[i];
        final chunk = res.chunk;
        buffer.writeln(
            '=== Result #${i + 1} (Score: ${res.score.toStringAsFixed(4)}) ===');
        buffer.writeln('Retrieval Type: ${res.retrievalType}');
        buffer.writeln('ID: ${chunk.id}');
        buffer.writeln('Source Type: ${res.sourceType}');
        if (res.sourceType == 'wiki') {
          buffer.writeln('Wiki: ${res.wiki}');
          if (res.sourceUrl != null) {
            buffer.writeln('Source URL: ${res.sourceUrl}');
          }
        } else if (res.sourceType == 'book' && res.bookId != null) {
          buffer.writeln('Book ID: ${res.bookId}');
        }
        buffer.writeln('Title: ${chunk.pageTitle}');
        if (chunk.section.isNotEmpty) {
          buffer.writeln('Section: ${chunk.section}');
        }
        buffer.writeln('Content:\n${chunk.content}');
        buffer.writeln();
      }

      return ToolExecutionResult(
        observation: buffer.toString().trim(),
        debugLog: [queryDiagnostics, scoreDiagnostics].join('\n'),
      );
    } catch (e) {
      return 'Error occurred during search: $e';
    }
  }

  List<String> _buildQueryVariants(String query) {
    final cleaned = query.trim();
    final variants = <String>{cleaned};

    for (final match in RegExp(r'[（(]([^（）()]+)[）)]').allMatches(cleaned)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) variants.add(value);
    }

    final withoutParens = cleaned
        .replaceAll(RegExp(r'[（(][^（）()]+[）)]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (withoutParens.isNotEmpty) variants.add(withoutParens);

    for (final token in cleaned.split(RegExp(r'\s+'))) {
      final normalized = token.trim();
      if (normalized.length >= 2 && normalized.length <= 20) {
        variants.add(normalized);
      }
    }

    return variants.where((v) => v.isNotEmpty).toList();
  }

  List<SearchResult> _mergeHybridResults({
    required List<SearchResult> keywordResults,
    required List<SearchResult> vectorResults,
    required int topK,
  }) {
    final byId = <String, SearchResult>{};
    for (final result in [...keywordResults, ...vectorResults]) {
      final existing = byId[result.chunk.id];
      if (existing == null ||
          _hybridRank(result).compareTo(_hybridRank(existing)) > 0) {
        byId[result.chunk.id] = result;
      }
    }

    final merged = byId.values.toList()
      ..sort((a, b) {
        final rankCompare = _hybridRank(b).compareTo(_hybridRank(a));
        if (rankCompare != 0) return rankCompare;
        if (a.wiki == 'prts' && b.wiki != 'prts') return -1;
        if (a.wiki != 'prts' && b.wiki == 'prts') return 1;
        return b.score.compareTo(a.score);
      });
    return merged.take(topK).toList();
  }

  double _hybridRank(SearchResult result) {
    final typeWeight = switch (result.retrievalType) {
      'title_exact' => 10000.0,
      'title_like' => 8000.0,
      'content_like' => 5000.0,
      _ => 1000.0,
    };
    final wikiWeight = result.wiki == 'prts' ? 100.0 : 0.0;
    final qualityPenalty = result.isLowInformation ? 500.0 : 0.0;
    return typeWeight + wikiWeight + result.score - qualityPenalty;
  }

  String _logQueryEmbeddingDiagnostics(String query, List<double> vector) {
    if (vector.isEmpty) {
      final message = '[search_wiki] Query embedding is empty for "$query".';
      debugPrint(message);
      return message;
    }

    var normSquared = 0.0;
    var sum = 0.0;
    var minValue = vector.first;
    var maxValue = vector.first;
    for (final value in vector) {
      normSquared += value * value;
      sum += value;
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }

    final firstValues =
        vector.take(16).map((value) => value.toStringAsFixed(6)).join(', ');
    final previousQuery = _previousDiagnosticQuery;
    final previousVector = _previousDiagnosticVector;
    final previousSimilarity = previousVector != null &&
            previousVector.length == vector.length &&
            previousQuery != null
        ? _cosineSimilarity(previousVector, vector).toStringAsFixed(6)
        : 'n/a';
    final message = '[search_wiki] Query embedding diagnostics: '
        'query="$query", '
        'dimension=${vector.length}, '
        'norm=${sqrt(normSquared).toStringAsFixed(6)}, '
        'min=${minValue.toStringAsFixed(6)}, '
        'max=${maxValue.toStringAsFixed(6)}, '
        'mean=${(sum / vector.length).toStringAsFixed(6)}, '
        'first16=[$firstValues], '
        'previousQuery="$previousQuery", '
        'previousCosine=$previousSimilarity';
    debugPrint(message);

    _previousDiagnosticQuery = query;
    _previousDiagnosticVector = List<double>.of(vector, growable: false);
    return message;
  }

  String _logSearchScoreDiagnostics(
    String query, {
    required List<SearchResult> keywordResults,
    required List<SearchResult> vectorResults,
    required List<SearchResult> mergedResults,
  }) {
    final vectorMessage = _scoreSummary('vector', vectorResults);
    final keywordTypes = <String, int>{};
    for (final result in keywordResults) {
      keywordTypes.update(result.retrievalType, (value) => value + 1,
          ifAbsent: () => 1);
    }
    final mergedTypes = <String, int>{};
    for (final result in mergedResults) {
      mergedTypes.update(result.retrievalType, (value) => value + 1,
          ifAbsent: () => 1);
    }
    final message = '[search_wiki] Score diagnostics: '
        'query="$query", '
        'keywordCount=${keywordResults.length}, '
        'keywordTypes=$keywordTypes, '
        '$vectorMessage, '
        'mergedTypes=$mergedTypes';
    debugPrint(message);
    return message;
  }

  String _scoreSummary(String label, List<SearchResult> results) {
    if (results.isEmpty) return '$label=count=0';
    final scores = results.map((result) => result.score).toList();
    final maxScore = scores.reduce(max);
    final minScore = scores.reduce(min);
    final meanScore = scores.reduce((a, b) => a + b) / scores.length;
    return '$label=count=${scores.length}, '
        'min=${minScore.toStringAsFixed(6)}, '
        'max=${maxScore.toStringAsFixed(6)}, '
        'mean=${meanScore.toStringAsFixed(6)}, '
        'range=${(maxScore - minScore).toStringAsFixed(6)}';
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;
    return dotProduct / denominator;
  }
}
