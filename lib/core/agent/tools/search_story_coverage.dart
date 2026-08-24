import '../../gamedata/gamedata_knowledge_store.dart';
import 'agent_tool.dart';

/// Enumerates every appearance of an entity across stories (schema v3
/// `entity_story_mentions`). Deterministic coverage: independent of query
/// phrasing, so a narrow compound query can never silently miss appearances.
class SearchStoryCoverageTool extends AgentTool {
  SearchStoryCoverageTool({GameDataKnowledgeStore? gameDataStore})
      : _gameDataStore = gameDataStore ?? GameDataKnowledgeStore();
  static const int _maxObservationChars = 4800;

  final GameDataKnowledgeStore? _gameDataStore;

  @override
  String get name => 'search_story_coverage';

  @override
  String get description =>
      'Enumerate all story appearances (story ids, scopes, line ranges, '
      'mention counts) of an entity. Pass a resolved entity_id, or a name to '
      'disambiguate first. Use before reading story lines to pick which '
      'chapters to read. Returns coverage counts as machine-readable markers.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Entity name or alias to resolve, e.g. 阿米娅. Omit when entity_id is provided.',
          },
          'entity_id': {
            'type': 'string',
            'description':
                'Resolved GameData entity id, e.g. char_002_amiya. Prefer this when already known.',
          },
          'scope_filter': {
            'type': 'string',
            'description':
                'Optional canonical scope key to restrict to, e.g. activity:act21mini or obt:main.',
          },
        },
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final query = (arguments['query'] as String?)?.trim();
    final entityIdArg = (arguments['entity_id'] as String?)?.trim();
    final scopeFilter = (arguments['scope_filter'] as String?)?.trim();
    if ((entityIdArg == null || entityIdArg.isEmpty) &&
        (query == null || query.isEmpty)) {
      return 'Error: provide either query or entity_id';
    }

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    var entityId = entityIdArg;
    String? matchedEntityLabel;
    if (entityId == null || entityId.isEmpty) {
      final candidates = await store.findEntityCandidates(query!);
      final exact = candidates
          .where((candidate) =>
              candidate.matchType == 'name_exact' ||
              candidate.matchType == 'canonical_alias_exact' ||
              candidate.matchType == 'alias_exact',)
          .toList(growable: false);
      if (exact.length > 1) {
        return _formatDisambiguationCandidates(query, exact);
      }
      if (candidates.isEmpty) {
        return ToolExecutionResult(
          observation:
              'No entity found for "$query" in the local GameData knowledge base.',
        );
      }
      final chosen = exact.isNotEmpty ? exact.first : candidates.first;
      entityId = chosen.entityId;
      matchedEntityLabel = '${chosen.name} (${chosen.entityId})';
    }

    final entries = await store.searchStoryCoverage(
      entityId: entityId,
      scopeFilter: scopeFilter,
    );
    if (entries.isEmpty) {
      return ToolExecutionResult(
        observation:
            'No story coverage found for entity "$entityId". The entity may '
            'not appear in any imported story, or the coverage layer is '
            'missing (old schema).\nCoverage Scopes: 0',
      );
    }

    final buffer = StringBuffer()
      ..writeln(
        matchedEntityLabel == null
            ? 'Entity: $entityId'
            : 'Entity: $matchedEntityLabel',
      );
    final scopes = <String>{};
    final stories = <String>{};
    String? currentScope;
    var omitted = 0;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final remaining = _maxObservationChars - buffer.length;
      if (remaining <= 900) {
        omitted = entries.length - i;
        break;
      }
      if (currentScope != entry.scopeId) {
        currentScope = entry.scopeId;
        scopes.add(entry.scopeId);
        buffer.writeln('Scope: ${entry.scopeId}');
      }
      stories.add(entry.storyId);
      buffer.writeln(
        'Story: ${entry.storyId} | Title: ${entry.title ?? '-'} | '
        'Lines: ${entry.lineStart}-${entry.lineEnd} | '
        'Mentions: ${entry.mentionCount} | Alias: ${entry.matchedAlias ?? '-'}',
      );
    }

    buffer.writeln();
    buffer.writeln('Coverage Scopes: ${scopes.length}');
    buffer.writeln('Coverage Stories: ${stories.length}');
    if (omitted > 0) {
      buffer.writeln(
        'Note: $omitted additional coverage row(s) omitted to keep the agent context concise.',
      );
    }

    return ToolExecutionResult(observation: buffer.toString().trim());
  }

  ToolExecutionResult _formatDisambiguationCandidates(
    String query,
    List<GameDataEntityCandidate> candidates,
  ) {
    final buffer = StringBuffer()
      ..writeln('Ambiguous GameData entity query: "$query".')
      ..writeln(
        'Multiple exact entity candidates were found. Ask the user to choose '
        'one, or call search_story_coverage again with entity_id.',
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
}
