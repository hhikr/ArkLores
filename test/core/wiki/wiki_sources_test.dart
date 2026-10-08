import 'dart:async';
import 'dart:convert';

import 'package:arklores/core/wiki/wiki_html_text.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:arklores/core/wiki/wiki_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 0.13: the wikis' HTML as paragraphs, and the two sources against
/// responses in the shape the sites send (fictional content).
void main() {
  group('wikiBlocksFromHtml', () {
    test('sections, paragraphs, list items and table rows', () {
      final blocks = wikiBlocksFromHtml('''
<div class="mw-parser-output">
  <p>星灯是<b>点灯人</b>。</p>
  <h2><span class="mw-headline">人物关系</span><span class="mw-editsection">[编辑]</span></h2>
  <ul><li>守夜人：旧识</li><li>甲：同伴<sup class="reference">[1]</sup></li></ul>
  <table><tr><th>名字</th><td>星灯</td></tr><tr><td>出身</td><td>虚构城市<br>北区</td></tr></table>
  <h3>经历</h3>
  <p>第一行<br>第二行</p>
</div>''', root: '.mw-parser-output',);
      expect([for (final b in blocks) '${b.section}|${b.text}'], [
        '|星灯是点灯人。',
        '人物关系|守夜人：旧识',
        '人物关系|甲：同伴',
        '人物关系|名字 | 星灯',
        '人物关系|出身 | 虚构城市\n北区',
        '经历|第一行\n第二行',
      ]);
    });

    test('page furniture and stat rows are left out', () {
      final blocks = wikiBlocksFromHtml('''
<html><head><title>星灯 - 某Wiki</title><script>var x = 1;</script></head>
<body><nav>首页 菜单</nav>
<main>
  <div class="toc">目录 1 简介</div>
  <button>展开</button>
  <p style="display: none">隐藏</p>
  <table><tr><td>攻击力</td><td>30</td><td>88</td><td>150</td><td>211</td></tr></table>
  <div>42</div>
  <p>正文还在。</p>
  <div class="navbox">导航 甲 乙 丙</div>
</main></body></html>''', root: 'main',);
      expect([for (final b in blocks) b.text], ['正文还在。']);
      expect(wikiHtmlTitle('<title>星灯（干员） - 某Wiki</title>'), '星灯（干员）');
    });

    test('without the root selector the body is read', () {
      final blocks = wikiBlocksFromHtml('<p>甲</p><p>乙</p>', root: 'main');
      expect([for (final b in blocks) b.text], ['甲', '乙']);
    });
  });

  group('PrtsWikiSource', () {
    test('search reads the MediaWiki result and cleans wikitext snippets',
        () async {
      late Uri asked;
      final source = PrtsWikiSource(MockClient((request) async {
        asked = request.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'query': {
              'search': [
                {
                  'pageid': 101,
                  'title': '星灯',
                  'snippet':
                      '{{人物|名称=<span class="searchmatch">星灯</span>}} [[虚构城市]]的点灯人',
                },
              ],
            },
          }),),
          200,
        );
      }),);
      final hits = await source.search('星灯', limit: 5);
      expect(asked.queryParameters['list'], 'search');
      expect(asked.queryParameters['srnamespace'], '0');
      expect(asked.queryParameters['srlimit'], '5');
      expect(hits.single.key, '101');
      expect(hits.single.ref, 'wiki:prts:101');
      expect(hits.single.snippet, isNot(contains('{{')));
      expect(hits.single.snippet, contains('星灯'));
      expect(hits.single.snippet, contains('虚构城市'));
    });

    test('fetch: by page id or title, the revision is the version', () async {
      final asked = <Uri>[];
      final source = PrtsWikiSource(MockClient((request) async {
        asked.add(request.url);
        if (request.url.queryParameters['page'] == '没有的页面') {
          return http.Response(
            jsonEncode({'error': {'code': 'missingtitle'}}),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'parse': {
              'title': '星灯',
              'pageid': 101,
              'revid': 5551,
              'text':
                  '<div class="mw-parser-output"><p>星灯是点灯人。</p><h2>经历</h2><p>点亮钟楼。</p></div>',
            },
          }),),
          200,
        );
      }),);
      final page = await source.fetch('101');
      expect(asked.last.queryParameters['pageid'], '101');
      expect(asked.last.queryParameters['action'], 'parse');
      expect(page!.id, 'wiki:prts:101@5551');
      expect(page.title, '星灯');
      expect(page.blocks.map((b) => b.text), ['星灯是点灯人。', '点亮钟楼。']);
      expect(page.blocks.last.section, '经历');
      await source.fetch('星灯');
      expect(asked.last.queryParameters['page'], '星灯');
      expect(await source.fetch('没有的页面'), isNull);
    });

    test('a timeout or an HTTP error is WikiUnavailable', () async {
      final slow = PrtsWikiSource(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        slow.search('星灯'),
        throwsA(isA<WikiUnavailable>()
            .having((e) => '$e', 'message', contains('PRTS')),),
      );
      final failing =
          PrtsWikiSource(MockClient((_) async => http.Response('', 503)));
      await expectLater(
        failing.fetch('101'),
        throwsA(isA<WikiUnavailable>()
            .having((e) => e.reason, 'reason', contains('503')),),
      );
    });
  });

  group('WarfarinWikiSource', () {
    MockClient warfarin(List<Uri> asked) => MockClient((request) async {
          asked.add(request.url);
          if (request.url.host == 'api.warfarin.wiki') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'query': request.url.queryParameters['q'],
                'results': [
                  {
                    'slug': 'lamp',
                    'name': '灯塔',
                    'type': 'lore',
                    'category': '',
                    'snippet': '灯塔的来历',
                  },
                  {
                    'slug': 'star-lamp',
                    'name': '星灯',
                    'type': 'operators',
                    'category': '术师',
                    'snippet': '星灯是一名术师',
                  },
                ],
              }),),
              200,
            );
          }
          if (request.url.path == '/cn/operators/star-lamp') {
            return http.Response.bytes(
              utf8.encode('<html><head><title>星灯（干员） - 某Wiki</title></head>'
                  '<body><nav>菜单</nav><main><h1>星灯</h1><h2>档案</h2>'
                  '<p>星灯来自虚构城市。</p></main></body></html>'),
              200,
            );
          }
          return http.Response('not found', 404);
        });

    test('search: the page key is type/slug', () async {
      final asked = <Uri>[];
      final hits =
          await WarfarinWikiSource(warfarin(asked)).search('星灯', limit: 1);
      expect(asked.single.toString(),
          'https://api.warfarin.wiki/v1/cn/search?q=%E6%98%9F%E7%81%AF',);
      expect(hits.single.key, 'lore/lamp');
      expect(hits.single.ref, 'wiki:warfarin:lore/lamp');
    });

    test('fetch by key reads <main>; a title goes through the search',
        () async {
      final asked = <Uri>[];
      final source = WarfarinWikiSource(warfarin(asked));
      final page = await source.fetch('operators/star-lamp');
      expect(page!.title, '星灯（干员）');
      expect(page.blocks.map((b) => b.text), ['星灯来自虚构城市。']);
      expect(page.blocks.single.section, '档案');
      expect(WikiPageId.parse(page.id)!.key, 'operators/star-lamp');
      expect(page.version, hasLength(8));
      // The same text gives the same version.
      expect((await source.fetch('operators/star-lamp'))!.version, page.version);
      asked.clear();
      final byTitle = await source.fetch('星灯');
      expect(byTitle!.key, 'operators/star-lamp');
      expect(asked.first.host, 'api.warfarin.wiki');
      expect(await source.fetch('lore/missing'), isNull);
    });
  });

  test('page ids and citations', () {
    final id = WikiPageId.parse('wiki:warfarin:operators/star-lamp@1a2b3c4d')!;
    expect(id.site, WikiSite.warfarin);
    expect(id.key, 'operators/star-lamp');
    expect(id.url.toString(), 'https://warfarin.wiki/cn/operators/star-lamp');
    expect(WikiPageId.parse('wiki:prts:101'), isNull);
    expect(WikiPageId.parse('wiki:other:1@2'), isNull);
    expect(WikiSite.prts.pageUrl('101').toString(),
        'https://prts.wiki/index.php?curid=101',);
    final m = wikiCitationPattern
        .firstMatch('见 `wiki:prts:101@5551:P2-3`。')!;
    expect([m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)],
        ['prts', '101', '5551', '2', '3'],);
  });
}
