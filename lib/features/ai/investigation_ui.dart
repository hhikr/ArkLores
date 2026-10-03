/// UI parsing helpers for story answers (R3b; R13 neutral envelope).
library;

import '../../core/agent/story_answer.dart';
import '../../core/gamedata/story_catalog.dart'
    show StoryCatalogEntry, fallbackStoryLabel;

final RegExp _lineRefPattern = RegExp(r'([\w\-/\.\[\]]+\.txt):(\d+)');

/// Pre-R13 summary answers ended with
/// `Coverage: read=.. | mapped=.. | skipped=..`; parsed only so old
/// conversations still render.
final RegExp coverageReportLinePattern = RegExp(
  r'Coverage:\s*read=\s*([^|]*?)\s*\|\s*mapped=\s*([^|]*?)\s*\|\s*skipped=(.*)',
  caseSensitive: false,
);

/// Parsed legacy `Coverage:` line.
class CoverageReportLine {
  const CoverageReportLine({
    required this.read,
    required this.mapped,
    required this.skipped,
  });
  final String read;
  final String mapped;
  final String skipped;
}

CoverageReportLine? parseCoverageReportLine(String content) {
  final match = coverageReportLinePattern.firstMatch(content);
  if (match == null) return null;
  return CoverageReportLine(
    read: match.group(1)!.trim(),
    mapped: match.group(2)!.trim(),
    skipped: match.group(3)!.trim(),
  );
}

/// Extracts `story_id:line` references from an answer.
List<String> extractLineReferences(String content) {
  final refs = <String>{};
  for (final match in _lineRefPattern.allMatches(content)) {
    refs.add('${match.group(1)}:${match.group(2)}');
  }
  return refs.toList()..sort();
}

/// R14: a citation in answer text — `story_id:line` or `story_id:start-end`,
/// optionally wrapped in backticks. Same shape the citation checker reads.
final RegExp _citationPattern = RegExp(
  r'`?([\w\-/\.\[\]]+\.txt)\s*[:：]\s*(\d+)(?:\s*[-–~]\s*(\d+))?`?',
);

/// Story ids cited in [content] (for label lookup).
Set<String> extractCitedStoryIds(String content) => {
      for (final match in _citationPattern.allMatches(content)) match.group(1)!,
    };

/// R17: a cited non-story record, `record:<id>` (optionally backticked).
final RegExp _recordCitationPattern = RegExp(r'`?record:([\w\-]+)`?');

/// R17: record ids cited in [content], in order of first citation.
List<String> extractCitedRecordIds(String content) => [
      ...{
        for (final m in _recordCitationPattern.allMatches(content)) m.group(1)!,
      },
    ];

/// Readable name of a cited story: the catalog label when known, otherwise a
/// name derived from the path.
String storyDisplayName(String storyId, Map<String, String> labels) =>
    labels[storyId] ?? fallbackStoryLabel(storyId);

/// Renders 1-based line numbers (`end` null for a single line).
typedef LineRangeText = String Function(int start, int? end);

String _defaultLineText(int start, int? end) =>
    end == null ? '第 $start 行' : '第 $start–$end 行';

String _lineText(String start, String? end, LineRangeText format) {
  // Story lines are stored 0-based; users count from 1.
  final a = int.parse(start) + 1;
  return format(a, end == null ? null : int.parse(end) + 1);
}

/// Formats one `story_id:line` reference for users: story name plus a
/// 1-based line number.
String formatLineReference(
  String ref,
  Map<String, String> labels, {
  LineRangeText lineText = _defaultLineText,
}) {
  final match = _citationPattern.firstMatch(ref);
  if (match == null) return ref;
  return '${storyDisplayName(match.group(1)!, labels)} · '
      '${_lineText(match.group(2)!, match.group(3), lineText)}';
}

/// R14: replaces raw `story_id:line` citations in answer markdown with
/// readable ones (`〔巴别塔 BB-7 行动前《…》 第 12 行〕`). The stored answer
/// keeps the raw ids (citation checks, logs); only the display changes.
String humanizeCitations(
  String content,
  Map<String, String> labels, {
  LineRangeText lineText = _defaultLineText,
  String recordLabel = '资料',
}) {
  // R17: records are numbered in citation order (the evidence list below
  // the answer uses the same numbers).
  final records = extractCitedRecordIds(content);
  return content
      .replaceAllMapped(_citationPattern, (m) {
        return '〔${storyDisplayName(m.group(1)!, labels)} '
            '${_lineText(m.group(2)!, m.group(3), lineText)}〕';
      })
      .replaceAllMapped(
        _recordCitationPattern,
        (m) => '〔$recordLabel ${records.indexOf(m.group(1)!) + 1}〕',
      );
}

/// R15: one cited line range (0-based, inclusive) of a chapter.
class CitedRange {
  const CitedRange(this.start, this.end);
  final int start;
  final int end;

  /// Raw reference as the answer stores it (`story_id:start[-end]`).
  String rawRef(String storyId) =>
      start == end ? '$storyId:$start' : '$storyId:$start-$end';
}

/// R15: the cited ranges of one chapter.
class CitedChapter {
  CitedChapter({required this.storyId, required this.label, required this.order});
  final String storyId;

  /// Chapter part of the label (`BB-9 行动前《尘埃落定》`), or the file part
  /// of a path-derived name.
  final String label;
  final int order;
  final List<CitedRange> ranges = [];
}

/// R15: the cited chapters of one collection.
class CitedCollection {
  CitedCollection(this.label);
  final String label;
  final List<CitedChapter> chapters = [];

  int get citationCount =>
      chapters.fold<int>(0, (n, c) => n + c.ranges.length);
}

/// R15: groups the citations of [content] by collection, then chapter
/// (catalog order), then line range (overlapping or adjacent ranges of a
/// chapter merged). Collections keep the order in which the answer first
/// cites them. Without a catalog entry the path-derived name is split into
/// a collection part and a chapter part.
List<CitedCollection> groupCitations(
  String content,
  Map<String, StoryCatalogEntry> entries,
) {
  final collections = <String, CitedCollection>{};
  final chapters = <String, CitedChapter>{};
  final rangesByStory = <String, List<CitedRange>>{};
  for (final m in _citationPattern.allMatches(content)) {
    final storyId = m.group(1)!;
    final a = int.parse(m.group(2)!);
    final b = m.group(3) == null ? a : int.parse(m.group(3)!);
    rangesByStory
        .putIfAbsent(storyId, () => [])
        .add(CitedRange(a <= b ? a : b, a <= b ? b : a));
    if (chapters.containsKey(storyId)) continue;
    final entry = entries[storyId];
    final String collectionLabel;
    final String chapterLabel;
    if (entry != null) {
      collectionLabel = entry.collectionLabel;
      chapterLabel = entry.chapterLabel;
    } else {
      final fallback = fallbackStoryLabel(storyId);
      final cut = fallback.indexOf(' · ');
      collectionLabel = cut < 0 ? fallback : fallback.substring(0, cut);
      chapterLabel = cut < 0 ? '' : fallback.substring(cut + 3);
    }
    final chapter = CitedChapter(
      storyId: storyId,
      label: chapterLabel,
      order: entry?.storySort ?? 1 << 30,
    );
    chapters[storyId] = chapter;
    collections
        .putIfAbsent(collectionLabel, () => CitedCollection(collectionLabel))
        .chapters
        .add(chapter);
  }
  for (final chapter in chapters.values) {
    final ranges = rangesByStory[chapter.storyId]!
      ..sort((x, y) => x.start.compareTo(y.start));
    for (final r in ranges) {
      final last = chapter.ranges.isEmpty ? null : chapter.ranges.last;
      if (last != null && r.start <= last.end + 1) {
        chapter.ranges[chapter.ranges.length - 1] =
            CitedRange(last.start, r.end > last.end ? r.end : last.end);
      } else {
        chapter.ranges.add(r);
      }
    }
  }
  for (final collection in collections.values) {
    collection.chapters.sort((x, y) {
      final byOrder = x.order.compareTo(y.order);
      return byOrder != 0 ? byOrder : x.storyId.compareTo(y.storyId);
    });
  }
  return collections.values.toList(growable: false);
}

/// R17b: the cited line ranges of one story inside an [AnswerBlock]
/// (0-based, merged when overlapping or adjacent).
class BlockStoryCitation {
  BlockStoryCitation(this.storyId);
  final String storyId;
  final List<CitedRange> ranges = [];
}

/// R17b: one block of an answer — a heading, paragraph, list item, table or
/// code block — with its citations taken out of the text. The UI shows the
/// text and then the evidence chain of these citations below it.
class AnswerBlock {
  AnswerBlock({
    required this.markdown,
    required this.indent,
    required this.stories,
    required this.records,
  });

  /// The block without citations; list items are dedented (the UI indents
  /// them by [indent]).
  final String markdown;

  /// Nesting level of a list item (0 for top-level blocks).
  final int indent;

  /// Cited stories in order of first citation.
  final List<BlockStoryCitation> stories;

  /// Cited `record:` ids in order of first citation.
  final List<String> records;

  bool get hasCitations => stories.isNotEmpty || records.isNotEmpty;
}

final RegExp _listItemStart = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])\s+');
final RegExp _headingLine = RegExp(r'^\s{0,3}#{1,6}\s');
final RegExp _ruleLine = RegExp(r'^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _tableLine = RegExp(r'^\s*\|');
final RegExp _fenceLine = RegExp(r'^\s*(```|~~~)');

/// Splits answer markdown into [AnswerBlock]s (R17b). Citations are removed
/// from each block's text, together with what only framed them (empty
/// brackets, "出处：", separators between citations).
List<AnswerBlock> splitAnswerBlocks(String content) {
  final raw = <({List<String> lines, int indent, bool table})>[];
  List<String>? current;
  var currentTable = false;
  var inFence = false;

  void flush() {
    if (current != null && current!.any((l) => l.trim().isNotEmpty)) {
      final first = current!.first;
      final item = _listItemStart.firstMatch(first);
      final width = item == null ? 0 : item.group(1)!.replaceAll('\t', '    ').length;
      raw.add((
        lines: [
          for (final l in current!) _dedent(l, width),
        ],
        indent: width ~/ 2,
        table: currentTable,
      ),);
    }
    current = null;
    currentTable = false;
  }

  for (final line in content.split('\n')) {
    if (inFence) {
      current!.add(line);
      if (_fenceLine.hasMatch(line)) {
        inFence = false;
        flush();
      }
      continue;
    }
    if (_fenceLine.hasMatch(line)) {
      flush();
      current = [line];
      inFence = true;
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
    } else if (_headingLine.hasMatch(line) || _ruleLine.hasMatch(line)) {
      flush();
      current = [line];
      flush();
    } else if (_tableLine.hasMatch(line)) {
      if (!currentTable) flush();
      (current ??= []).add(line);
      currentTable = true;
    } else if (_listItemStart.hasMatch(line)) {
      flush();
      current = [line];
    } else {
      if (currentTable) flush();
      (current ??= []).add(line);
    }
  }
  flush();

  return [
    for (final block in raw) _toAnswerBlock(block.lines.join('\n'), block.indent),
  ];
}

String _dedent(String line, int width) {
  var i = 0;
  while (i < width && i < line.length && (line[i] == ' ' || line[i] == '\t')) {
    i++;
  }
  return line.substring(i);
}

const String _citeMark = '\u0000';
final RegExp _framedCitations = RegExp(
  r'[（(〔【\[]\s*(?:(?:出处|来源|见)\s*[:：]?\s*)?'
  '(?:$_citeMark[\\s、，,；;和及]*)+[）)〕】\\]]',
);
final RegExp _bareCitations = RegExp(
  r'(?:(?:出处|来源)\s*[:：]\s*)?'
  '$_citeMark(?:[\\s、，,；;和及]*$_citeMark)*',
);
final RegExp _spaceBeforePunctuation = RegExp(r'[ \t]+(?=[。，；、！？：）)」』”])');
final RegExp _trailingSpaces = RegExp(r'[ \t]+$', multiLine: true);

AnswerBlock _toAnswerBlock(String text, int indent) {
  final stories = <String, BlockStoryCitation>{};
  final records = <String>[];
  final marked = text
      .replaceAllMapped(_citationPattern, (m) {
        final a = int.parse(m.group(2)!);
        final b = m.group(3) == null ? a : int.parse(m.group(3)!);
        _addRange(
          stories.putIfAbsent(m.group(1)!, () => BlockStoryCitation(m.group(1)!)),
          CitedRange(a <= b ? a : b, a <= b ? b : a),
        );
        return _citeMark;
      })
      .replaceAllMapped(_recordCitationPattern, (m) {
        if (!records.contains(m.group(1)!)) records.add(m.group(1)!);
        return _citeMark;
      });
  final cleaned = marked
      .replaceAll(_framedCitations, '')
      .replaceAll(_bareCitations, '')
      .replaceAll(_spaceBeforePunctuation, '')
      .replaceAll(_trailingSpaces, '');
  return AnswerBlock(
    markdown: cleaned,
    indent: indent,
    stories: stories.values.toList(growable: false),
    records: records,
  );
}

/// Adds [range] to [story], merging overlapping or adjacent ranges.
void _addRange(BlockStoryCitation story, CitedRange range) {
  final ranges = story.ranges..add(range);
  ranges.sort((x, y) => x.start.compareTo(y.start));
  final merged = <CitedRange>[];
  for (final r in ranges) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && r.start <= last.end + 1) {
      merged[merged.length - 1] =
          CitedRange(last.start, r.end > last.end ? r.end : last.end);
    } else {
      merged.add(r);
    }
  }
  ranges
    ..clear()
    ..addAll(merged);
}

/// 1-based display text of a cited range.
String citedRangeText(CitedRange range, LineRangeText lineText) =>
    lineText(range.start + 1, range.end == range.start ? null : range.end + 1);

/// True when [content] carries a story answer envelope (new or legacy).
bool isStoryAnswer(String content) => parseStoryAnswerEnvelope(content) != null;

/// Strips the envelope and the legacy Coverage line from [content] for
/// markdown display; the structured bar shows them instead.
String stripStoryAnswerMarkers(String content) {
  var cleaned = content.replaceFirst(storyAnswerEnvelopePattern, '');
  cleaned = cleaned.replaceFirst(coverageReportLinePattern, '').trim();
  return stripWriterCoverage(cleaned);
}

/// R16: the writer's `[COVERAGE: …]` line, also while it is still being
/// streamed (`[COVER…` at the end of the text).
final RegExp _writerCoverage = RegExp(
    r'\[COVERAGE:[^\]\n]*\]?|\[C?O?V?E?R?A?G?E?:?$',
    caseSensitive: false,);

/// Removes the writer's coverage line from displayed text.
String stripWriterCoverage(String content) =>
    content.replaceAll(_writerCoverage, '').trimRight();
