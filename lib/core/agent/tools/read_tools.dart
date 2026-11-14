part of '../lore_tools.dart';

/// `read_record`: the text of one record outside the story text (an
/// archive, a voice line, a module's story, an item's description).
class ReadRecordTool extends AgentTool {
  ReadRecordTool(this.store, this.seen, {this.ledger});
  final ContextLedger? ledger;

  final GameDataRetrieval store;
  final SeenLines seen;

  /// Characters of text per call.
  static const int pageChars = maxToolResultChars - 400;

  /// Each owner's line of [_ownerSpread], kept for the question: the count
  /// is a scan of every story line.
  final Map<String, Future<String?>> _spreads = {};

  /// 0.14: where the story text says the name of whose record this is, by
  /// collection (the same line `search` writes for a word). The name is the
  /// record's own (`RecordText.owner`, from the table's id), never one found
  /// in its text; none for a name of one character or one no line has. A
  /// hint for where to look: nothing here is read.
  Future<String?> _ownerSpread(RecordText record) {
    final owner = record.owner.trim();
    if (owner.runes.length < 2) return Future.value();
    return _spreads[owner] ??= () async {
      final own = narrowTo(store, gameOfId(record.id));
      final spread =
          await own.termSpread(await own.storyLineHitCounts([owner]));
      return spread == null ? null : '“$owner”在剧情里：${formatTermSpread(spread)}';
    }();
  }

  @override
  String get name => 'read_record';

  @override
  String get description => '读取一条剧情以外的资料（档案、语音、模组故事、物品与敌人的描述等）的全文：'
      'id 是检索结果或查询结果里的记录 id（record: 后面的部分）。'
      '开头一行写它的标题、类别和所属对象（这条语音是谁的、这个模组是谁的）；'
      '有所属对象时下一行写这个名字在剧情里出现在哪些故事集（只是去哪里找的线索）。'
      '很长的资料分页给出，按提示用 start 接着读。读过的资料可以作出处（record:<id>）。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': '记录 id'},
          'start': {'type': 'integer', 'description': '从第几个字开始，默认 0'},
        },
        'required': ['id'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final id =
        '${arguments['id'] ?? ''}'.trim().replaceFirst(_recordPrefix, '');
    if (id.isEmpty) return '缺少参数 id：写检索结果里 record: 后面的记录 id。';
    if ((_int(arguments['start']) ?? 0) <= 0 &&
        (ledger?.recordInContext(id) ?? false)) {
      return '$inContextPrefix record:$id 的全文仍在上文（${contextStep(ledger!.stepOfRecord(id)!)}的结果），没有重新读取。';
    }
    final record = await store.readRecord(id);
    if (record == null) {
      return '没有 id 为 $id 的资料。id 要与检索或查询结果里的完全一致；'
          '按名字找资料用 search，按条件找用 sql 查 normalized_records / entity_documents。';
    }
    final text = record.content;
    final start = (_int(arguments['start']) ?? 0).clamp(0, text.length);
    final end =
        start + pageChars > text.length ? text.length : start + pageChars;
    final kind = record.subtype.isEmpty || record.subtype == record.category
        ? record.category
        : '${record.category}·${record.subtype}';
    // Whole only when every character was shown in this call.
    seen.addRecord(id, partial: start > 0 || end < text.length);
    return [
      'record:$id | $kind | ${record.title}'
          '${record.owner.isEmpty || record.owner == record.title ? '' : ' | 所属：${record.owner}'}',
      if (start == 0)
        if (await _ownerSpread(record) case final spread?) spread,
      text.substring(start, end),
      if (end < text.length)
        '（本页到第 $end 个字，全文 ${text.length} 个字；继续读用 start=$end）'
      else if (start > 0)
        '（到全文末尾，共 ${text.length} 个字）',
    ].join('\n');
  }
}

/// `read_story`: one or more passages of one chapter.
class ReadStoryTool extends AgentTool {
  ReadStoryTool(this.store, this.seen, {this.ledger});
  final ContextLedger? ledger;

  final GameDataRetrieval store;
  final SeenLines seen;

  static const int defaultCount = 200;
  static const int maxCount = 300;

  @override
  String get name => 'read_story';

  @override
  String get description => '读取一个故事文件（章节）的原文：从 start 行开始的 count 行'
      '（默认 $defaultCount 行，最多 $maxCount 行，约一整章）。'
      '每行形如 “L行号 [说话人] 内容”，行号即 story_lines.line_index，引用时使用。'
      '没有 end 参数：想读到某一行，用 count 表示行数。'
      '读一章就一次读完需要的整段，不要几十行接着读；每多一次调用，整段对话都要重发一次。'
      '同一章不相邻的几处用 ranges 一次读；几章都要读时，在同一轮里各调一次。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_id': {
            'type': 'string',
            'description': '故事文件名（story_lines.story_id，完整路径，如查询结果里所示）',
          },
          'start': {'type': 'integer', 'description': '起始行号（整数，不带 L），默认 0'},
          'count': {'type': 'integer', 'description': '连续读取的行数，默认 $defaultCount、最多 $maxCount'},
          'ranges': {
            'type': 'array',
            'description': '同一章不相邻的几处，最多四段 [[start, count], ...]；第二项是行数，不是结束行；给了 ranges 就不看 start、count，合计最多 $maxCount 行',
            'minItems': 1,
            'maxItems': 4,
            'items': {
              'type': 'array',
              'minItems': 2,
              'maxItems': 2,
              'items': {'type': 'integer'},
            },
          },
        },
        'required': ['story_id'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    var storyId = '${arguments['story_id'] ?? ''}'.trim();
    if (storyId.isEmpty) return '错误：story_id 为空';
    if (!storyId.endsWith('.txt')) storyId = '$storyId.txt';
    if (hasStoryReadRanges(arguments['ranges'])) {
      if (!validStoryReadRanges(arguments['ranges'])) {
        return '错误：$storyReadRangesError';
      }
      return _readRanges(storyId, storyReadRanges(arguments['ranges'] as List));
    }
    final start = (_int(arguments['start']) ?? 0).clamp(0, 1 << 30);
    final count = (_int(arguments['count']) ?? defaultCount).clamp(1, maxCount);
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
    final printable = <StoryLineEntry>[];
    var chars = buffer.length;
    for (final line in page.lines) {
      final text = formatStoryLine(
        line.lineIndex,
        line.speaker,
        line.content,
        kind: line.kind,
      );
      if (chars + text.length > maxToolResultChars && printable.isNotEmpty) {
        break;
      }
      printable.add(line);
      chars += text.length + 1;
    }
    final deduped = renderStoryLinesWithContext(
      storyId: storyId,
      lines: printable,
      ledger: ledger,
      formatLine: (line) => formatStoryLine(
        line.lineIndex,
        line.speaker,
        line.content,
        kind: line.kind,
      ),
      requireSavings: false,
    );
    if (deduped.allEvidenceInContext) {
      final first = deduped.firstLine!;
      final last = deduped.lastLine!;
      final more = last < page.lines.last.lineIndex || page.hasMore;
      return '$inContextPrefix L$first–L$last 的原文仍在上文（${deduped.steps}的结果），没有重新读取。'
          '${more ? '直接使用上文；要读后面的内容用 start=${last + 1}。' : '这一章到 L$last 结束。'}';
    }
    final last = printable.last.lineIndex;
    for (final line in deduped.lines) {
      buffer.writeln(line);
    }
    for (final line in printable) {
      if (deduped.printedEvidence.contains(line.lineIndex)) {
        seen.addStoryLine(storyId, line);
      }
    }
    final more = last < page.lines.last.lineIndex || page.hasMore;
    buffer.writeln(
      more ? '（本页到 L$last，后面还有；继续读用 start=${last + 1}）' : '（到 L$last 为止，本章结束）',
    );
    return buffer.toString().trimRight();
  }

  Future<String> _readRanges(String storyId, List<(int, int)> ranges) async {
    final entries = await store.storyCatalogEntries([storyId]);
    final header = '《${_storyLabel(storyId, entries)}》 $storyId';
    final selected = <List<StoryLineEntry>>[];
    final pending = <(int, int)>[];
    // Budget against full source text, before context omission, as for one page.
    var chars = header.length + 1;
    var remaining = maxCount;
    var stopped = false;
    for (final range in ranges) {
      if (stopped) {
        pending.add(range);
        continue;
      }
      final page = await store.readStoryLines(
        storyId: storyId,
        startLine: range.$1,
        endLine: range.$2 - 1,
        maxLines: maxCount,
      );
      if (!page.storyFound) {
        // Preserve the existing missing-id suggestions.
        return execute({'story_id': storyId, 'start': range.$1});
      }
      final part = <StoryLineEntry>[];
      for (final line in page.lines) {
        final text = formatStoryLine(
          line.lineIndex,
          line.speaker,
          line.content,
          kind: line.kind,
        );
        final gapChars = part.isEmpty && selected.isNotEmpty
            ? '（L${selected.last.last.lineIndex + 1}–L${line.lineIndex - 1} 未读）'
                    .length +
                1
            : 0;
        if (remaining == 0 ||
            (chars + gapChars + text.length > maxToolResultChars &&
                selected.isNotEmpty) ||
            (chars + gapChars + text.length > maxToolResultChars &&
                part.isNotEmpty)) {
          pending.add((line.lineIndex, range.$2));
          stopped = true;
          break;
        }
        chars += gapChars;
        part.add(line);
        chars += text.length + 1;
        remaining--;
      }
      if (part.isNotEmpty) selected.add(part);
      if (!stopped && page.hasMore) {
        pending.add((page.lines.last.lineIndex + 1, range.$2));
        stopped = true;
      }
    }
    if (selected.isEmpty) {
      return '$storyId 在所选范围内没有内容（已到结尾）。';
    }
    final rendered = [
      for (final part in selected)
        renderStoryLinesWithContext(
          storyId: storyId,
          lines: part,
          ledger: ledger,
          formatLine: (line) => formatStoryLine(
            line.lineIndex,
            line.speaker,
            line.content,
            kind: line.kind,
          ),
          requireSavings: false,
        ),
    ];
    final allInContext = rendered.every((r) => r.allEvidenceInContext);
    final buffer = StringBuffer();
    if (allInContext) buffer.write('$inContextPrefix ');
    buffer.writeln(header);
    for (var i = 0; i < selected.length; i++) {
      if (i > 0) {
        final from = selected[i - 1].last.lineIndex + 1;
        final to = selected[i].first.lineIndex - 1;
        if (from <= to) buffer.writeln('（L$from–L$to 未读）');
      }
      buffer.writeln(rendered[i].lines.join('\n'));
      for (final line in selected[i]) {
        if (rendered[i].printedEvidence.contains(line.lineIndex)) {
          seen.addStoryLine(storyId, line);
        }
      }
    }
    if (pending.isNotEmpty) {
      buffer.writeln('（篇幅已满，剩余范围未读：'
          '${pending.map((r) => 'L${r.$1}–L${r.$2 - 1}（start=${r.$1}, count=${r.$2 - r.$1}）').join('；')}；按顺序接着读）');
    } else {
      // Say whether the chapter goes on, as a single page does.
      final last = selected.last.last.lineIndex;
      final next = await store.readStoryLines(
        storyId: storyId,
        startLine: last + 1,
        maxLines: 1,
      );
      final tail = next.lines.isNotEmpty
          ? '本章在 L$last 之后还有；继续读用 start=${last + 1}'
          : '这一章到 L$last 结束';
      buffer.writeln(allInContext
          ? '（所选范围的原文仍在上文，没有重新读取；$tail）'
          : '（所选范围已读完；$tail）',);
    }
    return buffer.toString().trimRight();
  }
}
