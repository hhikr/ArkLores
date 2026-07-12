import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Story Cleaner & Chunker Integration Tests', () {
    test('Integration: Crawl actual PRTS story "0-10 困境/BEG" and clean it', () async {
      final crawler = MediaWikiCrawler();

      print('📡 Fetching actual story page "0-10 困境/BEG" from PRTS Wiki...');
      
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

      // Print raw content preview before cleaning to see what we received from API
      print('\n=== Raw content preview (First 1500 chars) ===');
      final rawPreviewLen = page.content.length > 1500 ? 1500 : page.content.length;
      print(page.content.substring(0, rawPreviewLen));
      print('==============================================');

      // 3. Clean using the production regular expression parser
      final cleaned = WikiIndexingNotifier.cleanStoryContent(page.content);
      
      print('✨ Cleaned content length: ${cleaned.length} characters');
      final compressionPercent = (100 * (1 - cleaned.length / page.content.length)).toStringAsFixed(1);
      print('🧹 Compression / Noise Removal: $compressionPercent% of text stripped.');

      // Print preview of the cleaned script BEFORE assertions so they always output to stdout
      print('\n=== Cleaned Script Dialogue Preview (First 1500 chars) ===');
      final previewLen = cleaned.length > 1500 ? 1500 : cleaned.length;
      print(cleaned.substring(0, previewLen));
      print('===========================================================');

      // 6. Test Chunker on the cleaned script
      const chunker = Chunker();
      final chunks = chunker.chunkByHeadings(cleaned, pageTitle: page.title);

      print('\n=== Chunking Results (Total: ${chunks.length} chunks) ===');
      for (var i = 0; i < chunks.length; i++) {
        print('Chunk $i length: ${chunks[i].content.length} chars');
        print('Chunk $i preview:');
        final chunkPreviewLen = chunks[i].content.length > 300 ? 300 : chunks[i].content.length;
        print(chunks[i].content.substring(0, chunkPreviewLen));
        print('-----------------------------------------------------------');
      }
      print('===========================================================');

      // ── Expect Assertions (Run at the very end so prints are never skipped) ──
      
      // Verify wikitext macros were successfully stripped
      expect(cleaned.contains('Character('), isFalse);
      expect(cleaned.contains('Background('), isFalse);
      expect(cleaned.contains('PlayMusic('), isFalse);
      expect(cleaned.contains('Delay('), isFalse);
      
      // Verify that actual dialogues and narrations were preserved
      expect(cleaned.contains('阿米娅'), isTrue);
      expect(cleaned.contains('陈'), isTrue);
      expect(cleaned.contains('梅菲斯特'), isTrue);
      expect(cleaned.contains('临光'), isTrue);

      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.length < 10, isTrue, reason: 'Chunk count is too high: ${chunks.length}');

      crawler.dispose();
    });
  });
}
