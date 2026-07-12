import 'dart:io';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() async {
  final crawler = MediaWikiCrawler();
  final opTitle = '艾丽妮';
  final allTitles = [opTitle, '$opTitle/语音记录', '${opTitle}的信物'];

  print('📡 Fetching Irene pages...');
  final wikitexts = await crawler.fetchRawWikitexts(WikiSite.prts, allTitles);

  final mainPage = wikitexts[opTitle]!;
  final voicePage = wikitexts['$opTitle/语音记录']!;
  final tokenPage = wikitexts['${opTitle}的信物']!;

  print('✓ Assembling operator markdown...');
  final assembled = WikiIndexingNotifier.assembleOperatorMarkdown(
    opTitle,
    mainPage.content,
    voicePage.content,
    tokenPage.content,
  );

  File('assembled_irene.md').writeAsStringSync(assembled);
  print('Wrote output to assembled_irene.md');

  crawler.dispose();
}
