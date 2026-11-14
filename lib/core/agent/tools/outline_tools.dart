part of '../lore_tools.dart';

/// `outline`: the chapters of a story collection with official synopses.
class OutlineTool extends AgentTool {
  OutlineTool(this.store, {this.seen});

  final GameDataRetrieval store;

  /// Where the synopses shown are registered (they can be cited).
  final SeenLines? seen;

  @override
  String get name => 'outline';

  @override
  String get description =>
      '列出一个故事集（活动 / 主线章节 / 干员密录）的全部章节：story_id、关卡号、章名和官方梗概。'
      '官方梗概可以作出处，写法见结果开头；梗概只有大概经过，细节、台词和人物的态度要读原文。'
      '末尾列出与它相关的其他故事集（共有人物、内容相近），只是找资料的线索。';

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
          '${index.isEmpty ? collectionNotFoundHint : '名字相近的故事集：${index.take(10).map((c) => '${c.label}（${c.id}，${c.chapters} 章）').join('、')}。'}';
    }
    final month = collection.releaseMonth;
    // Written last, and always: the chapters give way to it.
    final related = _related(
      await store.relatedCollections(collection.collectionId),
    );
    final buffer = StringBuffer()
      ..writeln('${collection.label}（${collection.collectionId}，'
          '${collection.entries.length} 章${month == null ? '' : '，上线 $month'}）');
    final cited = collection.entries
        .where((e) => (e.synopsis ?? '').trim().isNotEmpty)
        .firstOrNull;
    if (cited != null) {
      buffer.writeln('（引用一章的官方梗概写 record:<story_id 去掉 .txt>$synopsisRecordSuffix，'
          '如 record:${synopsisRecordId(cited.storyId)}；结尾是“…”的梗概只列出了开头，'
          '全文用 read_record 读）');
    }
    for (final e in collection.entries) {
      final synopsis =
          (e.synopsis ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      buffer.writeln('${e.storyId} | ${e.chapterLabel}'
          '${synopsis.isEmpty ? '' : ' | ${_clip(synopsis, 160)}'}');
      if (synopsis.isNotEmpty) {
        seen?.addRecord(
          synopsisRecordId(e.storyId),
          partial: synopsis.length > 160,
        );
      }
      if (buffer.length + related.length > maxToolResultChars) {
        buffer.writeln('……（篇幅已满）');
        break;
      }
    }
    buffer.write(related);
    return buffer.toString().trimRight();
  }

  /// The section on related collections (empty when there are none): what
  /// each shares with this one, so the model can tell a strong hint from a
  /// weak one.
  static String _related(List<RelatedCollection> related) {
    if (related.isEmpty) return '';
    final near = related.any((r) => r.similarity != null);
    final buffer = StringBuffer()
      ..writeln('相关的故事集（按共有人物${near ? '和内容相近程度' : ''}排列；'
          '只是找资料的线索，是否承接、谁先谁后要读原文确认，上线时间不等于故事里的先后）：');
    for (final r in related) {
      final month = r.releaseMonth;
      buffer.writeln(
        [
          '${r.label}（${r.id}${month == null ? '' : '，上线 $month'}）',
          [
            if (r.shared > 0)
              '共有 ${r.shared} 人：${r.names.join('、')}'
                  '${r.shared > r.names.length ? '…' : ''}',
            if (r.similarity case final s?) '内容相近 ${s.toStringAsFixed(2)}',
          ].join('；'),
        ].join(''),
      );
    }
    return buffer.toString();
  }
}

/// `similar_names`: names in the DB spelled or pronounced like a term.
class SimilarNamesTool extends AgentTool {
  SimilarNamesTool(this.store);

  final GameDataRetrieval store;

  @override
  String get name => 'similar_names';

  @override
  String get description => '查库里与某个写法字形或读音相近的名字（人物、说话人、故事集、章节、实体）。'
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
        .map(
          (s) =>
              '${s.name}（${s.kind}${s.occurrences > 0 ? '，${s.occurrences} 次' : ''}）',
        )
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
  String get description => '把一部分查找和阅读交给一个子助手。子助手在自己的对话里用同样的查找与阅读工具，原始结果不进你的上下文，只交回笔记和出处。'
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
  LinePicker? picker,
  MaterialSnapshot? materials,
  ContextLedger? ledger,
}) {
  final manual = LibraryManual(store);
  final tools = <AgentTool>[
    SearchTool(
      store,
      seen,
      embeddingClient: embeddingClient,
      wiki: wiki,
      materials: materials,
      ledger: ledger,
    ),
    ReadStoryTool(store, seen, ledger: ledger),
    ReadRecordTool(store, seen, ledger: ledger),
    GrepTool(store, seen, ledger: ledger),
    SqlTool(store, seen, manual: manual),
    GuideTool(manual),
    OutlineTool(store, seen: seen),
    SimilarNamesTool(store),
    GatherTool(store, seen, picker: picker, ledger: ledger),
  ];
  if (materials == null || !materials.isAvailable) return tools;
  return [
    for (final tool in tools)
      if (const {'grep', 'gather', 'sql', 'guide'}.contains(tool.name))
        MaterialJoinedTool(tool, materials, seen, ledger: ledger)
      else
        tool,
    ReadMaterialTool(materials, seen, ledger: ledger),
  ];
}

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
