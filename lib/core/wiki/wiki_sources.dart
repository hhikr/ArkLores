/// 0.13: the wikis the Ask agent searches and reads.
///
/// - PRTS (Arknights): the MediaWiki API — `list=search` for searching,
///   `action=parse` for a page's HTML and revision.
/// - Warfarin Wiki (Endfield): its search API (`api.warfarin.wiki/v1/cn/
///   search`) and the server-rendered page (`warfarin.wiki/cn/` + the
///   page's type and slug).
///   fz.wiki, the other Endfield wiki the app browses, has no public API and
///   could not be reached from the development machine (2026-10-09), so the
///   agent reads Warfarin; see `docs/WIKI_EVIDENCE.md`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'wiki_html_text.dart';
import 'wiki_page.dart';

/// One wiki: search it, fetch a page as paragraphs.
abstract class WikiSource {
  WikiSite get site;

  /// Pages matching [query], best first.
  Future<List<WikiSearchHit>> search(String query, {int limit = 8});

  /// The current version of a page: [page] is a page key (PRTS page id,
  /// Warfarin `<type>/<slug>`) or a title. Null when there is no such page.
  Future<WikiPage?> fetch(String page);
}

/// The identification sent with every request (both sites ask clients to
/// say who they are).
const Map<String, String> wikiRequestHeaders = {
  'User-Agent': 'ArkLores/0.13 (story reader; +https://github.com/hhikr/ArkLores)',
  'Accept-Language': 'zh-CN,zh;q=0.9',
};

/// Base of the two sources: GET with a timeout, failures as
/// [WikiUnavailable].
abstract class _HttpWikiSource implements WikiSource {
  _HttpWikiSource(this._client, this.timeout);

  final http.Client _client;
  final Duration timeout;

  /// The body of [url]; null for 404.
  Future<String?> get(Uri url) async {
    final http.Response response;
    try {
      response =
          await _client.get(url, headers: wikiRequestHeaders).timeout(timeout);
    } on TimeoutException {
      throw WikiUnavailable(site, '超过 ${timeout.inSeconds} 秒没有响应');
    } catch (e) {
      throw WikiUnavailable(site, '网络错误：$e');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw WikiUnavailable(site, 'HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<Map<String, dynamic>?> getJson(Uri url) async {
    final body = await get(url);
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      throw WikiUnavailable(site, '返回的不是 JSON');
    }
  }
}

class PrtsWikiSource extends _HttpWikiSource {
  PrtsWikiSource(
    http.Client client, {
    Duration timeout = const Duration(seconds: 20),
  }) : super(client, timeout);

  static final Uri _api = Uri.parse('https://prts.wiki/api.php');

  @override
  WikiSite get site => WikiSite.prts;

  Uri _query(Map<String, String> params) => _api.replace(
        queryParameters: {...params, 'format': 'json', 'formatversion': '2'},
      );

  @override
  Future<List<WikiSearchHit>> search(String query, {int limit = 8}) async {
    final json = await getJson(_query({
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srnamespace': '0',
      'srlimit': '$limit',
      'srprop': 'snippet',
    }),);
    final hits = (json?['query'] as Map?)?['search'];
    if (hits is! List) return const [];
    return [
      for (final h in hits)
        if (h is Map && h['pageid'] != null)
          WikiSearchHit(
            site: site,
            key: '${h['pageid']}',
            title: '${h['title'] ?? ''}',
            snippet: _wikitextSnippet('${h['snippet'] ?? ''}'),
          ),
    ];
  }

  @override
  Future<WikiPage?> fetch(String page) async {
    final byId = int.tryParse(page.trim()) != null;
    final json = await getJson(_query({
      'action': 'parse',
      if (byId) 'pageid': page.trim() else 'page': page.trim(),
      'prop': 'text|revid|displaytitle',
      'redirects': '1',
      'disableeditsection': '1',
      'disabletoc': '1',
    }),);
    final parse = json?['parse'];
    if (parse is! Map) return null; // {"error": {"code": "missingtitle"}}
    final pageId = '${parse['pageid'] ?? ''}';
    final title = '${parse['title'] ?? page}';
    final text = parse['text'];
    if (pageId.isEmpty || text is! String) return null;
    return WikiPage(
      site: site,
      key: pageId,
      version: '${parse['revid'] ?? 0}',
      title: title,
      url: Uri.parse(
        'https://prts.wiki/w/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
      ),
      fetchedAt: DateTime.now(),
      blocks: wikiBlocksFromHtml(text, root: '.mw-parser-output'),
    );
  }

  /// MediaWiki's snippets are wikitext with highlight markup: kept as
  /// readable text (template braces, parameter names, link brackets out).
  static String _wikitextSnippet(String snippet) => wikiPlainText(snippet)
      .replaceAll(RegExp(r'\{\{|\}\}|\[\[|\]\]|={2,}|\|[^|=\n]{1,20}='), ' ')
      .replaceAll('|', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class WarfarinWikiSource extends _HttpWikiSource {
  WarfarinWikiSource(
    http.Client client, {
    Duration timeout = const Duration(seconds: 20),
  }) : super(client, timeout);

  @override
  WikiSite get site => WikiSite.warfarin;

  static final RegExp _pageKey = RegExp(r'^[a-z][a-z\-]*/[A-Za-z0-9_\-]+$');

  @override
  Future<List<WikiSearchHit>> search(String query, {int limit = 8}) async {
    final json = await getJson(
      Uri.https('api.warfarin.wiki', '/v1/cn/search', {'q': query}),
    );
    final results = json?['results'];
    if (results is! List) return const [];
    return [
      for (final r in results.take(limit))
        if (r is Map && r['slug'] != null && r['type'] != null)
          WikiSearchHit(
            site: site,
            key: '${r['type']}/${r['slug']}',
            title: '${r['name'] ?? r['slug']}',
            snippet: wikiPlainText('${r['snippet'] ?? ''}'),
            category: [r['type'], r['category']]
                .where((v) => v != null && '$v'.trim().isNotEmpty)
                .join(' · '),
          ),
    ];
  }

  @override
  Future<WikiPage?> fetch(String page) async {
    var key = page.trim();
    if (!_pageKey.hasMatch(key)) {
      // A title: the search hit with exactly that name, else the first.
      final hits = await search(key, limit: 10);
      if (hits.isEmpty) return null;
      key = hits
          .firstWhere((h) => h.title == page.trim(), orElse: () => hits.first)
          .key;
    }
    final url = site.pageUrl(key);
    final html = await get(url);
    if (html == null) return null;
    final blocks = wikiBlocksFromHtml(html, root: 'main');
    if (blocks.isEmpty) return null;
    final digest = sha1.convert(
      utf8.encode([for (final b in blocks) '${b.section}\u0001${b.text}'].join('\n')),
    );
    return WikiPage(
      site: site,
      key: key,
      version: '$digest'.substring(0, 8),
      title: wikiHtmlTitle(html),
      url: url,
      fetchedAt: DateTime.now(),
      blocks: blocks,
    );
  }
}
