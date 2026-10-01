import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';

/// Reads raw story lines by story id with window + pagination. Exposes the
/// original text so the agent can read key chapters directly instead of
/// relying only on similarity-ranked excerpts.
class ReadStoryLinesTool extends AgentTool {
  ReadStoryLinesTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  static const int _maxObservationChars = 4800;

  final GameDataRetrieval? _gameDataStore;

  @override
  String get name => 'read_story_lines';

  @override
  String get description =>
      'Read raw story lines (line_index, speaker, content) of one story file. '
      'Use start_line/end_line to bound the window and max_lines for page '
      'size. When the result is truncated, echo the returned Next Page Token '
      'verbatim in the next call\'s page_token to continue. Returns '
      'machine-readable Read Lines / Story / Scope markers.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_id': {
            'type': 'string',
            'description':
                'Story file id as returned by search_story_coverage, e.g. activities/act21mini/level_act21mini_st07.txt.',
          },
          'start_line': {
            'type': 'integer',
            'description': 'Optional inclusive starting line index.',
          },
          'end_line': {
            'type': 'integer',
            'description': 'Optional inclusive ending line index.',
          },
          'max_lines': {
            'type': 'integer',
            'description': 'Optional page size. Default 30, max 100.',
          },
          'page_token': {
            'type': 'string',
            'description':
                'Opaque continuation token from a previous read_story_lines result. Echo it verbatim.',
          },
        },
        'required': ['story_id'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final storyId = (arguments['story_id'] as String?)?.trim();
    if (storyId == null || storyId.isEmpty) {
      return 'Error: story_id parameter is empty';
    }
    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final startLine = (arguments['start_line'] as num?)?.toInt();
    final endLine = (arguments['end_line'] as num?)?.toInt();
    final maxLines = (arguments['max_lines'] as num?)?.toInt();
    final pageToken = arguments['page_token'] as String?;

    final page = await store.readStoryLines(
      storyId: storyId,
      startLine: startLine,
      endLine: endLine,
      maxLines: maxLines,
      pageToken: pageToken,
    );
    if (!page.storyFound) {
      return ToolExecutionResult(
        observation: 'Story not found: $storyId. Use search_story_coverage or '
            'get_story_map to obtain valid story ids.',
      );
    }
    if (page.lines.isEmpty) {
      return ToolExecutionResult(
        observation: 'No lines in the requested range for story "$storyId". '
            'Story: $storyId\nScope: ${page.scopeId ?? 'unknown'}\nRead Lines: 0',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Story: $storyId')
      ..writeln('Scope: ${page.scopeId ?? 'unknown'}');

    var included = 0;
    for (var i = 0; i < page.lines.length; i++) {
      final line = page.lines[i];
      final lineText = line.speaker == null || line.speaker!.trim().isEmpty
          ? '${line.lineIndex} | ${line.content}'
          : '${line.lineIndex} | ${line.speaker} | ${line.content}';
      final remaining = _maxObservationChars - buffer.length;
      if (remaining <= lineText.length + 2) {
        // Always include at least one line per page so the page token always
        // makes progress even when a single line exceeds the budget.
        if (included == 0) {
          final budget = remaining > 0 ? remaining : 200;
          final truncated = lineText.length > budget
              ? '${lineText.substring(0, budget)}… [truncated]'
              : lineText;
          buffer.writeln(truncated);
          included++;
        }
        break;
      }
      buffer.writeln(lineText);
      included++;
    }

    buffer.writeln();
    buffer.writeln('Read Lines: $included');
    if (included < page.lines.length) {
      final nextLine = page.lines[included].lineIndex;
      buffer.writeln('Next Page Token: $nextLine');
    } else if (page.hasMore) {
      buffer.writeln('Next Page Token: ${page.nextPageToken}');
    } else {
      buffer.writeln('End of Story: yes');
    }

    return ToolExecutionResult(observation: buffer.toString().trim());
  }
}
