part of '../lore_tools.dart';

/// `grep`: lines containing words, in some chapters or across the corpus.
class GrepTool extends AgentTool {
  GrepTool(this.store, this.seen, {this.ledger});

  final GameDataRetrieval store;
  final SeenLines seen;
  final ContextLedger? ledger;

  static const int defaultHits = 60;
  static const int maxHits = 150;

  /// Stories listed by a corpus-wide count; a major character appears in
  /// ~100–150 (the later ones are often what a question is about).
  static const int maxStoriesListed = 160;

  @override
  String get name => 'grep';

  @override
  String get description => '在剧情台词里找包含某些词的行（正文或说话人，子串匹配，多个词用 | 分隔表示“任一”）。'
      '给 story_ids 或 collection 时返回命中行及上下文；都不给时在全库统计每个故事的命中行数'
      '（只给分布，不给原文：先按故事集汇总，再逐章列出；不给 game 时统计所有已安装的游戏）。';

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
            'description':
                '只在这些故事文件里找（完整的 story_id；不存在的文件会报 0 行；同时给了 collection 时以这里为准）',
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
            '${index.isEmpty ? collectionNotFoundHint : '名字相近的故事集：${index.take(10).map((c) => '${c.label}（${c.id}）').join('、')}。'}';
      }
      // With both given the files are the scope (0.14 live: the model named
      // three chapters and their collection, and got the whole collection
      // from its first chapter each time).
      if (storyIds.isEmpty) {
        scopeLabel = collection.label;
        storyIds = [for (final e in collection.entries) e.storyId];
      }
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
    var budgetChars = 0;
    var printedStories = 0;
    final printed = <String, int>{};
    var full = false;
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
      final heading = '## 《${_storyLabel(storyId, entries)}》 $storyId'
          '（${lines.length} 处）';
      final block = StringBuffer()..writeln(heading);
      var originalBlockChars = block.length;
      final blockLines = <StoryLineEntry>[];
      final printedWindows = <List<StoryLineEntry>>[];
      String? truncatedNote;
      readWindows:
      for (final (a, b) in windows) {
        final page = await store.readStoryLines(
          storyId: storyId,
          startLine: a,
          endLine: b,
          maxLines: b - a + 1,
        );
        final windowLines = <StoryLineEntry>[];
        for (final line in page.lines) {
          final mark = hitSet.contains(line.lineIndex) ? '* ' : '  ';
          final text =
              '$mark${formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind)}';
          // Use pre-omission lengths so saved characters cannot add hits or stories.
          if (budgetChars + originalBlockChars + text.length >
                  maxToolResultChars &&
              (printedStories > 0 || blockLines.isNotEmpty)) {
            full = true;
            printedWindows.add(windowLines);
            truncatedNote = '（篇幅已满，后面的行没有列出；继续读用 read_story '
                'story_id=$storyId start=${line.lineIndex}）';
            originalBlockChars += truncatedNote.length + 1;
            break readWindows;
          }
          windowLines.add(line);
          blockLines.add(line);
          originalBlockChars += text.length + 1;
        }
        printedWindows.add(windowLines);
        originalBlockChars += '  …'.length + 1;
      }
      final printedEvidence = <int>{};
      for (final window in printedWindows) {
        final rendered = renderStoryLinesWithContext(
          storyId: storyId,
          lines: window,
          ledger: ledger,
          formatLine: (line) =>
              '${hitSet.contains(line.lineIndex) ? '* ' : '  '}'
              '${formatStoryLine(line.lineIndex, line.speaker, line.content, kind: line.kind)}',
          formatPointer: (note, omitted) =>
              '${omitted.any((line) => hitSet.contains(line.lineIndex)) ? '* ' : '  '}'
              '$note',
        );
        for (final line in rendered.lines) {
          block.writeln(line);
        }
        printedEvidence.addAll(rendered.printedEvidence);
        // A window separator and truncation guide are navigation information.
        if (truncatedNote == null || !identical(window, printedWindows.last)) {
          block.writeln('  …');
        }
      }
      if (truncatedNote != null) block.writeln(truncatedNote);
      budgetChars += originalBlockChars;
      buffer.write(block);
      if (blockLines.isNotEmpty) {
        for (final line in blockLines) {
          if (printedEvidence.contains(line.lineIndex)) {
            seen.addStoryLine(storyId, line);
          }
        }
        printedStories++;
        printed[storyId] =
            blockLines.where((l) => hitSet.contains(l.lineIndex)).length;
      }
      if (full) break;
    }
    buffer.writeln(
      '（* 为命中行${truncated ? '；命中超过 $limit 行，只列出前 $limit 行' : ''}）',
    );
    final text = buffer.toString().trimRight();
    if (!truncated && !full) return text;
    // Where the hits not listed are (0.14 live: with "only the first N"
    // and no way on, the same call was sent again twice).
    final counts = await store.storyLineHitCounts(terms, storyIds: storyIds);
    final rest = [
      for (final id in storyIds.toSet())
        if ((counts[id] ?? 0) > (printed[id] ?? 0))
          '$id ${counts[id]! - (printed[id] ?? 0)} 处',
    ];
    if (rest.isEmpty) return text;
    return '$text\n没有列出的命中：${rest.take(restListed).join('、')}'
        '${rest.length > restListed ? ' 等 ${rest.length} 个故事' : ''}。'
        '要看它们，用 story_ids 指定这些故事再 grep，或用 read_story 读。';
  }

  /// How many stories the note on hits not listed names.
  static const int restListed = 12;

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
      // 0.14: the same counts by collection first — the list below is by
      // chapter, and long.
      final spread = await narrowTo(store, game)
          .termSpread({for (final id in list) id: counts[id]!});
      if (spread != null) {
        buffer.writeln('按故事集：${formatTermSpread(spread)}');
      }
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
