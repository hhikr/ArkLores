/// R17: the tools of the story agent ([LoreAgentLoop]).
///
/// Modelled on what general agents did with the bare knowledge DB: look at
/// the whole corpus with one query (`sql`, `grep` without a scope), then read
/// chapters whole (`read_story`) and search inside them (`grep` with a
/// scope). Every tool returns plain text written for the model; zero hits are
/// stated as such, with near names when a name may be misspelled.
///
/// Tools record the story lines they show in a [SeenLines] log; answer
/// citations are checked against it.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../gamedata/game_retrieval.dart';
import '../gamedata/multi_game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../materials/material_snapshot.dart';
import '../wiki/wiki_lookup.dart';
import 'context_ledger.dart';
import 'coverage.dart';
import 'line_picker.dart';
import 'lore_agent_prompts.dart' show loreLibraryManual;
import 'tools/agent_tool.dart';
import 'tools/material_tools.dart';
import 'tools/search_tool.dart';

/// Story lines shown to the model in this run (per story, line indexes),
/// and ids of other records (`normalized_records` …) a query returned.
///
/// 0.14: the one ledger of what was shown. Every tool writes to it through
/// [add], [addRange] and [addRecord]; a line counts only when its text was
/// printed, a record is whole or only an excerpt ([recordIsPartial]). What
/// one tool call showed is also noted for that call ([duringCall]), so a
/// context ledger can track exactly which text remains visible.
class SeenLines {
  SeenLines();

  factory SeenLines.fromJson(Map<String, dynamic> json) {
    final seen = SeenLines();
    for (final e in (json['lines'] as Map<String, dynamic>).entries) {
      for (final value in e.value as List) {
        final range = value as List;
        seen.addRange(e.key, range[0] as int, range[1] as int);
      }
    }
    for (final e in (json['records'] as Map<String, dynamic>).entries) {
      seen.addRecord(e.key, partial: e.value as bool);
    }
    return seen;
  }

  Map<String, dynamic> toJson() => {
        'lines': {
          for (final id in stories)
            id: [
              for (final r in seenRanges(id, 0, 1 << 30)) [r.$1, r.$2],
            ],
        },
        'records': Map<String, bool>.of(_records),
      };
  final Map<String, Set<int>> _lines = {};

  /// Record id → only an excerpt of it was shown.
  final Map<String, bool> _records = {};

  /// Non-citation descriptions printed by this call, so ContextLedger can
  /// track whether their text remains in the conversation.
  final Set<String> _contextDescriptions = {};

  static final Object _callKey = Object();

  /// Runs [body]; what it adds to any ledger is noted in [shown] too.
  static Future<T> duringCall<T>(SeenLines shown, Future<T> Function() body) =>
      runZoned(body, zoneValues: {_callKey: shown});

  SeenLines? get _call {
    final call = Zone.current[_callKey];
    return call is SeenLines && !identical(call, this) ? call : null;
  }

  /// A record shown with its id; [partial]: only an excerpt of its text.
  void addRecord(String id, {bool partial = false}) {
    _records[id] = partial && (_records[id] ?? true);
    _call?.addRecord(id, partial: partial);
  }

  /// Mark a reusable explanation printed in the current tool result.
  void addContextDescription(String key) {
    _contextDescriptions.add(key);
    _call?.addContextDescription(key);
  }

  void removeContextDescription(String key) {
    _contextDescriptions.remove(key);
    _call?.removeContextDescription(key);
  }

  Iterable<String> get contextDescriptions =>
      UnmodifiableSetView(_contextDescriptions);

  Iterable<MapEntry<String, Set<int>>> get lineEntries =>
      _lines.entries.map((e) => MapEntry(e.key, UnmodifiableSetView(e.value)));
  bool recordIsWhole(String id) => _records[id] == false;
  Iterable<String> get recordIds => _records.keys;
  bool hasRecord(String id) => _records.containsKey(id);

  /// Only an excerpt of record [id] was shown (false when unknown).
  bool recordIsPartial(String id) => _records[id] ?? false;

  void add(String storyId, int line) {
    _lines.putIfAbsent(storyId, () => <int>{}).add(line);
    _call?.add(storyId, line);
  }

  void addStoryLine(String storyId, StoryLineEntry line) {
    if (isStoryEvidence(line.kind)) add(storyId, line.lineIndex);
  }

  void addRange(String storyId, int first, int last) {
    final set = _lines.putIfAbsent(storyId, () => <int>{});
    for (var i = first; i <= last; i++) {
      set.add(i);
    }
    _call?.addRange(storyId, first, last);
  }

  /// The runs of shown lines inside `first..last`, in order.
  List<(int, int)> seenRanges(String storyId, int first, int last) {
    final set = _lines[storyId];
    if (set == null) return const [];
    final out = <(int, int)>[];
    int? start;
    final sorted = set.where((i) => i >= first && i <= last).toList()..sort();
    int? end;
    for (final i in sorted) {
      if (end != null && i != end + 1) {
        out.add((start!, end));
        start = null;
      }
      start ??= i;
      end = i;
    }
    if (start != null) out.add((start, end!));
    return out;
  }

  /// What is in this ledger, as a short list for the model: each story's
  /// line runs, then the records (`a.txt L3-10、L20；record:x`), at most
  /// [maxChars] long.
  String summary({int maxChars = 500}) {
    final parts = <String>[];
    for (final MapEntry(key: story, value: lines) in _lines.entries) {
      final sorted = lines.toList()..sort();
      final runs = <String>[];
      var a = sorted.first;
      var b = a;
      for (final n in sorted.skip(1)) {
        if (n == b + 1) {
          b = n;
          continue;
        }
        runs.add(a == b ? 'L$a' : 'L$a-$b');
        a = b = n;
      }
      runs.add(a == b ? 'L$a' : 'L$a-$b');
      // (Wiki pages are kept by paragraph: `P`.)
      final text = runs.join('、');
      parts.add(
        '$story ${story.startsWith('wiki:') || story.startsWith('material:') ? text.replaceAll('L', 'P') : text}',
      );
    }
    for (final MapEntry(key: id, value: partial) in _records.entries) {
      parts.add('record:$id${partial ? '（片段）' : ''}');
    }
    final out = StringBuffer();
    for (final (i, part) in parts.indexed) {
      if (out.length + part.length > maxChars && i > 0) {
        out.write('；等 ${parts.length} 项');
        break;
      }
      if (i > 0) out.write('；');
      out.write(part);
    }
    return out.toString();
  }

  /// Whether every line of `first..last` was shown.
  bool covers(String storyId, int first, int last) {
    final set = _lines[storyId];
    if (set == null || last < first || last - first + 1 > set.length) {
      return false;
    }
    for (var i = first; i <= last; i++) {
      if (!set.contains(i)) return false;
    }
    return true;
  }

  bool get isEmpty => _lines.isEmpty && _records.isEmpty;

  void retainMaterials(Set<String> allowed) {
    _lines.removeWhere(
      (id, _) => id.startsWith('material:') && !allowed.contains(id),
    );
  }

  /// Adds everything [other] saw (a sub-agent's reading counts as read).
  void addAll(SeenLines other) {
    for (final MapEntry(key: story, value: lines) in other._lines.entries) {
      _lines.putIfAbsent(story, () => <int>{}).addAll(lines);
    }
    for (final MapEntry(key: id, value: partial) in other._records.entries) {
      _records[id] = partial && (_records[id] ?? true);
    }
    _contextDescriptions.addAll(other._contextDescriptions);
    final call = _call;
    if (call != null && !identical(call, other)) call.addAll(other);
  }

  /// Stories with at least one shown line.
  Iterable<String> get stories => _lines.keys;
}

/// Most characters a tool result may hand back (≈ 200 story lines). 0.14:
/// halved from 16000 — every result is sent again with each later turn, so
/// its size is paid many times; a longer chapter is read in pages.
const int maxToolResultChars = 8000;

/// Original text still above; this call was not run.
const String inContextPrefix = '（已在上文）';

/// [text] on one line: its line breaks shown as ` / `.
String oneLine(String text) => text.contains('\n')
    ? text.split('\n').where((l) => l.isNotEmpty).join(' / ')
    : text;

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

/// One story line as the tools print it: `L12 [阿米娅] 内容`. Lines that are
/// not dialogue or narration carry their kind instead: `L40 [字幕] 内容`.
/// A line with line breaks of its own (a letter, a poem) stays on one
/// printed line, its breaks shown as ` / `, so every printed line starts
/// with its `L` number.
String formatStoryLine(
  int index,
  String? speaker,
  String content, {
  String? kind,
}) {
  final label = speaker == null || speaker.trim().isEmpty
      ? storyKindLabel(kind)
      : speaker;
  final who = label == null || label.trim().isEmpty ? '' : '[$label] ';
  return 'L$index $who${oneLine(content)}';
}

/// A story passage after replacing evidence that is still in the conversation.
class ContextStoryLines {
  const ContextStoryLines({
    required this.lines,
    required this.printedEvidence,
    required this.allEvidenceInContext,
    this.firstLine,
    this.lastLine,
    this.steps,
  });

  final List<String> lines;
  final Set<int> printedEvidence;
  final bool allEvidenceInContext;
  final int? firstLine;
  final int? lastLine;
  final String? steps;
}

/// Do not replace source text when the pointer cannot save characters.
const int minimumContextOmissionSavings = 1;

/// Render [lines] in their existing order, replacing evidence still in the
/// conversation with pointers. [formatLine] and [formatPointer] preserve the
/// caller's indentation and hit markers.
ContextStoryLines renderStoryLinesWithContext({
  required String storyId,
  required List<StoryLineEntry> lines,
  required ContextLedger? ledger,
  required String Function(StoryLineEntry) formatLine,
  String Function(String note, List<StoryLineEntry> omitted)? formatPointer,
  bool requireSavings = true,
}) {
  String pointer(String note, List<StoryLineEntry> omitted) =>
      formatPointer?.call(note, omitted) ?? note;
  final evidence = lines.where((line) => isStoryEvidence(line.kind)).toList();
  final first = lines.isEmpty ? null : lines.first.lineIndex;
  final last = lines.isEmpty ? null : lines.last.lineIndex;
  final allInContext = ledger != null &&
      evidence.isNotEmpty &&
      evidence.every((line) => ledger.lineInContext(storyId, line.lineIndex));
  if (allInContext) {
    final steps = contextSteps(
      ledger,
      storyId,
      evidence.map((line) => line.lineIndex),
    );
    final note = '（L$first–L$last 的原文仍在上文，$steps的结果）';
    return ContextStoryLines(
      lines: [pointer(note, lines)],
      printedEvidence: const {},
      allEvidenceInContext: true,
      firstLine: first,
      lastLine: last,
      steps: steps,
    );
  }

  final rendered = <String>[];
  final printedEvidence = <int>{};
  bool above(StoryLineEntry line) =>
      ledger?.lineInContext(storyId, line.lineIndex) ?? false;
  for (var i = 0; i < lines.length;) {
    final line = lines[i];
    if (!isStoryEvidence(line.kind) || !above(line)) {
      rendered.add(formatLine(line));
      if (isStoryEvidence(line.kind)) printedEvidence.add(line.lineIndex);
      i++;
      continue;
    }

    var end = i;
    var previousLine = line.lineIndex;
    for (var scan = i + 1; scan < lines.length; scan++) {
      final next = lines[scan];
      if (next.lineIndex != previousLine + 1) break;
      if (isStoryEvidence(next.kind)) {
        if (!above(next)) break;
        end = scan;
      }
      previousLine = next.lineIndex;
    }
    final omitted = lines.sublist(i, end + 1);
    final note = '（L${line.lineIndex}–L${lines[end].lineIndex} 的原文仍在上文，略去）';
    final renderedPointer = pointer(note, omitted);
    final sourceChars = omitted.fold<int>(
      0,
      (total, item) => total + formatLine(item).length,
    );
    if (!requireSavings ||
        sourceChars - renderedPointer.length >= minimumContextOmissionSavings) {
      rendered.add(renderedPointer);
      i = end + 1;
      continue;
    }

    for (final item in omitted) {
      rendered.add(formatLine(item));
      if (isStoryEvidence(item.kind)) printedEvidence.add(item.lineIndex);
    }
    i = end + 1;
  }
  return ContextStoryLines(
    lines: rendered,
    printedEvidence: printedEvidence,
    allEvidenceInContext: false,
    firstLine: first,
    lastLine: last,
  );
}

/// Readable chapter name for [storyId] from [entries] (path-derived when the
/// catalog lacks it).
String _storyLabel(String storyId, Map<String, StoryCatalogEntry> entries) =>
    entries[storyId]?.label ?? fallbackStoryLabel(storyId);

/// Names that a zero-hit search may have misspelled: near names from the DB
/// (R15 string similarity, never an identity claim). A term the DB has as
/// a name is not misspelled (0.14 phone: a query that found nothing for
/// another reason was told the name it asked for "is not in the library").
Future<String> _nearNamesHint(
  GameDataRetrieval store,
  Iterable<String> terms,
) async {
  final hints = <String>[];
  for (final term in terms.toSet()) {
    if (term.runes.length < 2 || term.runes.length > 12) continue;
    if (await store.hasName(term)) continue;
    final similar = await store.similarNames(term, limit: 5);
    final line = describeSimilarNames(term, similar);
    if (line != null) hints.add(line);
  }
  return hints.join('\n');
}

/// Reads a JSON argument as a list of strings (accepts one string too).
List<String> _stringList(Object? raw) {
  if (raw is String) {
    return [
      for (final part in raw.split(RegExp(r'[,，\n]')))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
  if (raw is List) {
    return [
      for (final item in raw)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }
  return const [];
}

int? _int(Object? raw) => raw is num ? raw.toInt() : int.tryParse('$raw');

/// The `game` argument of a tool: which game's knowledge base to use.
Map<String, dynamic> _gameParameter(String description) => {
      'type': 'string',
      'enum': [for (final g in Game.values) g.key],
      'description': description,
    };

/// The tables whose `id` is a record's (`record:<id>`).
final RegExp _recordTables =
    RegExp(r'\b(normalized_records|entity_documents)\b', caseSensitive: false);

/// What a query looks for in a name or in the text: `speaker LIKE '%x%'`,
/// `e.name = 'x'`, `content LIKE '%x%'`. Only these may be a misspelled
/// name (a category, a document type or a part of an id is not).
final RegExp _comparedName = RegExp(
  r'\b(?:speaker|name|entity_name|alias|matched_alias|title|story_name|'
  r"collection_name|content)\s*(?:=|LIKE)\s*'%?([^'%_]+)%?'",
  caseSensitive: false,
);

/// The select list of a query (between its first SELECT and FROM).
final RegExp _selectList =
    RegExp(r'\bSELECT\b(.*?)\bFROM\b', caseSensitive: false, dotAll: true);

/// `id = '<id>'` in a query.
final RegExp _idEquals = RegExp(r"\bid\s*=\s*'([^']+)'", caseSensitive: false);

final RegExp _recordPrefix = RegExp(r'^(?:record:)+');

final RegExp _measured =
    RegExp(r'\b(?:length|count)\s*\([^()]*\)', caseSensitive: false);

/// `content` (bare or inside an expression) or `*` in a select list.
final RegExp _contentOrAll =
    RegExp(r'\bcontent\b|(?:^|[\s,.])\*', caseSensitive: false);

/// `sql`: one read-only query over the whole knowledge DB.
class SqlTool extends AgentTool {
  SqlTool(this.store, this.seen, {this.manual, this.ledger});

  final GameDataRetrieval store;
  final SeenLines seen;
  final ContextLedger? ledger;

  /// The manual of the tables (null: none is kept, as in a test of this
  /// tool alone). A question's first query brings it along when it was not
  /// looked at: whoever writes SQL needs it, whether they asked or not.
  final LibraryManual? manual;

  static const int maxRows = 200;

  @override
  String get name => 'sql';

  @override
  String get description => '对一个游戏的知识库执行一条只读 SQL（SQLite 语法，只能是 SELECT/WITH）。'
      '适合做全局统计和定位，例如按 story_id 统计某个名字出现的行数并关联 story_catalog 排序，'
      '或在 entities / entity_aliases / story_lines.speaker 里模糊查名字。'
      '两个游戏的库表结构相同、各是一个文件，一条 SQL 只查其中一个（game 参数）。'
      '最多返回 $maxRows 行；超过时请加条件、聚合或 LIMIT。'
      '主要的表：story_lines(story_id, line_index, speaker, content, kind)、'
      'story_catalog(story_id, collection_id, collection_name, story_code, story_name, …)、'
      'entries(id, type, name, code, collection_id, record_id, …)、entry_links(src, relation, dst)、'
      'collections(id, kind, name, parent_id, …)、normalized_records(id, category, subtype, title, entity_name, content, …)、'
      'entity_documents。各列的含义、绑定的种类、条目和书架的种类在知识库手册里（guide）：'
      '先看手册再写查询；手册尚未出现在上文时，第一条查询的结果会附上它。'
      '默认查询明日方舟库；查终末地要加 game=endfield。'
      '0 行结果若提示记录已存在，用 read_record 读全文，id 不带 record: 前缀。'
      '结果只显示部分行时，想看更多请加条件、聚合或分页。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '一条 SELECT 或 WITH 语句'},
          'game': _gameParameter('查哪个游戏的库，默认 arknights'),
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final out = await _query(arguments);
    final manual = this.manual;
    if (manual == null ||
        (ledger == null && manual.shown) ||
        ledger?.stepOfContextDescription(libraryManualDescriptionKey) != null) {
      return out;
    }
    final description = await manual.show();
    seen.addContextDescription(libraryManualDescriptionKey);
    return '$out\n\n$description';
  }

  Future<String> _query(Map<String, dynamic> arguments) async {
    final query = '${arguments['query'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：query 为空';
    // 0.14 live: a query naming an Endfield id (`'ef/…'`) without `game`
    // went to the Arknights database and found nothing; ids name their game.
    final game = Game.parse(arguments['game']) ??
        (RegExp("'(?:record:)?$endfieldIdPrefix").hasMatch(query)
            ? Game.endfield
            : null);
    final result = await store.readOnlySql(query, maxRows: maxRows, game: game);
    if (result.error != null) {
      return '${result.error!}${await _columnsHint(query, result.error!, game)}';
    }
    final overRecords = _recordTables.hasMatch(query);
    if (result.rows.isEmpty) {
      // 0.14 phone: a record's id was looked up in the table that does not
      // hold it (an operator's file is in entity_documents), a dozen times.
      if (overRecords) {
        for (final m in _idEquals.allMatches(query)) {
          final id = m.group(1)!.replaceFirst(_recordPrefix, '');
          if (await store.readRecord(id) != null) {
            return '0 行。这条记录在库里，id：$id。';
          }
        }
      }
      final terms = [
        for (final m in _comparedName.allMatches(query)) m.group(1)!,
      ];
      final hint = await _nearNamesHint(narrowTo(store, game), terms);
      return '0 行。${hint.isEmpty ? '' : '\n$hint'}';
    }
    final columns = result.columns;
    final storyCol = columns.indexOf('story_id');
    final lineCol = columns.indexOf('line_index');
    final idCol = columns.indexOf('id');
    // 0.14: a line or a record counts as shown only with its text (a
    // column of, or cut from, `content`), and an id is a record's only in
    // a query over the tables that hold records.
    // 0.14 phone: the text is often selected under another name
    // (`substr(content, 1, 500) c`), and a record read by `WHERE id = '…'`
    // without its id column; neither was counted as shown.
    final list = (_selectList.firstMatch(query)?.group(1) ?? '')
        // Its length or a count shows none of the text.
        .replaceAll(_measured, '');
    final showsContent = _contentOrAll.hasMatch(list);
    final contentCol = showsContent ? 0 : -1;
    final sourceKinds = <(String, int), String?>{};
    if (storyCol >= 0 && lineCol >= 0 && showsContent) {
      final byStory = <String, Set<int>>{};
      for (final row in result.rows) {
        final line = _int(row[lineCol]);
        if (line != null) {
          byStory.putIfAbsent('${row[storyCol]}', () => {}).add(line);
        }
      }
      if (byStory.isNotEmpty) {
        final where = byStory.entries
            .map(
              (e) =>
                  "(story_id = '${e.key.replaceAll("'", "''")}' AND line_index IN (${e.value.join(',')}))",
            )
            .join(' OR ');
        // Validate against source rows even when SQL omits or aliases kind.
        var sources = await store.readOnlySql(
          'SELECT story_id, line_index, kind FROM story_lines WHERE $where',
          maxRows: result.rows.length,
          game: game,
        );
        if (sources.error?.contains('no such column: kind') ?? false) {
          sources = await store.readOnlySql(
            'SELECT story_id, line_index FROM story_lines WHERE $where',
            maxRows: result.rows.length,
            game: game,
          );
        }
        for (final row in sources.rows) {
          sourceKinds[('${row[0]}', _int(row[1])!)] =
              row.length > 2 ? row[2] as String? : null;
        }
      }
    }
    final wholeContent = columns.contains('content');
    final onlyId = idCol < 0 && result.rows.length == 1
        ? _idEquals.firstMatch(query)?.group(1)?.replaceFirst(_recordPrefix, '')
        : null;
    // One row is what was asked for: its cells are not cut short (the
    // result as a whole still is). A cut cell was read 400 characters a
    // call.
    final cell = result.rows.length == 1
        ? (maxToolResultChars - 400) ~/ columns.length
        : 400;
    final buffer = StringBuffer()..writeln(columns.join(' | '));
    var shown = 0;
    for (final row in result.rows) {
      final text = row.map((v) => _clip('${v ?? ''}', cell)).join(' | ');
      if (buffer.length + text.length > maxToolResultChars) break;
      buffer.writeln(text);
      shown++;
      if (storyCol >= 0 && lineCol >= 0 && contentCol >= 0) {
        final line = _int(row[lineCol]);
        final key = ('${row[storyCol]}', line);
        if (line != null &&
            sourceKinds.containsKey(key) &&
            isStoryEvidence(sourceKinds[key])) {
          seen.add('${row[storyCol]}', line);
        }
      }
      // A record shown with its id can be cited as `record:<id>`.
      final id = idCol >= 0 ? row[idCol] : onlyId;
      if (overRecords && contentCol >= 0 && id != null) {
        seen.addRecord(
          '$id',
          partial: !wholeContent ||
              '${row[columns.indexOf('content')] ?? ''}'.length > cell,
        );
      }
    }
    if (shown < result.rows.length || result.truncated) {
      buffer.writeln(
        '（只显示前 $shown 行${result.truncated ? '，结果超过 $maxRows 行' : ''}）',
      );
    } else {
      buffer.writeln('（共 $shown 行）');
    }
    return buffer.toString().trimRight();
  }

  /// 0.14: after a wrong column or table, the real columns of the tables
  /// the query names, so the next try does not guess again.
  Future<String> _columnsHint(String query, String error, Game? game) async {
    if (!error.contains('no such column') && !error.contains('no such table')) {
      return '';
    }
    final tables = <String>{
      for (final m in RegExp(
        r'\b(?:FROM|JOIN)\s+([A-Za-z_][A-Za-z0-9_]*)',
        caseSensitive: false,
      ).allMatches(query))
        m.group(1)!,
    };
    final lines = <String>[];
    for (final table in tables.take(4)) {
      final columns = await store.readOnlySql(
        "SELECT name FROM pragma_table_info('$table')",
        maxRows: 60,
        game: game,
      );
      if (columns.error != null) continue;
      lines.add(
        columns.rows.isEmpty
            ? '没有表 $table'
            : '$table 的列：${columns.rows.map((r) => r.first).join(', ')}',
      );
    }
    if (error.contains('no such table') || lines.isEmpty) {
      final all = await store.readOnlySql(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
        "AND name NOT LIKE '%fts%' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        maxRows: 80,
        game: game,
      );
      if (all.error == null) {
        lines.add('可用的表：${all.rows.map((r) => r.first).join(', ')}');
      }
    }
    return lines.isEmpty ? '' : '\n${lines.join('\n')}';
  }
}

/// 0.14: lookups of one tool that may find nothing in one question before
/// the tool is not run again. A question the library cannot answer (the
/// rows are not there) used to go on for two dozen queries, each a little
/// different, none repeated.
const int maxFailedLookups = 6;

/// How a result that is the limit's refusal starts.
const String lookupLimitPrefix = '没有执行：';

/// What to do at the limit.
const String lookupLimitAdvice =
    '库里很可能没有这样的数据：不要再换条件重试，用已经读到的内容作答，没查到的在答案里说明；确实还要找时换别的工具。';

/// The result of a call to [tool] past the limit.
String lookupLimitNote(String tool) =>
    '$lookupLimitPrefix$tool 在这次问答里已有 $maxFailedLookups 次没有结果。$lookupLimitAdvice';

/// Whether a tool's result says it found nothing or could not run (every
/// tool starts such a result in one of these ways).
bool lookupFoundNothing(String result) {
  final text = result.trimLeft();
  return const ['0 行', 'SQL 错误', '错误', '没有', '缺少参数'].any(text.startsWith);
}

/// 0.14: the knowledge base's manual for one question — the tables, their
/// columns and bindings, the library's shelves ([loreLibraryManual]) — and
/// whether the model has it yet. It used to be over half of the system
/// prompt, sent with every call of every question; only `sql` needs it.
class LibraryManual {
  LibraryManual(this.store);

  final GameDataRetrieval store;

  /// Whether this question's conversation holds the manual already.
  bool shown = false;

  /// The manual for the installed games; marks it shown.
  Future<String> show() async {
    shown = true;
    final store = this.store;
    return loreLibraryManual(
      store is MultiGameRetrieval
          ? await store.installedGames()
          : const [Game.arknights],
    );
  }
}

const String libraryManualDescriptionKey = 'library_manual';

/// `guide`: the manual, when the model asks for it.
class GuideTool extends AgentTool {
  GuideTool(this.manual, this.seen, {this.ledger});

  final LibraryManual manual;
  final SeenLines seen;
  final ContextLedger? ledger;

  @override
  String get name => 'guide';

  @override
  String get description =>
      '查看知识库手册：各表的列和含义、条目之间绑定的种类、资料页的书架和条目种类（装了两个游戏时还有两个库的不同之处）。'
      '写 sql 之前，或遇到不认识的类别、绑定时看；一次问答看一次就够。若首次 sql 结果已附手册，照它写查询。没有参数。';

  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': <String, dynamic>{}};

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    if (ledger?.stepOfContextDescription(libraryManualDescriptionKey) != null) {
      return inContextPrefix;
    }
    if (ledger == null && manual.shown) return inContextPrefix;
    final description = await manual.show();
    seen.addContextDescription(libraryManualDescriptionKey);
    return description;
  }
}

/// `read_record`: the text of one record outside the story text (an
/// archive, a voice line, a module's story, an item's description).
class ReadRecordTool extends AgentTool {
  ReadRecordTool(this.store, this.seen, {this.ledger});
  final ContextLedger? ledger;

  final GameDataRetrieval store;
  final SeenLines seen;

  /// Characters of text per call.
  static const int pageChars = maxToolResultChars - 400;

  /// Each owner's line of [_ownerSpread], kept for the question: the count
  /// is a scan of every story line.
  final Map<String, Future<String?>> _spreads = {};

  /// 0.14: where the story text says the name of whose record this is, by
  /// collection (the same line `search` writes for a word). The name is the
  /// record's own (`RecordText.owner`, from the table's id), never one found
  /// in its text; none for a name of one character or one no line has. A
  /// hint for where to look: nothing here is read.
  Future<String?> _ownerSpread(RecordText record) {
    final owner = record.owner.trim();
    if (owner.runes.length < 2) return Future.value();
    return _spreads[owner] ??= () async {
      final own = narrowTo(store, gameOfId(record.id));
      final spread =
          await own.termSpread(await own.storyLineHitCounts([owner]));
      return spread == null ? null : '“$owner”在剧情里：${formatTermSpread(spread)}';
    }();
  }

  @override
  String get name => 'read_record';

  @override
  String get description => '读取一条剧情以外的资料（档案、语音、模组故事、物品与敌人的描述等）的全文：'
      'id 是检索结果或查询结果里的记录 id（record: 后面的部分）。'
      '开头一行写它的标题、类别和所属对象（这条语音是谁的、这个模组是谁的）；'
      '有所属对象时下一行写这个名字在剧情里出现在哪些故事集（只是去哪里找的线索）。'
      '很长的资料分页给出；有后续时结果提供下一页 start。读过的资料可以作出处（record:<id>）。'
      '找不到 id 时，按名字用 search，按条件用 sql 查 normalized_records / entity_documents。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': '记录 id'},
          'start': {'type': 'integer', 'description': '从第几个字开始，默认 0'},
        },
        'required': ['id'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final id =
        '${arguments['id'] ?? ''}'.trim().replaceFirst(_recordPrefix, '');
    if (id.isEmpty) return '缺少参数 id：写检索结果里 record: 后面的记录 id。';
    if ((_int(arguments['start']) ?? 0) <= 0 &&
        (ledger?.recordInContext(id) ?? false)) {
      return '$inContextPrefix record:$id 的全文仍在上文（${contextStep(ledger!.stepOfRecord(id)!)}的结果），没有重新读取。';
    }
    final record = await store.readRecord(id);
    if (record == null) {
      return '没有 id 为 $id 的资料。';
    }
    final text = record.content;
    final start = (_int(arguments['start']) ?? 0).clamp(0, text.length);
    final end =
        start + pageChars > text.length ? text.length : start + pageChars;
    final kind = record.subtype.isEmpty || record.subtype == record.category
        ? record.category
        : '${record.category}·${record.subtype}';
    // Whole only when every character was shown in this call.
    seen.addRecord(id, partial: start > 0 || end < text.length);
    return [
      'record:$id | $kind | ${record.title}'
          '${record.owner.isEmpty || record.owner == record.title ? '' : ' | 所属：${record.owner}'}',
      if (start == 0)
        if (await _ownerSpread(record) case final spread?) spread,
      text.substring(start, end),
      if (end < text.length)
        '（本页到第 $end 个字，全文 ${text.length} 个字；下一页 start=$end）'
      else if (start > 0)
        '（到全文末尾，共 ${text.length} 个字）',
    ].join('\n');
  }
}

/// `read_story`: consecutive lines of one chapter.
class ReadStoryTool extends AgentTool {
  ReadStoryTool(this.store, this.seen, {this.ledger});
  final ContextLedger? ledger;

  final GameDataRetrieval store;
  final SeenLines seen;

  static const int defaultCount = 200;
  static const int maxCount = 300;

  @override
  String get name => 'read_story';

  @override
  String get description => '读取一个故事文件（章节）的原文：从 start 行开始的 count 行'
      '（默认 $defaultCount 行，最多 $maxCount 行，约一整章）。'
      '每行形如 “L行号 [说话人] 内容”，行号即 story_lines.line_index，引用时使用。'
      '没有 end 参数：想读到某一行，用 count 表示行数；本页有后续时，结果会给出下一页 start。'
      'story_id 找不到时，可用 sql 在 story_catalog 按 collection_name / story_code / story_name 查真实 id。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_id': {
            'type': 'string',
            'description': '故事文件名（story_lines.story_id，完整路径，如查询结果里所示）',
          },
          'start': {'type': 'integer', 'description': '起始行号（整数，不带 L），默认 0'},
          'count': {'type': 'integer', 'description': '行数，默认 $defaultCount'},
        },
        'required': ['story_id'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    var storyId = '${arguments['story_id'] ?? ''}'.trim();
    if (storyId.isEmpty) return '错误：story_id 为空';
    if (!storyId.endsWith('.txt')) storyId = '$storyId.txt';
    final start = (_int(arguments['start']) ?? 0).clamp(0, 1 << 30);
    final count = (_int(arguments['count']) ?? defaultCount).clamp(1, maxCount);
    final page = await store.readStoryLines(
      storyId: storyId,
      startLine: start,
      maxLines: count,
    );
    if (!page.storyFound) {
      // Level codes are not zero-padded (`16-7`), file numbers are (`16-07`).
      final code = RegExp(r'(\d+-\d+|[A-Z]+-\d+)')
          .firstMatch(storyId)
          ?.group(1)
          ?.replaceAllMapped(
            RegExp(r'(^|-)0+(\d)'),
            (m) => '${m.group(1)}${m.group(2)}',
          );
      final similar = code == null
          ? const <StoryCatalogEntry>[]
          : await store.storiesByCode(code);
      return '没有这个 story_id：$storyId。'
          '${similar.isEmpty ? '' : '关卡号 $code 的章节：${similar.map((e) => '${e.storyId}《${e.label}》').join('；')}。'}';
    }
    if (page.lines.isEmpty) {
      return '$storyId 在 L$start 之后没有内容（已到结尾）。';
    }
    final entries = await store.storyCatalogEntries([storyId]);
    final buffer = StringBuffer()
      ..writeln('《${_storyLabel(storyId, entries)}》 $storyId');
    final printable = <StoryLineEntry>[];
    var chars = buffer.length;
    for (final line in page.lines) {
      final text = formatStoryLine(
        line.lineIndex,
        line.speaker,
        line.content,
        kind: line.kind,
      );
      if (chars + text.length > maxToolResultChars && printable.isNotEmpty) {
        break;
      }
      printable.add(line);
      chars += text.length + 1;
    }
    final deduped = renderStoryLinesWithContext(
      storyId: storyId,
      lines: printable,
      ledger: ledger,
      formatLine: (line) => formatStoryLine(
        line.lineIndex,
        line.speaker,
        line.content,
        kind: line.kind,
      ),
      requireSavings: false,
    );
    if (deduped.allEvidenceInContext) {
      final first = deduped.firstLine!;
      final last = deduped.lastLine!;
      final more = last < page.lines.last.lineIndex || page.hasMore;
      return '$inContextPrefix L$first–L$last 的原文仍在上文（${deduped.steps}的结果），没有重新读取。'
          '${more ? '直接使用上文；要读后面的内容用 start=${last + 1}。' : '这一章到 L$last 结束。'}';
    }
    final last = printable.last.lineIndex;
    for (final line in deduped.lines) {
      buffer.writeln(line);
    }
    for (final line in printable) {
      if (deduped.printedEvidence.contains(line.lineIndex)) {
        seen.addStoryLine(storyId, line);
      }
    }
    final more = last < page.lines.last.lineIndex || page.hasMore;
    buffer.writeln(
      more ? '（本页到 L$last，后面还有；下一页 start=${last + 1}）' : '（到 L$last 为止，本章结束）',
    );
    return buffer.toString().trimRight();
  }
}

/// `grep`: lines containing words, in some chapters or across the corpus.
const String collectionNotFoundDescription =
    '主线单章可用 main_<章号>；新故事可能尚未收录。找不到且无相近名称时，可用 sql 查 story_catalog 的 collection_name / collection_id。';

class GrepTool extends AgentTool {
  GrepTool(this.store, this.seen, {this.ledger});

  final GameDataRetrieval store;
  final SeenLines seen;
  final ContextLedger? ledger;

  static const int defaultHits = 60;
  static const int maxHits = 150;

  /// Stories listed by a corpus-wide count; a major character appears in
  /// ~100–150 (the later ones are often what a question is about).
  static const int maxStoriesListed = 160;

  @override
  String get name => 'grep';

  @override
  String get description => '在剧情台词里找包含某些词的行（正文或说话人，子串匹配，多个词用 | 分隔表示“任一”）。'
      '给 story_ids 或 collection 时返回命中行及上下文；都不给时在全库统计每个故事的命中行数'
      '（只给分布，不给原文：先按故事集汇总，再逐章列出；不给 game 时统计所有已安装的游戏）。'
      '命中行前的 * 是命中标记。只给分布时按主线在前、其余按上线时间排列，格式为 story_id | 章节 | 命中行数；分布不是原文。'
      '全库分布只列部分故事时，可用 sql 按需要的条件统计。'
      '结果被截断时会标出未列出的命中及其所在故事；要看它们，用 story_ids 指定故事再 grep，或用 read_story 读。'
      '$collectionNotFoundDescription';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': '要找的词，多个用 | 分隔，例如 名字|别名',
          },
          'story_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '只在这些故事文件里找（完整的 story_id；不存在的文件会报 0 行；同时给了 collection 时以这里为准）',
          },
          'collection': {
            'type': 'string',
            'description': '只在这个故事集里找（故事集名字或 collection_id，主线某章形如 main_<章>）',
          },
          'context': {
            'type': 'integer',
            'description': '每个命中前后各带几行，默认 2，最多 8',
          },
          'max_hits': {
            'type': 'integer',
            'description': '最多返回多少命中行，默认 $defaultHits，最多 $maxHits',
          },
          'game': _gameParameter('只在这个游戏里找（可选，默认所有已安装的游戏）'),
        },
        'required': ['pattern'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) =>
      _run(narrowTo(store, Game.parse(arguments['game'])), arguments);

  Future<String> _run(
    GameDataRetrieval store,
    Map<String, dynamic> arguments,
  ) async {
    final terms = [
      for (final t in '${arguments['pattern'] ?? ''}'.split('|'))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (terms.isEmpty) return '错误：pattern 为空';
    var storyIds = _stringList(arguments['story_ids'])
        .map((id) => id.endsWith('.txt') ? id : '$id.txt')
        .toList();
    final collectionQuery = '${arguments['collection'] ?? ''}'.trim();
    String? scopeLabel;
    if (collectionQuery.isNotEmpty) {
      final collection = await store.storyCollection(collectionQuery);
      if (collection == null || collection.entries.isEmpty) {
        final index = await store.storyCollectionIndex(like: collectionQuery);
        return '没有找到故事集“$collectionQuery”。'
            '${index.isEmpty ? '' : '名字相近的故事集：${index.take(10).map((c) => '${c.label}（${c.id}）').join('、')}。'}';
      }
      // With both given the files are the scope (0.14 live: the model named
      // three chapters and their collection, and got the whole collection
      // from its first chapter each time).
      if (storyIds.isEmpty) {
        scopeLabel = collection.label;
        storyIds = [for (final e in collection.entries) e.storyId];
      }
    }
    if (storyIds.isEmpty) return _corpusCounts(store, terms);
    final context = (_int(arguments['context']) ?? 2).clamp(0, 8);
    final limit =
        (_int(arguments['max_hits']) ?? defaultHits).clamp(1, maxHits);
    final hits =
        await store.grepStoryLines(terms, storyIds: storyIds, limit: limit + 1);
    if (hits.isEmpty) {
      final hint = await _nearNamesHint(store, terms);
      return '0 行：${scopeLabel ?? '${storyIds.length} 个故事'}里没有 ${terms.join(' / ')}。'
          '${hint.isEmpty ? '' : '\n$hint'}';
    }
    final truncated = hits.length > limit;
    final shown = truncated ? hits.sublist(0, limit) : hits;
    final byStory = <String, List<int>>{};
    for (final hit in shown) {
      byStory.putIfAbsent(hit.storyId, () => []).add(hit.lineIndex);
    }
    final entries = await store.storyCatalogEntries(byStory.keys);
    final buffer = StringBuffer();
    var budgetChars = 0;
    var printedStories = 0;
    final printed = <String, int>{};
    var full = false;
    for (final MapEntry(key: storyId, value: lines) in byStory.entries) {
      final hitSet = lines.toSet();
      // Merge each hit's context window with its neighbours.
      final windows = <(int, int)>[];
      for (final line in lines) {
        final a = (line - context).clamp(0, 1 << 30);
        final b = line + context;
        if (windows.isNotEmpty && a <= windows.last.$2 + 1) {
          windows[windows.length - 1] = (windows.last.$1, b);
        } else {
          windows.add((a, b));
        }
      }
      final heading = '## 《${_storyLabel(storyId, entries)}》 $storyId'
          '（${lines.length} 处）';
      final block = StringBuffer()..writeln(heading);
      var originalBlockChars = block.length;
      final blockLines = <StoryLineEntry>[];
      final printedWindows = <List<StoryLineEntry>>[];
      String? truncatedNote;
      readWindows:
      for (final (a, b) in windows) {
        final page = await store.readStoryLines(
          storyId: storyId,
          startLine: a,
          endLine: b,
          maxLines: b - a + 1,
        );
        final windowLines = <StoryLineEntry>[];
        for (final line in page.lines) {
          final mark = hitSet.contains(line.lineIndex) ? '* ' : '  ';
          final text =
              '$mark${formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind)}';
          // Use pre-omission lengths so saved characters cannot add hits or stories.
          if (budgetChars + originalBlockChars + text.length >
                  maxToolResultChars &&
              (printedStories > 0 || blockLines.isNotEmpty)) {
            full = true;
            printedWindows.add(windowLines);
            truncatedNote = '（篇幅已满，后面的行没有列出：'
                'story_id=$storyId start=${line.lineIndex}）';
            originalBlockChars += truncatedNote.length + 1;
            break readWindows;
          }
          windowLines.add(line);
          blockLines.add(line);
          originalBlockChars += text.length + 1;
        }
        printedWindows.add(windowLines);
        originalBlockChars += '  …'.length + 1;
      }
      final printedEvidence = <int>{};
      for (final window in printedWindows) {
        final rendered = renderStoryLinesWithContext(
          storyId: storyId,
          lines: window,
          ledger: ledger,
          formatLine: (line) =>
              '${hitSet.contains(line.lineIndex) ? '* ' : '  '}'
              '${formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind)}',
          formatPointer: (note, omitted) =>
              '${omitted.any((line) => hitSet.contains(line.lineIndex)) ? '* ' : '  '}'
              '$note',
        );
        for (final line in rendered.lines) {
          block.writeln(line);
        }
        printedEvidence.addAll(rendered.printedEvidence);
        // A window separator and truncation guide are navigation information.
        if (truncatedNote == null || !identical(window, printedWindows.last)) {
          block.writeln('  …');
        }
      }
      if (truncatedNote != null) block.writeln(truncatedNote);
      budgetChars += originalBlockChars;
      buffer.write(block);
      if (blockLines.isNotEmpty) {
        for (final line in blockLines) {
          if (printedEvidence.contains(line.lineIndex)) {
            seen.addStoryLine(storyId, line);
          }
        }
        printedStories++;
        printed[storyId] =
            blockLines.where((l) => hitSet.contains(l.lineIndex)).length;
      }
      if (full) break;
    }
    if (truncated) buffer.writeln('（命中超过 $limit 行，只列出前 $limit 行）');
    final text = buffer.toString().trimRight();
    if (!truncated && !full) return text;
    // Where the hits not listed are (0.14 live: with "only the first N"
    // and no way on, the same call was sent again twice).
    final counts = await store.storyLineHitCounts(terms, storyIds: storyIds);
    final rest = [
      for (final id in storyIds.toSet())
        if ((counts[id] ?? 0) > (printed[id] ?? 0))
          '$id ${counts[id]! - (printed[id] ?? 0)} 处',
    ];
    if (rest.isEmpty) return text;
    return '$text\n没有列出的命中：${rest.take(restListed).join('、')}'
        '${rest.length > restListed ? ' 等 ${rest.length} 个故事' : ''}。';
  }

  /// How many stories the note on hits not listed names.
  static const int restListed = 12;

  /// Hit counts per story over the whole corpus, main story first, then by
  /// release.
  Future<String> _corpusCounts(
    GameDataRetrieval store,
    List<String> terms,
  ) async {
    final counts = await store.storyLineHitCounts(terms);
    if (counts.isEmpty) {
      final hint = await _nearNamesHint(store, terms);
      return '0 行：全库没有包含 ${terms.join(' / ')} 的台词。'
          '${hint.isEmpty ? '' : '\n$hint'}';
    }
    final entries = await store.storyCatalogEntries(counts.keys);
    (int, int, int, String) key(String id) {
      final e = entries[id];
      if (e == null) return (3, 0, 0, id);
      if (e.collectionType == 'MAINLINE') {
        final n = int.tryParse(
              RegExp(r'(\d+)').firstMatch(e.collectionId)?.group(1) ?? '',
            ) ??
            0;
        return (0, n, e.storySort, id);
      }
      final t = e.startTime ?? 0;
      return (t > 0 ? 1 : 2, t, e.storySort, id);
    }

    final ids = counts.keys.toList()
      ..sort((x, y) {
        final a = key(x);
        final b = key(y);
        for (final c in [
          a.$1.compareTo(b.$1),
          a.$2.compareTo(b.$2),
          a.$3.compareTo(b.$3),
        ]) {
          if (c != 0) return c;
        }
        return a.$4.compareTo(b.$4);
      });
    final total = counts.values.fold<int>(0, (n, c) => n + c);
    // 0.14: one part per game, each with its own totals first, so a game
    // with few hits is not lost at the end of a long list.
    final byGame = <Game, List<String>>{};
    for (final id in ids) {
      byGame.putIfAbsent(gameOfId(id), () => []).add(id);
    }
    final buffer = StringBuffer()
      ..writeln('全库共 $total 行命中，分布在 ${ids.length} 个故事'
          '${byGame.length > 1 ? '（${[
              for (final MapEntry(key: g, value: list) in byGame.entries)
                '${g.label} ${list.fold<int>(0, (n, id) => n + counts[id]!)} 行 / ${list.length} 个故事',
            ].join('；')}）' : ''}'
          '：');
    final perGame = byGame.length > 1
        ? (maxStoriesListed / byGame.length).floor()
        : maxStoriesListed;
    for (final MapEntry(key: game, value: list) in byGame.entries) {
      if (byGame.length > 1) buffer.writeln('## ${game.label}');
      // 0.14: the same counts by collection first — the list below is by
      // chapter, and long.
      final spread = await narrowTo(store, game)
          .termSpread({for (final id in list) id: counts[id]!});
      if (spread != null) {
        buffer.writeln('按故事集：${formatTermSpread(spread)}');
      }
      var listed = 0;
      for (final id in list) {
        if (listed >= perGame) {
          buffer.writeln('……还有 ${list.length - listed} 个故事未列出。');
          break;
        }
        buffer.writeln('$id | ${_storyLabel(id, entries)} | ${counts[id]}');
        listed++;
      }
    }
    return buffer.toString().trimRight();
  }
}

/// `outline`: the chapters of a story collection with official synopses.
class OutlineTool extends AgentTool {
  OutlineTool(this.store);

  final GameDataRetrieval store;

  @override
  String get name => 'outline';

  @override
  String get description =>
      '列出一个故事集（活动 / 主线章节 / 干员密录）的全部章节：story_id、关卡号、章名和官方梗概。'
      '梗概只用于定位，不能当证据。'
      '末尾列出与它相关的其他故事集，按共有人物及（有数据时）内容相似度排列，只作线索；是否承接及故事内先后要读原文确认，上线时间不等于故事里的先后。'
      '$collectionNotFoundDescription';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'collection': {
            'type': 'string',
            'description': '故事集名字或 collection_id，也可以是其中一个 story_id',
          },
        },
        'required': ['collection'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = '${arguments['collection'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：collection 为空';
    final collection = await store.storyCollection(query);
    if (collection == null || collection.entries.isEmpty) {
      final index = await store.storyCollectionIndex(like: query);
      return '没有找到故事集“$query”。'
          '${index.isEmpty ? '' : '名字相近的故事集：${index.take(10).map((c) => '${c.label}（${c.id}，${c.chapters} 章）').join('、')}。'}';
    }
    final month = collection.releaseMonth;
    // Written last, and always: the chapters give way to it.
    final related = _related(
      await store.relatedCollections(collection.collectionId),
    );
    final buffer = StringBuffer()
      ..writeln('${collection.label}（${collection.collectionId}，'
          '${collection.entries.length} 章${month == null ? '' : '，上线 $month'}）');
    for (final e in collection.entries) {
      final synopsis =
          (e.synopsis ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      buffer.writeln('${e.storyId} | ${e.chapterLabel}'
          '${synopsis.isEmpty ? '' : ' | ${_clip(synopsis, 160)}'}');
      if (buffer.length + related.length > maxToolResultChars) {
        buffer.writeln('……（篇幅已满）');
        break;
      }
    }
    buffer.write(related);
    return buffer.toString().trimRight();
  }

  /// The section on related collections (empty when there are none): what
  /// each shares with this one, so the model can tell a strong hint from a
  /// weak one.
  static String _related(List<RelatedCollection> related) {
    if (related.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('相关的故事集：');
    for (final r in related) {
      final month = r.releaseMonth;
      buffer.writeln(
        [
          '${r.label}（${r.id}${month == null ? '' : '，上线 $month'}）',
          [
            if (r.shared > 0)
              '共有 ${r.shared} 人：${r.names.join('、')}'
                  '${r.shared > r.names.length ? '…' : ''}',
            if (r.similarity case final s?) '内容相近 ${s.toStringAsFixed(2)}',
          ].join('；'),
        ].join(''),
      );
    }
    return buffer.toString();
  }
}

/// `similar_names`: names in the DB spelled or pronounced like a term.
class SimilarNamesTool extends AgentTool {
  SimilarNamesTool(this.store);

  final GameDataRetrieval store;

  @override
  String get name => 'similar_names';

  @override
  String get description => '查库里与某个写法字形或读音相近的名字（人物、说话人、故事集、章节、实体）。'
      '某个名字查不到时用来找正确写法；结果只说明字符串相近。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '查不到的写法'},
        },
        'required': ['name'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final term = '${arguments['name'] ?? ''}'.trim();
    if (term.isEmpty) return '错误：name 为空';
    final similar = await store.similarNames(term, limit: 8);
    if (similar.isEmpty) return '没有找到与“$term”相近的名字。';
    return similar
        .map(
          (s) =>
              '${s.name}（${s.kind}${s.occurrences > 0 ? '，${s.occurrences} 次' : ''}）',
        )
        .join('\n');
  }
}

/// `delegate`: hands one search to a sub-agent with its own conversation
/// (R17 phase 2); several can run in the same turn.
class DelegateTool extends AgentTool {
  DelegateTool(this.runSubtask);

  /// Runs the sub-agent and returns its checked findings.
  final Future<String> Function(Map<String, dynamic> arguments) runSubtask;

  @override
  String get name => 'delegate';

  @override
  String get description => '把一部分查找和阅读交给一个子助手（独立对话，只有查库工具，不占用你的上下文）。'
      '同一轮可以派出多个并行执行，例如按时间阶段或故事集拆分。task 要写清查什么、交回什么；'
      '可用 story_ids 或 collection 限定范围。返回子助手的要点，每点带出处，这些出处已经核对过，可以直接引用。'
      '适合涉及很多章节的问题；只需查一两章时，直接调用读取工具更快。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'task': {'type': 'string', 'description': '交给子助手的任务'},
          'story_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '建议它阅读的故事文件（可选）',
          },
          'collection': {
            'type': 'string',
            'description': '限定的故事集（可选）',
          },
        },
        'required': ['task'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) =>
      runSubtask(arguments);
}

/// The scope hints of a `delegate` call, as text for the sub-agent.
String delegateTaskText(Map<String, dynamic> arguments) {
  final task = '${arguments['task'] ?? ''}'.trim();
  final ids = _stringList(arguments['story_ids']);
  final collection = '${arguments['collection'] ?? ''}'.trim();
  return [
    task,
    if (ids.isNotEmpty) '建议阅读：${ids.join('、')}',
    if (collection.isNotEmpty) '范围：故事集 $collection',
  ].join('\n');
}

/// The story agent's tools, sharing one [SeenLines] log. 0.14: `search`
/// (story text of every game by meaning and names, and the wikis when
/// [wiki] is given) comes first and replaces `find`.
List<AgentTool> loreTools(
  GameDataRetrieval store,
  SeenLines seen, {
  EmbeddingClient? embeddingClient,
  WikiLookup? wiki,
  LinePicker? picker,
  MaterialSnapshot? materials,
  ContextLedger? ledger,
}) {
  final manual = LibraryManual(store);
  final tools = <AgentTool>[
    SearchTool(
      store,
      seen,
      embeddingClient: embeddingClient,
      wiki: wiki,
      materials: materials,
      ledger: ledger,
    ),
    ReadStoryTool(store, seen, ledger: ledger),
    ReadRecordTool(store, seen, ledger: ledger),
    GrepTool(store, seen, ledger: ledger),
    SqlTool(store, seen, manual: manual, ledger: ledger),
    GuideTool(manual, seen, ledger: ledger),
    OutlineTool(store),
    SimilarNamesTool(store),
    GatherTool(store, seen, picker: picker, ledger: ledger),
  ];
  if (materials == null || !materials.isAvailable) return tools;
  return [
    for (final tool in tools)
      if (const {'grep', 'gather', 'sql', 'guide'}.contains(tool.name))
        MaterialJoinedTool(tool, materials, seen, ledger: ledger)
      else
        tool,
    ReadMaterialTool(materials, seen, ledger: ledger),
  ];
}

/// Decodes tool-call arguments; malformed JSON becomes an empty map.
Map<String, dynamic> decodeToolArguments(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}
