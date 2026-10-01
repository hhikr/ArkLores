import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';

/// Returns chapter profiles (line range, speakers, entity density, summary,
/// triage keyword hits) for choosing which stories to read closely.
/// Profiles are browsing aids, not evidence.
class GetStoryMapTool extends AgentTool {
  GetStoryMapTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  static const int _maxObservationChars = 4800;

  final GameDataRetrieval? _gameDataStore;

  @override
  String get name => 'get_story_map';

  @override
  String get description =>
      'Get chapter profiles (line range, speaker set, top entities, extractive '
      'summary, triage keyword hits) for a list of story_ids or all stories of '
      'a scope_id. Use after search_story_coverage to choose which chapters to '
      'read. Returns machine-readable Mapped Stories / Scope markers.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional list of story ids. Mutually exclusive with scope_id.',
          },
          'scope_id': {
            'type': 'string',
            'description':
                'Optional canonical scope key (e.g. activity:act21mini, '
                'obt:main, obt:rogue) to list all its chapters (compact '
                'one-line-per-chapter list, ordered by chapter number). '
                'Mutually exclusive with story_ids.',
          },
          'page_token': {
            'type': 'string',
            'description':
                'Opaque continuation token from a previous get_story_map '
                'result (compact scope list). Echo it verbatim.',
          },
        },
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final rawStoryIds = arguments['story_ids'];
    final storyIds = rawStoryIds is List
        ? rawStoryIds.map((item) => '$item').toList(growable: false)
        : null;
    final scopeId = (arguments['scope_id'] as String?)?.trim();
    if ((storyIds == null || storyIds.isEmpty) &&
        (scopeId == null || scopeId.isEmpty)) {
      return 'Error: provide either story_ids or scope_id';
    }

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final profiles = await store.getStoryMap(
      storyIds: storyIds,
      scopeId: scopeId,
    );
    if (profiles.isEmpty) {
      return ToolExecutionResult(
        observation:
            'No chapter profiles found for the requested story ids/scope. The '
            'coverage layer may be missing (old schema) or the ids are invalid.\n'
            'Mapped Stories: 0',
      );
    }
    // Natural (chapter-number) ordering so 09_beg sorts after 09_a1 and before
    // 10_beg — plain lexicographic order buried the core chapters behind
    // interlude files and the observation budget (M4a).
    final sorted = [...profiles]
      ..sort((a, b) => _compareNatural(a.storyId, b.storyId));

    // Scope mode: compact one-line-per-chapter list so EVERY chapter of a
    // large activity stays visible within the observation budget. Full
    // profiles (speakers/entities/summary) are available via story_ids mode.
    final listMode = storyIds == null || storyIds.isEmpty;
    if (listMode) {
      return _buildCompactList(sorted, arguments);
    }

    final buffer = StringBuffer();
    var omitted = 0;
    for (var i = 0; i < sorted.length; i++) {
      final profile = sorted[i];
      final remaining = _maxObservationChars - buffer.length;
      if (remaining <= 600) {
        omitted = sorted.length - i;
        break;
      }
      buffer.writeln('=== Chapter #${i + 1} ===');
      buffer.writeln('Story: ${profile.storyId}');
      buffer.writeln('Scope: ${profile.scopeId}');
      buffer.writeln('Title: ${profile.title ?? '-'}');
      buffer.writeln('Lines: ${profile.lineStart}-${profile.lineEnd}');
      buffer.writeln('Speakers: ${profile.speakerSet.length} '
          '[${profile.speakerSet.take(8).join(', ')}${profile.speakerSet.length > 8 ? ', …' : ''}]');
      if (profile.entityDensity.isNotEmpty) {
        final top = profile.entityDensity.entries.take(5).map(
              (entry) => '${entry.key}(${entry.value})',
            ).join(', ');
        buffer.writeln('Top Entities: $top');
      }
      if (profile.summary != null && profile.summary!.isNotEmpty) {
        buffer.writeln('Summary: ${profile.summary}');
      }
      buffer.writeln();
    }

    buffer.writeln('Mapped Stories: ${sorted.length}');
    if (omitted > 0) {
      buffer.writeln(
        'Note: $omitted additional profile(s) omitted to keep the agent context concise.',
      );
    }
    return ToolExecutionResult(observation: buffer.toString().trim());
  }

  /// Compact scope listing: one line per chapter, paged by chapter index.
  ToolExecutionResult _buildCompactList(
    List<StoryChapterProfile> sorted,
    Map<String, dynamic> arguments,
  ) {
    final pageToken = int.tryParse(
      '${arguments['page_token'] ?? ''}'.trim(),
    );
    final pageStart = pageToken == null || pageToken < 0 ? 0 : pageToken;
    final buffer = StringBuffer();
    var index = 0;
    for (var i = pageStart; i < sorted.length; i++) {
      final profile = sorted[i];
      final remaining = _maxObservationChars - buffer.length;
      if (remaining <= 300) break;
      // Summaries are short (avg 53 chars, max ~200) and are the chapter
      // selection signal — keep them FULL, no truncation. A chapter list that
      // silently cut "屠戮魔王" made the model skip the assassination scene.
      final summary =
          (profile.summary ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      buffer.writeln(
        'Story: ${profile.storyId} | Lines: ${profile.lineStart}-${profile.lineEnd}'
        '${summary.isEmpty ? '' : ' | Summary: $summary'}',
      );
      index++;
    }
    final nextStart = pageStart + index;
    final hasMore = nextStart < sorted.length;
    buffer.writeln();
    buffer.writeln('Chapter List: ${sorted.length}');
    buffer.writeln(
      '提示: 用 story_ids 参数指定章节可获取完整画像（speakers/entities/完整摘要）。',
    );
    if (hasMore) {
      buffer.writeln('Next Page Token: $nextStart');
    } else {
      buffer.writeln('End of Chapters: yes');
    }
    return ToolExecutionResult(observation: buffer.toString().trim());
  }

  /// Natural comparison of story ids: digit runs compare numerically, so
  /// `level_act33side_09_beg` < `level_act33side_10_beg`.
  static int _compareNatural(String a, String b) {
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
        return -1; // numeric segment sorts before a text segment
      } else if (y is int) {
        return 1;
      } else {
        final c = (x as String).compareTo(y as String);
        if (c != 0) return c;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }
}
