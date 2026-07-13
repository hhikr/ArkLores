import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/wiki/warfarin_crawler.dart';

void main() {
  group('WarfarinWikiCrawler Tests', () {
    test('Unit Test: decodeRemixStream correctly decodes index references', () {
      final mockRemixArray = [
        {"version": 3},
        "route_a",
        {"_3": 4},
        "title",
        "佩丽卡"
      ];
      final decoded = decodeRemixStream(mockRemixArray);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded.containsKey('route_a'), isTrue);
      expect(decoded['route_a'], isA<Map<String, dynamic>>());
      expect((decoded['route_a'] as Map)['title'], '佩丽卡');
    });

    test('Integration Test: Fetch listing and detail data from Warfarin Wiki', () async {
      final crawler = WarfarinWikiCrawler();

      print('📡 Fetching operator slugs from Warfarin Wiki...');
      final opSlugs = await crawler.fetchOperatorSlugs();
      print('✓ Found ${opSlugs.length} operators. First few: ${opSlugs.take(3).toList()}');
      expect(opSlugs, isNotEmpty);

      print('📡 Fetching lore slugs...');
      final loreSlugs = await crawler.fetchLoreSlugs();
      print('✓ Found ${loreSlugs.length} lore entries. First few: ${loreSlugs.take(3).toList()}');
      expect(loreSlugs, isNotEmpty);

      print('📡 Fetching mission slugs...');
      final missionSlugs = await crawler.fetchMissionSlugs();
      print('✓ Found ${missionSlugs.length} missions. First few: ${missionSlugs.take(3).toList()}');
      expect(missionSlugs, isNotEmpty);

      // Fetch Perlica Operator Detail
      final testOp = 'perlica';
      print('📡 Fetching detail for operator: $testOp...');
      final opData = await crawler.fetchOperatorDetail(testOp);
      expect(opData, isNotEmpty);
      final opMarkdown = crawler.formatOperatorToMarkdown(opData);
      print('=== OPERATOR MARKDOWN PREVIEW ===');
      print(opMarkdown.split('\n').take(15).join('\n'));
      print('=================================');

      // Fetch first Lore Detail
      final testLore = loreSlugs.first;
      print('📡 Fetching detail for lore: $testLore...');
      final loreData = await crawler.fetchLoreDetail(testLore);
      expect(loreData, isNotEmpty);
      final loreMarkdown = crawler.formatLoreToMarkdown(loreData);
      print('=== LORE MARKDOWN PREVIEW ===');
      print(loreMarkdown.split('\n').take(15).join('\n'));
      print('=============================');

      // Fetch first Mission Detail
      final testMission = missionSlugs.first;
      print('📡 Fetching detail for mission: $testMission...');
      final missionData = await crawler.fetchMissionDetail(testMission);
      expect(missionData, isNotEmpty);
      final missionMarkdown = crawler.formatMissionToMarkdown(missionData);
      print('=== MISSION MARKDOWN PREVIEW ===');
      print(missionMarkdown.split('\n').take(15).join('\n'));
      print('================================');

      crawler.dispose();
    });
  });
}
