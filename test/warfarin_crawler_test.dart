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

    test(
      'Integration Test: Fetch operators listing only',
      () async {
        final crawler = WarfarinWikiCrawler();

        print('📡 Fetching operator slugs from Warfarin Wiki...');
        final opSlugs = await crawler.fetchOperatorSlugs();
        print('✓ Found ${opSlugs.length} operators. First few: ${opSlugs.take(5).toList()}');
        expect(opSlugs.length, greaterThanOrEqualTo(1));

        print('📡 Fetching operator listings (with names)...');
        final opItems = await crawler.fetchOperatorListings();
        print('✓ Listing items: ${opItems.length}');
        for (final item in opItems.take(5)) {
          print('  ${item.slug} / ${item.name}');
        }
        expect(opItems.length, greaterThanOrEqualTo(1));
        expect(opItems.first.slug, isNotEmpty);
        expect(opItems.first.name, isNotEmpty);

        crawler.dispose();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'Integration Test: Fetch lore listing',
      () async {
        final crawler = WarfarinWikiCrawler();

        print('📡 Fetching lore slugs...');
        final loreSlugs = await crawler.fetchLoreSlugs();
        print('✓ Found ${loreSlugs.length} lore entries. First few: ${loreSlugs.take(3).toList()}');
        expect(loreSlugs.length, greaterThanOrEqualTo(1));

        final loreItems = await crawler.fetchLoreListings();
        expect(loreItems.length, greaterThanOrEqualTo(1));
        expect(loreItems.first.slug, isNotEmpty);
        expect(loreItems.first.name, isNotEmpty);

        crawler.dispose();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'Integration Test: Fetch mission listing',
      () async {
        final crawler = WarfarinWikiCrawler();

        print('📡 Fetching mission slugs...');
        final missionSlugs = await crawler.fetchMissionSlugs();
        print('✓ Found ${missionSlugs.length} missions. First few: ${missionSlugs.take(3).toList()}');
        expect(missionSlugs.length, greaterThanOrEqualTo(1));

        final missionItems = await crawler.fetchMissionListings();
        expect(missionItems.length, greaterThanOrEqualTo(1));
        expect(missionItems.first.slug, isNotEmpty);
        expect(missionItems.first.name, isNotEmpty);

        crawler.dispose();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'Integration Test: Fetch operator detail and format',
      () async {
        final crawler = WarfarinWikiCrawler();
        final ops = await crawler.fetchOperatorListings();

        if (ops.isNotEmpty) {
          final slug = ops.first.slug;
          print('📡 Fetching detail for operator: $slug (${ops.first.name})...');
          final opData = await crawler.fetchOperatorDetail(slug);
          expect(opData, isNotEmpty);
          print('Detail data keys: ${opData.keys.take(8).toList()}');
          var markdown = crawler.formatOperatorToMarkdown(opData);
          if (markdown.isEmpty || markdown == '# \n') {
            markdown = '# ${ops.first.name}\n${markdown}';
          }
          print('=== MARKDOWN PREVIEW ===');
          print(markdown.split('\n').take(10).join('\n'));
          print('=======================');
        }

        crawler.dispose();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'Integration Test: Fetch lore detail and format',
      () async {
        final crawler = WarfarinWikiCrawler();
        final loreItems = await crawler.fetchLoreListings();

        if (loreItems.isNotEmpty) {
          final slug = loreItems.first.slug;
          print('📡 Fetching lore detail: $slug...');
          final data = await crawler.fetchLoreDetail(slug);
          expect(data, isNotEmpty);
          final markdown = crawler.formatLoreToMarkdown(data);
          print('=== MARKDOWN PREVIEW ===');
          print(markdown.split('\n').take(10).join('\n'));
        }

        crawler.dispose();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    test(
      'Integration Test: Fetch mission detail and format',
      () async {
        final crawler = WarfarinWikiCrawler();
        final missionItems = await crawler.fetchMissionListings();

        if (missionItems.isNotEmpty) {
          final slug = missionItems.first.slug;
          print('📡 Fetching mission detail: $slug...');
          final data = await crawler.fetchMissionDetail(slug);
          expect(data, isNotEmpty);
          final markdown = crawler.formatMissionToMarkdown(data);
          print('=== MARKDOWN PREVIEW ===');
          print(markdown.split('\n').take(10).join('\n'));
        }

        crawler.dispose();
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  group('Formatter Full Output — 分块向量化前的文本（无断言）', () {
    test('Format: 干员 汤汤', () async {
      final crawler = WarfarinWikiCrawler();
      final ops = await crawler.fetchOperatorListings();
      final tangtang = ops.firstWhere((o) => o.slug == 'tangtang',
          orElse: () => ops[0]);
      print('═══════════════════════════════════════════');
      print('📄 干员：${tangtang.name} (${tangtang.slug})');
      print('═══════════════════════════════════════════');
      final data = await crawler.fetchOperatorDetail(tangtang.slug);
      final md = crawler.formatOperatorToMarkdown(data);
      print('字符数：${md.length}');
      print('════');
      print(md);
      print('═══════════════════════════════════════════');
      crawler.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('Format: 干员 佩丽卡', () async {
      final crawler = WarfarinWikiCrawler();
      final ops = await crawler.fetchOperatorListings();
      final target = ops.firstWhere((o) => o.slug == 'perlica',
          orElse: () => ops[0]);
      print('═══════════════════════════════════════════');
      print('📄 干员：${target.name} (${target.slug})');
      print('═══════════════════════════════════════════');
      final data = await crawler.fetchOperatorDetail(target.slug);
      final md = crawler.formatOperatorToMarkdown(data);
      print('字符数：${md.length}');
      print('════');
      print(md);
      print('═══════════════════════════════════════════');
      crawler.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('Format: 干员 汤汤', () async {
      final crawler = WarfarinWikiCrawler();
      final loreItems = await crawler.fetchLoreListings();
      final target = loreItems.firstWhere(
          (o) => o.slug.contains('text_sm1l5m1'),
          orElse: () => loreItems[0]);
      print('═══════════════════════════════════════════');
      print('📄 资料：${target.name} (${target.slug})');
      print('═══════════════════════════════════════════');
      final data = await crawler.fetchLoreDetail(target.slug);
      final md = crawler.formatLoreToMarkdown(data);
      print('字符数：${md.length}');
      print('════');
      print(md);
      print('═══════════════════════════════════════════');
      crawler.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('Format: 资料 弩箭残片的记录', () async {
      final crawler = WarfarinWikiCrawler();
      final data = await crawler
          .fetchLoreDetail('text_map01_lv001_sm1l1m4_1');
      print('═══════════════════════════════════════════');
      print('📄 资料：弩箭残片的记录');
      print('═══════════════════════════════════════════');
      final md = crawler.formatLoreToMarkdown(data);
      print('字符数：${md.length}');
      print('════');
      print(md);
      print('═══════════════════════════════════════════');
      crawler.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('Format: 任务 c27m1 完整对话', () async {
      final crawler = WarfarinWikiCrawler();
      print('═══════════════════════════════════════════');
      print('📄 任务：c27m1（风平水不静）');
      print('═══════════════════════════════════════════');
      final data = await crawler.fetchMissionDetail('c27m1');
      final md = crawler.formatMissionToMarkdown(data);
      print('字符数：${md.length} ｜ 对话条目数：${(data['dialog'] as List?)?.length ?? 0}');
      print('════');
      print(md);
      print('═══════════════════════════════════════════');
      crawler.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('Format: 任务 最后一个 mission', () async {
      final crawler = WarfarinWikiCrawler();
      final missions = await crawler.fetchMissionListings();
      final last = missions.last;
      print('═══════════════════════════════════════════');
      print('📄 任务：${last.slug}（${last.name}）');
      print('═══════════════════════════════════════════');
      final data = await crawler.fetchMissionDetail(last.slug);
      final md = crawler.formatMissionToMarkdown(data);
      print('字符数：${md.length}');
      print('════');
      print(md);
      print('═══════════════════════════════════════════');
      crawler.dispose();
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
