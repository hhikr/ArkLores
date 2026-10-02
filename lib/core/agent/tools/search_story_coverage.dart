import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';
import 'collection_scope.dart';

/// Enumerates every appearance of an entity across stories (schema v3
/// `entity_story_mentions`). Deterministic coverage: independent of query
/// phrasing, so a narrow compound query can never silently miss appearances.
///
/// R15: the observation starts with an overview of EVERY collection the
/// entity appears in (release order, chapter and mention counts), then
/// per-chapter details shared round-robin between collections. The old
/// output listed runs in scope-name order and cut off after the first
/// collection or two, so an entity seemed to appear only there.
class SearchStoryCoverageTool extends AgentTool {
  SearchStoryCoverageTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  static const int _maxObservationChars = 4800;

  /// Line runs listed per chapter in the details.
  static const int _runsPerStory = 6;

  final GameDataRetrieval? _gameDataStore;

  @override
  String get name => 'search_story_coverage';

  @override
  String get description =>
      'Enumerate all story appearances (collections, chapters, line ranges, '
      'mention counts) of an entity. Pass a resolved entity_id, or a name to '
      'disambiguate first. Starts with an overview of every collection the '
      'entity appears in, in release order. Use before reading story lines '
      'to pick which chapters to read.';

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
                'Optional canonical scope key to restrict to, e.g. activity:<activity_id> or obt:main.',
          },
        },
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final query = (arguments['query'] as String?)?.trim();
    final entityIdArg = (arguments['entity_id'] as String?)?.trim();
    var scopeFilter = (arguments['scope_filter'] as String?)?.trim();
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
    // R16: a collection id that is not a scope (`main_9`) keeps that
    // collection's chapters of the whole coverage.
    final collectionStories = await collectionScopeStories(store, scopeFilter);
    if (collectionStories != null) scopeFilter = null;

    var entityId = entityIdArg;
    String? matchedEntityLabel;
    List<StoryCoverageEntry> entries;
    if (entityId == null || entityId.isEmpty) {
      final candidates = await store.findEntityCandidates(query!);
      final exact = candidates
          .where((candidate) =>
              candidate.matchType == 'name_exact' ||
              candidate.matchType == 'canonical_alias_exact' ||
              candidate.matchType == 'alias_exact',)
          .toList(growable: false);
      if (candidates.isEmpty) {
        // R15: a misspelt name resolves to nothing; say which names the DB
        // does contain that look or sound alike — unless the story text has
        // the string (a name without an entity), which FIND can search.
        final inText =
            (await store.storyLineTermCounts([query]))[query]?.all ?? 0;
        final hint = inText > 0
            ? '没有名为“$query”的实体，但剧情原文有 $inText 行包含它：用 FIND $query 查找。'
            : describeSimilarNames(query, await store.similarNames(query)) ??
                '库中没有“$query”这个写法，也没有字形或读音相近的名字。';
        return ToolExecutionResult(
          observation:
              'No entity found for "$query" in the local GameData knowledge base.'
              '\n$hint',
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
    if (collectionStories != null) {
      entries = [
        for (final e in entries)
          if (collectionStories.contains(e.storyId)) e,
      ];
    }
    if (entries.isEmpty) {
      return ToolExecutionResult(
        observation:
            'No story coverage found for entity "$entityId". The entity may '
            'not appear in any imported story, or the coverage layer is '
            'missing (old schema).\nCoverage Scopes: 0',
      );
    }

    final catalog = await _catalogOf(store, entries);
    final collections = _groupByCollection(entries, catalog);

    final buffer = StringBuffer()
      ..writeln(
        matchedEntityLabel == null
            ? 'Entity: $entityId'
            : 'Entity: $matchedEntityLabel',
      );
    final totalStories = collections.fold<int>(0, (n, c) => n + c.stories.length);
    buffer.writeln(
      '出场总览（共 ${collections.length} 个故事集 / $totalStories 章，'
      '按上线时间排序；只是定位线索）:',
    );
    for (var i = 0; i < collections.length; i++) {
      buffer.writeln('  ${i + 1}. ${collections[i].overviewLine()}');
    }
    buffer.writeln('出场明细（各故事集提及最多的章节，行号是出场位置）:');

    // Round-robin: each pass adds every collection's next-most-mentioned
    // chapter, so a long collection cannot use up the whole budget.
    final listed = <String>{};
    var omittedStories = 0;
    var budgetLeft = true;
    for (var pass = 0; budgetLeft; pass++) {
      var addedThisPass = false;
      for (final collection in collections) {
        if (pass >= collection.stories.length) continue;
        final story = collection.stories[pass];
        final line = story.detailLine(collection.label);
        if (buffer.length + line.length > _maxObservationChars - 200) {
          budgetLeft = false;
          break;
        }
        buffer.writeln(line);
        listed.add(story.storyId);
        addedThisPass = true;
      }
      if (!addedThisPass) break;
    }
    omittedStories = totalStories - listed.length;

    buffer.writeln();
    buffer.writeln('Coverage Scopes: ${{for (final e in entries) e.scopeId}.length}');
    buffer.writeln('Coverage Stories: $totalStories');
    if (omittedStories > 0) {
      buffer.writeln(
        'Note: 另有 $omittedStories 章的出场明细未列出；需要时用 '
        'COVER <名字> scope=<scope_id> 查看某个故事集的全部出场，'
        '或用 OUTLINE <故事集> 看章节梗概。',
      );
    }
    return ToolExecutionResult(observation: buffer.toString().trim());
  }

  Future<Map<String, StoryCatalogEntry>> _catalogOf(
    GameDataRetrieval store,
    List<StoryCoverageEntry> entries,
  ) async {
    try {
      return await store.storyCatalogEntries({for (final e in entries) e.storyId});
    } catch (_) {
      // Names are a convenience; raw ids still work.
      return const {};
    }
  }

  /// Groups appearance runs by collection (catalog collection, else scope),
  /// collections in release order, chapters by mentions (most first).
  List<_CollectionCoverage> _groupByCollection(
    List<StoryCoverageEntry> entries,
    Map<String, StoryCatalogEntry> catalog,
  ) {
    final byStory = <String, _StoryCoverage>{};
    for (final entry in entries) {
      byStory
          .putIfAbsent(
            entry.storyId,
            () => _StoryCoverage(entry.storyId, entry.scopeId, entry.title,
                catalog[entry.storyId],),
          )
          .add(entry);
    }
    final byCollection = <String, _CollectionCoverage>{};
    for (final story in byStory.values) {
      final key = story.catalog?.collectionId ?? story.scopeId;
      byCollection
          .putIfAbsent(key, () => _CollectionCoverage(key, story.catalog))
          .stories
          .add(story);
    }
    final collections = byCollection.values.toList()
      ..sort((a, b) => compareReleaseKeys(a.releaseKey, b.releaseKey));
    for (final collection in collections) {
      collection.stories.sort((a, b) {
        final byMentions = b.mentions.compareTo(a.mentions);
        if (byMentions != 0) return byMentions;
        return a.order.compareTo(b.order);
      });
    }
    return collections;
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

/// One chapter's appearance runs.
class _StoryCoverage {
  _StoryCoverage(this.storyId, this.scopeId, this.title, this.catalog);
  final String storyId;
  final String scopeId;
  final String? title;
  final StoryCatalogEntry? catalog;
  final List<StoryCoverageEntry> runs = [];
  int mentions = 0;

  void add(StoryCoverageEntry entry) {
    runs.add(entry);
    mentions += entry.mentionCount;
  }

  /// In-collection order (catalog sort, else the file name).
  int get order => catalog?.storySort ?? 1 << 30;

  String get label =>
      catalog?.chapterLabel ?? title ?? fallbackStoryLabel(storyId);

  String detailLine(String collectionLabel) {
    runs.sort((a, b) => a.lineStart.compareTo(b.lineStart));
    final shown = runs.take(SearchStoryCoverageTool._runsPerStory).map(
          (r) => r.lineStart == r.lineEnd
              ? '${r.lineStart}'
              : '${r.lineStart}-${r.lineEnd}',
        );
    final more = runs.length > SearchStoryCoverageTool._runsPerStory
        ? ' 等 ${runs.length} 处'
        : '';
    final aliases = {
      for (final r in runs)
        if (r.matchedAlias != null && r.matchedAlias!.isNotEmpty)
          r.matchedAlias!,
    };
    final name = catalog == null
        ? label
        : '$collectionLabel ${catalog!.chapterLabel}'.trim();
    return 'Story: $storyId | $name | '
        'Mentions: $mentions | Lines: ${shown.join(', ')}$more'
        '${aliases.isEmpty ? '' : ' | Alias: ${aliases.join('/')}'}';
  }
}

/// One collection's chapters.
class _CollectionCoverage {
  _CollectionCoverage(this.key, this.catalog);
  final String key;
  final StoryCatalogEntry? catalog;
  final List<_StoryCoverage> stories = [];

  String get label =>
      catalog?.collectionLabel ??
      '${fallbackStoryLabel(stories.first.storyId).split(' · ').first}（$key）';

  (int, int, String) get releaseKey => collectionReleaseKey(
        collectionId: catalog?.collectionId ?? key,
        collectionType: catalog?.collectionType ?? '',
        startTime: catalog?.startTime,
      );

  String overviewLine() {
    final mentions = stories.fold<int>(0, (n, s) => n + s.mentions);
    final release = catalog?.releaseMonth;
    final ordered = [...stories]..sort((a, b) => a.order.compareTo(b.order));
    String code(_StoryCoverage s) =>
        s.catalog?.storyCode ??
        s.storyId.split('/').last.replaceAll(RegExp(r'\.txt$'), '');
    final span = ordered.length == 1
        ? code(ordered.first)
        : '${code(ordered.first)} … ${code(ordered.last)}';
    final id = catalog == null ? '' : '（${catalog!.collectionId}'
        '${release == null ? '' : '，上线 $release'}）';
    return '$label$id: ${stories.length} 章，提及 $mentions 次，$span';
  }
}
