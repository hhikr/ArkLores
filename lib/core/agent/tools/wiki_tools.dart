/// 0.13: the Ask agent's wiki tools — search a game's wiki, read a page as
/// numbered paragraphs. The paragraphs a read shows are recorded in
/// [SeenLines] under the page id, so wiki citations are checked like story
/// citations.
library;

import '../../gamedata/game.dart';
import '../../wiki/wiki_lookup.dart';
import '../../wiki/wiki_page.dart';
import '../lore_tools.dart';
import 'agent_tool.dart';

int? _int(Object? raw) => raw is num ? raw.toInt() : int.tryParse('$raw');

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

Map<String, dynamic> _gameParameter(String description) => {
      'type': 'string',
      'enum': [for (final g in Game.values) g.key],
      'description': description,
    };

/// `wiki_search`: pages of a game's wiki matching a query.
class WikiSearchTool extends AgentTool {
  WikiSearchTool(this.wiki);

  final WikiLookup wiki;

  static const int defaultLimit = 8;
  static const int maxLimit = 15;

  @override
  String get name => 'wiki_search';

  @override
  String get description =>
      '在游戏 Wiki 上搜索页面（明日方舟：PRTS；终末地：Warfarin Wiki），返回页面引用、标题和摘要。'
      '摘要只是线索，正文用 wiki_read 读。需要联网；网络不可用时会说明。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '要找的名字、词或短语'},
          'game': _gameParameter('搜哪个游戏的 Wiki，默认 arknights'),
          'limit': {
            'type': 'integer',
            'description': '最多返回几个页面，默认 $defaultLimit，最多 $maxLimit',
          },
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = '${arguments['query'] ?? ''}'.trim();
    if (query.isEmpty) return '错误：query 为空';
    final game = Game.parse(arguments['game']) ?? Game.arknights;
    final site = WikiSite.of(game);
    final limit =
        (_int(arguments['limit']) ?? defaultLimit).clamp(1, maxLimit);
    final List<WikiSearchHit> hits;
    try {
      hits = await wiki.search(game, query, limit: limit);
    } on WikiUnavailable catch (e) {
      return '$e。请只用本地知识库作答，并在答案里说明没能查 Wiki。';
    }
    if (hits.isEmpty) return '没有找到：${site.label} 上没有与“$query”相关的页面。';
    final buffer = StringBuffer()
      ..writeln('${site.label} 搜索“$query”，${hits.length} 个页面'
          '（格式：页面引用 | 标题 | 摘要；读正文用 wiki_read 的 page 参数填页面引用）：');
    for (final h in hits) {
      buffer.writeln([
        h.ref,
        h.category.isEmpty ? h.title : '${h.title}（${h.category}）',
        if (h.snippet.isNotEmpty) _clip(h.snippet, 160),
      ].join(' | '),);
    }
    return buffer.toString().trimRight();
  }
}

/// `wiki_read`: paragraphs of one wiki page.
class WikiReadTool extends AgentTool {
  WikiReadTool(this.wiki, this.seen);

  final WikiLookup wiki;
  final SeenLines seen;

  static const int defaultCount = 120;
  static const int maxCount = 250;

  @override
  String get name => 'wiki_read';

  @override
  String get description =>
      '读一个 Wiki 页面的正文：从 start 段开始的 count 段（默认 $defaultCount 段）。'
      '每段形如 “P段号 内容”，表格每行一段（单元格用 | 分隔），“## 标题” 行是小节标题（不算段）。'
      '输出开头给出页面 id（含 @ 后的版本），引用时用这个 id 加段号。'
      '给 section 时只读标题包含该词的小节。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'page': {
            'type': 'string',
            'description': '页面引用（wiki_search 结果里的 wiki:… 或 wiki_read 给出的页面 id）或页面标题',
          },
          'game': _gameParameter('page 是标题时，在哪个游戏的 Wiki 上找，默认 arknights'),
          'start': {'type': 'integer', 'description': '起始段号（整数，不带 P），默认 0'},
          'count': {'type': 'integer', 'description': '段数，默认 $defaultCount'},
          'section': {'type': 'string', 'description': '只读标题包含这个词的小节（可选）'},
        },
        'required': ['page'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final ref = '${arguments['page'] ?? ''}'.trim();
    if (ref.isEmpty) return '错误：page 为空';
    final game = Game.parse(arguments['game']);
    final WikiPage? page;
    try {
      page = await wiki.read(ref, game: game);
    } on WikiUnavailable catch (e) {
      return '$e。请只用本地知识库作答，并在答案里说明没能查 Wiki。';
    }
    if (page == null) {
      return '没有这个页面：$ref。可以先用 wiki_search 搜索，再用结果里的页面引用读取。';
    }
    if (page.blocks.isEmpty) return '《${page.title}》没有可读的正文。';
    final start = (_int(arguments['start']) ?? 0).clamp(0, page.blocks.length);
    final count =
        (_int(arguments['count']) ?? defaultCount).clamp(1, maxCount);
    final section = '${arguments['section'] ?? ''}'.trim();
    final picked = <(int, WikiBlock)>[
      for (final (i, b) in page.range(start, page.blocks.length - 1))
        if (section.isEmpty || b.section.contains(section)) (i, b),
    ];
    final buffer = StringBuffer()
      ..writeln('《${page.title}》 ${page.site.label}，共 ${page.blocks.length} 段')
      ..writeln('页面 id：${page.id}（引用写 ["${page.id}", 起始段, 结束段]）')
      ..writeln('网址：${page.url}');
    if (start == 0 && section.isEmpty) {
      final outline = _outline(page);
      if (outline.isNotEmpty) buffer.writeln('小节：$outline');
    }
    if (picked.isEmpty) {
      buffer.writeln(section.isEmpty
          ? '（P$start 之后没有内容，已到结尾）'
          : '（没有标题包含“$section”的小节）',);
      return buffer.toString().trimRight();
    }
    String? lastSection;
    var shown = 0;
    var last = picked.first.$1;
    for (final (i, block) in picked) {
      if (shown >= count) break;
      final text = 'P$i ${oneLine(block.text)}';
      if (buffer.length + text.length > maxToolResultChars && shown > 0) break;
      if (block.section != lastSection) {
        lastSection = block.section;
        if (block.section.isNotEmpty) buffer.writeln('## ${block.section}');
      }
      buffer.writeln(text);
      seen.add(page.id, i);
      last = i;
      shown++;
    }
    final more = picked.any((p) => p.$1 > last);
    buffer.writeln(more
        ? '（本次到 P$last，后面还有；继续读用 start=${last + 1}${section.isEmpty ? '' : ' 并保留 section'}）'
        : '（到 P$last 为止${section.isEmpty ? '，页面结束' : '，该小节结束'}）',);
    return buffer.toString().trimRight();
  }

  /// The page's sections with their first paragraph: `标题(P12)`.
  static String _outline(WikiPage page) {
    final out = <String>[];
    String? current;
    for (final (i, b) in page.blocks.indexed) {
      if (b.section == current || b.section.isEmpty) continue;
      current = b.section;
      out.add('${_clip(b.section, 20)}(P$i)');
      if (out.length >= 40) {
        out.add('…');
        break;
      }
    }
    return out.join(' ');
  }
}

/// The wiki tools sharing [seen] with the knowledge-base tools.
List<AgentTool> wikiTools(WikiLookup wiki, SeenLines seen) => [
      WikiSearchTool(wiki),
      WikiReadTool(wiki, seen),
    ];
