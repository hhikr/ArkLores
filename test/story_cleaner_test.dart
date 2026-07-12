import 'package:flutter_test/flutter_test.dart';
import 'package:arklores/core/rag/wiki_indexing_provider.dart';
import 'package:arklores/core/rag/chunker.dart';

void main() {
  group('Story Cleaner & Chunker Tests', () {
    const rawStoryText = '''
<!-- 剧透警告 -->
{{Navigator/plot|上一集=0-9 压线/END|下一集=0-10 困境/END|故事主页=黑暗时代}}
{{剧情模拟器
|背景=bg_rhodes_office
|音频=music_active
|文本=
[Background(image="bg_rhodes_office", fade=1.5)]
[PlayMusic(sound="music_active", delay=0.5)]
[Character(name="char_002_amiya", focus=true, state="smile")]
阿米娅：博士，我们该出发了。
[Delay(time=1.0)]
[Character(name="char_002_amiya", focus=false)]
[Character(name="char_010_chen", focus=true)]
陈：等等，阿米娅。
[PlaySound(sound="music_combat")]
[Character(name="char_010_chen", focus=false)]
（远处传来炮火声）
}}
''';

    test('cleanStoryContent should strip HTML comments, Wiki templates and game macros', () {
      final cleaned = WikiIndexingNotifier.cleanStoryContent(rawStoryText);

      // Verify that HTML comments are gone
      expect(cleaned.contains('<!-- 剧透警告 -->'), isFalse);

      // Verify that Navigator and 剧情模拟器 templates are gone
      expect(cleaned.contains('{{Navigator/plot'), isFalse);
      expect(cleaned.contains('{{剧情模拟器'), isFalse);
      expect(cleaned.contains('|背景='), isFalse);

      // Verify that game scripting macros are gone
      expect(cleaned.contains('[Background'), isFalse);
      expect(cleaned.contains('[PlayMusic'), isFalse);
      expect(cleaned.contains('[Character'), isFalse);
      expect(cleaned.contains('[PlaySound'), isFalse);
      expect(cleaned.contains('[Delay'), isFalse);

      // Verify that actual dialogue and narration remain intact
      expect(cleaned.contains('阿米娅：博士，我们该出发了。'), isTrue);
      expect(cleaned.contains('陈：等等，阿米娅。'), isTrue);
      expect(cleaned.contains('（远处传来炮火声）'), isTrue);

      // Print clean content for manual review
      print('=== Cleaned Story Content Preview ===');
      print(cleaned);
      print('=====================================');
    });

    test('Chunker should properly chunk cleaned story content', () {
      final cleaned = WikiIndexingNotifier.cleanStoryContent(rawStoryText);
      const chunker = Chunker();

      // Chunk the clean dialogue text
      final chunks = chunker.chunkByHeadings(cleaned, pageTitle: '0-10 困境/BEG');

      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.pageTitle, equals('0-10 困境/BEG'));

      // The text shouldn't be empty and should match parts of our script
      expect(chunks.first.content.contains('阿米娅：博士，我们该出发了。'), isTrue);
      expect(chunks.first.content.contains('陈：等等，阿米娅。'), isTrue);

      print('=== Chunked Result Preview ===');
      for (var i = 0; i < chunks.length; i++) {
        print('Chunk \$i:');
        print(chunks[i].content);
      }
      print('==============================');
    });
  });
}
