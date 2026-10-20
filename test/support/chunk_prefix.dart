import 'dart:convert';

/// Chunk prefixes (unified refactor, phase 5 P6): a model reads a whole
/// story and writes, for each of its retrieval chunks, one sentence on
/// where the passage is and who talks about what; the chunk is embedded
/// again as `《title》sentence` + its text, so a passage that only makes
/// sense in its story (the place, the people, the matter) can be found by
/// meaning. Experimental: for the recall check, not the knowledge base.

/// The instruction. No names, chapters or story devices (anti-fixture
/// rule): placeholders only.
const String chunkPrefixPrompt = '''
下面是一篇游戏剧情的原文，每行以 L<行号> 开头，方括号里是说话人。原文后面列出了这篇被切成的若干段（行号范围）。
请为每一段写一句话的“定位说明”，供按意思检索时使用：这一段发生在哪里（地点、场合）、谁在场、在谈什么或发生了什么。
可以用全篇提供的背景（比如整篇发生的地点、人物的身份），但只写原文里有的内容，不推测，不评价。
每句不超过 50 字，用原文里的名字与说法，不用“他”“她”指代。

只输出一个 JSON 对象，键是段的行号范围（照抄下面列出的写法），值是那一句话，骨架如下（<> 是占位符）：
{"<起始行号>-<结束行号>": "<地点或场合>，<谁>与<谁><在谈什么或发生了什么>", "<起始行号>-<结束行号>": "<…>"}
''';

/// One story line, as the chunker and the model see it.
typedef PrefixLine = ({int line, String speaker, String content});

/// The story as the model reads it, then the chunks it is to describe.
String chunkPrefixRequest(
  String title,
  List<PrefixLine> lines,
  List<(int, int)> chunks,
) =>
    [
      '《$title》',
      for (final l in lines)
        'L${l.line} ${l.speaker.isEmpty ? '' : '[${l.speaker}] '}${l.content}',
      '',
      '要写说明的段：${[for (final (a, b) in chunks) '$a-$b'].join('、')}',
    ].join('\n');

/// The chunk text as `story_vectors.dart` builds it: `speaker：content` per
/// non-empty line in [first]..[last].
String chunkText(List<PrefixLine> lines, int first, int last) => [
      for (final l in lines)
        if (l.line >= first && l.line <= last && l.content.trim().isNotEmpty)
          l.speaker.trim().isEmpty
              ? l.content.trim()
              : '${l.speaker.trim()}：${l.content.trim()}',
    ].join('\n');

/// The sentences of the model's [reply] by chunk (`first-last`), only for
/// the [chunks] asked about.
Map<String, String> parseChunkPrefixes(String reply, List<(int, int)> chunks) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(reply.substring(start, end + 1));
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  final wanted = {for (final (a, b) in chunks) '$a-$b'};
  return {
    for (final MapEntry(:key, :value) in decoded.entries)
      if (wanted.contains('$key'.replaceAll(' ', '')) &&
          '$value'.trim().isNotEmpty)
        '$key'.replaceAll(' ', ''): '$value'.trim(),
  };
}

/// What is embedded for a chunk: the title and its sentence, then the text.
String prefixedChunkText(String title, String? sentence, String text) =>
    '《$title》${sentence ?? ''}\n$text';
