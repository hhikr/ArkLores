import '../../gamedata/build/story_coverage_builder.dart'
    show extractCharacterBigrams;
import '../../gamedata/gamedata_knowledge_store.dart';
import 'agent_tool.dart';
import 'observation_data.dart';

/// Cross-chapter detail matching (P1): extracts rare feature terms from a
/// known passage (the death scene) and finds their other occurrences across
/// the whole story corpus, locating foreshadowing lines that a similarity
/// ranking would never surface. Rare terms use the `rare_terms` IDF table;
/// entity names/aliases are excluded so characters cannot dominate the terms.
class FindDetailEchoesTool extends AgentTool {
  FindDetailEchoesTool({GameDataKnowledgeStore? gameDataStore})
      : _gameDataStore = gameDataStore ?? GameDataKnowledgeStore();
  static const int _maxObservationChars = 4800;

  final GameDataKnowledgeStore? _gameDataStore;

  @override
  String get name => 'find_detail_echoes';

  @override
  String get description =>
      'Extract rare feature terms from a passage (source_text, or a '
      'story_id + line range) and find their other occurrences across all '
      'stories. Use after locating the key scene to find cross-chapter '
      'foreshadowing details (e.g. the murder weapon). Returns term, story_id, '
      'line and snippet, plus a machine-readable DATA block.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'source_text': {
            'type': 'string',
            'description':
                'The passage to extract detail terms from. Omit when story_id + line range is given.',
          },
          'story_id': {
            'type': 'string',
            'description':
                'Story id whose lines form the passage (with start_line/end_line).',
          },
          'start_line': {
            'type': 'integer',
            'description': 'Optional inclusive start line of the passage.',
          },
          'end_line': {
            'type': 'integer',
            'description': 'Optional inclusive end line of the passage.',
          },
          'max_terms': {
            'type': 'integer',
            'description': 'Max rare terms to search. Default 5, max 10.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Max matches per term. Default 10, max 20.',
          },
        },
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final sourceText = (arguments['source_text'] as String?)?.trim();
    final storyId = (arguments['story_id'] as String?)?.trim();
    final startLine = (arguments['start_line'] as num?)?.toInt();
    final endLine = (arguments['end_line'] as num?)?.toInt();
    final maxTerms = (arguments['max_terms'] as num?)?.toInt() ?? 5;
    final maxResults = (arguments['max_results'] as num?)?.toInt() ?? 10;
    final cleanMaxTerms = maxTerms.clamp(1, 10);
    final cleanMaxResults = maxResults.clamp(1, 20);

    if ((sourceText == null || sourceText.isEmpty) &&
        (storyId == null || storyId.isEmpty)) {
      return 'Error: provide either source_text or story_id';
    }

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    // Resolve the passage.
    String passage;
    if (storyId != null && storyId.isNotEmpty) {
      final page = await store.readStoryLines(
        storyId: storyId,
        startLine: startLine,
        endLine: endLine,
        maxLines: 200,
      );
      if (!page.storyFound) {
        return ToolExecutionResult(
          observation: 'Story not found: $storyId',
        );
      }
      passage = page.lines.map((line) => line.content).join('\n');
    } else {
      passage = sourceText!;
    }
    if (passage.trim().isEmpty) {
      return 'Error: the passage is empty';
    }

    // Rare terms (IDF whitelist), excluding entity names/aliases.
    final rareTerms = await store.filterRareTerms(
      extractCharacterBigrams(passage),
    );
    final entityNames = await store.loadEntityNamesAndAliases();
    final termCounts = <String, int>{};
    final runes = passage.runes.toList(growable: false);
    for (var i = 0; i + 1 < runes.length; i++) {
      final bigram = String.fromCharCodes([runes[i], runes[i + 1]]);
      if (rareTerms.contains(bigram)) {
        termCounts[bigram] = (termCounts[bigram] ?? 0) + 1;
      }
    }
    final candidates = termCounts.entries
        .where(
          (entry) => !entityNames.any((name) => name.contains(entry.key)),
        )
        .toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Rank candidates by how many DISTINCT stories they echo in (excluding
    // the source story), then by passage count: terms that recur across
    // chapters are the ones that locate cross-chapter foreshadowing.
    final ranked = <({String term, int count, int stories})>[];
    for (final candidate in candidates.take(12)) {
      final rows = await store.searchStoryLinesContentLike(
        candidate.key,
        limit: 30,
      );
      final hitStories = <String>{};
      for (final row in rows) {
        final hitStory = '${row['story_id']}';
        if (storyId != null && storyId.isNotEmpty && hitStory == storyId) {
          continue;
        }
        hitStories.add(hitStory);
      }
      if (hitStories.isEmpty) continue;
      ranked.add((
        term: candidate.key,
        count: candidate.value,
        stories: hitStories.length,
      ),);
    }
    ranked.sort((a, b) {
      final byStories = b.stories.compareTo(a.stories);
      return byStories != 0 ? byStories : b.count.compareTo(a.count);
    });
    final selectedTerms = ranked.take(cleanMaxTerms).toList(growable: false);

    if (selectedTerms.isEmpty) {
      final data = <String, Object?>{
        'type': 'find_detail_echoes',
        'terms': <String>[],
        'matches': <Object?>[],
        'total': 0,
      };
      return ToolExecutionResult(
        observation: appendDataBlock(
          'No rare detail terms found in the passage. The passage may only '
          'contain common words or entity names.',
          data,
        ),
      );
    }

    // Search echoes across all stories (excluding the source story).
    final matches = <Map<String, Object?>>[];
    final buffer = StringBuffer();
    var omitted = 0;
    for (var t = 0; t < selectedTerms.length; t++) {
      final term = selectedTerms[t];
      final rows = await store.searchStoryLinesContentLike(
        term.term,
        limit: cleanMaxResults,
      );
      for (final row in rows) {
        final hitStory = '${row['story_id']}';
        if (storyId != null && storyId.isNotEmpty && hitStory == storyId) {
          continue;
        }
        final line = (row['line_index'] as num?)?.toInt() ?? 0;
        final content = '${row['content'] ?? ''}';
        final remaining = _maxObservationChars - buffer.length;
        if (remaining <= 200) {
          omitted += rows.length;
          break;
        }
        buffer.writeln(
          'Echo: ${term.term} | $hitStory | line $line | $content',
        );
        matches.add({
          'term': term.term,
          'story_id': hitStory,
          'line': line,
          'snippet': content,
        });
      }
    }

    final data = <String, Object?>{
      'type': 'find_detail_echoes',
      'terms': [for (final term in selectedTerms) term.term],
      'matches': matches,
      'total': matches.length,
    };
    if (matches.isEmpty) {
      return ToolExecutionResult(
        observation: appendDataBlock(
          'Rare terms [${selectedTerms.map((t) => t.term).join(', ')}] have '
          'no echoes outside the source passage.',
          data,
        ),
      );
    }

    final body = StringBuffer()
      ..writeln(
        'Detail Terms: ${selectedTerms.map((t) => '${t.term} (${t.count})').join(', ')}',
      )
      ..writeln();
    body.write(buffer);
    if (omitted > 0) {
      body.writeln(
        'Note: $omitted additional echo(s) omitted to keep the agent context concise.',
      );
    }
    return ToolExecutionResult(
      observation: appendDataBlock(body.toString().trim(), data),
    );
  }
}
