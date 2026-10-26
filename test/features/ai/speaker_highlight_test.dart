import 'package:arklores/features/ai/speaker_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

String link(String name) =>
    '[$name]($speakerLinkScheme:${Uri.encodeComponent(name)})';

void main() {
  test('leftmost longest names do not overlap', () {
    final matcher = SpeakerMatcher(['凯尔希', '凯尔希医生', '阿米娅']);
    expect(matcher.linkNames('凯尔希医生和阿米娅'), '${link('凯尔希医生')}和${link('阿米娅')}');
  });
  test('first occurrence only and each call has its own set', () {
    final matcher = SpeakerMatcher(['阿米娅']);
    expect(matcher.linkNames('阿米娅和阿米娅'), '${link('阿米娅')}和阿米娅');
    expect(matcher.linkNames('阿米娅'), link('阿米娅'));
  });
  test('inline code including multiple backticks stays intact', () {
    expect(
      SpeakerMatcher(['阿米娅']).linkNames('`阿米娅` ``阿米娅`x`` 阿米娅'),
      '`阿米娅` ``阿米娅`x`` ${link('阿米娅')}',
    );
  });
  test('existing links including nested brackets and destinations stay intact',
      () {
    const prefix = '[阿米娅 [阿米娅]](https://example.test/(阿米娅))';
    expect(
      SpeakerMatcher(['阿米娅']).linkNames('$prefix 阿米娅'),
      '$prefix ${link('阿米娅')}',
    );
  });
  test('headings are skipped', () {
    expect(
      SpeakerMatcher(['阿米娅']).linkNames('## 阿米娅\n阿米娅'),
      '## 阿米娅\n${link('阿米娅')}',
    );
  });
  test('angle brackets are skipped', () {
    expect(
      SpeakerMatcher(['阿米娅']).linkNames('<阿米娅>阿米娅'),
      '<阿米娅>${link('阿米娅')}',
    );
  });
  test('single Unicode code point names are excluded', () {
    expect(SpeakerMatcher(['陈', '𠮷']).linkNames('陈𠮷'), '陈𠮷');
  });
  test('Markdown link labels escape brackets and backslashes', () {
    const name = r'名字]\[甲';
    final output = SpeakerMatcher([name]).linkNames(name);
    final document = md.Document();
    final node = document.parseInline(output).single as md.Element;
    expect(node.tag, 'a');
    expect(node.textContent, name);
    expect(Uri.decodeComponent(node.attributes['href']!.split(':').last), name);
  });
  test('a Latin name matches only as a whole word', () {
    final matcher = SpeakerMatcher(['Ace', 'W2']);
    expect(matcher.linkNames('Space W22'), 'Space W22');
    expect(matcher.linkNames('Ace与W2'), '${link('Ace')}与${link('W2')}');
  });
  test('empty inputs preserve original text', () {
    expect(SpeakerMatcher([]).linkNames('原文'), '原文');
    expect(SpeakerMatcher(['名字']).linkNames(''), '');
  });
  test('5000 names and 20000 characters stay below 50 ms', () {
    final matcher = SpeakerMatcher(List.generate(5000, (i) => '角色$i'));
    final text = '无关文字' * 5000;
    matcher.linkNames(text);
    final watch = Stopwatch()..start();
    expect(matcher.linkNames(text), text);
    watch.stop();
    expect(watch.elapsedMicroseconds, lessThan(50000));
  });
}
