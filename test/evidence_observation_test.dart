import 'package:arklores/features/ai/evidence_observation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses multiple GameData result blocks and required metadata', () {
    const observation = '''Retrieval Plan: evidence mode

=== Result #1 (Score: 1.0000) ===
Source Kind: GameData
Retrieval Type: scoped_story_evidence
Evidence Level: direct candidate
Ranking Reason: entity and claim terms are nearby
Content Type: story
Title: 关卡之后
Section: 行动后
Source Path: activities/test.txt
Raw ID: story:test:1
Trust: GameData / game original text (highest).
Content Excerpt:
第一行: 保留冒号。

=== Result #2 (Score: 0.5000) ===
Source Kind: GameData
Retrieval Type: entity_document
Ranking Reason: structured entity match
Title: 阿米娅
Trust: GameData / game original text (highest).
Content Excerpt:
档案文本''';

    final records = parseGameDataEvidence(observation);
    expect(records, hasLength(2));
    expect(records.first.title, '关卡之后');
    expect(records.first.isDirectCandidate, isTrue);
    expect(records.first.sourcePath, 'activities/test.txt');
    expect(records.first.excerpt, contains('第一行: 保留冒号。'));
    expect(records.last.isDirectCandidate, isFalse);
  });

  test('rejects non-GameData and incomplete result blocks', () {
    expect(parseGameDataEvidence('Source Kind: Wiki\nTitle: page'), isEmpty);
    expect(
      parseGameDataEvidence(
          '=== Result #1 ===\nSource Kind: GameData\nTitle: incomplete'),
      isEmpty,
    );
  });
}
