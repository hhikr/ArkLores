import '../../gamedata/game_retrieval.dart';
import '../../llm/embedding_client.dart';
import 'agent_tool.dart';
import 'observation_data.dart';

/// R12 raw story-line search (the planner's `FIND` intent): finds which
/// stories — and which line ranges — talk about a phrase or idea, so the
/// agent can READ those lines.
///
/// Two legs fused per story with reciprocal-rank fusion:
/// - semantic: query embedding vs `story_chunk_vectors` (when an embedding
///   client is configured AND the DB carries vectors from the same model);
/// - keyword: any term per line, ranked by IDF-weighted matched terms (LIKE;
///   exact names and wording; R14 — was every term in one line).
/// R14: official chapter synopses that contain a term are listed first.
/// Either leg alone still works. All hits are LOCATING HINTS (CLAUDE.md
/// principle 5): only lines returned by `read_story_lines` become evidence.
class SearchStoryLinesTool extends AgentTool {
  SearchStoryLinesTool({
    GameDataRetrieval? gameDataStore,
    EmbeddingClient? embeddingClient,
  })  : _gameDataStore = gameDataStore,
        _embeddingClient = embeddingClient;
  static const int _maxLineChars = 90;
  static const int _rrfK = 60;

  final GameDataRetrieval? _gameDataStore;
  final EmbeddingClient? _embeddingClient;

  @override
  String get name => 'search_story_lines';

  @override
  String get description =>
      'Search raw story lines (dialogue and narration) for a phrase or an '
      'idea. Returns the best-matching stories with line ranges and short '
      'samples. Use the result to choose READ ranges; hits are locating '
      'hints, not evidence.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Phrase, question or space-separated terms.',
          },
          'scope_id': {
            'type': 'string',
            'description':
                'Optional canonical scope key, e.g. activity:<activity_id> or obt:main.',
          },
          'top_k': {
            'type': 'integer',
            'description': 'Number of stories to return. Default 6, max 10.',
          },
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) return 'Error: query parameter is empty';
    // R15: a single chapter is not a search scope (a live run repeated
    // `FIND x @<file>.txt` seven times, matching nothing); lines inside a
    // known chapter are read with READ.
    var rawScope = '${arguments['scope_id'] ?? ''}'.trim();
    if (rawScope.startsWith('@')) rawScope = rawScope.substring(1).trim();
    final isFile = rawScope.endsWith('.txt') ||
        (rawScope.contains('/') &&
            !RegExp(r'^activities/[^/]+/?$').hasMatch(rawScope));
    if (isFile) {
      final file = rawScope.endsWith('.txt') ? rawScope : '$rawScope.txt';
      return ToolExecutionResult(
        observation: '“$file”是单个章节文件，不是检索范围。要看这一章里的内容，'
            '直接 READ $file <起始行> <结束行>（检索结果已给出行号）；要在整个故事集'
            '里检索，scope 用 activity:<活动id>，或去掉 scope 检索全库。',
      );
    }
    final scopeId = normalizeScopeId(arguments['scope_id'] as String?);
    final topK = ((arguments['top_k'] as num?)?.toInt() ?? 6).clamp(1, 10);

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    // Keyword leg.
    final terms = [
      for (final t in query.split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];
    final keywordHits = await store.searchStoryLinesLike(
      terms,
      scopeId: scopeId,
      storyLimit: topK * 2,
    );

    // Semantic leg.
    final semantic = await _semanticHits(store, query, scopeId, topK * 4);
    final vectorHits = semantic.hits;

    // R15: terms with no literal line — near names for a term the DB lacks,
    // hits outside the scope for a term the scope lacks.
    final termNotes = await _termNotes(store, terms, scopeId);
    final anyLiteralElsewhere = termNotes.elsewhere;

    if (keywordHits.isEmpty && vectorHits.isEmpty) {
      return ToolExecutionResult(
        observation: [
          'No story line matches "$query"'
              '${scopeId == null ? '' : ' in $scopeId'} '
              '(${semantic.mode}). Try other wording, fewer terms, or COVER an '
              'entity name.',
          ...termNotes.lines,
        ].join('\n'),
      );
    }

    // Reciprocal-rank fusion per story.
    final fused = <String, _StoryResult>{};
    for (var rank = 0; rank < keywordHits.length; rank++) {
      final hit = keywordHits[rank];
      fused.putIfAbsent(hit.storyId, () => _StoryResult(hit.storyId, hit.scopeId))
        ..score += 1 / (_rrfK + rank + 1)
        ..keyword = hit;
    }
    final storyRank = <String, int>{};
    for (final hit in vectorHits) {
      final result = fused.putIfAbsent(
        hit.storyId,
        () => _StoryResult(hit.storyId, hit.scopeId),
      );
      if (!storyRank.containsKey(hit.storyId)) {
        storyRank[hit.storyId] = storyRank.length;
        result.score += 1 / (_rrfK + storyRank[hit.storyId]! + 1);
      }
      if (result.chunks.length < 3) result.chunks.add(hit);
    }
    final ranked = fused.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final top = ranked.take(topK).toList();
    final labels = await store.storyCatalogEntries(
      [for (final r in top) r.storyId],
    );
    // R14: official chapter synopses that mention the terms point at the
    // chapters where an event is set up, not only where it is spoken of.
    final synopsisHits = await store.searchStorySynopses(
      terms,
      collectionId: _collectionOf(scopeId),
      limit: 4,
    );

    final buffer = StringBuffer()
      ..writeln('Story line hits for "$query" (${semantic.mode}; locating '
          'hints — READ the lines before using them as evidence):');
    if (synopsisHits.isNotEmpty) {
      buffer.writeln('官方章节梗概命中（只是定位线索）:');
      for (final entry in synopsisHits) {
        buffer.writeln('  ${entry.storyId} 《${entry.label}》: '
            '${_clip(entry.synopsis ?? '', 80)}');
      }
    }
    // R12: nearest-neighbour search always returns *something*, even for a
    // name that never occurs (live negative case: a fictional name "hit"
    // unrelated chapters). Scores of related and unrelated chunks overlap,
    // so instead of a threshold the observation states it plainly.
    for (final note in termNotes.lines) {
      buffer.writeln(note);
    }
    if (keywordHits.isEmpty) {
      buffer.writeln('注意：${scopeId == null ? '' : '范围内'}原文中没有任何一行包含'
          '这些词中的任何一个。以下只是语义相近的段落，可能与问题无关'
          '${anyLiteralElsewhere || termNotes.hasSuggestions ? '；先看上面的近似名或范围外命中' : '；若要找的是专有名词，这通常意味着资料未覆盖'}。');
    } else if (terms.length > 1 &&
        keywordHits.every((h) => h.bestTermCount < terms.length)) {
      buffer.writeln('注意：没有一行同时包含全部 ${terms.length} 个词；结果按单行'
          '命中词数和词的稀有度排序。问题里的抽象词（如“原因”“谁”）通常不会出现在'
          '原文中，可改搜人物、动作、物件。');
    }
    for (final result in top) {
      final keyword = result.keyword;
      final label = labels[result.storyId]?.label;
      buffer.writeln(
        'Story: ${result.storyId}'
        '${label == null ? '' : ' | 《$label》'} | Scope: ${result.scopeId ?? '-'}'
        '${keyword == null ? ' | 无字面命中（仅语义相近）' : ' | Keyword lines: ${keyword.hits}'
            '${terms.length > 1 ? '（单行最多命中 ${keyword.bestTermCount}/${terms.length} 词）' : ''}'}',
      );
      for (final chunk in result.chunks) {
        buffer.writeln(
          '  Lines ${chunk.lineStart}-${chunk.lineEnd} '
          '(semantic ${chunk.score.toStringAsFixed(2)})',
        );
      }
      for (final line in keyword?.lines ?? const <StoryLineEntry>[]) {
        final text = line.speaker == null || line.speaker!.trim().isEmpty
            ? line.content
            : '${line.speaker}：${line.content}';
        final clipped = text.length > _maxLineChars
            ? '${text.substring(0, _maxLineChars)}…'
            : text;
        buffer.writeln('  L${line.lineIndex}: $clipped');
      }
    }
    return ToolExecutionResult(
      observation: appendDataBlock(buffer.toString().trim(), {
        'type': 'search_story_lines',
        'query': query,
        'mode': semantic.mode,
        'stories': [
          for (final result in top)
            {
              'story_id': result.storyId,
              'keyword_hits': result.keyword?.hits ?? 0,
              'keyword_lines': [
                for (final l in result.keyword?.lines ?? const <StoryLineEntry>[])
                  l.lineIndex,
              ],
              'semantic_ranges': [
                for (final c in result.chunks) [c.lineStart, c.lineEnd],
              ],
            },
        ],
      }),
    );
  }

  /// Notes for terms without a literal line: near names when the whole DB
  /// lacks a term (a misspelt name), where else it occurs when only the
  /// scope lacks it.
  Future<({List<String> lines, bool elsewhere, bool hasSuggestions})>
      _termNotes(
    GameDataRetrieval store,
    List<String> terms,
    String? scopeId,
  ) async {
    final lines = <String>[];
    var elsewhere = false;
    var suggestions = false;
    final Map<String, ({int all, int inScope})> counts;
    try {
      counts = await store.storyLineTermCounts(terms, scopeId: scopeId);
    } catch (_) {
      return (lines: lines, elsewhere: false, hasSuggestions: false);
    }
    for (final entry in counts.entries) {
      final term = entry.key;
      final count = entry.value;
      if (count.all == 0) {
        final hint = describeSimilarNames(term, await store.similarNames(term));
        lines.add(hint ?? '库中没有“$term”这个写法，也没有字形或读音相近的名字。');
        suggestions = suggestions || hint != null;
      } else if (scopeId != null && count.inScope == 0) {
        elsewhere = true;
        final outside = await store.searchStoryLinesLike(
          [term],
          storyLimit: 3,
          linesPerStory: 1,
        );
        final labels = await store.storyCatalogEntries(
          [for (final h in outside) h.storyId],
        );
        final where = [
          for (final h in outside)
            '${h.storyId}（${labels[h.storyId]?.label ?? fallbackStoryLabel(h.storyId)}，${h.hits} 行）',
        ].join('、');
        lines.add('范围外命中：“$term”在 $scopeId 内 0 行，全库 ${count.all} 行，'
            '例如 $where。去掉 scope 再 FIND 可看全部。');
      }
    }
    return (lines: lines, elsewhere: elsewhere, hasSuggestions: suggestions);
  }

  /// Collection id of an activity scope key (`activity:act33side` →
  /// `act33side`); other scopes span several collections.
  static String? _collectionOf(String? scopeId) {
    if (scopeId == null || !scopeId.startsWith('activity:')) return null;
    return scopeId.substring('activity:'.length);
  }

  static String _clip(String text, int max) =>
      text.length > max ? '${text.substring(0, max)}…' : text;

  /// Embeds [query] and searches the vector index; reports which mode ran.
  Future<({List<StoryChunkHit> hits, String mode})> _semanticHits(
    GameDataRetrieval store,
    String query,
    String? scopeId,
    int topK,
  ) async {
    final client = _embeddingClient;
    if (client == null) {
      return (hits: const <StoryChunkHit>[], mode: 'keyword only: no embedding API configured');
    }
    final info = await store.storyVectorInfo;
    if (info == null) {
      return (hits: const <StoryChunkHit>[], mode: 'keyword only: knowledge base has no vectors');
    }
    if (info.model != client.model || info.dims != client.dimensions) {
      return (
        hits: const <StoryChunkHit>[],
        mode: 'keyword only: vectors are ${info.model}@${info.dims}, '
            'configured ${client.model}@${client.dimensions}',
      );
    }
    try {
      final vector = (await client.embed([query])).single;
      final hits = await store.searchStoryChunksByVector(
        vector,
        scopeId: scopeId,
        topK: topK,
      );
      return (hits: hits, mode: 'semantic + keyword');
    } catch (e) {
      return (hits: const <StoryChunkHit>[], mode: 'keyword only: embedding failed ($e)');
    }
  }
}

/// R14: canonical scope key from what the planner wrote: `@` prefix and
/// `activities:` spelling tolerated, and a bare id (`act21mini`) is an
/// activity scope, since `obt` scopes are always written with their prefix.
String? normalizeScopeId(String? raw) {
  var scope = raw?.trim() ?? '';
  if (scope.startsWith('@')) scope = scope.substring(1).trim();
  if (scope.isEmpty) return null;
  if (scope.startsWith('activities:')) {
    scope = 'activity:${scope.substring('activities:'.length)}';
  }
  // R15: a story-path spelling (`activities/<id>` or `activities/<id>/`)
  // names the activity, as in OUTLINE.
  final path = RegExp(r'^activities/([^/]+)/?$').firstMatch(scope);
  if (path != null) return 'activity:${path.group(1)}';
  if (!scope.contains(':') && scope != 'obt') scope = 'activity:$scope';
  return scope;
}

class _StoryResult {
  _StoryResult(this.storyId, this.scopeId);
  final String storyId;
  final String? scopeId;
  double score = 0;
  StoryLineHit? keyword;
  final List<StoryChunkHit> chunks = [];
}
