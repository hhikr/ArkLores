import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

/// A no-assertion integration test that simulates the app's full operator
/// assembly pipeline — raw wikitext fetching → parsing → assembling → output.
///
/// All [expect] calls are commented out; this test always passes.
/// Its sole purpose is to print the complete assembled output for inspection.
void main() {
  group('Full Operator Assembly Simulation (no assertions)', () {
    final crawler = MediaWikiCrawler();
    tearDownAll(() => crawler.dispose());

    test('Fetch, assemble and print COMPLETE operator content — 艾丽妮', () async {
      const opTitle = '艾丽妮';

      // ── Step 1: Collect all page titles ──
      final allTitles = [
        opTitle,
        '$opTitle/语音记录',
        '${opTitle}的信物',
        '${opTitle}/干员密录/1',
      ];
      print('╔══════════════════════════════════════════════════════════╗');
      print('║  Step 1: Fetching raw wikitext from PRTS Wiki           ║');
      print('╚══════════════════════════════════════════════════════════╝');
      print('Titles to fetch: $allTitles');

      // ── Step 2: Fetch raw wikitexts ──
      final wikitexts = await crawler.fetchRawWikitexts(
        WikiSite.prts,
        allTitles,
      );

      for (final title in allTitles) {
        final page = wikitexts[title];
        if (page != null) {
          print('  ✓ $title (${page.content.length} chars)');
        } else {
          print('  ✗ $title — NOT FOUND');
        }
      }

      // ── Step 3: Discover record story pages (simulating pipeline Phase 1.5) ──
      final mainWikitext = wikitexts[opTitle]?.content ?? '';
      final recordStoryWikitexts = <String, String>{};

      if (mainWikitext.isNotEmpty) {
        final miluTemplates = WikiIndexingNotifier.parseAllTemplates(
          mainWikitext,
          '干员密录/list',
        );
        for (final m in miluTemplates) {
          for (int j = 1; j <= 20; j++) {
            final rawPage = m['storyTxt$j'] ?? '';
            if (rawPage.isEmpty) break;
            final resolved = rawPage
                .replaceAll('{{FULLPAGENAME}}', opTitle)
                .trim();
            if (resolved.isNotEmpty) {
              final storyPage = wikitexts[resolved];
              if (storyPage != null && storyPage.content.isNotEmpty) {
                recordStoryWikitexts[resolved] = storyPage.content;
              }
            }
          }
        }
      }

      print('\nDiscovered ${recordStoryWikitexts.length} record story page(s)');
      for (final key in recordStoryWikitexts.keys) {
        print('  ✓ $key (${recordStoryWikitexts[key]!.length} raw chars)');
      }

      // ── Step 4: Assemble operator markdown ──
      print('\n╔══════════════════════════════════════════════════════════╗');
      print('║  Step 2: Assembling operator markdown                    ║');
      print('╚══════════════════════════════════════════════════════════╝');

      final assembled = WikiIndexingNotifier.assembleOperatorMarkdown(
        opTitle,
        mainWikitext,
        wikitexts['$opTitle/语音记录']?.content ?? '',
        wikitexts['${opTitle}的信物']?.content ?? '',
        recordStoryWikitexts: recordStoryWikitexts,
      );

      print('Assembled content length: ${assembled.length} characters\n');

      // ── Step 5: Print FULL assembled content (no truncation) ──
      print('╔══════════════════════════════════════════════════════════╗');
      print('║  COMPLETE ASSEMBLED OUTPUT                               ║');
      print('╚══════════════════════════════════════════════════════════╝');
      print(assembled);
      print('\n╔══════════════════════════════════════════════════════════╗');
      print('║  END OF OUTPUT                                           ║');
      print('╚══════════════════════════════════════════════════════════╝');

      // ── Step 6: Verify section presence (commented out — no assertions) ──
      // expect(assembled.contains('## 个人档案'), true);
      // expect(assembled.contains('## 招聘合同'), true);
      // expect(assembled.contains('## 天赋设定'), true);
      // expect(assembled.contains('## 技能设定'), true);
      // expect(assembled.contains('## 后勤技能'), true);
      // expect(assembled.contains('## 模组设定'), true);
      // expect(assembled.contains('## 悖论模拟'), true);
      // expect(assembled.contains('## 干员密录'), true);
      // expect(assembled.contains('## 信物描述'), true);
      // expect(assembled.contains('## 语音记录'), true);

      // Also write to file for offline inspection
      File('record_story_output.txt').writeAsStringSync(assembled);
      print('\n(Also written to record_story_output.txt for offline inspection)');

      // Always pass — no assertions
      expect(true, isTrue);
    });
  });
}
