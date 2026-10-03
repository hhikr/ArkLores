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

  /// `story_id:a-b` / `record:id` references.
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
    if (raw is List) {
      for (final c in raw) {
        final ref = loreCitationRef(c is List ? c : [c]);
        if (ref != null && !cites.contains(ref)) cites.add(ref);
      }
    }
    out.add(LoreAnswerEntry(text: text.trim(), cites: cites));
  }
  return out;
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
  final stages = _decodeObject(content, _stagesStart)?['stages'];
  if (stages is! List) return null;
  final out = <LoreAnswerStage>[];
  for (final s in stages) {
    if (s is! Map) continue;
    final text = s['text'];
    if (text is! String || text.trim().isEmpty) continue;
    final from = <int>[
      for (final f in s['from'] is List ? s['from'] as List : const [])
        if (_int(f) case final int n when n >= 1 && n <= entryCount) n,
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

final RegExp _storyRef = RegExp(r'^(.+\.txt):(\d+)(?:-(\d+))?$');

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
    .replaceAll(RegExp(r'\s*`[^`\n]*(?:\.txt[:：][^`\n]*|record:[^`\n]*)`'), '')
    .trim();

int? _int(Object? v) => v is int ? v : int.tryParse('$v'.trim());

/// The JSON object starting at [start] in [content] (text after its last
/// closing brace is ignored), or null.
Map<String, dynamic>? _decodeObject(String content, RegExp start) {
  final m = start.firstMatch(content);
  if (m == null) return null;
  final end = content.lastIndexOf('}');
  if (end < m.start) return null;
  try {
    final decoded = jsonDecode(content.substring(m.start, end + 1));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
