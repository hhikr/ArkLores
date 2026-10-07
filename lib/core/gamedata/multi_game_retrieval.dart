/// 0.12: one retrieval surface over the knowledge bases of several games.
///
/// Ids carry their game (`game.dart`), so a call about one story, record,
/// scope or collection goes to that game's database; a call about the whole
/// corpus asks every installed database and merges the answers (their ids
/// never collide). The agent's tools take this as their store unchanged; a
/// tool that is told to look at one game narrows it with [only].
library;

import 'game_retrieval.dart';

class MultiGameRetrieval implements GameDataRetrieval {
  MultiGameRetrieval(this.stores);

  /// The database of each game (installed or not; a missing one answers
  /// empty).
  final Map<Game, GameDataRetrieval> stores;

  /// [game]'s database alone (the default one when it has none).
  GameDataRetrieval only(Game game) => stores[game] ?? _default;

  GameDataRetrieval get _default =>
      stores[Game.arknights] ?? stores.values.first;

  GameDataRetrieval _of(String id) => only(gameOfId(id));

  /// The games whose database is installed, default game first.
  Future<List<Game>> installedGames() async => [
        for (final game in Game.values)
          if (stores[game] != null && await stores[game]!.isAvailable) game,
      ];

  Future<List<GameDataRetrieval>> _installed() async => [
        for (final game in await installedGames()) stores[game]!,
      ];

  @override
  Future<bool> get isAvailable async => (await installedGames()).isNotEmpty;

  @override
  Future<StoryLinesPage> readStoryLines({
    required String storyId,
    int? startLine,
    int? endLine,
    int? maxLines,
    String? pageToken,
  }) =>
      _of(storyId).readStoryLines(
        storyId: storyId,
        startLine: startLine,
        endLine: endLine,
        maxLines: maxLines,
        pageToken: pageToken,
      );

  @override
  Future<List<StoryLineHit>> searchStoryLinesLike(
    List<String> terms, {
    String? scopeId,
    int storyLimit = 8,
    int linesPerStory = 3,
  }) async {
    if (scopeId != null) {
      return _of(scopeId).searchStoryLinesLike(
        terms,
        scopeId: scopeId,
        storyLimit: storyLimit,
        linesPerStory: linesPerStory,
      );
    }
    final all = <StoryLineHit>[
      for (final store in await _installed())
        ...await store.searchStoryLinesLike(
          terms,
          storyLimit: storyLimit,
          linesPerStory: linesPerStory,
        ),
    ];
    // Best first across games: lines with more of the terms, then more hits.
    all.sort((a, b) {
      final byTerms = b.bestTermCount.compareTo(a.bestTermCount);
      return byTerms != 0 ? byTerms : b.hits.compareTo(a.hits);
    });
    return all.take(storyLimit).toList();
  }

  @override
  Future<({String model, int dims})?> get storyVectorInfo async {
    for (final store in await _installed()) {
      final info = await store.storyVectorInfo;
      if (info != null) return info;
    }
    return null;
  }

  @override
  Future<List<StoryChunkHit>> searchStoryChunksByVector(
    List<double> queryVector, {
    String? scopeId,
    int topK = 20,
  }) async {
    if (scopeId != null) {
      return _of(scopeId)
          .searchStoryChunksByVector(queryVector, scopeId: scopeId, topK: topK);
    }
    final wanted = await storyVectorInfo;
    final all = <StoryChunkHit>[];
    for (final store in await _installed()) {
      final info = await store.storyVectorInfo;
      // Scores of different models do not compare.
      if (info == null || info != wanted) continue;
      all.addAll(await store.searchStoryChunksByVector(queryVector, topK: topK));
    }
    all.sort((a, b) => b.score.compareTo(a.score));
    return all.take(topK).toList();
  }

  @override
  Future<Map<String, StoryCatalogEntry>> storyCatalogEntries(
    Iterable<String> storyIds,
  ) async {
    final byGame = <Game, List<String>>{};
    for (final id in storyIds) {
      byGame.putIfAbsent(gameOfId(id), () => []).add(id);
    }
    return {
      for (final MapEntry(key: game, value: ids) in byGame.entries)
        ...await only(game).storyCatalogEntries(ids),
    };
  }

  @override
  Future<StoryCollection?> storyCollection(String query) async {
    final first = gameOfId(query);
    final found = await only(first).storyCollection(query);
    if (found != null) return found;
    for (final store in await _installed()) {
      if (identical(store, only(first))) continue;
      final other = await store.storyCollection(query);
      if (other != null) return other;
    }
    return null;
  }

  @override
  Future<List<StoryCatalogEntry>> storiesByCode(String code) async => [
        for (final store in await _installed())
          ...await store.storiesByCode(code),
      ];

  @override
  Future<List<({String id, String label, int chapters})>> storyCollectionIndex({
    String? like,
    String? type,
  }) async =>
      [
        for (final store in await _installed())
          ...await store.storyCollectionIndex(like: like, type: type),
      ];

  @override
  Future<List<StoryCatalogEntry>> searchStorySynopses(
    List<String> terms, {
    String? collectionId,
    int limit = 5,
  }) async {
    if (collectionId != null) {
      return _of(collectionId).searchStorySynopses(
        terms,
        collectionId: collectionId,
        limit: limit,
      );
    }
    return [
      for (final store in await _installed())
        ...await store.searchStorySynopses(terms, limit: limit),
    ].take(limit).toList();
  }

  @override
  Future<List<SimilarName>> similarNames(String term, {int limit = 3}) async {
    final all = [
      for (final store in await _installed())
        ...await store.similarNames(term, limit: limit),
    ]..sort((a, b) => a.cost.compareTo(b.cost));
    final seen = <String>{};
    return [
      for (final name in all)
        if (seen.add(name.name)) name,
    ].take(limit).toList();
  }

  @override
  Future<Map<String, ({int all, int inScope})>> storyLineTermCounts(
    List<String> terms, {
    String? scopeId,
  }) async {
    final total = <String, ({int all, int inScope})>{};
    for (final store in await _installed()) {
      final inThis = scopeId != null && identical(store, _of(scopeId));
      final counts = await store.storyLineTermCounts(
        terms,
        scopeId: inThis ? scopeId : null,
      );
      for (final MapEntry(key: term, value: c) in counts.entries) {
        final before = total[term] ?? (all: 0, inScope: 0);
        total[term] = (
          all: before.all + c.all,
          inScope: before.inScope + (scopeId == null || inThis ? c.inScope : 0),
        );
      }
    }
    return total;
  }

  @override
  Future<SqlQueryResult> readOnlySql(
    String sql, {
    int maxRows = 200,
    Game? game,
  }) =>
      only(game ?? Game.arknights).readOnlySql(sql, maxRows: maxRows);

  @override
  Future<List<StoryLineHitRow>> grepStoryLines(
    List<String> terms, {
    Iterable<String>? storyIds,
    int limit = 80,
  }) async {
    if (storyIds == null) {
      return [
        for (final store in await _installed())
          ...await store.grepStoryLines(terms, limit: limit),
      ].take(limit).toList();
    }
    final byGame = <Game, List<String>>{};
    for (final id in storyIds) {
      byGame.putIfAbsent(gameOfId(id), () => []).add(id);
    }
    return [
      for (final MapEntry(key: game, value: ids) in byGame.entries)
        ...await only(game).grepStoryLines(terms, storyIds: ids, limit: limit),
    ].take(limit).toList();
  }

  @override
  Future<Map<String, int>> storyLineHitCounts(
    List<String> terms, {
    Iterable<String>? storyIds,
  }) async {
    if (storyIds == null) {
      return {
        for (final store in await _installed())
          ...await store.storyLineHitCounts(terms),
      };
    }
    final byGame = <Game, List<String>>{};
    for (final id in storyIds) {
      byGame.putIfAbsent(gameOfId(id), () => []).add(id);
    }
    return {
      for (final MapEntry(key: game, value: ids) in byGame.entries)
        ...await only(game).storyLineHitCounts(terms, storyIds: ids),
    };
  }
}

/// [store] narrowed to [game] when it spans several games and [game] is set.
GameDataRetrieval narrowTo(GameDataRetrieval store, Game? game) =>
    store is MultiGameRetrieval && game != null ? store.only(game) : store;
