import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Operator Assembly Integration Tests', () {
    final crawler = MediaWikiCrawler();

    tearDownAll(() {
      crawler.dispose();
    });

    test('Fix 1: Skills should only contain names, not effects (银灰 — has 技能+技能2 templates)', () async {
      // SilverAsh has skills split across {{技能}} and {{技能2}} templates.
      // The parser must parse both and deduplicate by 技能名.
      const opTitle = '银灰';
      final wikitexts = await crawler.fetchRawWikitexts(
        WikiSite.prts,
        [opTitle, '$opTitle/语音记录', '${opTitle}的信物'],
      );

      final assembled = WikiIndexingNotifier.assembleOperatorMarkdown(
        opTitle,
        wikitexts[opTitle]?.content ?? '',
        wikitexts['$opTitle/语音记录']?.content ?? '',
        wikitexts['${opTitle}的信物']?.content ?? '',
      );

      print('\n═══════════════════════════════════════════');
      print('Fix 1: Skills/Talents — names only, no effects');
      print('═══════════════════════════════════════════');

      // Extract the talents section
      final talentSection = _extractBetween(assembled, '## 天赋设定', '\n## ');
      print('--- Talents ---');
      print(talentSection);

      // Extract the skills section
      final skillSection = _extractBetween(assembled, '## 技能设定', '\n## ');
      print('\n--- Skills ---');
      print(skillSection);

      // Verify talents only have names (天赋名), not effects
      expect(talentSection, contains('第一天赋'));
      expect(talentSection, isNot(contains('无视')),  // no effect descriptions
          reason: 'Talent effects (like "无视防御") should not appear');

      // Verify skills only have names, no description/effect text
      expect(skillSection, contains('强力击·γ型'));
      expect(skillSection, contains('雪境生存法则'));
      expect(skillSection, contains('真银斩'));

      // Count skill entries
      final skillNameCount = RegExp(r'技能：').allMatches(skillSection).length;
      print('\nSkill entries count: $skillNameCount');
      print('Expected: 3 (强力击·γ型, 雪境生存法则, 真银斩 — no dupes)');

      // 银灰 has exactly 3 skills (across {{技能}} and {{技能2}})
      expect(skillNameCount, equals(3),
          reason: 'Should have exactly 3 skills (强力击·γ型, 雪境生存法则, 真银斩), no duplicates');

      // Verify NO effect descriptions leak into the section
      expect(skillSection, isNot(contains('攻击力提高至')),
          reason: 'Skill effect descriptions should not be present');
      expect(skillSection, isNot(contains('{{')),
          reason: 'No wikitext template syntax should leak');

      print('\n✓ Fix 1 verified: Skills contain names only, no effects, no dupes\n');
    });

    test('Fix 2+3: Recruitment contract + Operator record story content (艾丽妮)', () async {
      const opTitle = '艾丽妮';
      final allTitles = [
        opTitle,
        '$opTitle/语音记录',
        '${opTitle}的信物',
        '${opTitle}/干员密录/1',
      ];

      print('═══════════════════════════════════════════');
      print('Fixes 2 & 3: Contract text + Record story content');
      print('═══════════════════════════════════════════');

      final wikitexts = await crawler.fetchRawWikitexts(
        WikiSite.prts,
        allTitles,
      );

      final recordStoryWikitexts = <String, String>{
        '${opTitle}/干员密录/1': wikitexts['${opTitle}/干员密录/1']?.content ?? '',
      };

      final assembled = WikiIndexingNotifier.assembleOperatorMarkdown(
        opTitle,
        wikitexts[opTitle]?.content ?? '',
        wikitexts['$opTitle/语音记录']?.content ?? '',
        wikitexts['${opTitle}的信物']?.content ?? '',
        recordStoryWikitexts: recordStoryWikitexts,
      );

      // Verify Fix 2: Recruitment Contract present
      print('\n--- Recruitment Contract ---');
      final contractSection = _extractBetween(assembled, '## 招聘合同', '\n## ');
      print(contractSection);

      expect(contractSection, isNotEmpty,
          reason: '招聘合同 section should exist and contain text');
      expect(contractSection, contains('艾丽妮'),
          reason: 'Contract should mention the operator name');
      expect(contractSection, contains('利剑挑破黑夜'),
          reason: 'Contract should include the poetic supplementary line');
      expect(contractSection, isNot(contains('{{')),
          reason: 'No wikitext syntax should leak into contract text');
      print('✓ Fix 2 verified: Recruitment contract with full poetic text\n');

      // Verify Fix 3: Operator Records include cleaned story dialogues
      print('\n--- Operator Record: 灯火微明 (first 500 chars) ---');
      final recordSection = _extractBetween(assembled, '## 干员密录', '\n## ');
      print(recordSection.length > 500
          ? '${recordSection.substring(0, 500)}...'
          : recordSection);
      print('\nTotal record content length: ${recordSection.length} chars');

      expect(recordSection, contains('灯火微明'),
          reason: 'Record name should be present');
      expect(recordSection, contains('大审判官达里奥'),
          reason: 'Cleaned story dialogue should contain character names');
      expect(recordSection, isNot(contains('剧情模拟器')),
          reason: 'Story content should be cleaned, no wikitext macros left');
      expect(recordSection, isNot(contains('[Background(')),
          reason: 'Story content should be cleaned, no scripting commands');
      expect(recordSection, isNot(contains('[name=')),
          reason: 'Character names should be extracted from [name="..."] tags');

      print('✓ Fix 3 verified: Operator records include cleaned story dialogues\n');
    });
  });
}

/// Extracts the text between [startMarker] and the next occurrence of [endMarker].
String _extractBetween(String text, String startMarker, String endMarker) {
  final startIdx = text.indexOf(startMarker);
  if (startIdx == -1) return '';
  final fromStart = text.substring(startIdx + startMarker.length);
  final endIdx = fromStart.indexOf(endMarker);
  if (endIdx == -1) return fromStart.trim();
  return fromStart.substring(0, endIdx).trim();
}
