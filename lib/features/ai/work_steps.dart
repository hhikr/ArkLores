import 'dart:convert';

import '../../core/agent/chat_message.dart';
import '../../core/agent/lore_tools.dart' show lookupLimitPrefix;
import '../../core/agent/react_event.dart';
import '../../core/gamedata/game.dart';
import '../../core/wiki/wiki_page.dart';

/// What one step of the answer's work was, for the reader: a tool call
/// with what it found, a note the model wrote between calls, a rewrite of
/// the answer, or an error. Built from the raw [ReActStep]s, which keep the
/// model's and the tools' own words.
enum WorkKind {
  sql,
  grep,
  read,
  readRecord,
  outline,
  find,
  similarNames,
  delegate,
  wikiSearch,
  wikiRead,

  /// `gather`: the lines around a few names.
  gather,
  otherTool,
  note,

  /// What code did to the answer (sent back, citations cut or dropped).
  record,
  error,
}

class WorkStep {
  WorkStep(
    this.kind, {
    this.tool,
    this.args = const {},
    this.text = '',
    this.subtask,
    this.planned = false,
    this.number = 0,
    this.repeated = false,
  });

  /// One of the first searches, written by the planning call.
  final bool planned;

  /// The tool call's number among the calls of this answer (from 1).
  final int number;

  /// The same tool with the same arguments was called earlier.
  final bool repeated;

  /// The arguments as the model wrote them (one line of JSON).
  String get argsJson => args.isEmpty ? '' : jsonEncode(args);

  /// The call was not run: the tool had found nothing too many times.
  bool get notRun => done && text.trimLeft().startsWith(lookupLimitPrefix);

  /// A wiki did not answer (also when the rest of a search did).
  bool get wikiDown => done && text.contains('暂时无法访问');

  final WorkKind kind;
  final String? tool;
  final Map<String, dynamic> args;

  /// 0.14: the sub-agent that took this step (1-based), or null.
  final int? subtask;

  /// The note, the error, or (once it arrives) the tool's raw output.
  String text;

  /// Whether the tool's output has arrived.
  bool done = false;

  bool get isTool => tool != null;

  String arg(String name) {
    final value = args[name];
    if (value == null) return '';
    if (value is List) return value.join(' / ');
    return '$value'.trim();
  }

  /// The game the step looked in when it named one (its `game` argument,
  /// or an Endfield story id); null for "every installed game".
  Game? get game {
    final named = Game.parse(args['game']);
    if (named != null) return named;
    // A wiki page names its site, and the site its game.
    final page = WikiPageId.parse(_versionedPage(arg('page')));
    if (page != null) return page.site.game == Game.endfield ? Game.endfield : null;
    final story = arg('story_id');
    return story.isNotEmpty && gameOfId(story) == Game.endfield
        ? Game.endfield
        : null;
  }

  /// A `wiki:<site>:<key>` ref with a placeholder version, so it parses.
  static String _versionedPage(String ref) =>
      ref.startsWith(wikiIdPrefix) && !ref.contains('@') ? '$ref@0' : ref;

  /// [WorkKind.wikiRead]: the page title from the output (`《title》 …` on
  /// its first line), else the page argument.
  String get wikiTitle {
    final title = RegExp(r'^《(.+?)》').firstMatch(text.trimLeft());
    if (title != null) return title.group(1)!.trim();
    final page = arg('page');
    final id = WikiPageId.parse(_versionedPage(page));
    return id == null ? page : id.key.split('/').last;
  }

  /// [WorkKind.wikiRead]: paragraphs shown (first and last `P<n>`).
  (int, int)? get paragraphRange {
    final numbers = [
      for (final m in RegExp(r'^P(\d+) ', multiLine: true).allMatches(text))
        int.parse(m.group(1)!),
    ];
    if (numbers.isEmpty) return null;
    numbers.sort();
    return (numbers.first, numbers.last);
  }

  /// [WorkKind.wikiSearch]: pages found, or null when not stated.
  int? get wikiPageCount {
    final m = RegExp(r'，(\d+) 个页面').firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// The story read ([WorkKind.read]): its title from the output (its first
  /// line, `《title》 story_id`), else the file name without folders and
  /// extension.
  String get storyTitle {
    final title = RegExp(r'^\s*[《【](.+?)[》】]\s+\S+\.txt').firstMatch(text);
    if (title != null) return title.group(1)!.trim();
    final id = arg('story_id').replaceAll('\\', '/');
    final name = id.split('/').last;
    return name.endsWith('.txt') ? name.substring(0, name.length - 4) : name;
  }

  /// Line range shown by [WorkKind.read] (first and last `L<n>`), or null.
  (int, int)? get lineRange {
    final lines = [
      for (final m in RegExp(r'^\s*L(\d+)', multiLine: true).allMatches(text))
        int.parse(m.group(1)!),
    ];
    if (lines.isEmpty) return null;
    lines.sort();
    return (lines.first, lines.last);
  }

  /// [WorkKind.readRecord]: what was read, from the output's first line
  /// (`record:<id> | kind | title | 所属：owner`): `owner · title`, the
  /// title alone, else the id asked for.
  String get recordTitle {
    final head = text.trimLeft().split('\n').first.split(' | ');
    if (head.length < 3 || !head.first.startsWith('record:')) return arg('id');
    final title = head[2].trim();
    final owner = head.length > 3 ? head[3].replaceFirst('所属：', '').trim() : '';
    return owner.isEmpty ? title : '$owner · $title';
  }

  /// The stories this step showed lines of, with their text (what the
  /// agent's ledger of read lines counts): a header line carrying a story
  /// id followed by `L<n>` lines, or the rows of a query that selects
  /// story lines with their content.
  Set<String> get storiesShown {
    final out = <String>{};
    if (!done || failed) return out;
    final lines = text.split('\n');
    if (kind == WorkKind.sql) {
      final columns = lines.first.split(' | ');
      final story = columns.indexOf('story_id');
      if (story < 0 ||
          !columns.contains('line_index') ||
          !RegExp(r'\bcontent\b|\*').hasMatch(arg('query'))) {
        return out;
      }
      for (final row in lines.skip(1)) {
        final cells = row.split(' | ');
        if (cells.length > story && cells[story].endsWith('.txt')) {
          out.add(cells[story]);
        }
      }
      return out;
    }
    String? current;
    for (final line in lines) {
      if (_shownLine.hasMatch(line)) {
        if (current != null) out.add(current);
        continue;
      }
      final id = _storyIdIn.firstMatch(line)?.group(1);
      if (id != null) current = id;
    }
    return out;
  }

  static final RegExp _shownLine = RegExp(r'^[\s*]*L\d+\b');
  static final RegExp _storyIdIn = RegExp(r'([\w./-]+\.txt)\b');

  /// [WorkKind.grep]: hits and stories in the output. A search of the
  /// whole library states its totals in a line of its own.
  (int hits, int stories) get grepCounts {
    final corpus =
        RegExp(r'全库共 (\d+) 行命中，分布在 (\d+) 个故事').firstMatch(text);
    if (corpus != null) {
      return (int.parse(corpus.group(1)!), int.parse(corpus.group(2)!));
    }
    final stories = RegExp(r'^## ', multiLine: true).allMatches(text).length;
    var hits = 0;
    for (final m in RegExp(r'（(\d+) 处）').allMatches(text)) {
      hits += int.parse(m.group(1)!);
    }
    return (hits, stories);
  }

  /// [WorkKind.sql]: rows returned, or null when not stated.
  int? get rowCount {
    if (text.trimLeft().startsWith('0 行')) return 0;
    final m = RegExp(r'（共 (\d+) 行）').firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// [WorkKind.find] (the `search` tool): stories listed, over all games.
  int? get searchStoryCount {
    final counts = [
      for (final m in RegExp(r'最相关的 (\d+) 篇').allMatches(text))
        int.parse(m.group(1)!),
    ];
    return counts.isEmpty ? null : counts.fold<int>(0, (n, c) => n + c);
  }

  /// [WorkKind.gather]: stories whose lines were given.
  int? get gatherStoryCount {
    final m = RegExp(r'给了 (\d+) 篇剧情').firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// The tool refused the call or could not run it.
  bool get failed {
    if (!done) return false;
    final t = text.trimLeft();
    return _failurePrefix.hasMatch(t) ||
        // A wiki that could not be reached (a search's wiki part aside).
        (kind != WorkKind.find && t.contains('暂时无法访问'));
  }

  /// Why the step failed, in the tool's words (its first line), or ''.
  String get failure => failed ? text.trimLeft().split('\n').first : '';

  static final RegExp _failurePrefix = RegExp(
    r'^(错误|Error|SQL 错误|子任务出错|工具出错|参数不是合法|缺少参数|没有名为|'
    r'只允许|只读查询|一次只能|本地知识库未安装)',
  );

  bool get empty {
    if (!done || failed) return false;
    final t = text.trimLeft();
    return t.isEmpty ||
        t.startsWith('没有') ||
        t.startsWith('0 行') ||
        (kind == WorkKind.grep && grepCounts.$2 == 0 && t.contains('0 处'));
  }
}

WorkKind _kindOf(String tool) => switch (tool) {
      // 0.14: `search` took over from `find` (same row in the timeline).
      'search' || 'find' => WorkKind.find,
      'sql' => WorkKind.sql,
      'grep' => WorkKind.grep,
      'read_story' => WorkKind.read,
      'read_record' => WorkKind.readRecord,
      'outline' => WorkKind.outline,
      'similar_names' => WorkKind.similarNames,
      'delegate' => WorkKind.delegate,
      'wiki_search' => WorkKind.wikiSearch,
      'wiki_read' => WorkKind.wikiRead,
      'gather' => WorkKind.gather,
      _ => WorkKind.otherTool,
    };

/// The reader's view of [steps]: each tool call carries its output (tools
/// running in parallel answer in any order, so outputs go to the oldest
/// call of the same tool still waiting).
List<WorkStep> workStepsOf(List<ReActStep> steps) {
  final out = <WorkStep>[];
  final waiting = <WorkStep>[];
  final asked = <String>{};
  var number = 0;
  for (final step in steps) {
    switch (step.type) {
      case ReActEventType.toolCall:
        final tool = step.toolName ?? '';
        final args = step.toolArgs ?? const <String, dynamic>{};
        final work = WorkStep(
          _kindOf(tool),
          tool: tool,
          args: args,
          subtask: step.subtask,
          planned: step.planned,
          number: ++number,
          repeated: !asked.add('${step.subtask}|$tool|${jsonEncode(args)}'),
        );
        out.add(work);
        waiting.add(work);
      case ReActEventType.toolObservation:
        final i = waiting.indexWhere(
          (w) =>
              w.subtask == step.subtask &&
              (step.toolName == null || w.tool == step.toolName),
        );
        if (i < 0) continue;
        waiting.removeAt(i)
          ..text = step.content
          ..done = true;
      case ReActEventType.thought:
        final text = step.content.trim();
        if (text.isNotEmpty) out.add(WorkStep(WorkKind.note, text: text));
      case ReActEventType.recordNote:
        out.add(WorkStep(WorkKind.record, text: step.content.trim()));
      case ReActEventType.error:
        out.add(WorkStep(WorkKind.error, text: step.content.trim()));
      default:
        break;
    }
  }
  return out;
}

/// Tool calls, and the stories whose text was shown, for the one-line
/// summary. 0.14: every tool that prints story lines counts (a search or a
/// grep lists lines that can be cited); counting `read_story` alone gave
/// "nine citations, no story read".
({int calls, int reads}) workCounts(List<WorkStep> steps) {
  var calls = 0;
  final stories = <String>{};
  for (final s in steps) {
    if (!s.isTool) continue;
    calls++;
    stories.addAll(s.storiesShown);
  }
  return (calls: calls, reads: stories.length);
}
