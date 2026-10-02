/// Investigation verdict validation for the Story Investigation Agent (P1,
/// R3). Code-level gates per `AI_RETRIEVAL_OPTIMIZATION.md` §5.3 and
/// `docs/R3_DESIGN_DECISIONS.md`:
///
/// 1. S6 gate: a `culprit` conclusion is only allowed when at least two
///    suspects have non-empty evidence sets (from `collect_suspect_evidence`
///    DATA blocks), or the model explicitly declared single-suspect-exhausted;
///    otherwise the verdict is downgraded to unresolved.
/// 2. Line-level provenance: every `story_id:line` reference in the answer
///    must appear in the actual observations; unsupported references get a
///    warning appended (extending `applySourceGuard` to line level).
/// 3. Coverage report: normalized against actual tool observations via
///    [validateCoverageReport].
///
/// DATA blocks are parsed with priority; text markers are the fallback.
library;

import 'story_coverage_transform.dart';
import 'tools/observation_data.dart';

final RegExp _verdictPattern = RegExp(
  r'\[INVESTIGATION_VERDICT:\s*culprit\s*=\s*([^|\]]+?)\s*\|'
  r'\s*confidence\s*=\s*([^|\]]+?)\s*\|'
  r'\s*basis\s*=\s*([^|\]]+?)\s*\]',
  caseSensitive: false,
);

final RegExp _lineRefPattern = RegExp(r'([\w\-/\.\[\]]+\.txt):(\d+)');

/// Parsed investigation verdict envelope.
class InvestigationVerdictEnvelope {
  const InvestigationVerdictEnvelope({
    required this.culprit,
    required this.confidence,
    required this.basis,
  });
  final String culprit;
  final String confidence;
  final String basis;
}

/// Parses the `[INVESTIGATION_VERDICT: ...]` envelope; null when absent.
InvestigationVerdictEnvelope? parseInvestigationVerdictLine(String content) {
  final match = _verdictPattern.firstMatch(content);
  if (match == null) return null;
  return InvestigationVerdictEnvelope(
    culprit: match.group(1)!.trim(),
    confidence: match.group(2)!.trim(),
    basis: match.group(3)!.trim(),
  );
}

/// Validates and normalizes an investigation answer.
String validateInvestigationVerdict(
  String answer,
  List<String> observations,
) {
  var result = _gateCulprit(answer, observations);
  result = _guardLineReferences(result, observations);
  return validateCoverageReport(result, observations);
}

/// S6 gate: downgrade unsupported culprit conclusions.
String _gateCulprit(String answer, List<String> observations) {
  final match = _verdictPattern.firstMatch(answer);
  if (match == null) return answer;
  final culprit = match.group(1)!.trim();
  if (culprit.isEmpty || culprit == 'unresolved') return answer;

  final joined = observations.join('\n');
  final blocks = parseDataBlocks(joined);
  final suspectsWithEvidence = <String>{};
  for (final block in blocks) {
    if (block['type'] != 'collect_suspect_evidence') continue;
    final entityId = block['entity_id'];
    final rows = (block['evidence_rows'] as num?)?.toInt() ?? 0;
    if (entityId is String && rows > 0) {
      suspectsWithEvidence.add(entityId);
    }
  }
  final singleExhausted = joined.contains('single-suspect-exhausted');
  final s6Satisfied = suspectsWithEvidence.length >= 2 || singleExhausted;
  if (s6Satisfied) return answer;

  final downgraded = answer.replaceRange(
    match.start,
    match.end,
    '[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | '
        'basis=insufficient_evidence]',
  );
  return '$downgraded\n\n> Warning: culprit claim rejected: fewer than two '
      'suspects with non-empty evidence sets were collected (S6 gate). '
      'Collected: ${suspectsWithEvidence.isEmpty ? 'none' : suspectsWithEvidence.join(', ')}.';
}

/// Appends a warning for every `story_id:line` reference in the answer that
/// has no counterpart in the observations.
String _guardLineReferences(String answer, List<String> observations) {
  final observedRefs = _lineRefsFromObservations(observations);
  final claimedRefs = <String>{};
  for (final match in _lineRefPattern.allMatches(answer)) {
    claimedRefs.add('${match.group(1)}:${match.group(2)}');
  }
  final missing = claimedRefs.difference(observedRefs).toList()..sort();
  if (missing.isEmpty) return answer;
  return '$answer\n\n> Source warning: the following line reference(s) were '
      'not found in any Observation and may be fabricated: '
      '${missing.join(', ')}.';
}

/// Collects `story_id:line` pairs from observations that carry line rows
/// (`Story:` header followed by `N | ...` lines).
Set<String> _lineRefsFromObservations(List<String> observations) {
  final refs = <String>{};
  final storyPattern = RegExp(r'^Story:\s*(\S+)', multiLine: true);
  final linePattern = RegExp(r'^(\d+)\s*\|', multiLine: true);
  for (final observation in observations) {
    final storyMatch = storyPattern.firstMatch(observation);
    if (storyMatch == null) continue;
    final storyId = storyMatch.group(1)!;
    for (final lineMatch in linePattern.allMatches(observation)) {
      refs.add('$storyId:${lineMatch.group(1)}');
    }
  }
  return refs;
}
