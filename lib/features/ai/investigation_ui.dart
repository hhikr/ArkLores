/// UI parsing helpers for investigation answers (R3b).
library;

import '../../core/agent/investigation_verdict.dart';
import '../../core/agent/story_coverage_transform.dart';

final RegExp _lineRefPattern = RegExp(r'([\w\-/\.\[\]]+\.txt):(\d+)');

/// Extracts `story_id:line` references from an investigation answer.
List<String> extractLineReferences(String content) {
  final refs = <String>{};
  for (final match in _lineRefPattern.allMatches(content)) {
    refs.add('${match.group(1)}:${match.group(2)}');
  }
  return refs.toList()..sort();
}

/// True when [content] carries an investigation verdict envelope.
bool isInvestigationAnswer(String content) =>
    parseInvestigationVerdictLine(content) != null;

/// Strips the verdict envelope and the Coverage line from [content] for
/// markdown display; the structured bars show them instead.
String stripInvestigationMarkers(String content) {
  var cleaned = content.replaceFirst(
    RegExp(r'\[INVESTIGATION_VERDICT:[^\]]*\]\s*', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceFirst(coverageReportLinePattern, '').trim();
  return cleaned;
}
