/// UI parsing helpers for story answers (R3b; R13 neutral envelope).
library;

import '../../core/agent/story_answer.dart';
import '../../core/gamedata/story_catalog.dart' show fallbackStoryLabel;

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

/// True when [content] carries a story answer envelope (new or legacy).
bool isStoryAnswer(String content) => parseStoryAnswerEnvelope(content) != null;

/// Strips the envelope and the legacy Coverage line from [content] for
/// markdown display; the structured bar shows them instead.
String stripStoryAnswerMarkers(String content) {
  var cleaned = content.replaceFirst(storyAnswerEnvelopePattern, '');
  cleaned = cleaned.replaceFirst(coverageReportLinePattern, '').trim();
  return cleaned;
}
