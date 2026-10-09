/// R18: the reorganised answer and the reader's review.
///
/// The main agent's detailed answer (one entry per thing found, R17c JSON)
/// is reorganised into a few paragraphs, one per stage or aspect. The model
/// writes only the paragraphs and which detailed entries each covers
/// (`from`); the citations of a paragraph are the union of those entries'
/// citations, merged by code — so no citation is lost and none is added
/// that the citation check has not passed. The detailed answer stays below
/// [loreDetailsMarker], folded in the app.
library;

import 'dart:convert';

import 'lore_answer_json.dart';

/// Separates the reorganised answer (above) from the detailed one (below).
const String loreDetailsMarker = '[DETAILS]';

/// One entry of a detailed JSON answer.
class LoreAnswerEntry {
  const LoreAnswerEntry({this.heading, this.text = '', this.cites = const []});

  /// Set for a section heading; [text] and [cites] are then empty.
  final String? heading;
  final String text;

  /// `story_id:a-b` / `record:id` / `wiki:<page id>:a-b` references.
  final List<String> cites;

  bool get isText => heading == null;
}

/// The entries of the JSON answer in [content], or null when [content]
/// holds no parsable JSON answer.
List<LoreAnswerEntry>? loreAnswerEntries(String content) {
  final decoded = _decodeObject(content, loreAnswerJsonStart);
  final entries = decoded?['entries'];
  if (entries is! List) return null;
  final out = <LoreAnswerEntry>[];
  for (final e in entries) {
    if (e is! Map) continue;
    final heading = e['heading'];
    if (heading is String && heading.trim().isNotEmpty) {
      out.add(LoreAnswerEntry(heading: heading.trim()));
    }
    final text = e['text'];
    if (text is! String || text.trim().isEmpty) continue;
    final cites = <String>[];
    final raw = e['cite'];
    if (raw is List) cites.addAll(loreCitationRefs(raw));
    out.add(LoreAnswerEntry(text: text.trim(), cites: cites));
  }
  return out;
}

/// [content] with every `cite` of its JSON answer rewritten in the nested
/// form the prompt asks for (`[["<story_id>", a, b], ["record", "<id>"]]`),
/// so a flat or odd citation shape is not replayed to the model in later
/// turns. [content] itself when it holds no parsable JSON answer.
String normalizeAnswerCites(String content) {
  final start = loreAnswerJsonStart.firstMatch(content);
  final decoded = _decodeObject(content, loreAnswerJsonStart);
  final entries = decoded?['entries'];
  if (start == null || decoded == null || entries is! List) return content;
  for (final e in entries) {
    if (e is! Map || e['cite'] is! List) continue;
    e['cite'] = [
      for (final ref in loreCitationRefs(e['cite'] as List))
        if (ref.startsWith('record:'))
          ['record', ref.substring(7)]
        else if (_storyRef.firstMatch(ref) case final m?)
          [
            m.group(1)!,
            int.parse(m.group(2)!),
            int.parse(m.group(3) ?? m.group(2)!),
          ],
    ];
  }
  return jsonEncode(decoded);
}

/// The text entries of [entries], numbered from 1 for the reorganising
/// turn (headings shown unnumbered for context, citations left out).
String numberedEntries(List<LoreAnswerEntry> entries) {
  final out = StringBuffer();
  var n = 0;
  for (final e in entries) {
    if (e.isText) {
      out.writeln('${++n}. ${e.text}');
    } else {
      out.writeln('【${e.heading}】');
    }
  }
  return out.toString().trimRight();
}

/// One paragraph of the reorganised answer.
class LoreAnswerStage {
  const LoreAnswerStage({this.heading, required this.text, required this.from});
  final String? heading;
  final String text;

  /// 1-based numbers of the detailed entries it covers.
  final List<int> from;
}

final RegExp _stagesStart = RegExp(r'\{\s*"stages"');

/// The paragraphs of a reorganising reply, keeping only valid entry
/// numbers (1..[entryCount]); a paragraph covering no valid entry is
/// dropped. Null when nothing usable is left.
List<LoreAnswerStage>? parseLoreStages(String content, int entryCount) {
  final stages = _decodeObject(content, _stagesStart, last: true)?['stages'];
  if (stages is! List) return null;
  final out = <LoreAnswerStage>[];
  for (final s in stages) {
    if (s is! Map) continue;
    final text = s['text'];
    if (text is! String || text.trim().isEmpty) continue;
    final from = <int>[
      for (final f in s['from'] is List ? s['from'] as List : [s['from']])
        for (final n in _numbers(f))
          if (n >= 1 && n <= entryCount) n,
    ];
    if (from.isEmpty) continue;
    final heading = s['heading'];
    out.add(LoreAnswerStage(
      heading: heading is String && heading.trim().isNotEmpty
          ? heading.trim()
          : null,
      text: text.trim(),
      from: from.toSet().toList()..sort(),
    ),);
  }
  return out.isEmpty ? null : out;
}

/// Markdown of the reorganised answer: each paragraph followed by the
/// merged citations of the entries it covers. A detailed entry no
/// paragraph covers gives its citations to the paragraph covering the
/// nearest earlier entry (else the first one), so every citation stays.
String stagedAnswerMarkdown(
  List<LoreAnswerStage> stages,
  List<LoreAnswerEntry> entries,
) {
  final texts = [for (final e in entries) if (e.isText) e];
  final refs = [for (final _ in stages) <String>[]];
  final owner = <int, int>{}; // entry number → stage index
  for (final (i, s) in stages.indexed) {
    for (final n in s.from) {
      owner.putIfAbsent(n, () => i);
      refs[i].addAll(texts[n - 1].cites);
    }
  }
  var last = 0;
  for (var n = 1; n <= texts.length; n++) {
    final i = owner[n];
    if (i != null) {
      last = i;
    } else {
      refs[last].addAll(texts[n - 1].cites);
    }
  }
  final out = <String>[];
  for (final (i, s) in stages.indexed) {
    if (s.heading != null) out.add('## ${s.heading}');
    final cites = mergeCitationRefs(refs[i]);
    out.add([s.text, for (final c in cites) '`$c`'].join(' '));
  }
  return out.join('\n\n');
}

/// [refs] without duplicates; line ranges of one story that overlap or
/// touch become one range. Stories keep the order they first appear in,
/// records follow.
List<String> mergeCitationRefs(List<String> refs) {
  final ranges = <String, List<(int, int)>>{};
  final records = <String>[];
  for (final ref in refs) {
    if (ref.startsWith('record:')) {
      if (!records.contains(ref)) records.add(ref);
      continue;
    }
    final m = _storyRef.firstMatch(ref);
    if (m == null) continue;
    final a = int.parse(m.group(2)!);
    final b = int.tryParse(m.group(3) ?? '') ?? a;
    ranges.putIfAbsent(m.group(1)!, () => []).add(a <= b ? (a, b) : (b, a));
  }
  final out = <String>[];
  for (final MapEntry(key: story, value: list) in ranges.entries) {
    list.sort((x, y) => x.$1.compareTo(y.$1));
    var (lo, hi) = list.first;
    void emit() => out.add(lo == hi ? '$story:$lo' : '$story:$lo-$hi');
    for (final (a, b) in list.skip(1)) {
      if (a <= hi + 1) {
        if (b > hi) hi = b;
      } else {
        emit();
        (lo, hi) = (a, b);
      }
    }
    emit();
  }
  return [...out, ...records];
}

/// A story ref, or (0.13) a wiki ref: a page id with paragraph numbers.
final RegExp _storyRef = RegExp(
  r'^(.+\.txt|wiki:[a-z]+:[A-Za-z0-9_\-/]+@[A-Za-z0-9]+):[LP]?(\d+)(?:-[LP]?(\d+))?$',
);

/// The questions of a review reply (`{"issues": [...]}`); empty for
/// `{"ok": true}` or a reply that cannot be read.
List<String> parseReviewIssues(String content, {int max = 3}) {
  final issues = _decodeObject(content, RegExp(r'\{'))?['issues'];
  if (issues is! List) return const [];
  return [
    for (final i in issues)
      if (i is String && i.trim().isNotEmpty) i.trim(),
  ].take(max).toList();
}

/// [markdown] without its citations, for the reviewer (who reads the
/// answer as a reader would).
String withoutCitations(String markdown) => markdown
    .replaceAll(
      RegExp(r'\s*`[^`\n]*(?:\.txt[:：][^`\n]*|record:[^`\n]*|wiki:[^`\n]*)`'),
      '',
    )
    .trim();

/// An entry number, or a "3-5" range of them, as a list of numbers.
List<int> _numbers(Object? v) {
  if (v is num) return [v.toInt()];
  final m = RegExp(r'^\s*(\d+)\s*(?:[-–~—]\s*(\d+))?\s*$').firstMatch('$v');
  if (m == null) return const [];
  final a = int.parse(m.group(1)!);
  final b = m.group(2) == null ? a : int.parse(m.group(2)!);
  if (b < a || b - a > 200) return [a];
  return [for (var n = a; n <= b; n++) n];
}

/// The JSON object starting at [start] in [content] (text after its last
/// closing brace is ignored), or null.
Map<String, dynamic>? _decodeObject(
  String content,
  RegExp start, {
  bool last = false,
}) {
  // 0.14: each candidate is cut at its own closing brace (strings
  // respected), so text or a second object after it does not spoil it; a
  // model that wrote several versions gives the [last] usable one when
  // asked for.
  Map<String, dynamic>? found;
  for (final m in start.allMatches(content)) {
    final end = _closingBrace(content, m.start);
    final text = content.substring(m.start, end < 0 ? content.length : end + 1);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      // Older shape: up to the last brace of the whole text.
      final lastBrace = content.lastIndexOf('}');
      if (end >= 0 || lastBrace < m.start) continue;
      try {
        decoded = jsonDecode(content.substring(m.start, lastBrace + 1));
      } on FormatException {
        continue;
      }
    }
    if (decoded is! Map<String, dynamic>) continue;
    found = decoded;
    if (!last) return found;
  }
  return found;
}

/// Index of the brace that closes the object opening at [open], or -1.
int _closingBrace(String text, int open) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
