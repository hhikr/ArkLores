import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Operator Indexing & Assembly Integration Tests', () {
    test('Integration: Fetch and assemble Irene ("艾丽妮") operator data from PRTS Wiki', () async {
      final crawler = MediaWikiCrawler();

      final opTitle = '艾丽妮';
      final allTitles = [opTitle, '$opTitle/语音记录', '${opTitle}的信物'];

      print('📡 Fetching Irene raw pages from PRTS Wiki: $allTitles...');
      final wikitexts = await crawler.fetchRawWikitexts(WikiSite.prts, allTitles);

      final mainPage = wikitexts[opTitle];
      final voicePage = wikitexts['$opTitle/语音记录'];
      final tokenPage = wikitexts['${opTitle}的信物'];

      if (mainPage == null) {
        print('⚠️ Main page for $opTitle is not found on PRTS Wiki!');
        crawler.dispose();
        return;
      }

      print('✓ Fetched wikitexts. Assembling operator markdown...');

      final assembled = WikiIndexingNotifier.assembleOperatorMarkdown(
        opTitle,
        mainPage.content,
        voicePage?.content ?? '',
        tokenPage?.content ?? '',
      );

      print('\n=== Assembled Operator Markdown (ALL characters) ===');
      print(assembled);
      print('====================================================\n');

      print('🧱 Chunking assembled operator markdown...');
      const chunker = Chunker();
      final chunks = chunker.chunkByHeadings(assembled, pageTitle: opTitle);

      print('Found ${chunks.length} chunks.');

      print('\n=== Chunking Results (Total: ${chunks.length} chunks) ===');
      for (var i = 0; i < chunks.length; i++) {
        print('Chunk $i Section: "${chunks[i].section}" (length: ${chunks[i].content.length} chars)');
        print('Chunk $i content:');
        print(chunks[i].content);
        print('-----------------------------------------------------------');
      }
      print('===========================================================');

      crawler.dispose();
    });
  });
}
