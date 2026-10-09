import 'package:arklores/core/wiki/wiki_lookup.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:arklores/core/wiki/wiki_sources.dart';

/// A wiki held in memory: pages by key (title as the second key). Fictional
/// content only. [unavailable] makes every call fail as a network error
/// would; [fetches] counts page fetches.
class FakeWikiSource implements WikiSource {
  FakeWikiSource(this.site, this.pages, {this.version = '7'});

  @override
  final WikiSite site;
  final Map<String, ({String title, List<WikiBlock> blocks})> pages;
  String version;
  bool unavailable = false;
  int fetches = 0;

  @override
  Future<List<WikiSearchHit>> search(String query, {int limit = 8}) async {
    if (unavailable) throw WikiUnavailable(site, '网络错误：测试');
    return [
      for (final MapEntry(key: key, value: page) in pages.entries)
        if (page.title.contains(query) ||
            page.blocks.any((b) => b.text.contains(query)))
          WikiSearchHit(
            site: site,
            key: key,
            title: page.title,
            snippet: page.blocks.first.text,
          ),
    ].take(limit).toList();
  }

  @override
  Future<WikiPage?> fetch(String page) async {
    if (unavailable) throw WikiUnavailable(site, '网络错误：测试');
    fetches++;
    final entry = pages.entries
        .where((e) => e.key == page || e.value.title == page)
        .firstOrNull;
    if (entry == null) return null;
    return WikiPage(
      site: site,
      key: entry.key,
      version: version,
      title: entry.value.title,
      url: site.pageUrl(entry.key),
      fetchedAt: DateTime.now(),
      blocks: entry.value.blocks,
    );
  }
}

/// A fictional PRTS-like wiki: one character page with three sections.
FakeWikiSource fakePrts() => FakeWikiSource(WikiSite.prts, {
      '101': (
        title: '星灯',
        blocks: const [
          WikiBlock('', '星灯是虚构城市里的点灯人。'),
          WikiBlock('人物关系', '星灯与守夜人是旧识。'),
          WikiBlock('人物关系', '守夜人 | 旧识'),
          WikiBlock('相关活动', '星灯在虚构活动中登场。'),
        ],
      ),
    });

WikiLookup fakeWikiLookup({FakeWikiSource? prts, FakeWikiSource? warfarin}) =>
    WikiLookup(
      sources: {
        WikiSite.prts: prts ?? fakePrts(),
        if (warfarin != null) WikiSite.warfarin: warfarin,
      },
    );
