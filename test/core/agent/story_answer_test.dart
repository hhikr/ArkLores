// The status line in front of a story answer (`[STORY_ANSWER: …]`), decided
// by code, and the older envelopes saved conversations still carry.
import 'package:arklores/core/agent/story_answer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats and parses every status', () {
    for (final status in StoryAnswerStatus.values) {
      final line = formatStoryAnswerEnvelope(status, confidence: '0.7');
      final parsed = parseStoryAnswerEnvelope('$line\n正文')!;
      expect(parsed.status, status);
      expect(parsed.confidence, '0.7');
    }
    final bare = parseStoryAnswerEnvelope(
      formatStoryAnswerEnvelope(StoryAnswerStatus.notCovered),
    )!;
    expect(bare.status, StoryAnswerStatus.notCovered);
    expect(bare.confidence, isNull);
    expect(parseStoryAnswerEnvelope('no envelope here'), isNull);
  });

  test('reads the pre-R13 envelope of saved conversations', () {
    final answered = parseStoryAnswerEnvelope(
      '[INVESTIGATION_VERDICT: culprit=char_b | confidence=0.8 | '
      'basis=multi_hypothesis_contrast]\n正文',
    )!;
    expect(answered.status, StoryAnswerStatus.answered);
    expect(answered.confidence, '0.8');
    final unresolved = parseStoryAnswerEnvelope(
      '[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | '
      'basis=insufficient_evidence]',
    )!;
    expect(unresolved.status, StoryAnswerStatus.partial);
  });
}
