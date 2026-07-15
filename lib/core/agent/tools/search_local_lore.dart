import '../../gamedata/gamedata_knowledge_store.dart';
import 'agent_tool.dart';

/// Source-neutral local lore search tool.
class SearchLocalLoreTool extends AgentTool {
  static const int _maxObservationChars = 4800;
  static const int _maxContentExcerptChars = 700;

  final GameDataKnowledgeStore? _gameDataStore;

  SearchLocalLoreTool({
    GameDataKnowledgeStore? gameDataStore,
  }) : _gameDataStore = gameDataStore ?? GameDataKnowledgeStore();

  @override
  String get name => 'search_local_lore';

  @override
  String get description =>
      'Search the local ArkLores GameData knowledge base. Supports entity '
      'disambiguation, summary/evidence retrieval, optional content_type, '
      'scope_id, and entity_id filters. Returns source kind, content_type, source_path, '
      'raw_id, ranking reason, and chunk/record id for citations.';

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
          'content_type': {
            'type': 'string',
            'description':
                'Optional GameData content type filter, e.g. operator_voice, enemy_profile, roguelike_topic.',
          },
          'entity_id': {
            'type': 'string',
            'description':
                'Optional GameData entity id filter, e.g. char_002_amiya.',
          },
          'scope_id': {
            'type': 'string',
            'description':
                'Optional resolved story scope id, e.g. activity:act21mini. Use with entity_id and evidence mode.',
          },
          'search_mode': {
            'type': 'string',
            'enum': ['general', 'summary', 'evidence'],
            'description':
                'Use summary for entity summaries: entity document first, then story context, then raw records.',
            'default': 'general',
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
    final contentType = arguments['content_type'] as String?;
    final entityId = arguments['entity_id'] as String?;
    final scopeId = arguments['scope_id'] as String?;
    final searchMode = (arguments['search_mode'] as String?) ?? 'general';
    if (searchMode == 'evidence' &&
        (entityId == null ||
            entityId.trim().isEmpty ||
            scopeId == null ||
            scopeId.trim().isEmpty)) {
      return const ToolExecutionResult(
        observation: 'Evidence search requires both a resolved entity_id and '
            'a canonical scope_id. Resolve them separately, then retry.',
      );
    }

    final store = _gameDataStore;
    if (store != null && await store.isAvailable) {
      if ((entityId == null || entityId.trim().isEmpty) &&
          contentType == null) {
        final candidates = await store.findEntityCandidates(query);
        final exactCandidates = candidates
            .where((candidate) =>
                candidate.matchType == 'name_exact' ||
                candidate.matchType == 'canonical_alias_exact' ||
                candidate.matchType == 'alias_exact')
            .toList(growable: false);
        if (exactCandidates.length > 1) {
          return _formatDisambiguationCandidates(query, exactCandidates);
        }
      }

      final results = await store.search(
        query: query,
        topK: cleanTopK,
        contentType: contentType,
        entityId: entityId,
        searchMode: searchMode,
        scopeId: scopeId,
      );
      if (results.isNotEmpty) {
        return _formatGameDataResults(results, searchMode: searchMode);
      }
      if (searchMode == 'evidence') {
        return ToolExecutionResult(
          observation:
              'No scoped direct candidate found for "$query". The scope and '
              'entity intersection was checked. Retry evidence mode with the '
              'same scope_id and entity_id but only one short claim '
              'relationship, state, or action term; do not use the scope or '
              'entity names as query terms.',
        );
      }
      return ToolExecutionResult(
        observation:
            'No matching GameData result found for "$query". The local GameData knowledge DB is installed, but structured/FTS search returned no result.',
      );
    }

    return const ToolExecutionResult(
      observation:
          'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
    );
  }

  ToolExecutionResult _formatGameDataResults(
    List<GameDataSearchResult> results, {
    required String searchMode,
  }) {
    final buffer = StringBuffer();
    var omittedResults = 0;

    if (searchMode == 'summary') {
      buffer.writeln(
        'Retrieval Plan: summary mode = entity document first, then story context, then raw records and FTS fallback.',
      );
      buffer.writeln();
    }
    if (searchMode == 'evidence') {
      buffer.writeln(
        'Retrieval Plan: evidence mode = resolved story scope and entity intersection, then claim-term match.',
      );
      buffer.writeln();
    }

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final remainingBudget = _maxObservationChars - buffer.length;
      if (remainingBudget <= 900) {
        omittedResults = results.length - i;
        break;
      }

      buffer.writeln(
        '=== Result #${i + 1} (Score: ${result.score.toStringAsFixed(4)}) ===',
      );
      buffer.writeln('Source Kind: ${result.sourceKind}');
      buffer.writeln('Source Type: ${result.sourceType}');
      buffer.writeln('Retrieval Type: ${result.retrievalType}');
      if (result.retrievalType == 'scoped_story_evidence') {
        buffer.writeln('Evidence Scope Match: yes');
        buffer.writeln('Evidence Level: direct candidate');
      }
      buffer.writeln('Ranking Reason: ${result.rankingReason}');
      buffer.writeln('ID: ${result.id}');
      if (result.contentCategory != null) {
        buffer.writeln('Content Category: ${result.contentCategory}');
      }
      if (result.contentSubtype != null) {
        buffer.writeln('Content Subtype: ${result.contentSubtype}');
      }
      if (result.contentType != null) {
        buffer.writeln('Content Type: ${result.contentType}');
      }
      if (result.entityId != null) {
        buffer.writeln('Entity ID: ${result.entityId}');
      }
      if (result.storyId != null) {
        buffer.writeln('Story ID: ${result.storyId}');
      }
      buffer.writeln('Title: ${result.title}');
      if (result.section != null && result.section!.isNotEmpty) {
        buffer.writeln('Section: ${result.section}');
      }
      if (result.sourcePath != null) {
        buffer.writeln('Source Path: ${result.sourcePath}');
      }
      if (result.rawId != null) {
        buffer.writeln('Raw ID: ${result.rawId}');
      }
      if (result.lineStart != null || result.lineEnd != null) {
        buffer.writeln(
            'Lines: ${result.lineStart ?? '?'}-${result.lineEnd ?? '?'}');
      }
      buffer.writeln('Trust: GameData / game original text (highest).');
      buffer.writeln('Content Excerpt:\n${_excerpt(result.content)}');
      buffer.writeln();
    }

    if (omittedResults > 0) {
      buffer.writeln(
        'Note: $omittedResults additional GameData result(s) were omitted to keep the agent context concise.',
      );
    }
    buffer.writeln(
      'Note: Content excerpts may be truncated. Use the listed ID/source_path/raw_id for exact citation details.',
    );

    return ToolExecutionResult(observation: buffer.toString().trim());
  }

  ToolExecutionResult _formatDisambiguationCandidates(
    String query,
    List<GameDataEntityCandidate> candidates,
  ) {
    final buffer = StringBuffer()
      ..writeln('Ambiguous GameData entity query: "$query".')
      ..writeln(
        'Multiple exact entity candidates were found. Ask the user to choose one, or call search_local_lore again with entity_id.',
      )
      ..writeln();

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      buffer.writeln('=== Candidate #${i + 1} ===');
      buffer.writeln('Entity ID: ${candidate.entityId}');
      buffer.writeln('Name: ${candidate.name}');
      buffer.writeln('Entity Type: ${candidate.entityType}');
      buffer.writeln('Matched Alias: ${candidate.matchedAlias}');
      buffer.writeln('Match Type: ${candidate.matchType}');
      buffer.writeln(
        'Confidence: ${candidate.confidence.toStringAsFixed(2)}',
      );
      buffer.writeln('Source Type: ${candidate.sourceType}');
      if (candidate.sourcePath != null) {
        buffer.writeln('Source Path: ${candidate.sourcePath}');
      }
      buffer.writeln('Trust: GameData / game original text (highest).');
      buffer.writeln();
    }

    return ToolExecutionResult(observation: buffer.toString().trim());
  }

  String _excerpt(String content) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= _maxContentExcerptChars) return normalized;
    return '${normalized.substring(0, _maxContentExcerptChars)}... [truncated]';
  }
}
