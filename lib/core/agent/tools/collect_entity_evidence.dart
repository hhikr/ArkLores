import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';
import 'observation_data.dart';

/// Collects every appearance line of one entity via `entity_story_mentions`,
/// grouped by scope with pagination. Optional terms put the stories whose
/// lines contain them first. Appearance rows are locating hints: only text
/// read through READ becomes evidence.
class CollectEntityEvidenceTool extends AgentTool {
  CollectEntityEvidenceTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  static const int _maxObservationChars = 4800;
  static const int _pageSize = 4; // runs per page

  final GameDataRetrieval? _gameDataStore;

  @override
  String get name => 'collect_entity_evidence';

  @override
  String get description =>
      'Collect every appearance line of one entity (via the story coverage '
      'index), grouped by scope, with pagination. Returns the actual lines '
      'plus a machine-readable DATA block with row counts.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'entity_id': {
            'type': 'string',
            'description':
                'Entity id (resolved, e.g. char_002_amiya or speaker:<name>).',
          },
          'scope_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional scope keys to restrict to (e.g. activity:act21mini, obt:main).',
          },
          'terms': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional terms; stories whose lines contain them are listed first and matching lines are marked.',
          },
          'page_token': {
            'type': 'string',
            'description':
                'Opaque continuation token from a previous collect_entity_evidence result. Echo it verbatim.',
          },
        },
        'required': ['entity_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final entityId = (arguments['entity_id'] as String?)?.trim();
    if (entityId == null || entityId.isEmpty) {
      return 'Error: entity_id parameter is empty';
    }
    final rawScopes = arguments['scope_ids'];
    final scopeIds = rawScopes is List
        ? rawScopes.map((item) => '$item').toList(growable: false)
        : null;
    final rawTerms = arguments['terms'] ?? arguments['claim_terms'];
    final terms = rawTerms is List
        ? rawTerms.map((item) => '$item').toList(growable: false)
        : null;
    final pageToken = arguments['page_token'] as String?;
    var offset = int.tryParse(pageToken?.trim() ?? '') ?? 0;
    if (offset < 0) offset = 0;

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final entries = await store.searchStoryCoverage(entityId: entityId);
    var runs = entries;
    if (scopeIds != null && scopeIds.isNotEmpty) {
      final allowed = scopeIds.toSet();
      runs = entries
          .where((entry) => allowed.contains(entry.scopeId))
          .toList(growable: false);
    }
    // M4b: terms are prioritized GLOBALLY before paging, so the first page
    // shows the runs whose lines actually match them (an entity with
    // hundreds of appearance runs otherwise buries the relevant ones behind
    // unrelated daily dialogue). Non-matching runs follow in natural
    // story order so same-chapter runs stay grouped.
    if (terms != null && terms.isNotEmpty && runs.isNotEmpty) {
      final hitCounts = <String, int>{};
      final storyIds = runs.map((run) => run.storyId).toSet().toList();
      for (final term in terms) {
        final rows = await store.searchStoryLinesLikeInStories(term, storyIds);
        for (final row in rows) {
          final storyId = '${row['story_id']}';
          hitCounts[storyId] = (hitCounts[storyId] ?? 0) + 1;
        }
      }
      runs = List<StoryCoverageEntry>.of(runs)
        ..sort((a, b) {
          final ca = hitCounts[a.storyId] ?? 0;
          final cb = hitCounts[b.storyId] ?? 0;
          if (ca != cb) return cb.compareTo(ca);
          return _compareNatural(a.storyId, b.storyId);
        });
    }
    if (runs.isEmpty) {
      final data = <String, Object?>{
        'type': 'collect_entity_evidence',
        'entity_id': entityId,
        'evidence_rows': 0,
        'scopes': <String>[],
        'total_runs': 0,
        'next_page_token': null,
      };
      final hint = entries.isEmpty
          ? 'No appearances found for entity_id "$entityId". If you passed a '
              'display name, it was not resolved: call search_story_coverage '
              '(query: <name>) first to obtain the exact entity_id, then retry '
              'this tool with it.'
          : 'No appearances found for entity_id "$entityId" in the requested '
              'scopes (${scopeIds?.join(', ')}). Try omitting scope_ids to '
              'see all scopes, or pass the canonical scope key.';
      return ToolExecutionResult(
        observation: appendDataBlock(
          '$hint\nNo more evidence pages for "$entityId" (page 0 of 0 runs).',
          data,
        ),
      );
    }
    if (offset >= runs.length) {
      final data = <String, Object?>{
        'type': 'collect_entity_evidence',
        'entity_id': entityId,
        'evidence_rows': 0,
        'scopes': <String>[],
        'total_runs': runs.length,
        'next_page_token': null,
      };
      return ToolExecutionResult(
        observation: appendDataBlock(
          'No more evidence pages for "$entityId" (page $offset of '
          '${runs.length} runs).',
          data,
        ),
      );
    }

    final pageRuns = runs.sublist(
      offset,
      offset + _pageSize > runs.length ? runs.length : offset + _pageSize,
    );
    final buffer = StringBuffer();
    var evidenceRows = 0;
    final scopes = <String>{};
    var omitted = 0;

    for (var i = 0; i < pageRuns.length; i++) {
      final run = pageRuns[i];
      final remaining = _maxObservationChars - buffer.length;
      if (remaining <= 600) {
        omitted = pageRuns.length - i;
        break;
      }
      scopes.add(run.scopeId);
      final page = await store.readStoryLines(
        storyId: run.storyId,
        startLine: run.lineStart,
        endLine: run.lineEnd,
        maxLines: 60,
      );
      buffer.writeln(
        'Story: ${run.storyId} | Scope: ${run.scopeId} | '
        'Lines: ${run.lineStart}-${run.lineEnd}',
      );
      for (final line in page.lines) {
        final lineText = line.speaker == null || line.speaker!.trim().isEmpty
            ? '${line.lineIndex} | ${line.content}'
            : '${line.lineIndex} | ${line.speaker} | ${line.content}';
        final hasTerm = terms != null &&
            terms.any((term) => line.content.contains(term));
        buffer.writeln(hasTerm ? '[term] $lineText' : lineText);
        evidenceRows++;
      }
      buffer.writeln();
    }

    final processed = pageRuns.length - omitted;
    final nextOffset = offset + processed;
    final hasMore = nextOffset < runs.length;
    final data = <String, Object?>{
      'type': 'collect_entity_evidence',
      'entity_id': entityId,
      'evidence_rows': evidenceRows,
      'scopes': scopes.toList(),
      'total_runs': runs.length,
      'next_page_token': hasMore ? '$nextOffset' : null,
    };

    final body = StringBuffer()
      ..writeln('Entity: $entityId | Total appearance runs: ${runs.length}')
      ..writeln();
    body.write(buffer);
    if (omitted > 0) {
      body.writeln(
        'Note: $omitted additional run(s) omitted to keep the agent context concise.',
      );
    }
    if (hasMore) {
      body.writeln('Next Page Token: $nextOffset');
    } else {
      body.writeln('End of Evidence: yes');
    }
    return ToolExecutionResult(
      observation: appendDataBlock(body.toString().trim(), data),
    );
  }
}

/// Natural comparison of story ids: digit runs compare numerically, so
/// `level_act33side_09_beg` < `level_act33side_10_beg`.
int _compareNatural(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final aParts = [
    for (final m in re.allMatches(a))
      m.group(1) != null ? int.parse(m.group(1)!) : m.group(2)!,
  ];
  final bParts = [
    for (final m in re.allMatches(b))
      m.group(1) != null ? int.parse(m.group(1)!) : m.group(2)!,
  ];
  final len = aParts.length < bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < len; i++) {
    final x = aParts[i];
    final y = bParts[i];
    if (x is int && y is int) {
      if (x != y) return x.compareTo(y);
    } else if (x is int) {
      return -1;
    } else if (y is int) {
      return 1;
    } else {
      final c = (x as String).compareTo(y as String);
      if (c != 0) return c;
    }
  }
  return aParts.length.compareTo(bParts.length);
}
