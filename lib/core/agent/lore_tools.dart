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
import '../gamedata/story_catalog.dart'
    show synopsisRecordId, synopsisRecordSuffix;
import '../llm/embedding_client.dart';
import '../materials/material_snapshot.dart';
import '../wiki/wiki_lookup.dart';
import 'context_ledger.dart';
import 'coverage.dart';
import 'line_picker.dart';
import 'lore_agent_prompts.dart' show loreLibraryManual;
import 'story_read_ranges.dart';
import 'tools/agent_tool.dart';
import 'tools/material_tools.dart';
import 'tools/search_tool.dart';

part 'tools/sql_tool.dart';
part 'tools/read_tools.dart';
part 'tools/grep_tool.dart';
part 'tools/outline_tools.dart';
part 'tools/timeline_tool.dart';

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
