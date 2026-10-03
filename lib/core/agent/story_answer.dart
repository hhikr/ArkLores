/// Answer envelope and output styles of the story QA pipeline (R13).
///
/// Every answer the story agent (`LoreAgentLoop`) writes starts with one
/// machine-readable line:
///
/// ```text
/// [STORY_ANSWER: status=answered|partial|not_covered]
/// ```
///
/// The status is decided by CODE from what the run actually did:
/// `not_covered` when no citation could be checked against text the tools
/// showed, `partial` when the model reported gaps (`[COVERAGE: gaps]`) or
/// the turn limit was reached, `answered` otherwise. It says nothing about
/// the kind of question — the same envelope serves "who", "how", summaries
/// and fact checks. (R13–R16 sessions may also carry `confidence=`.)
///
/// Pre-R13 sessions stored `[INVESTIGATION_VERDICT: field=… | confidence=… |
/// basis=…]`; [parseStoryAnswerEnvelope] still reads it so old
/// conversations render (display compatibility only: the first field's
/// value `unresolved` maps to [StoryAnswerStatus.partial]).
library;

/// How the writer formats the answer. The style changes ONLY the output
/// format; retrieval, evidence and citation checks are identical.
enum AnswerStyle {
  /// Direct answer, cited evidence, counter-evidence, confidence.
  answer,

  /// Overview, timeline and key moments, each cited.
  summary,

  /// `[FACT_CHECK_VERDICT:…]` line, claim breakdown, cited evidence.
  factCheck,
}

/// Outcome of a run, decided by code.
enum StoryAnswerStatus {
  answered('answered'),
  partial('partial'),
  notCovered('not_covered');

  const StoryAnswerStatus(this.wireValue);
  final String wireValue;

  static StoryAnswerStatus? fromWire(String value) {
    for (final status in values) {
      if (status.wireValue == value.trim().toLowerCase()) return status;
    }
    return null;
  }
}

/// Parsed answer envelope.
class StoryAnswerEnvelope {
  const StoryAnswerEnvelope({required this.status, this.confidence});
  final StoryAnswerStatus status;

  /// 0–1 as given by the planner/writer; null when absent.
  final String? confidence;
}

/// Renders the envelope line.
String formatStoryAnswerEnvelope(
  StoryAnswerStatus status, {
  String? confidence,
}) =>
    '[STORY_ANSWER: status=${status.wireValue}'
    '${confidence == null ? '' : ' | confidence=$confidence'}]';

final RegExp _envelopePattern = RegExp(
  r'\[STORY_ANSWER:\s*status\s*=\s*([a-z_]+)\s*(?:\|\s*confidence\s*=\s*([^\]\s]+)\s*)?\]',
  caseSensitive: false,
);

final RegExp _legacyPattern = RegExp(
  r'\[INVESTIGATION_VERDICT:\s*[a-z_]+\s*=\s*([^|\]]+?)\s*\|'
  r'\s*confidence\s*=\s*([^|\]]+?)\s*\|'
  r'\s*basis\s*=\s*([^|\]]+?)\s*\]',
  caseSensitive: false,
);

/// Matches either envelope form (for stripping it from displayed text).
final RegExp storyAnswerEnvelopePattern = RegExp(
  r'\[(?:STORY_ANSWER|INVESTIGATION_VERDICT):[^\]]*\]\s*',
  caseSensitive: false,
);

/// Outcome label of one recorded answer, used by the live harness and
/// `tools/summarize_eval.dart`: `error`, `no_answer` (empty, or a pre-R12
/// state dump `调查无法推进`), or the envelope status (`answered`, `partial`,
/// `not_covered`); answers without an envelope count as `answered`.
String classifyAnswer({required bool completed, required String answer}) {
  if (!completed) return 'error';
  if (answer.trim().isEmpty || answer.contains('调查无法推进')) {
    return 'no_answer';
  }
  return parseStoryAnswerEnvelope(answer)?.status.wireValue ?? 'answered';
}

/// Parses the envelope of [content]; null when absent.
StoryAnswerEnvelope? parseStoryAnswerEnvelope(String content) {
  final match = _envelopePattern.firstMatch(content);
  if (match != null) {
    final status = StoryAnswerStatus.fromWire(match.group(1)!);
    if (status == null) return null;
    return StoryAnswerEnvelope(status: status, confidence: match.group(2));
  }
  final legacy = _legacyPattern.firstMatch(content);
  if (legacy == null) return null;
  final unresolved = legacy.group(1)!.trim() == 'unresolved';
  return StoryAnswerEnvelope(
    status: unresolved ? StoryAnswerStatus.partial : StoryAnswerStatus.answered,
    confidence: legacy.group(2)!.trim(),
  );
}

/// Normalizes the fact-check verdict line of a writer answer (R13): a
/// definite verdict needs cited, actually-read text. Exposed for tests.
String normalizeFactCheckBody(
  String body, {
  required bool nothingRead,
  required bool hasValidCitation,
}) {
  final marker = RegExp(
    r'\[FACT_CHECK_VERDICT:(supported|refuted|uncertain|unavailable)\]\s*',
    caseSensitive: false,
  );
  final requested = marker.firstMatch(body)?.group(1)?.toLowerCase();
  var verdict = requested ?? 'uncertain';
  if (nothingRead) {
    verdict = 'unavailable';
  } else if ((verdict == 'supported' || verdict == 'refuted') &&
      !hasValidCitation) {
    verdict = 'uncertain';
  }
  return '[FACT_CHECK_VERDICT:$verdict]\n${body.replaceFirst(marker, '').trim()}';
}
