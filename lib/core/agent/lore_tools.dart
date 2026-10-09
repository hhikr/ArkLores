/// R17: the tools of the story agent ([LoreAgentLoop]).
///
/// Modelled on what general agents did with the bare knowledge DB: look at
/// the whole corpus with one query (`sql`, `grep` without a scope), then read
/// chapters whole (`read_story`) and search inside them (`grep` with a
/// scope). Every tool returns plain text written for the model; zero hits are
/// stated as such, with near names when a name may be misspelled.
///
/// Tools record the story lines they show in a [SeenLines] log; answer
/// citations are checked against it.
library;

import 'dart:convert';

import '../gamedata/game_retrieval.dart';
import '../gamedata/multi_game_retrieval.dart';
import '../llm/embedding_client.dart';
import '../wiki/wiki_lookup.dart';
import 'tools/agent_tool.dart';
import 'tools/observation_data.dart' show dataBlockPrefix;
import 'tools/search_story_lines.dart';
import 'tools/search_tool.dart';

/// Story lines shown to the model in this run (per story, line indexes),
/// and ids of other records (`normalized_records` …) a query returned.
class SeenLines {
  final Map<String, Set<int>> _lines = {};
  final Set<String> _records = {};

  void addRecord(String id) => _records.add(id);

  bool hasRecord(String id) => _records.contains(id);

  void add(String storyId, int line) =>
      _lines.putIfAbsent(storyId, () => <int>{}).add(line);

  void addRange(String storyId, int first, int last) {
    final set = _lines.putIfAbsent(storyId, () => <int>{});
    for (var i = first; i <= last; i++) {
      set.add(i);
    }
  }

  /// Whether every line of `first..last` was shown.
  bool covers(String storyId, int first, int last) {
    final set = _lines[storyId];
    if (set == null) return false;
    for (var i = first; i <= last && i - first < 1000; i++) {
      if (!set.contains(i)) return false;
    }
    return true;
  }

  bool get isEmpty => _lines.isEmpty && _records.isEmpty;

  /// Adds everything [other] saw (a sub-agent's reading counts as read).
  void addAll(SeenLines other) {
    for (final MapEntry(key: story, value: lines) in other._lines.entries) {
      _lines.putIfAbsent(story, () => <int>{}).addAll(lines);
    }
    _records.addAll(other._records);
  }

  /// Stories with at least one shown line.
  Iterable<String> get stories => _lines.keys;
}

/// Most characters a tool result may hand back (≈ 200 story lines). 0.14:
/// halved from 16000 — every result is sent again with each later turn, so
/// its size is paid many times; a longer chapter is read in pages.
const int maxToolResultChars = 8000;

/// [text] on one line: its line breaks shown as ` / `.
String oneLine(String text) =>
    text.contains('\n') ? text.split('\n').where((l) => l.isNotEmpty).join(' / ') : text;

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

/// One story line as the tools print it: `L12 [阿米娅] 内容`. Lines that are
/// not dialogue or narration carry their kind instead: `L40 [字幕] 内容`.
/// A line with line breaks of its own (a letter, a poem) stays on one
/// printed line, its breaks shown as ` / `, so every printed line starts
/// with its `L` number.
String formatStoryLine(
  int index,
  String? speaker,
  String content, {
  String? kind,
}) {
  final label = speaker == null || speaker.trim().isEmpty
      ? storyKindLabel(kind)
      : speaker;
  final who = label == null || label.trim().isEmpty ? '' : '[$label] ';
  return 'L$index $who${oneLine(content)}';
}

/// Readable chapter name for [storyId] from [entries] (path-derived when the
/// catalog lacks it).
String _storyLabel(String storyId, Map<String, StoryCatalogEntry> entries) =>
    entries[storyId]?.label ?? fallbackStoryLabel(storyId);

/// Names that a zero-hit search may have misspelled: near names from the DB
/// (R15 string similarity, never an identity claim).
Future<String> _nearNamesHint(
  GameDataRetrieval store,
  Iterable<String> terms,
) async {
  final hints = <String>[];
  for (final term in terms.toSet()) {
    if (term.runes.length < 2 || term.runes.length > 12) continue;
    final similar = await store.similarNames(term, limit: 5);
    final line = describeSimilarNames(term, similar);
    if (line != null) hints.add(line);
  }
  return hints.join('\n');
}

/// Reads a JSON argument as a list of strings (accepts one string too).
List<String> _stringList(Object? raw) {
  if (raw is String) {
    return [
      for (final part in raw.split(RegExp(r'[,，\n]')))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
  if (raw is List) {
    return [
      for (final item in raw)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }
  return const [];
}

int? _int(Object? raw) => raw is num ? raw.toInt() : int.tryParse('$raw');

/// The `game` argument of a tool: which game's knowledge base to use.
Map<String, dynamic> _gameParameter(String description) => {
      'type': 'string',
      'enum': [for (final g in Game.values) g.key],
      'description': description,
    };

/// `sql`: one read-only query over the whole knowledge DB.
class SqlTool extends AgentTool {
  SqlTool(this.store, this.seen);

  final GameDataRetrieval store;
  final SeenLines seen;

  static const int maxRows = 200;

  @override
  String get name => 'sql';

  @override
  String get description =>
      '对一个游戏的知识库执行一条只读 SQL（SQLite 语法，只能是 SELECT/WITH）。'
      '适合做全局统计和定位，例如按 story_id 统计某个名字出现的行数并关联 story_catalog 排序，'
      '或在 entities / entity_aliases / story_lines.speaker 里模糊查名字。'
      '两个游戏的库表结构相同、各是一个文件，一条 SQL 只查其中一个（game 参数）。'
      '最多返回 $maxRows 行；超过时请加条件、聚合或 LIMIT。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '一条 SELECT 或 WITH 语句'},
          'game': _gameParameter('查哪个游戏的库，默认 arknights'),
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = '${arguments['query'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：query 为空';
    final game = Game.parse(arguments['game']);
    final result = await store.readOnlySql(query, maxRows: maxRows, game: game);
    if (result.error != null) {
      return '${result.error!}${await _columnsHint(query, result.error!, game)}';
    }
    if (result.rows.isEmpty) {
      final terms = [
        for (final m in RegExp(r"LIKE\s+'%?([^'%_]+)%?'", caseSensitive: false)
            .allMatches(query))
          m.group(1)!,
      ];
      final hint = await _nearNamesHint(narrowTo(store, game), terms);
      return '0 行。${hint.isEmpty ? '' : '\n$hint'}';
    }
    final columns = result.columns;
    final storyCol = columns.indexOf('story_id');
    final lineCol = columns.indexOf('line_index');
    final idCol = columns.indexOf('id');
    final buffer = StringBuffer()..writeln(columns.join(' | '));
    var shown = 0;
    for (final row in result.rows) {
      final text = row.map((v) => _clip('${v ?? ''}', 400)).join(' | ');
      if (buffer.length + text.length > maxToolResultChars) break;
      buffer.writeln(text);
      shown++;
      if (storyCol >= 0 && lineCol >= 0) {
        final line = _int(row[lineCol]);
        if (line != null) seen.add('${row[storyCol]}', line);
      }
      // A record shown with its id can be cited as `record:<id>`.
      if (idCol >= 0 && row[idCol] != null) seen.addRecord('${row[idCol]}');
    }
    if (shown < result.rows.length || result.truncated) {
      buffer.writeln(
        '（只显示前 $shown 行${result.truncated ? '，结果超过 $maxRows 行' : ''}；'
        '需要更多请加条件、聚合或分页）',
      );
    } else {
      buffer.writeln('（共 $shown 行）');
    }
    return buffer.toString().trimRight();
  }

  /// 0.14: after a wrong column or table, the real columns of the tables
  /// the query names, so the next try does not guess again.
  Future<String> _columnsHint(String query, String error, Game? game) async {
    if (!error.contains('no such column') && !error.contains('no such table')) {
      return '';
    }
    final tables = <String>{
      for (final m in RegExp(r'\b(?:FROM|JOIN)\s+([A-Za-z_][A-Za-z0-9_]*)',
              caseSensitive: false,)
          .allMatches(query))
        m.group(1)!,
    };
    final lines = <String>[];
    for (final table in tables.take(4)) {
      final columns = await store.readOnlySql(
        "SELECT name FROM pragma_table_info('$table')",
        maxRows: 60,
        game: game,
      );
      if (columns.error != null) continue;
      lines.add(
        columns.rows.isEmpty
            ? '没有表 $table'
            : '$table 的列：${columns.rows.map((r) => r.first).join(', ')}',
      );
    }
    if (error.contains('no such table') || lines.isEmpty) {
      final all = await store.readOnlySql(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
        "AND name NOT LIKE '%fts%' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        maxRows: 80,
        game: game,
      );
      if (all.error == null) {
        lines.add('可用的表：${all.rows.map((r) => r.first).join(', ')}');
      }
    }
    return lines.isEmpty ? '' : '\n${lines.join('\n')}';
  }
}

/// `read_story`: consecutive lines of one chapter.
class ReadStoryTool extends AgentTool {
  ReadStoryTool(this.store, this.seen);

  final GameDataRetrieval store;
  final SeenLines seen;

  static const int defaultCount = 200;
  static const int maxCount = 300;

  @override
  String get name => 'read_story';

  @override
  String get description =>
      '读取一个故事文件（章节）的原文：从 start 行开始的 count 行'
      '（默认 $defaultCount 行，最多 $maxCount 行，约一整章）。'
      '每行形如 “L行号 [说话人] 内容”，行号即 story_lines.line_index，引用时使用。'
      '没有 end 参数：想读到某一行，用 count 表示行数。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_id': {
            'type': 'string',
            'description': '故事文件名（story_lines.story_id，完整路径，如查询结果里所示）',
          },
          'start': {'type': 'integer', 'description': '起始行号（整数，不带 L），默认 0'},
          'count': {'type': 'integer', 'description': '行数，默认 $defaultCount'},
        },
        'required': ['story_id'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    var storyId = '${arguments['story_id'] ?? ''}'.trim();
    if (storyId.isEmpty) return '错误：story_id 为空';
    if (!storyId.endsWith('.txt')) storyId = '$storyId.txt';
    final start = (_int(arguments['start']) ?? 0).clamp(0, 1 << 30);
    final count =
        (_int(arguments['count']) ?? defaultCount).clamp(1, maxCount);
    final page = await store.readStoryLines(
      storyId: storyId,
      startLine: start,
      maxLines: count,
    );
    if (!page.storyFound) {
      // Level codes are not zero-padded (`16-7`), file numbers are (`16-07`).
      final code = RegExp(r'(\d+-\d+|[A-Z]+-\d+)')
          .firstMatch(storyId)
          ?.group(1)
          ?.replaceAllMapped(
            RegExp(r'(^|-)0+(\d)'),
            (m) => '${m.group(1)}${m.group(2)}',
          );
      final similar = code == null
          ? const <StoryCatalogEntry>[]
          : await store.storiesByCode(code);
      return '没有这个 story_id：$storyId。'
          '${similar.isEmpty ? '' : '关卡号 $code 的章节：${similar.map((e) => '${e.storyId}《${e.label}》').join('；')}。'}'
          '可以用 sql 在 story_catalog 里按 collection_name / story_code / story_name 查真实的 story_id。';
    }
    if (page.lines.isEmpty) {
      return '$storyId 在 L$start 之后没有内容（已到结尾）。';
    }
    final entries = await store.storyCatalogEntries([storyId]);
    final buffer = StringBuffer()
      ..writeln('《${_storyLabel(storyId, entries)}》 $storyId');
    var last = start;
    for (final line in page.lines) {
      final text = formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind);
      if (buffer.length + text.length > maxToolResultChars &&
          line.lineIndex > page.lines.first.lineIndex) {
        break;
      }
      buffer.writeln(text);
      last = line.lineIndex;
    }
    seen.addRange(storyId, page.lines.first.lineIndex, last);
    final more = last < page.lines.last.lineIndex || page.hasMore;
    buffer.writeln(
      more ? '（本页到 L$last，后面还有；继续读用 start=${last + 1}）' : '（到 L$last 为止，本章结束）',
    );
    return buffer.toString().trimRight();
  }
}

/// `grep`: lines containing words, in some chapters or across the corpus.
class GrepTool extends AgentTool {
  GrepTool(this.store, this.seen);

  final GameDataRetrieval store;
  final SeenLines seen;

  static const int defaultHits = 60;
  static const int maxHits = 150;
  /// Stories listed by a corpus-wide count; a major character appears in
  /// ~100–150 (the later ones are often what a question is about).
  static const int maxStoriesListed = 160;

  @override
  String get name => 'grep';

  @override
  String get description =>
      '在剧情台词里找包含某些词的行（正文或说话人，子串匹配，多个词用 | 分隔表示“任一”）。'
      '给 story_ids 或 collection 时返回命中行及上下文；都不给时在全库统计每个故事的命中行数'
      '（只给分布，不给原文；不给 game 时统计所有已安装的游戏）。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': '要找的词，多个用 | 分隔，例如 名字|别名',
          },
          'story_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '只在这些故事文件里找（完整的 story_id；不存在的文件会报 0 行）',
          },
          'collection': {
            'type': 'string',
            'description': '只在这个故事集里找（故事集名字或 collection_id，主线某章形如 main_<章>）',
          },
          'context': {
            'type': 'integer',
            'description': '每个命中前后各带几行，默认 2，最多 8',
          },
          'max_hits': {
            'type': 'integer',
            'description': '最多返回多少命中行，默认 $defaultHits，最多 $maxHits',
          },
          'game': _gameParameter('只在这个游戏里找（可选，默认所有已安装的游戏）'),
        },
        'required': ['pattern'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) =>
      _run(narrowTo(store, Game.parse(arguments['game'])), arguments);

  Future<String> _run(
    GameDataRetrieval store,
    Map<String, dynamic> arguments,
  ) async {
    final terms = [
      for (final t in '${arguments['pattern'] ?? ''}'.split('|'))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (terms.isEmpty) return '错误：pattern 为空';
    var storyIds = _stringList(arguments['story_ids'])
        .map((id) => id.endsWith('.txt') ? id : '$id.txt')
        .toList();
    final collectionQuery = '${arguments['collection'] ?? ''}'.trim();
    String? scopeLabel;
    if (collectionQuery.isNotEmpty) {
      final collection = await store.storyCollection(collectionQuery);
      if (collection == null || collection.entries.isEmpty) {
        final index = await store.storyCollectionIndex(like: collectionQuery);
        return '没有找到故事集“$collectionQuery”。'
            '${index.isEmpty ? '可以用 sql 查 story_catalog 的 collection_name / collection_id。' : '名字相近的故事集：${index.take(10).map((c) => '${c.label}（${c.id}）').join('、')}。'}';
      }
      scopeLabel = collection.label;
      storyIds = [
        ...storyIds,
        for (final e in collection.entries) e.storyId,
      ];
    }
    if (storyIds.isEmpty) return _corpusCounts(store, terms);
    final context = (_int(arguments['context']) ?? 2).clamp(0, 8);
    final limit =
        (_int(arguments['max_hits']) ?? defaultHits).clamp(1, maxHits);
    final hits =
        await store.grepStoryLines(terms, storyIds: storyIds, limit: limit + 1);
    if (hits.isEmpty) {
      final hint = await _nearNamesHint(store, terms);
      return '0 行：${scopeLabel ?? '${storyIds.length} 个故事'}里没有 ${terms.join(' / ')}。'
          '${hint.isEmpty ? '' : '\n$hint'}';
    }
    final truncated = hits.length > limit;
    final shown = truncated ? hits.sublist(0, limit) : hits;
    final byStory = <String, List<int>>{};
    for (final hit in shown) {
      byStory.putIfAbsent(hit.storyId, () => []).add(hit.lineIndex);
    }
    final entries = await store.storyCatalogEntries(byStory.keys);
    final buffer = StringBuffer();
    var printedStories = 0;
    for (final MapEntry(key: storyId, value: lines) in byStory.entries) {
      final hitSet = lines.toSet();
      // Merge each hit's context window with its neighbours.
      final windows = <(int, int)>[];
      for (final line in lines) {
        final a = (line - context).clamp(0, 1 << 30);
        final b = line + context;
        if (windows.isNotEmpty && a <= windows.last.$2 + 1) {
          windows[windows.length - 1] = (windows.last.$1, b);
        } else {
          windows.add((a, b));
        }
      }
      final block = StringBuffer()
        ..writeln('## 《${_storyLabel(storyId, entries)}》 $storyId'
            '（${lines.length} 处）');
      for (final (a, b) in windows) {
        final page = await store.readStoryLines(
          storyId: storyId,
          startLine: a,
          endLine: b,
          maxLines: b - a + 1,
        );
        for (final line in page.lines) {
          final mark = hitSet.contains(line.lineIndex) ? '* ' : '  ';
          block.writeln(
            '$mark${formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind)}',
          );
          seen.add(storyId, line.lineIndex);
        }
        block.writeln('  …');
      }
      if (buffer.length + block.length > maxToolResultChars &&
          printedStories > 0) {
        buffer.writeln('（篇幅已满，后面的故事没有列出；请缩小范围或调小 context）');
        break;
      }
      buffer.write(block);
      printedStories++;
    }
    buffer.writeln(
      '（* 为命中行${truncated ? '；命中超过 $limit 行，只列出前 $limit 行，可加 max_hits 或缩小范围' : ''}）',
    );
    return _clip(buffer.toString().trimRight(), maxToolResultChars + 200);
  }

  /// Hit counts per story over the whole corpus, main story first, then by
  /// release.
  Future<String> _corpusCounts(
    GameDataRetrieval store,
    List<String> terms,
  ) async {
    final counts = await store.storyLineHitCounts(terms);
    if (counts.isEmpty) {
      final hint = await _nearNamesHint(store, terms);
      return '0 行：全库没有包含 ${terms.join(' / ')} 的台词。'
          '${hint.isEmpty ? '' : '\n$hint'}';
    }
    final entries = await store.storyCatalogEntries(counts.keys);
    (int, int, int, String) key(String id) {
      final e = entries[id];
      if (e == null) return (3, 0, 0, id);
      if (e.collectionType == 'MAINLINE') {
        final n = int.tryParse(
              RegExp(r'(\d+)').firstMatch(e.collectionId)?.group(1) ?? '',
            ) ??
            0;
        return (0, n, e.storySort, id);
      }
      final t = e.startTime ?? 0;
      return (t > 0 ? 1 : 2, t, e.storySort, id);
    }

    final ids = counts.keys.toList()
      ..sort((x, y) {
        final a = key(x);
        final b = key(y);
        for (final c in [
          a.$1.compareTo(b.$1),
          a.$2.compareTo(b.$2),
          a.$3.compareTo(b.$3),
        ]) {
          if (c != 0) return c;
        }
        return a.$4.compareTo(b.$4);
      });
    final total = counts.values.fold<int>(0, (n, c) => n + c);
    // 0.14: one part per game, each with its own totals first, so a game
    // with few hits is not lost at the end of a long list.
    final byGame = <Game, List<String>>{};
    for (final id in ids) {
      byGame.putIfAbsent(gameOfId(id), () => []).add(id);
    }
    final buffer = StringBuffer()
      ..writeln('全库共 $total 行命中，分布在 ${ids.length} 个故事'
          '${byGame.length > 1 ? '（${[
              for (final MapEntry(key: g, value: list) in byGame.entries)
                '${g.label} ${list.fold<int>(0, (n, id) => n + counts[id]!)} 行 / ${list.length} 个故事',
            ].join('；')}）' : ''}'
          '（主线在前，其余按上线时间；格式：story_id | 章节 | 命中行数）：');
    final perGame = byGame.length > 1
        ? (maxStoriesListed / byGame.length).floor()
        : maxStoriesListed;
    for (final MapEntry(key: game, value: list) in byGame.entries) {
      if (byGame.length > 1) buffer.writeln('## ${game.label}');
      var listed = 0;
      for (final id in list) {
        if (listed >= perGame) {
          buffer.writeln('……还有 ${list.length - listed} 个故事未列出；'
              '可用 sql 按需要的条件统计。');
          break;
        }
        buffer.writeln('$id | ${_storyLabel(id, entries)} | ${counts[id]}');
        listed++;
      }
    }
    buffer.writeln('（这里只是分布；读原文用 read_story，或带 story_ids 再 grep）');
    return buffer.toString().trimRight();
  }
}

/// `outline`: the chapters of a story collection with official synopses.
class OutlineTool extends AgentTool {
  OutlineTool(this.store);

  final GameDataRetrieval store;

  @override
  String get name => 'outline';

  @override
  String get description =>
      '列出一个故事集（活动 / 主线章节 / 干员密录）的全部章节：story_id、关卡号、章名和官方梗概。'
      '梗概只用于定位，不能当证据。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'collection': {
            'type': 'string',
            'description': '故事集名字或 collection_id，也可以是其中一个 story_id',
          },
        },
        'required': ['collection'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = '${arguments['collection'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：collection 为空';
    final collection = await store.storyCollection(query);
    if (collection == null || collection.entries.isEmpty) {
      final index = await store.storyCollectionIndex(like: query);
      return '没有找到故事集“$query”。'
          '${index.isEmpty ? '可以用 sql 查 story_catalog。' : '名字相近的故事集：${index.take(10).map((c) => '${c.label}（${c.id}，${c.chapters} 章）').join('、')}。'}';
    }
    final month = collection.releaseMonth;
    final buffer = StringBuffer()
      ..writeln('${collection.label}（${collection.collectionId}，'
          '${collection.entries.length} 章${month == null ? '' : '，上线 $month'}）');
    for (final e in collection.entries) {
      final synopsis = (e.synopsis ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      buffer.writeln('${e.storyId} | ${e.chapterLabel}'
          '${synopsis.isEmpty ? '' : ' | ${_clip(synopsis, 160)}'}');
      if (buffer.length > maxToolResultChars) {
        buffer.writeln('……（篇幅已满）');
        break;
      }
    }
    return buffer.toString().trimRight();
  }
}

/// `find`: ranked search for a phrase or a described scene — FTS keywords
/// fused with the optional story vectors (R12). 0.14: replaced in the
/// agent's tools by `search` (`tools/search_tool.dart`); kept for callers
/// of the old search output.
class FindTool extends AgentTool {
  FindTool(this._store, this._embeddingClient);

  final GameDataRetrieval _store;
  final EmbeddingClient? _embeddingClient;

  @override
  String get name => 'find';

  @override
  String get description =>
      '按意思找剧情：给一句描述、台词或几个词，返回最相关的故事和其中最相关的几行（关键词检索，'
      '配置了向量模型时再加语义检索）。适合不知道确切用词的场景、事件；知道确切名字时用 grep 更准。'
      '结果只是定位线索，要用 read_story 读原文。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '描述、台词或空格分隔的词'},
          'collection': {'type': 'string', 'description': '只在这个故事集里找（可选）'},
          'game': _gameParameter('只在这个游戏里找（可选，默认所有已安装的游戏）'),
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final store = narrowTo(_store, Game.parse(arguments['game']));
    // The search takes collection ids; resolve a collection name first.
    final collection = '${arguments['collection'] ?? ''}'.trim();
    final scope = collection.isEmpty
        ? null
        : (await store.storyCollection(collection))?.collectionId ?? collection;
    final search = SearchStoryLinesTool(
      gameDataStore: store,
      embeddingClient: _embeddingClient,
    );
    final result = await search.execute({
      'query': arguments['query'],
      if (scope != null) 'scope_id': scope,
    });
    final text = result is ToolExecutionResult ? result.observation : '$result';
    return [
      for (final line in text.split('\n'))
        if (!line.startsWith(dataBlockPrefix))
          // The search speaks the R16 planner's commands.
          line
              .replaceAll('READ', 'read_story')
              .replaceAll('COVER', 'grep')
              .replaceAll('FIND', 'find'),
    ].join('\n').trim();
  }
}

/// `similar_names`: names in the DB spelled or pronounced like a term.
class SimilarNamesTool extends AgentTool {
  SimilarNamesTool(this.store);

  final GameDataRetrieval store;

  @override
  String get name => 'similar_names';

  @override
  String get description =>
      '查库里与某个写法字形或读音相近的名字（人物、说话人、故事集、章节、实体）。'
      '某个名字查不到时用来找正确写法；结果只说明字符串相近。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '查不到的写法'},
        },
        'required': ['name'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final term = '${arguments['name'] ?? ''}'.trim();
    if (term.isEmpty) return '错误：name 为空';
    final similar = await store.similarNames(term, limit: 8);
    if (similar.isEmpty) return '没有找到与“$term”相近的名字。';
    return similar
        .map((s) => '${s.name}（${s.kind}${s.occurrences > 0 ? '，${s.occurrences} 次' : ''}）')
        .join('\n');
  }
}

/// `delegate`: hands one search to a sub-agent with its own conversation
/// (R17 phase 2); several can run in the same turn.
class DelegateTool extends AgentTool {
  DelegateTool(this.runSubtask);

  /// Runs the sub-agent and returns its checked findings.
  final Future<String> Function(Map<String, dynamic> arguments) runSubtask;

  @override
  String get name => 'delegate';

  @override
  String get description =>
      '把一部分查找和阅读交给一个子助手（独立对话，只有查库工具，不占用你的上下文）。'
      '同一轮可以派出多个并行执行，例如按时间阶段或故事集拆分。task 要写清查什么、交回什么；'
      '可用 story_ids 或 collection 限定范围。返回子助手的要点，每点带出处，这些出处已经核对过，可以直接引用。'
      '适合涉及很多章节的问题；只需读一两章时自己读更快。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'task': {'type': 'string', 'description': '交给子助手的任务'},
          'story_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '建议它阅读的故事文件（可选）',
          },
          'collection': {
            'type': 'string',
            'description': '限定的故事集（可选）',
          },
        },
        'required': ['task'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) =>
      runSubtask(arguments);
}

/// The scope hints of a `delegate` call, as text for the sub-agent.
String delegateTaskText(Map<String, dynamic> arguments) {
  final task = '${arguments['task'] ?? ''}'.trim();
  final ids = _stringList(arguments['story_ids']);
  final collection = '${arguments['collection'] ?? ''}'.trim();
  return [
    task,
    if (ids.isNotEmpty) '建议阅读：${ids.join('、')}',
    if (collection.isNotEmpty) '范围：故事集 $collection',
  ].join('\n');
}

/// The story agent's tools, sharing one [SeenLines] log. 0.14: `search`
/// (story text of every game by meaning and names, and the wikis when
/// [wiki] is given) comes first and replaces `find`.
List<AgentTool> loreTools(
  GameDataRetrieval store,
  SeenLines seen, {
  EmbeddingClient? embeddingClient,
  WikiLookup? wiki,
}) =>
    [
      SearchTool(store, seen, embeddingClient: embeddingClient, wiki: wiki),
      ReadStoryTool(store, seen),
      GrepTool(store, seen),
      SqlTool(store, seen),
      OutlineTool(store),
      SimilarNamesTool(store),
    ];

/// Decodes tool-call arguments; malformed JSON becomes an empty map.
Map<String, dynamic> decodeToolArguments(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}
