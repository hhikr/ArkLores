/// 0.14: `search` — one call that looks everywhere at once: the story text of
/// every installed game (meaning first, by the story vectors; the names the
/// query mentions by keyword) and the games' wikis, grouped by source.
///
/// It replaces the R12 `find` and is also run once on the question itself
/// before the first model call ([preSearch]), so the agent starts from
/// candidate passages instead of spending turns on where a name occurs.
/// The story lines it prints are recorded in [SeenLines]: they can be cited
/// like lines of `read_story`. Every question gets the same search.
library;

import 'dart:async';

import '../../gamedata/game_retrieval.dart';
import '../../gamedata/multi_game_retrieval.dart';
import '../../llm/embedding_client.dart';
import '../../wiki/wiki_lookup.dart';
import '../../wiki/wiki_page.dart';
import '../lore_tools.dart';
import 'agent_tool.dart';

/// How the story text was searched.
enum SearchMode {
  /// Story vectors (meaning) and keywords.
  semantic,

  /// Keywords only: no embedding service, vectors from another model, or
  /// the embedding call failed.
  keywordOnly,
}

/// What a search found, as text for the model, and how it searched.
class SearchResult {
  const SearchResult(this.text, this.mode, {this.modeNote});
  final String text;
  final SearchMode mode;

  /// Why only keywords were used (null with vectors).
  final String? modeNote;
}

class SearchTool extends AgentTool {
  SearchTool(
    this.store,
    this.seen, {
    this.embeddingClient,
    this.wiki,
  });

  final GameDataRetrieval store;
  final SeenLines seen;
  final EmbeddingClient? embeddingClient;

  /// The wikis (null when the wiki option is off).
  final WikiLookup? wiki;

  /// Stories listed per game, lines shown per story, characters in all.
  static const int storiesPerGame = 5;
  static const int linesPerPassage = 8;
  static const int maxChars = 7000;
  static const int _rrfK = 60;

  @override
  String get name => 'search';

  @override
  String get description =>
      '一次检索所有资料：已安装的每个游戏的剧情原文（有向量服务时按意思检索，再用问题里的名字做关键词检索）'
      '${wiki == null ? '' : '，以及游戏 Wiki'}，按来源分组返回最相关的段落：故事名、story_id、行号和原文片段。'
      '适合任何“发生了什么、是什么、为什么、谁”的问题，用一句话或几个词描述要找的内容。'
      '片段里列出的行已经读到，可以直接引用；需要上下文时用 read_story 从附近读。'
      '要精确统计某个词出现在哪些故事里时用 grep。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '要找的内容：一句描述、一个问题，或空格分隔的几个词/名字',
          },
          'game': {
            'type': 'string',
            'enum': [for (final g in Game.values) g.key],
            'description': '只查这个游戏（可选；默认所有已安装的游戏）',
          },
          'collection': {
            'type': 'string',
            'description': '只在这个故事集里找（可选，故事集名字或 collection_id）',
          },
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = '${arguments['query'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：query 为空';
    final result = await run(
      query,
      game: Game.parse(arguments['game']),
      collection: '${arguments['collection'] ?? ''}'.trim(),
    );
    return result.text;
  }

  /// Searches for [query] (also used for the search before the first turn).
  Future<SearchResult> run(
    String query, {
    Game? game,
    String collection = '',
  }) async {
    final games = await _games(game);
    final names = await store.namesInText(query);
    final terms = _terms(query, names);

    // Meaning: one embedding of the query, used for every game.
    final (vector, modeNote) = await _embed(query);

    // A collection narrows the stories (in its own game).
    Set<String>? inCollection;
    var scopeLabel = '';
    if (collection.isNotEmpty) {
      final found = await store.storyCollection(collection);
      if (found == null || found.entries.isEmpty) {
        return SearchResult(
          '没有找到故事集“$collection”。去掉 collection 再检索，或用 outline 查故事集。',
          vector == null ? SearchMode.keywordOnly : SearchMode.semantic,
          modeNote: modeNote,
        );
      }
      inCollection = {for (final e in found.entries) e.storyId};
      scopeLabel = found.label;
    }

    final ranked = await Future.wait([
      for (final g in games)
        _rank(narrowTo(store, g), terms, vector, inCollection),
    ]);
    final wikiPart = wiki == null || inCollection != null
        ? const <String>[]
        : await _searchWiki(games, names.isEmpty ? query : names.take(2).join(' '));

    // A game with no keyword hit whose closest passage is clearly further
    // from the query than another game's is listed as such, not printed
    // (vector search always returns something; same model, same scale).
    final best = ranked.fold<double>(
      double.negativeInfinity,
      (b, r) => r.best > b ? r.best : b,
    );
    final mode = vector == null ? SearchMode.keywordOnly : SearchMode.semantic;
    final buffer = StringBuffer()
      ..writeln('检索“$query”${scopeLabel.isEmpty ? '' : '（$scopeLabel 内）'}：'
          '${mode == SearchMode.semantic ? '按意思检索 + 关键词' : '只有关键词检索（$modeNote）'}'
          '${terms.isEmpty ? '' : '；关键词：${terms.join('、')}'}');
    for (final (i, g) in games.indexed) {
      final r = ranked[i];
      if (r.top.isNotEmpty &&
          !r.anyKeyword &&
          games.length > 1 &&
          r.best < best - farther) {
        buffer.writeln('## ${g.label}剧情：只有意思较远的段落（最接近 '
            '${r.best.toStringAsFixed(2)}，另一游戏 ${best.toStringAsFixed(2)}），已略去；'
            '需要时用 search 指定 game=${g.key} 再查');
        continue;
      }
      final part = await _render(narrowTo(store, g), r);
      buffer.writeln('## ${g.label}剧情'
          '${part.isEmpty ? '：没有相关段落' : '（最相关的 ${part.length} 篇）'}');
      for (final block in part) {
        if (buffer.length + block.length > maxChars) {
          buffer.writeln('……（篇幅已满，其余从略）');
          break;
        }
        buffer.write(block);
      }
    }
    if (wikiPart.isNotEmpty) {
      buffer.writeln('## Wiki');
      for (final line in wikiPart) {
        buffer.writeln(line);
      }
    }
    buffer.writeln('（片段里的行已读到，可直接引用；要上下文用 read_story 从附近的行读'
        '${wikiPart.isEmpty ? '' : '；Wiki 正文用 wiki_read 读后才能引用'}）');
    return SearchResult(buffer.toString().trimRight(), mode, modeNote: modeNote);
  }

  /// The games to search: [only] when given, else every installed one.
  Future<List<Game>> _games(Game? only) async {
    final store = this.store;
    final installed = store is MultiGameRetrieval
        ? await store.installedGames()
        : const [Game.arknights];
    if (only == null) return installed;
    return installed.contains(only) ? [only] : installed;
  }

  /// Keyword terms: the words of a query written with spaces or `|`, else
  /// the names it mentions (Chinese questions have no spaces), else a short
  /// query as it is.
  static List<String> _terms(String query, List<String> names) {
    // Only spaces and `|` separate words: a comma separates clauses.
    final split = [
      for (final t in query.split(RegExp(r'[\s|]+')))
        if (t.trim().runes.length >= 2 && t.trim().runes.length <= 12) t.trim(),
    ];
    if (split.length > 1) return split.take(6).toList();
    if (names.isNotEmpty) return names;
    return query.runes.length <= 10 ? [query] : const [];
  }

  Future<(List<double>?, String?)> _embed(String query) async {
    final client = embeddingClient;
    if (client == null) return (null, '没有配置向量服务');
    final info = await store.storyVectorInfo;
    if (info == null) return (null, '知识库没有向量');
    if (info.model != client.model || info.dims != client.dimensions) {
      return (null, '库里的向量是 ${info.model}，配置的是 ${client.model}');
    }
    try {
      return ((await client.embed([query])).single, null);
    } catch (e) {
      return (null, '向量服务出错');
    }
  }

  /// How much further (in cosine similarity) a game's closest passage may be
  /// than the best one before that game's passages are left out.
  static const double farther = 0.08;

  /// One game's best stories (not printed yet).
  Future<_Ranked> _rank(
    GameDataRetrieval store,
    List<String> terms,
    List<double>? vector,
    Set<String>? inCollection,
  ) async {
    bool keep(String storyId) =>
        inCollection == null || inCollection.contains(storyId);
    final wide = inCollection == null ? 1 : 6;

    var chunks = <StoryChunkHit>[];
    if (vector != null) {
      final info = await store.storyVectorInfo;
      if (info != null && info.model == embeddingClient?.model) {
        chunks = [
          for (final c in await store.searchStoryChunksByVector(
            vector,
            topK: storiesPerGame * 4 * wide,
          ))
            if (keep(c.storyId)) c,
        ];
      }
    }
    final keywords = terms.isEmpty
        ? const <StoryLineHit>[]
        : [
            for (final h in await store.searchStoryLinesLike(
              terms,
              storyLimit: storiesPerGame * 2 * wide,
              linesPerStory: 3,
            ))
              if (keep(h.storyId)) h,
          ];

    // Reciprocal-rank fusion per story.
    final score = <String, double>{};
    final firstChunk = <String, StoryChunkHit>{};
    final keywordOf = <String, StoryLineHit>{};
    for (final (rank, hit) in keywords.indexed) {
      score[hit.storyId] = (score[hit.storyId] ?? 0) + 1 / (_rrfK + rank + 1);
      keywordOf[hit.storyId] = hit;
    }
    var storyRank = 0;
    for (final c in chunks) {
      if (firstChunk.containsKey(c.storyId)) continue;
      firstChunk[c.storyId] = c;
      score[c.storyId] = (score[c.storyId] ?? 0) + 1 / (_rrfK + storyRank + 1);
      storyRank++;
    }
    final ranked = score.keys.toList()
      ..sort((a, b) => score[b]!.compareTo(score[a]!));
    return _Ranked(
      ranked.take(storiesPerGame).toList(),
      firstChunk,
      keywordOf,
      best: chunks.isEmpty ? double.negativeInfinity : chunks.first.score,
      anyKeyword: keywords.isNotEmpty,
    );
  }

  /// [ranked] as printed blocks; the lines printed become citable.
  Future<List<String>> _render(GameDataRetrieval store, _Ranked ranked) async {
    final top = ranked.top;
    if (top.isEmpty) return const [];
    final labels = await store.storyCatalogEntries(top);

    final blocks = <String>[];
    for (final (i, storyId) in top.indexed) {
      final chunk = ranked.firstChunk[storyId];
      final keyword = ranked.keywordOf[storyId];
      final block = StringBuffer()
        ..writeln('${i + 1}. 《${labels[storyId]?.label ?? fallbackStoryLabel(storyId)}》 $storyId'
            '（${[
              if (chunk != null) '意思相近 ${chunk.score.toStringAsFixed(2)}',
              if (keyword != null) '关键词 ${keyword.hits} 行',
            ].join('；')}）');
      final shown = <int>{};
      if (chunk != null) {
        final end = chunk.lineEnd < chunk.lineStart + linesPerPassage - 1
            ? chunk.lineEnd
            : chunk.lineStart + linesPerPassage - 1;
        final page = await store.readStoryLines(
          storyId: storyId,
          startLine: chunk.lineStart,
          endLine: end,
          maxLines: linesPerPassage,
        );
        for (final line in page.lines) {
          block.writeln('   ${_line(line)}');
          shown.add(line.lineIndex);
          seen.add(storyId, line.lineIndex);
        }
        if (chunk.lineEnd > end) {
          block.writeln('   …（这一段到 L${chunk.lineEnd}）');
        }
      }
      for (final line in keyword?.lines ?? const <StoryLineEntry>[]) {
        if (!shown.add(line.lineIndex)) continue;
        block.writeln('   ${_line(line)}');
        seen.add(storyId, line.lineIndex);
      }
      blocks.add(block.toString());
    }
    return blocks;
  }

  static String _line(StoryLineEntry line) {
    final text =
        formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind);
    return text.length <= 140 ? text : '${text.substring(0, 140)}…';
  }

  /// Wiki pages for [query] on the wikis of [games], one line each.
  Future<List<String>> _searchWiki(List<Game> games, String query) async {
    final wiki = this.wiki;
    if (wiki == null) return const [];
    final parts = await Future.wait([
      for (final g in games)
        () async {
          final site = WikiSite.of(g);
          try {
            final hits = await wiki
                .search(g, query, limit: 6)
                .timeout(const Duration(seconds: 12));
            // Subpages (`<page>/<part>`) only when nothing else came.
            final pages = hits.where((h) => !h.title.contains('/')).toList();
            final shown = (pages.isEmpty ? hits : pages).take(4);
            if (shown.isEmpty) return ['${site.label}：没有相关页面'];
            return [
              for (final h in shown)
                '${site.label}：${h.ref} | ${h.title}'
                    '${h.snippet.isEmpty ? '' : ' | ${_clip(h.snippet, 80)}'}',
            ];
          } on WikiUnavailable catch (e) {
            return ['$e'];
          } on TimeoutException {
            return ['${site.label} 暂时无法访问（超时）'];
          } catch (e) {
            return ['${site.label} 暂时无法访问'];
          }
        }(),
    ]);
    return [for (final p in parts) ...p];
  }


  static String _clip(String text, int max) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max)}…';
  }
}

/// One game's ranked stories with what found each.
class _Ranked {
  _Ranked(
    this.top,
    this.firstChunk,
    this.keywordOf, {
    required this.best,
    required this.anyKeyword,
  });
  final List<String> top;
  final Map<String, StoryChunkHit> firstChunk;
  final Map<String, StoryLineHit> keywordOf;

  /// Score of the game's closest passage (−∞ without vectors).
  final double best;
  final bool anyKeyword;
}
