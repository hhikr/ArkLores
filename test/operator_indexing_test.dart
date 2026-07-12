import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Operator Indexing & Chunker Integration Tests', () {
    final crawler = MediaWikiCrawler();

    test('Integration: Crawl Amiya operator pages and analyze contents', () async {
      final targets = [
        '阿米娅',
        '阿米娅/干员档案',
        '阿米娅/语音记录',
      ];

      print('📡 Fetching Amiya pages from PRTS Wiki: $targets...');
      
      final pages = await crawler.fetchPageContents(
        WikiSite.prts,
        targets,
      );

      print('✓ Fetched ${pages.length} pages.\n');

      const chunker = Chunker();

      for (final page in pages) {
        print('===========================================================');
        print('📄 PAGE TITLE: ${page.title}');
        print('📝 Raw content length: ${page.content.length} characters');
        
        // Write each raw page to a local file for inspection
        final safeTitle = page.title.replaceAll('/', '_');
        File('raw_op_$safeTitle.txt').writeAsStringSync(page.content);

        // Preview the explaintext raw content
        print('\n--- Raw Content Preview (First 800 chars) ---');
        final rawPreviewLen = page.content.length > 800 ? 800 : page.content.length;
        print(page.content.substring(0, rawPreviewLen));
        print('---------------------------------------------');

        // Chunking analysis
        final chunks = chunker.chunkByHeadings(page.content, pageTitle: page.title);
        print('🧱 Chunking Results (Total: ${chunks.length} chunks)');
        for (var i = 0; i < chunks.length; i++) {
          print('  -> Chunk $i title: ${chunks[i].heading} (${chunks[i].content.length} chars)');
          // Print snippet of the chunk
          final snippetLen = chunks[i].content.length > 150 ? 150 : chunks[i].content.length;
          print('     [Snippet] ${chunks[i].content.substring(0, snippetLen).replaceAll('\n', ' ')}...');
        }
        print('===========================================================\n');
      }

      crawler.dispose();
    });
  });
}
