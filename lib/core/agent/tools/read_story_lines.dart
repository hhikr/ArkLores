import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';
import 'observation_data.dart';

/// Reads raw story lines by story id with window + pagination. Exposes the
/// original text so the agent can read key chapters directly instead of
/// relying only on similarity-ranked excerpts.
class ReadStoryLinesTool extends AgentTool {
  ReadStoryLinesTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;
  /// R14: raised from 4800 so one READ covers most of a chapter scene
  /// (~150 lines) instead of 30-line slices. R16: 20000 (~450 lines), so most
  /// chapters arrive whole — a chapter split into ~200-line pages was read
  /// page by page and then re-requested "to confirm the first half" (live).
  /// Only the newest observation is sent in full; older pages become a
  /// pointer to the state.
  static const int _maxObservationChars = 20000;

  /// Page size of an open-ended READ (the observation budget still bounds
  /// it); R14 raised from the store's 30-line default, R16 to a whole
  /// chapter (an open READ returned 150 lines and the planner went on to
  /// read the chapter in slices, then re-read the first slice).
  static const int _defaultPageLines = 450;

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
                'Story file id as returned by search_story_coverage, e.g. activities/<activity_id>/<file>.txt.',
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
            'description': 'Optional page size. Default 450, max 500.',
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
    var storyId = (arguments['story_id'] as String?)?.trim();
    if (storyId == null || storyId.isEmpty) {
      return 'Error: story_id parameter is empty';
    }
    // R16: ids are file names; `level_st_09-04` without `.txt` was "not
    // found" (live).
    if (!storyId.endsWith('.txt')) storyId = '$storyId.txt';
    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final startLine = (arguments['start_line'] as num?)?.toInt();
    final endLine = (arguments['end_line'] as num?)?.toInt();
    // R14: an explicit window is read whole (up to the 100-line page and the
    // observation budget) instead of the 30-line default page, which made
    // the planner re-request the rest of its window piece by piece.
    final maxLines = (arguments['max_lines'] as num?)?.toInt() ??
        (startLine != null && endLine != null && endLine >= startLine
            ? endLine - startLine + 1
            : _defaultPageLines);
    final pageToken = arguments['page_token'] as String?;

    final page = await store.readStoryLines(
      storyId: storyId,
      startLine: startLine,
      endLine: endLine,
      maxLines: maxLines,
      pageToken: pageToken,
    );
    if (!page.storyFound) {
      // R16: an id put together from a level code (`level_st_10-10_beg`
      // for 10-10) — name the real ones with that code.
      // File numbers are zero-padded (`16-07`), level codes are not (`16-7`).
      final raw = RegExp(r'(\d+-\d+|[A-Z]+-\d+)').firstMatch(storyId)?.group(1);
      final code = raw?.replaceAllMapped(
        RegExp(r'(^|-)0+(\d)'),
        (m) => '${m.group(1)}${m.group(2)}',
      );
      final similar = code == null
          ? const <StoryCatalogEntry>[]
          : await store.storiesByCode(code);
      return ToolExecutionResult(
        observation: 'Story not found: $storyId. '
            '${similar.isEmpty ? 'Use search_story_coverage or get_story_map to '
                'obtain valid story ids.' : '关卡号 $code 的章节是：'
                '${similar.map((e) => '${e.storyId}《${e.label}》').join('；')}。'
                '用这些 story_id READ，不要自己拼写。'}',
      );
    }
    if (page.lines.isEmpty) {
      return ToolExecutionResult(
        observation: 'No lines in the requested range for story "$storyId". '
            'Story: $storyId\nScope: ${page.scopeId ?? 'unknown'}\nRead Lines: 0',
      );
    }

    final entry = (await store.storyCatalogEntries([storyId]))[storyId];
    final buffer = StringBuffer()
      ..writeln('Story: $storyId')
      ..writeln('Scope: ${page.scopeId ?? 'unknown'}');
    // R14: where the chapter sits in its story (name, code, order).
    if (entry != null) buffer.writeln('Chapter: 《${entry.label}》');

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

    // R12: the range ACTUALLY returned (after the observation budget), so the
    // executor records real coverage instead of the requested window.
    return ToolExecutionResult(
      observation: appendDataBlock(buffer.toString().trim(), {
        'type': 'read_story_lines',
        'story_id': storyId,
        'scope_id': page.scopeId,
        'first_line': page.lines.first.lineIndex,
        'last_line': page.lines[included - 1].lineIndex,
        'read_lines': included,
      }),
    );
  }
}
