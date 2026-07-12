import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Character Story Fetch and Clean Simulation', () {
    test('Simulate fetching and cleaning for Amiya ("阿米娅")', () async {
      final crawler = MediaWikiCrawler();

      final testTitles = ['阿米娅', '阿米娅/语音记录'];
      print('📡 Fetching pages $testTitles from PRTS Wiki...');

      final pages = await crawler.fetchPageContents(
        WikiSite.prts,
        testTitles,
      );

      print('✓ Fetched ${pages.length} pages.');

      for (final page in pages) {
        print('\n===========================================================');
        print('PAGE TITLE: ${page.title}');
        print('Raw content length: ${page.content.length} characters');
        
        if (page.content.isEmpty) {
          print('Content is empty.');
          continue;
        }

        print('--- Raw Content Preview (first 500 chars) ---');
        final rawLen = page.content.length > 500 ? 500 : page.content.length;
        print(page.content.substring(0, rawLen));
        print('---------------------------------------------');

        // Simulate the indexing pipeline decision logic:
        final isStoryPage = page.content.contains('剧情模拟器');
        print('Is detected as story page (contains "剧情模拟器"): $isStoryPage');

        var finalContent = page.content;
        if (isStoryPage) {
          finalContent = WikiIndexingNotifier.cleanStoryContent(page.content);
        }

        print('\n--- Processed Content (Ready for Chunker & LLM) ---');
        print('Final content length: ${finalContent.length} characters');
        
        // Print the first 1500 chars of processed content to inspect
        final finalLen = finalContent.length > 1500 ? 1500 : finalContent.length;
        print(finalContent.substring(0, finalLen));
        if (finalContent.length > 1500) {
          print('\n... [Content Truncated to 1500 chars for output preview] ...');
        }
        print('===========================================================');
      }

      crawler.dispose();
    });
  });
}
