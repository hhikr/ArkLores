/// 0.13: the wikis as the Ask agent and the answer view use them.
///
/// Pages are fetched once per [cacheTtl] (a question reads a page in
/// several calls) and every fetched version is kept as a snapshot under its
/// page id, so a citation (`wiki:<site>:<key>@<version>:a-b`) shows the
/// paragraphs the agent read even after the page was edited, and offline.
library;

import 'dart:convert';
import 'dart:io';

import '../gamedata/game.dart';
import 'wiki_page.dart';
import 'wiki_sources.dart';

/// Fetched page versions, by page id: in memory, and in [directory] when
/// there is one (one JSON file per version; the oldest are removed past
/// [maxFiles]).
class WikiSnapshotStore {
  WikiSnapshotStore({Future<Directory?> Function()? directory, this.maxFiles = 400})
      : _directory = directory;

  final Future<Directory?> Function()? _directory;
  final int maxFiles;
  final Map<String, WikiPage> _memory = {};

  Future<Directory?> _dir() async {
    try {
      final dir = await _directory?.call();
      if (dir == null) return null;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static String _fileName(String pageId) =>
      '${Uri.encodeComponent(pageId)}.json';

  Future<void> save(WikiPage page) async {
    _memory[page.id] = page;
    final dir = await _dir();
    if (dir == null) return;
    try {
      final file = File('${dir.path}/${_fileName(page.id)}');
      if (!file.existsSync()) {
        await file.writeAsString(jsonEncode(page.toJson()), flush: true);
        _prune(dir);
      }
    } catch (_) {
      // A snapshot that cannot be written only costs the offline view.
    }
  }

  Future<WikiPage?> load(String pageId) async {
    final cached = _memory[pageId];
    if (cached != null) return cached;
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/${_fileName(pageId)}');
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final page = WikiPage.fromJson(json);
      if (page != null) _memory[pageId] = page;
      return page;
    } catch (_) {
      return null;
    }
  }

  void _prune(Directory dir) {
    try {
      final files = dir.listSync().whereType<File>().toList();
      if (files.length <= maxFiles) return;
      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
      for (final f in files.take(files.length - maxFiles)) {
        f.deleteSync();
      }
    } catch (_) {}
  }
}

/// What the agent's wiki tools call.
class WikiLookup {
  WikiLookup({
    required Map<WikiSite, WikiSource> sources,
    WikiSnapshotStore? snapshots,
    this.cacheTtl = const Duration(minutes: 30),
    DateTime Function()? now,
  })  : _sources = sources,
        snapshots = snapshots ?? WikiSnapshotStore(),
        _now = now ?? DateTime.now;

  final Map<WikiSite, WikiSource> _sources;
  final WikiSnapshotStore snapshots;
  final Duration cacheTtl;
  final DateTime Function() _now;

  /// Current versions fetched recently, by `<site>:<key or title>`, with
  /// when they were fetched.
  final Map<String, (WikiPage, DateTime)> _current = {};

  Iterable<WikiSite> get sites => _sources.keys;

  WikiSource? sourceOf(WikiSite site) => _sources[site];

  /// Pages of [game]'s wiki matching [query].
  Future<List<WikiSearchHit>> search(
    Game game,
    String query, {
    int limit = defaultSearchLimit,
  }) async {
    final site = WikiSite.of(game);
    final source = _sources[site];
    if (source == null) return const [];
    // 0.14 live: the searches of one question ask for the same word again
    // and again (three planned searches sharing their first word, then
    // `wiki_search` for it), at once; the wiki answered the burst slowly and
    // some of them timed out. One request per word, shared while it runs.
    final key = '${site.key}:$query';
    final kept = _searches[key];
    if (kept != null &&
        kept.limit >= limit &&
        _now().difference(kept.at) < cacheTtl) {
      return (await kept.hits).take(limit).toList();
    }
    final hits = source.search(query, limit: limit);
    final entry = (hits: hits, limit: limit, at: _now());
    _searches[key] = entry;
    try {
      return await hits;
    } catch (_) {
      if (identical(_searches[key], entry)) _searches.remove(key);
      rethrow;
    }
  }

  /// How many pages a search asks for unless told otherwise.
  static const int defaultSearchLimit = 8;

  /// Searches asked recently, by `<site>:<query>` (running ones included).
  final Map<String, ({Future<List<WikiSearchHit>> hits, int limit, DateTime at})>
      _searches = {};

  /// The page [page] names: a page id with a version (that version, from
  /// the snapshots when it is there), a page id without one or a `wiki:`
  /// ref from a search (the current version), or a title on [game]'s wiki.
  /// Null when there is no such page.
  Future<WikiPage?> read(String page, {Game? game}) async {
    final text = page.trim();
    final versioned = WikiPageId.parse(text);
    if (versioned != null) {
      final kept = await snapshots.load(versioned.toString());
      if (kept != null) return kept;
      return _fetchCurrent(versioned.site, versioned.key);
    }
    final ref = RegExp(r'^wiki:([a-z]+):(.+)$').firstMatch(text);
    if (ref != null) {
      final site = WikiSite.parse(ref.group(1));
      if (site == null) return null;
      return _fetchCurrent(site, ref.group(2)!);
    }
    return _fetchCurrent(WikiSite.of(game ?? Game.arknights), text);
  }

  Future<WikiPage?> _fetchCurrent(WikiSite site, String keyOrTitle) async {
    final source = _sources[site];
    if (source == null) return null;
    final cacheKey = '${site.key}:$keyOrTitle';
    final cached = _current[cacheKey];
    if (cached != null && _now().difference(cached.$2) < cacheTtl) {
      return cached.$1;
    }
    final page = await source.fetch(keyOrTitle);
    if (page == null) return null;
    final entry = (page, _now());
    _current[cacheKey] = entry;
    _current['${site.key}:${page.key}'] = entry;
    await snapshots.save(page);
    return page;
  }

  /// The version a citation names, for the answer view and the quote
  /// check: the kept snapshot only (null when it is not kept).
  Future<WikiPage?> snapshot(String pageId) => snapshots.load(pageId);
}
