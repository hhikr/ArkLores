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
}) =>
    content.replaceAllMapped(_citationPattern, (m) {
      return '〔${storyDisplayName(m.group(1)!, labels)} '
          '${_lineText(m.group(2)!, m.group(3), lineText)}〕';
    });

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
  return cleaned;
}
