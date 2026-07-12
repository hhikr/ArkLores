import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/wiki/wiki_crawler.dart';
import 'package:arklores/core/wiki/wiki_models.dart';

void main() {
  group('Operator Indexing & Assembly Integration Tests', () {
    test('Unit Test: parseTemplate with simple and nested structures', () {
      const wikitext = '''
{{人员档案set
|性别=女
|种族=卡特斯/奇美拉
|体细胞与源石融合率=19%
}}
{{人员档案
|档案1=基础档案
|档案1文本=【代号】阿米娅
【性别】女
}}
''';

      final setParams = WikiIndexingNotifier.parseTemplate(wikitext, '人员档案set');
      expect(setParams['性别'], equals('女'));
      expect(setParams['种族'], equals('卡特斯/奇美拉'));
      expect(setParams['体细胞与源石融合率'], equals('19%'));

      final archiveParams = WikiIndexingNotifier.parseTemplate(wikitext, '人员档案');
      expect(archiveParams['档案1'], equals('基础档案'));
      expect(archiveParams['档案1文本'], contains('【代号】阿米娅'));
    });

    test('Integration: Fetch and assemble Amiya operator data from PRTS Wiki', () async {
      final crawler = MediaWikiCrawler();

      final opTitle = '阿米娅';
      final allTitles = [opTitle, '$opTitle/语音记录', '${opTitle}的信物'];

      print('📡 Fetching Amiya raw pages from PRTS Wiki: $allTitles...');
      final wikitexts = await crawler.fetchRawWikitexts(WikiSite.prts, allTitles);

      expect(wikitexts.containsKey(opTitle), isTrue);
      expect(wikitexts.containsKey('$opTitle/语音记录'), isTrue);
      expect(wikitexts.containsKey('${opTitle}的信物'), isTrue);

      final mainPage = wikitexts[opTitle]!;
      final voicePage = wikitexts['$opTitle/语音记录']!;
      final tokenPage = wikitexts['${opTitle}的信物']!;

      print('✓ Fetched wikitexts. Assembling operator markdown...');

      final assembled = WikiIndexingNotifier.assembleOperatorMarkdown(
        opTitle,
        mainPage.content,
        voicePage.content,
        tokenPage.content,
      );

      print('\n=== Assembled Operator Markdown (Snippet) ===');
      final snippetLen = assembled.length > 1200 ? 1200 : assembled.length;
      print(assembled.substring(0, snippetLen));
      if (assembled.length > 1200) {
        print('...\n[Assembled content truncated for display]');
      }
      print('=============================================\n');

      // 1. Verify Archives
      expect(assembled, contains('# 阿米娅'));
      expect(assembled, contains('## 个人档案'));
      expect(assembled, contains('性别：女'));
      expect(assembled, contains('体细胞与源石融合率：19%'));
      expect(assembled, contains('血液源石结晶密度：0.27u/L'));
      expect(assembled, contains('### 基础档案'));
      expect(assembled, contains('### 临床诊断分析'));

      // 2. Verify Token
      expect(assembled, contains('## 信物描述'));
      expect(assembled, contains('信物文案：“总有一天你会理解我的选择......原谅我。”'));
      expect(assembled, contains('- 用途：用于提升阿米娅的潜能。'));

      // 3. Verify Voice
      expect(assembled, contains('## 语音记录'));
      expect(assembled, contains('- 任命助理：博士，您工作辛苦了。'));
      expect(assembled, contains('- 交谈1：凯尔希医生教导过我，工作的时候一定要保持全神贯注......嗯，全神贯注。'));

      // 4. Test Chunker on the assembled Markdown
      print('🧱 Chunking assembled operator markdown...');
      const chunker = Chunker();
      final chunks = chunker.chunkByHeadings(assembled, pageTitle: opTitle);

      print('Found ${chunks.length} chunks.');
      expect(chunks.isNotEmpty, isTrue);

      for (var i = 0; i < chunks.length; i++) {
        print('Chunk $i: Section="${chunks[i].section}" Length=${chunks[i].content.length} chars');
        expect(chunks[i].content.isNotEmpty, isTrue);
      }

      crawler.dispose();
    });
  });
}
