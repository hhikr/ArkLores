/// UI parsing helpers for story answers (R3b; R13 neutral envelope).
library;

import '../../core/agent/story_answer.dart';

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

/// True when [content] carries a story answer envelope (new or legacy).
bool isStoryAnswer(String content) => parseStoryAnswerEnvelope(content) != null;

/// Strips the envelope and the legacy Coverage line from [content] for
/// markdown display; the structured bar shows them instead.
String stripStoryAnswerMarkers(String content) {
  var cleaned = content.replaceFirst(storyAnswerEnvelopePattern, '');
  cleaned = cleaned.replaceFirst(coverageReportLinePattern, '').trim();
  return cleaned;
}
