/// 0.14: `search` — one call that looks everywhere at once: the story text of
/// every installed game (meaning first, by the story vectors; the names the
/// query mentions by keyword) and the games' wikis, grouped by source.
///
/// It replaces the R12 `find`. The first searches of a question are planned
/// by a call of its own (`search_planner.dart`) and run before the first
/// turn, so the agent starts from candidate passages instead of spending
/// turns on where a name occurs.
/// The story lines it prints are recorded in [SeenLines]: they can be cited
/// like lines of `read_story`. Every question gets the same search.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../gamedata/game_retrieval.dart';
import '../../gamedata/multi_game_retrieval.dart';
import '../../gamedata/story_line_search.dart' show maxKeywordTerms;
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
  static const int recordsPerGame = 3;
  static const int maxChars = 7000;

  /// Most characters of one line printed.
  static const int lineChars = 400;
  static const int _rrfK = 60;

  @override
  String get name => 'search';

  /// 0.14: no meaning search for this question ([keywordOnlyReason]), set
  /// by the agent before it describes its tools: the description then asks
  /// for words that occur in the text.
  bool keywordOnly = false;

  @override
  String get description => keywordOnly
      ? '一次检索所有资料：已安装的每个游戏的剧情原文、剧情以外的资料原文（档案、干员资料、语音等）'
          '${wiki == null ? '' : '和游戏 Wiki'}，按来源分组返回最相关的段落：故事名、story_id、行号和原文片段，资料给出 record 出处。'
          '现在没有向量服务，只按字面（子串）匹配原文：query 写原文里会出现的词——人物、地点、组织、事件、物品的叫法，'
          '以及它们的别称、相关的说法，空格分隔，每个词 2–6 个字，不要写整句或长短语（整句不会出现在原文里）。'
          '一次最多 $maxKeywordTerms 个词；结果开头列出每个词命中多少行，命中 0 行的词换个说法再查。'
          '片段里列出的行已经读到，可以直接引用；需要上下文时用 read_story 从附近读。'
          '要精确统计某个词出现在哪些故事里时用 grep。'
      : '一次检索所有资料：已安装的每个游戏的剧情原文（按整个 query 的意思检索；query 里用空格分开的词还各自做关键词检索）'
          '，以及剧情以外的资料原文（档案、干员资料、语音等）'
          '${wiki == null ? '' : '和游戏 Wiki'}，按来源分组返回最相关的段落：故事名、story_id、行号和原文片段，资料给出 record 出处。'
          '适合任何“发生了什么、是什么、为什么、谁”的问题：写空格分隔的几个词（原文里会出现的名字、叫法和相关说法，'
          '每个词 2–6 个字，一次最多 $maxKeywordTerms 个），或一句描述（只按意思检索，资料和 Wiki 要靠词才查得到）。'
          '结果开头列出每个词命中多少行，命中 0 行的词换个说法再查。'
          '片段里列出的行已经读到，可以直接引用；需要上下文时用 read_story 从附近读。'
          '要精确统计某个词出现在哪些故事里时用 grep。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': keywordOnly
                ? '原文里会出现的词，空格分隔（名字、叫法、别称；不要写整句）'
                : '空格分隔的几个词（名字、叫法、相关说法），或一句描述',
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
          if (wiki != null)
            'wiki': {
              'type': 'string',
              'description': '在 Wiki 上搜的一个页面名或名词（可选；默认用 query 的第一个词）',
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
      wikiQuery: '${arguments['wiki'] ?? ''}',
    );
    return result.text;
  }

  /// Searches for [query] (also used for the searches planned before the
  /// first turn). [wikiQuery] is what the wikis are searched for: by
  /// default the query's first word (a wiki finds pages by a name; two
  /// words together found none), nothing for a sentence.
  Future<SearchResult> run(
    String query, {
    Game? game,
    String collection = '',
    String? wikiQuery,
  }) async {
    final games = await _games(game);
    final allTerms = termsOf(query);
    final forWiki = (wikiQuery ?? '').trim().isNotEmpty
        ? wikiQuery!.trim()
        : allTerms.isEmpty
            ? ''
            : allTerms.first;
    // The wikis answer over the network: asked while the library is read.
    final wikiSearch = wiki == null || collection.isNotEmpty || forWiki.isEmpty
        ? Future.value(const <String>[])
        : _timed('wiki', () => _searchWiki(games, forWiki));

    // Meaning: one embedding of the query, used for every game.
    final (vector, modeNote) = await _timed('embed', () => _embed(query));
    final terms = allTerms.take(maxKeywordTerms).toList();
    final unused = allTerms.skip(maxKeywordTerms).toList();
    final termLines = <String, int>{};

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
        _rank(g, narrowTo(store, g), terms, vector, inCollection, termLines),
    ]);
    // Archives, profiles, voice lines and the like (not story text), by the
    // same keywords; not within a collection. A word that is everywhere in
    // the story text weighs less: without that, a common word of the query
    // brought records that had nothing to do with it.
    if (terms.isNotEmpty && inCollection == null) {
      final weights = {
        for (final t in terms)
          t: 1 / (1 + math.log(1 + (termLines[t] ?? 0))),
      };
      final records = await _timed(
        'records',
        () => Future.wait([
          for (final g in games)
            narrowTo(store, g).searchRecordsLike(
              terms,
              limit: recordsPerGame,
              weights: weights,
            ),
        ]),
      );
      for (final (i, r) in ranked.indexed) {
        r.records = records[i];
      }
    }
    final wikiPart = await wikiSearch;

    // A game whose closest passage is clearly further from the query than
    // another game's is listed as such, not printed (vector search always
    // returns something; same model, same scale) — unless the query's
    // words are found there more than in the other game (0.14: any keyword
    // hit used to keep it, and a common word always hits).
    final best = ranked.fold<double>(
      double.negativeInfinity,
      (b, r) => r.best > b ? r.best : b,
    );
    final mostLines = ranked.fold<int>(0, (n, r) => r.lines > n ? r.lines : n);
    final mode = vector == null ? SearchMode.keywordOnly : SearchMode.semantic;
    final buffer = StringBuffer()
      ..writeln('检索“$query”'
          '${scopeLabel.isEmpty ? '' : '（$scopeLabel 内）'}：'
          '${mode == SearchMode.semantic ? '按意思检索 + 关键词' : '只有关键词检索（$modeNote）'}'
          '${terms.isNotEmpty ? '；关键词：${_termCounts(terms, termLines, inCollection != null)}' : mode == SearchMode.keywordOnly ? '；query 里没有可以匹配的词：要写空格分隔的词（每个 2–12 个字），不是整句' : ''}'
          '${unused.isEmpty ? '' : '；一次最多 $maxKeywordTerms 个词，未使用：${unused.join('、')}'}');
    for (final (i, g) in games.indexed) {
      final r = ranked[i];
      if (r.top.isNotEmpty &&
          games.length > 1 &&
          r.best < best - farther &&
          (r.lines == 0 || r.lines < mostLines)) {
        buffer.writeln('## ${g.label}剧情：只有意思较远的段落（最接近 '
            '${r.best.toStringAsFixed(2)}，另一游戏 ${best.toStringAsFixed(2)}'
            '${r.lines == 0 && r.records.isEmpty ? '' : '；关键词命中 ${r.lines} 行、${r.records.length} 条资料'}），已略去；'
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
      final records = _renderRecords(r);
      if (records.isNotEmpty) {
        buffer.writeln('## ${g.label}资料（档案、干员资料、语音等；格式：出处 | 类别 | 标题 | 片段）');
        records.forEach(buffer.write);
      }
    }
    if (wikiPart.isNotEmpty) {
      buffer.writeln('## Wiki');
      for (final line in wikiPart) {
        buffer.writeln(line);
      }
    }
    buffer.writeln('（上面列出的行可以引用，没有列出的行要先读；要上下文用 read_story 从附近的行读。'
        '资料只列了片段，可以按片段引用，全文用 sql 按 id 查 normalized_records（类别是 *_profile_bundle 的在 entity_documents）'
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

  /// Keyword terms: the words of a query as its writer separated them, by
  /// spaces or `|` (a comma separates clauses, not words). 0.14: code no
  /// longer cuts words out of a sentence — it took fragments of clauses for
  /// words; whoever writes the query (the model, or the call that plans
  /// the first searches) chooses them. A sentence has no terms: it is
  /// searched by meaning only.
  static List<String> termsOf(String query) {
    final words = {
      for (final t in query.split(RegExp(r'[\s|]+')))
        if (t.trim().runes.length >= 2 && t.trim().runes.length <= 12)
          t.trim(),
    }.toList();
    // Written without a space, only a short query is a word.
    return words.length == 1 && words.single.runes.length > loneWordChars
        ? const []
        : words;
  }

  /// Most characters of a query that is one word (a name).
  static const int loneWordChars = 8;

  /// `term（N 行）` for each of [terms]; a term no line has is marked, so
  /// the next search tries other words.
  static String _termCounts(
    List<String> terms,
    Map<String, int> lines,
    bool scoped,
  ) =>
      [
        for (final t in terms)
          switch (lines[t]) {
            null => t,
            0 => '$t（0 行，原文里没有这个写法）',
            final n => '$t（${scoped ? '全库 ' : ''}$n 行）',
          },
      ].join('、');

  /// Why a search will use keywords only (no embedding service, no vectors
  /// in the knowledge base, vectors of another model), or null when it can
  /// search by meaning. Checked without calling the embedding service.
  Future<String?> keywordOnlyReason() async {
    final client = embeddingClient;
    if (client == null) return '没有配置向量服务';
    final info = await store.storyVectorInfo;
    if (info == null) return '知识库没有向量';
    if (info.model != client.model || info.dims != client.dimensions) {
      return '库里的向量是 ${info.model}，配置的是 ${client.model}';
    }
    return null;
  }

  Future<(List<double>?, String?)> _embed(String query) async {
    final reason = await keywordOnlyReason();
    if (reason != null) return (null, reason);
    try {
      return ((await embeddingClient!.embed([query])).single, null);
    } catch (e) {
      return (null, '向量服务出错');
    }
  }

  /// How much further (in cosine similarity) a game's closest passage may be
  /// than the best one before that game's passages are left out.
  static const double farther = 0.08;

  /// One game's best stories (not printed yet).
  Future<_Ranked> _rank(
    Game game,
    GameDataRetrieval store,
    List<String> terms,
    List<double>? vector,
    Set<String>? inCollection,
    Map<String, int> termLines,
  ) async {
    bool keep(String storyId) =>
        inCollection == null || inCollection.contains(storyId);
    final wide = inCollection == null ? 1 : 6;

    var chunks = <StoryChunkHit>[];
    if (vector != null) {
      final info = await store.storyVectorInfo;
      if (info != null && info.model == embeddingClient?.model) {
        chunks = [
          for (final c in await _timed(
            'vectors:${game.key}',
            () => store.searchStoryChunksByVector(
              vector,
              topK: storiesPerGame * 4 * wide,
            ),
          ))
            if (keep(c.storyId)) c,
        ];
      }
    }
    final keywords = terms.isEmpty
        ? const <StoryLineHit>[]
        : [
            for (final h in await _timed(
              'keywords:${game.key}',
              () => store.searchStoryLinesLike(
                terms,
                storyLimit: storiesPerGame * 2 * wide,
                linesPerStory: 3,
                termLines: termLines,
              ),
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
      lines: keywords.fold(0, (n, h) => n + h.hits),
    );
  }

  /// Measurement only (0.14): where a search spends its time — the
  /// embedding call, each game's vector scan and keyword scan, the records,
  /// the wikis. Set by the agent; never changes behaviour.
  void Function(String name, DateTime start, DateTime end)? onSpan;

  Future<T> _timed<T>(String part, Future<T> Function() run) async {
    final start = DateTime.now();
    try {
      return await run();
    } finally {
      onSpan?.call('search:$part', start, DateTime.now());
    }
  }

  /// [ranked]'s records as printed lines; the records printed become
  /// citable (`record:<id>`).
  List<String> _renderRecords(_Ranked ranked) => [
        for (final r in ranked.records)
          () {
            // Only the excerpt was shown.
            seen.addRecord(r.id, partial: true);
            return '   record:${r.id} | ${r.category}${r.subtype.isEmpty || r.subtype == r.category ? '' : '·${r.subtype}'}'
                ' | ${r.title} | ${r.snippet}\n';
          }(),
      ];

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
        ..writeln(
            '${i + 1}. 《${labels[storyId]?.label ?? fallbackStoryLabel(storyId)}》 $storyId'
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
          // 0.14: not "the passage goes on to L…", which read as shown.
          block.writeln('   …（L${end + 1}-${chunk.lineEnd} 没有列出，要引用先用 read_story 读）');
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
    // 0.14: a line is shown whole, as `read_story` shows it (it counts as
    // read); only a very long one (a letter, a document) is cut, and says so.
    return text.length <= lineChars
        ? text
        : '${text.substring(0, lineChars)}…（本行未完）';
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
    required this.lines,
  });
  final List<String> top;
  final Map<String, StoryChunkHit> firstChunk;
  final Map<String, StoryLineHit> keywordOf;
  List<RecordHit> records = const [];

  /// Score of the game's closest passage (−∞ without vectors).
  final double best;

  /// Story lines the keywords hit, over the stories found.
  final int lines;
}
