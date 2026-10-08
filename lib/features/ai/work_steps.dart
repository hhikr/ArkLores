import '../../core/agent/chat_message.dart';
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
  outline,
  find,
  similarNames,
  delegate,
  wikiSearch,
  wikiRead,
  otherTool,
  note,
  redo,
  error,
}

class WorkStep {
  WorkStep(this.kind, {this.tool, this.args = const {}, this.text = ''});

  final WorkKind kind;
  final String? tool;
  final Map<String, dynamic> args;

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

  /// The story read ([WorkKind.read]): its title from the output, else the
  /// file name without folders and extension.
  String get storyTitle {
    final title = RegExp(r'^【(.+?)】', multiLine: true).firstMatch(text);
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

  /// [WorkKind.grep]: hits and stories in the output.
  (int hits, int stories) get grepCounts {
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

  /// The tool said it found nothing or refused the call.
  bool get failed {
    final t = text.trimLeft();
    return t.startsWith('错误') ||
        t.startsWith('Error') ||
        // A wiki that could not be reached.
        t.contains('暂时无法访问');
  }

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
      'sql' => WorkKind.sql,
      'grep' => WorkKind.grep,
      'read_story' => WorkKind.read,
      'outline' => WorkKind.outline,
      'find' => WorkKind.find,
      'similar_names' => WorkKind.similarNames,
      'delegate' => WorkKind.delegate,
      'wiki_search' => WorkKind.wikiSearch,
      'wiki_read' => WorkKind.wikiRead,
      _ => WorkKind.otherTool,
    };

/// The reader's view of [steps]: each tool call carries its output (tools
/// running in parallel answer in any order, so outputs go to the oldest
/// call of the same tool still waiting).
List<WorkStep> workStepsOf(List<ReActStep> steps) {
  final out = <WorkStep>[];
  final waiting = <WorkStep>[];
  for (final step in steps) {
    switch (step.type) {
      case ReActEventType.toolCall:
        final tool = step.toolName ?? '';
        final work = WorkStep(
          _kindOf(tool),
          tool: tool,
          args: step.toolArgs ?? const {},
        );
        out.add(work);
        waiting.add(work);
      case ReActEventType.toolObservation:
        final i = waiting.indexWhere(
          (w) => step.toolName == null || w.tool == step.toolName,
        );
        if (i < 0) continue;
        waiting.removeAt(i)
          ..text = step.content
          ..done = true;
      case ReActEventType.thought:
        final text = step.content.trim();
        if (text.isNotEmpty) out.add(WorkStep(WorkKind.note, text: text));
      case ReActEventType.finalAnswerReset:
        out.add(WorkStep(WorkKind.redo, text: step.content.trim()));
      case ReActEventType.error:
        out.add(WorkStep(WorkKind.error, text: step.content.trim()));
      default:
        break;
    }
  }
  return out;
}

/// Tool calls and stories read, for the one-line summary.
({int calls, int reads}) workCounts(List<WorkStep> steps) {
  var calls = 0;
  final stories = <String>{};
  for (final s in steps) {
    if (!s.isTool) continue;
    calls++;
    if (s.kind == WorkKind.read) stories.add(s.arg('story_id'));
  }
  return (calls: calls, reads: stories.length);
}
