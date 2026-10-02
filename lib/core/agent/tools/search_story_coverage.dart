import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';

/// Enumerates every appearance of an entity across stories (schema v3
/// `entity_story_mentions`). Deterministic coverage: independent of query
/// phrasing, so a narrow compound query can never silently miss appearances.
class SearchStoryCoverageTool extends AgentTool {
  SearchStoryCoverageTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  static const int _maxObservationChars = 4800;

  final GameDataRetrieval? _gameDataStore;

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
    final List<StoryCoverageEntry> entries;
    if (entityId == null || entityId.isEmpty) {
      final candidates = await store.findEntityCandidates(query!);
      final exact = candidates
          .where((candidate) =>
              candidate.matchType == 'name_exact' ||
              candidate.matchType == 'canonical_alias_exact' ||
              candidate.matchType == 'alias_exact',)
          .toList(growable: false);
      if (candidates.isEmpty) {
        return ToolExecutionResult(
          observation:
              'No entity found for "$query" in the local GameData knowledge base.',
        );
      }
      if (exact.length > 1) {
        // R12: same-name entities share their alias in the coverage trie, so
        // their appearances are (almost always) the same story lines — on
        // the v4 DB 499 of 515 shared aliases with coverage were identical.
        // Appearances are locating hints, so merge them instead of forcing a
        // disambiguation that cannot change what the agent can read.
        entityId = exact.first.entityId;
        matchedEntityLabel = '$query（合并 ${exact.length} 个同名实体: '
            '${exact.map((c) => c.entityId).join(', ')}）';
        entries = await _mergedCoverage(store, exact, scopeFilter);
      } else {
        final chosen = exact.isNotEmpty ? exact.first : candidates.first;
        entityId = chosen.entityId;
        matchedEntityLabel = '${chosen.name} (${chosen.entityId})';
        entries = await store.searchStoryCoverage(
          entityId: entityId,
          scopeFilter: scopeFilter,
        );
      }
    } else {
      entries = await store.searchStoryCoverage(
        entityId: entityId,
        scopeFilter: scopeFilter,
      );
    }
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

  /// Union of the appearance runs of [candidates], de-duplicated by story and
  /// line range, in the store's scope/story/line order.
  Future<List<StoryCoverageEntry>> _mergedCoverage(
    GameDataRetrieval store,
    List<GameDataEntityCandidate> candidates,
    String? scopeFilter,
  ) async {
    final seen = <String>{};
    final merged = <StoryCoverageEntry>[];
    for (final candidate in candidates) {
      for (final entry in await store.searchStoryCoverage(
        entityId: candidate.entityId,
        scopeFilter: scopeFilter,
      )) {
        if (seen.add('${entry.storyId}#${entry.lineStart}-${entry.lineEnd}')) {
          merged.add(entry);
        }
      }
    }
    merged.sort((a, b) {
      final scope = a.scopeId.compareTo(b.scopeId);
      if (scope != 0) return scope;
      final story = a.storyId.compareTo(b.storyId);
      if (story != 0) return story;
      return a.lineStart.compareTo(b.lineStart);
    });
    return merged;
  }
}
