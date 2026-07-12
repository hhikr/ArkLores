import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Story Cleaner & Chunker Integration Tests', () {
    test('Integration: Crawl actual PRTS story "0-10 困境/BEG" and clean it', () async {
      // 1. Instantiate the mediawiki crawler (pure Dart http client backend)
      final crawler = MediaWikiCrawler();

      print('📡 Fetching actual story page "0-10 困境/BEG" from PRTS Wiki...');
      
      // 2. Fetch page contents from the real live wiki API
      final pages = await crawler.fetchPageContents(
        WikiSite.prts,
        ['0-10 困境/BEG'],
      );

      expect(pages.isNotEmpty, isTrue, reason: 'Failed to fetch the page from PRTS API');
      final page = pages.first;

      // Write raw content to file for local debugging
      File('raw_page.txt').writeAsStringSync(page.content);

      print('✓ Page successfully fetched: ${page.title}');
      print('📝 Raw content length: ${page.content.length} characters');

      // 3. Clean using the production regular expression parser
      final cleaned = WikiIndexingNotifier.cleanStoryContent(page.content);
      
      print('✨ Cleaned content length: ${cleaned.length} characters');
      final compressionPercent = (100 * (1 - cleaned.length / page.content.length)).toStringAsFixed(1);
      print('🧹 Compression / Noise Removal: $compressionPercent% of text stripped.');

      // 4. Assertions to verify wikitext macros were successfully stripped from real data
      expect(cleaned.contains('Character('), isFalse);
      expect(cleaned.contains('Background('), isFalse);
      expect(cleaned.contains('PlayMusic('), isFalse);
      expect(cleaned.contains('Delay('), isFalse);
      
      // 5. Assertions to verify that actual dialogues and narrations were preserved
      expect(cleaned.contains('阿米娅'), isTrue);
      expect(cleaned.contains('陈'), isTrue);
      expect(cleaned.contains('梅菲斯特'), isTrue);
      expect(cleaned.contains('临光'), isTrue);

      // Print preview of the cleaned script
      print('\n=== Cleaned Script Dialogue Preview (First 500 chars) ===');
      final previewLen = cleaned.length > 500 ? 500 : cleaned.length;
      print(cleaned.substring(0, previewLen));
      print('===========================================================');

      // 6. Test Chunker on the cleaned script
      const chunker = Chunker();
      final chunks = chunker.chunkByHeadings(cleaned, pageTitle: page.title);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.length < 10, isTrue, reason: 'Chunk count is too high: ${chunks.length}');

      print('\n=== Chunking Results (Total: ${chunks.length} chunks) ===');
      for (var i = 0; i < chunks.length; i++) {
        print('Chunk $i length: ${chunks[i].content.length} chars');
      }
      print('===========================================================');

      crawler.dispose();
    });
  });
}
