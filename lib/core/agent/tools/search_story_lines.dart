import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';
import 'observation_data.dart';

/// R12 raw story-line search (the planner's `FIND` intent): finds which
/// stories contain a phrase and where, so the agent can READ those lines.
///
/// Hits are LOCATING HINTS only (CLAUDE.md principle 5): the observation
/// says so explicitly, and only lines returned by `read_story_lines` enter
/// the evidence notebook.
class SearchStoryLinesTool extends AgentTool {
  SearchStoryLinesTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  static const int _maxLineChars = 90;

  final GameDataRetrieval? _gameDataStore;

  @override
  String get name => 'search_story_lines';

  @override
  String get description =>
      'Search raw story lines (dialogue and narration) for a phrase. '
      'Space-separated terms must all appear in the same line. Returns the '
      'stories with the most matching lines, each with line numbers and short '
      'samples. Use the result to choose READ ranges; hits are locating hints, '
      'not evidence.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Phrase or space-separated terms, e.g. 巴别塔 刺杀.',
          },
          'scope_id': {
            'type': 'string',
            'description':
                'Optional canonical scope key, e.g. activity:act21mini or obt:main.',
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
    final scopeId = (arguments['scope_id'] as String?)?.trim();
    final topK = ((arguments['top_k'] as num?)?.toInt() ?? 6).clamp(1, 10);

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final terms = query.split(RegExp(r'\s+'));
    final hits = await store.searchStoryLinesLike(
      terms,
      scopeId: scopeId == null || scopeId.isEmpty ? null : scopeId,
      storyLimit: topK,
    );
    if (hits.isEmpty) {
      return ToolExecutionResult(
        observation: 'No story line contains "$query"'
            '${scopeId == null || scopeId.isEmpty ? '' : ' in $scopeId'}. '
            'Try fewer or shorter terms, a synonym, or COVER an entity name.',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Story line hits for "$query" (locating hints — READ the '
          'lines before using them as evidence):');
    for (final hit in hits) {
      buffer.writeln(
        'Story: ${hit.storyId} | Scope: ${hit.scopeId ?? '-'} | '
        'Matching lines: ${hit.hits}',
      );
      for (final line in hit.lines) {
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
        'stories': [
          for (final hit in hits)
            {
              'story_id': hit.storyId,
              'hits': hit.hits,
              'lines': [for (final l in hit.lines) l.lineIndex],
            },
        ],
      }),
    );
  }
}
