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

      final page = pages.first;

      // Write raw content to file for local debugging
      File('raw_page.txt').writeAsStringSync(page.content);

      print('✓ Page successfully fetched: ${page.title}');
      print('📝 Raw content length: ${page.content.length} characters');

      // Print raw content preview before cleaning
      print('\n=== Raw content preview (First 1000 chars) ===');
      final rawPreviewLen = page.content.length > 1000 ? 1000 : page.content.length;
      print(page.content.substring(0, rawPreviewLen));
      print('==============================================');

      // Clean using the production regular expression parser
      final cleaned = WikiIndexingNotifier.cleanStoryContent(page.content);
      
      print('✨ Cleaned content length: ${cleaned.length} characters');
      final compressionPercent = (100 * (1 - cleaned.length / page.content.length)).toStringAsFixed(1);
      print('🧹 Compression / Noise Removal: $compressionPercent% of text stripped.');

      // Print preview of the cleaned script
      print('\n=== Cleaned Script Dialogue Preview (All chars) ===');
      print(cleaned);
      print('===========================================================');

      // Test Chunker on the cleaned script
      const chunker = Chunker();
      final chunks = chunker.chunkByHeadings(cleaned, pageTitle: page.title);

      print('\n=== Chunking Results (Total: ${chunks.length} chunks) ===');
      for (var i = 0; i < chunks.length; i++) {
        print('Chunk $i length: ${chunks[i].content.length} chars');
        print('Chunk $i preview:');
        print(chunks[i].content);
        print('-----------------------------------------------------------');
      }
      print('===========================================================');

      crawler.dispose();
    });

    test('Integration: Crawl actual operator story "阿米娅/干员密录/1" and clean it', () async {
      final crawler = MediaWikiCrawler();

      print('📡 Fetching actual operator story page "阿米娅/干员密录/1" from PRTS Wiki...');
      
      final pages = await crawler.fetchPageContents(
        WikiSite.prts,
        ['阿米娅/干员密录/1'],
      );

      final page = pages.first;

      // Write raw content to file for local debugging
      File('operator_story_raw.txt').writeAsStringSync(page.content);

      print('✓ Page successfully fetched: ${page.title}');
      print('📝 Raw content length: ${page.content.length} characters');

      // Print raw content preview before cleaning
      print('\n=== Raw Operator Story preview (First 1000 chars) ===');
      final rawPreviewLen = page.content.length > 1000 ? 1000 : page.content.length;
      print(page.content.substring(0, rawPreviewLen));
      print('==============================================');

      // Clean using the production regular expression parser
      final cleaned = WikiIndexingNotifier.cleanStoryContent(page.content);
      
      print('✨ Cleaned content length: ${cleaned.length} characters');
      final compressionPercent = (100 * (1 - cleaned.length / page.content.length)).toStringAsFixed(1);
      print('🧹 Compression / Noise Removal: $compressionPercent% of text stripped.');

      // Print preview of the cleaned script
      print('\n=== Cleaned Operator Script Dialogue Preview (All chars) ===');
      print(cleaned);
      print('===========================================================');

      // Test Chunker on the cleaned script
      const chunker = Chunker();
      final chunks = chunker.chunkByHeadings(cleaned, pageTitle: page.title);

      print('\n=== Chunking Results (Total: ${chunks.length} chunks) ===');
      for (var i = 0; i < chunks.length; i++) {
        print('Chunk $i length: ${chunks[i].content.length} chars');
        print('Chunk $i preview:');
        print(chunks[i].content);
        print('-----------------------------------------------------------');
      }
      print('===========================================================');

      crawler.dispose();
    });
  });
}
