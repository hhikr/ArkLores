import 'dart:convert';
import 'dart:math' as math;

/// Scene cards (unified refactor, phase 3 P3): one card a story, written by
/// a model that reads the whole story — who is in it, what happens, whose
/// state changes, what is left open — each claim with the lines it comes
/// from. A card only points at lines (S2: a question is matched against
/// the cards by meaning, and the lines they point at are shown); it is
/// never evidence itself.
///
/// Experimental: built for the recall check (`test/live/scene_cards_test.dart`,
/// `recall_eval_test.dart`), not stored in the knowledge base.
class SceneCard {
  const SceneCard({
    required this.storyId,
    required this.title,
    this.people = const [],
    this.events = const [],
    this.changes = const [],
    this.open = const [],
  });

  factory SceneCard.fromJson(Map<String, dynamic> json) => SceneCard(
        storyId: '${json['story_id']}',
        title: '${json['title'] ?? ''}',
        people: [for (final p in json['people'] as List? ?? const []) '$p'],
        events: [
          for (final e in json['events'] as List? ?? const [])
            SceneClaim.fromJson(e as Map<String, dynamic>),
        ],
        changes: [
          for (final e in json['changes'] as List? ?? const [])
            SceneClaim.fromJson(e as Map<String, dynamic>),
        ],
        open: [for (final p in json['open'] as List? ?? const []) '$p'],
      );

  final String storyId;

  /// Collection and story name, as the catalog has them.
  final String title;

  /// Names that occur in the story's lines (checked by [parseSceneCard]).
  final List<String> people;

  /// What happens, two to four sentences.
  final List<SceneClaim> events;

  /// Whose state changes (death, injury, leaving, rescue, identity
  /// revealed…).
  final List<SceneClaim> changes;

  /// What is left open.
  final List<String> open;

  Map<String, dynamic> toJson() => {
        'story_id': storyId,
        'title': title,
        'people': people,
        'events': [for (final e in events) e.toJson()],
        'changes': [for (final e in changes) e.toJson()],
        'open': open,
      };

  /// The text that is embedded for matching by meaning.
  String get embeddingText => [
        title,
        if (people.isNotEmpty) '人物：${people.join('、')}',
        for (final e in events) e.text,
        for (final c in changes) c.text,
        for (final o in open) o,
      ].join('\n');

  /// The line ranges the card points at, merged.
  List<(int, int)> get ranges {
    final all = [
      for (final c in [...events, ...changes]) (c.first, c.last),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in all) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2 + 1) {
        final last = merged.removeLast();
        merged.add((last.$1, math.max(last.$2, r.$2)));
      } else {
        merged.add(r);
      }
    }
    return merged;
  }
}

class SceneClaim {
  const SceneClaim(this.text, this.first, this.last);

  factory SceneClaim.fromJson(Map<String, dynamic> json) => SceneClaim(
        '${json['text']}',
        (json['lines'] as List)[0] as int,
        (json['lines'] as List)[1] as int,
      );

  final String text;
  final int first;
  final int last;

  Map<String, dynamic> toJson() => {
        'text': text,
        'lines': [first, last],
      };
}

/// Lines a claim may point at; a wider range is cut to its start.
const int sceneClaimMaxLines = 30;

/// The instruction for the model that writes a card. No names, chapters or
/// story devices of any kind (anti-fixture rule): placeholders only.
const String sceneCardPrompt = '''
你在为一篇游戏剧情写一张“场景卡”，供检索定位用。只根据下面给出的原文写，不补充原文没有的内容，不推测。
原文每行以 L<行号> 开头，方括号里是说话人。

只输出一个 JSON 对象，骨架如下（<> 是占位符）：
{"people": ["<人名>", "<人名>"],
 "events": [{"text": "<一句话：发生了什么>", "lines": [<起始行号>, <结束行号>]}],
 "changes": [{"text": "<一句话：谁的处境发生了什么变化>", "lines": [<起始行号>, <结束行号>]}],
 "open": ["<一句话：这篇留下、没有解答的问题>"]}

要求：
- people：在这篇里出场或被谈到的人物，名字照原文写法（说话人名或原文里出现的称呼），最多 12 个。
- events：2–4 句，按发生顺序概括这篇里的主要事情，写清谁对谁做了什么、为什么；每句的 lines 是这件事在原文里的行号范围，不超过 $sceneClaimMaxLines 行，挑最能说明这件事的那段。
- changes：这篇里谁的处境变了（死去、受伤、离开、被救、被捕、身份揭露、关系破裂或结成等），没有就写空数组；lines 同上。
- open：这篇留下的悬念或没有交代的事，0–2 句。
- 用原文里的说法与名词，便于按意思检索；每句话独立可读，不用“他”“她”指代上文。
''';

/// The story text as the model reads it: `L<n> [speaker] content`.
String sceneCardStoryText(
  List<({int line, String speaker, String content})> lines,
) =>
    [
      for (final l in lines)
        'L${l.line} ${l.speaker.isEmpty ? '' : '[${l.speaker}] '}${l.content}',
    ].join('\n');

/// The card in the model's [reply], checked against the story: names that
/// do not occur in its [lines] are dropped, claims whose lines are outside
/// the story are dropped, ranges longer than [sceneClaimMaxLines] are cut.
/// Null when the reply holds no card.
SceneCard? parseSceneCard(
  String reply, {
  required String storyId,
  required String title,
  required List<({int line, String speaker, String content})> lines,
}) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(reply.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  if (lines.isEmpty) return null;
  final first = lines.first.line;
  final last = lines.last.line;
  final text = lines.map((l) => '${l.speaker}\n${l.content}').join('\n');

  List<SceneClaim> claims(Object? raw) {
    final out = <SceneClaim>[];
    for (final c in raw is List ? raw : const []) {
      if (c is! Map) continue;
      final t = '${c['text'] ?? ''}'.trim();
      final r = c['lines'];
      if (t.isEmpty || r is! List || r.isEmpty) continue;
      final a = r[0] is num ? (r[0] as num).toInt() : null;
      final b = r.length > 1 && r[1] is num ? (r[1] as num).toInt() : a;
      if (a == null || b == null) continue;
      var lo = math.min(a, b);
      var hi = math.max(a, b);
      if (hi < first || lo > last) continue;
      lo = math.max(lo, first);
      hi = math.min(hi, last);
      if (hi - lo + 1 > sceneClaimMaxLines) hi = lo + sceneClaimMaxLines - 1;
      out.add(SceneClaim(t, lo, hi));
    }
    return out;
  }

  final events = claims(decoded['events']);
  if (events.isEmpty) return null;
  return SceneCard(
    storyId: storyId,
    title: title,
    people: [
      for (final p in {
        for (final p in decoded['people'] is List
            ? decoded['people'] as List
            : const [])
          '$p'.trim(),
      })
        if (p.isNotEmpty && text.contains(p)) p,
    ],
    events: events,
    changes: claims(decoded['changes']),
    open: [
      for (final o in decoded['open'] is List
          ? decoded['open'] as List
          : const [])
        if ('$o'.trim().isNotEmpty) '$o'.trim(),
    ],
  );
}

double cosineSimilarity(List<double> a, List<double> b) {
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na == 0 || nb == 0 ? 0 : dot / math.sqrt(na * nb);
}
