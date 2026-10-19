/// The material for a question, gathered by code before the model reads
/// anything (unified refactor, phase 1: S2–S4).
///
/// The question's anchors (names and nouns it is about) are located in the
/// story text: every line a name speaks or holds. Stories are scored by the
/// anchors they hold — a rarer anchor weighs more, two anchors within a few
/// lines of each other (one scene) weigh most — chosen with a cap per
/// collection so that one long collection does not take all the room, and
/// cut down to the lines around the anchors. What is chosen is printed in
/// the order players could read it ([storyReleaseKey]).
///
/// Every rule is the same for every question and every anchor: no kind of
/// question, name or plot is treated apart (CLAUDE.md R13). The anchors
/// are where the material comes from; which lines answer is the model's
/// reading.
library;

import 'dart:math' as math;

import '../gamedata/game_retrieval.dart';
import 'line_picker.dart';
import 'lore_tools.dart';
import 'tools/agent_tool.dart';

/// One run of lines of a story given as material.
class CoveragePassage {
  CoveragePassage(this.storyId, this.first, this.last, this.lines);

  final String storyId;
  final int first;
  final int last;
  final List<StoryLineEntry> lines;

  int get chars => lines.fold(0, (n, l) => n + l.content.length + 8);
}

/// Where one anchor is in the story text.
class AnchorFootprint {
  const AnchorFootprint(this.anchor, this.lines, this.stories, this.spoken);

  final String anchor;
  final int lines;
  final int stories;

  /// Lines the anchor speaks.
  final int spoken;
}

/// The material [CoverageBuilder.build] gathered.
class Coverage {
  Coverage({
    required this.footprints,
    required this.passages,
    required this.located,
    required this.records,
    required this.labels,
    this.pickedFrom,
  });

  final List<AnchorFootprint> footprints;

  /// Set when [passages] were picked ([LinePicker]) from a wider
  /// gathering: its story count and characters.
  final ({int stories, int chars})? pickedFrom;

  /// This gathering with [picked] lines in place of its passages; the
  /// stories left without a line join [located].
  Coverage withPicked(List<CoveragePassage> picked) {
    final kept = {for (final p in picked) p.storyId};
    return Coverage(
      footprints: footprints,
      passages: picked,
      located: <String>{
        for (final p in passages)
          if (!kept.contains(p.storyId)) p.storyId,
        ...located,
      }.toList(),
      records: records,
      labels: labels,
      pickedFrom: (stories: stories.length, chars: chars),
    );
  }

  /// In reading order: stories by [storyReleaseKey], lines in order.
  final List<CoveragePassage> passages;

  /// Stories that hold an anchor and were not given (best first), for the
  /// list of "located, not given".
  final List<String> located;

  final List<RecordHit> records;

  final Map<String, StoryCatalogEntry> labels;

  int get chars => passages.fold(0, (n, p) => n + p.chars);

  Set<String> get stories => {for (final p in passages) p.storyId};

  /// Records what is given in [seen] (the lines in full, the records as
  /// excerpts).
  void register(SeenLines seen) {
    for (final p in passages) {
      for (final l in p.lines) {
        seen.add(p.storyId, l.lineIndex);
      }
    }
    for (final r in records) {
      seen.addRecord(r.id, partial: true);
    }
  }

  /// The material as the model reads it.
  String render() {
    final b = StringBuffer();
    if (passages.isEmpty && records.isEmpty) {
      b.writeln('没有在剧情和资料里找到这些名字。');
    } else {
      final picked = pickedFrom;
      b.writeln('按名字取材：给了 ${stories.length} 篇剧情的原文（$chars 字）'
          '${records.isEmpty ? '' : '和 ${records.length} 条资料的片段'}。'
          '${picked == null ? '每篇只取这些名字出现、说话的行及前后各两行' : '从这些名字出现的 ${picked.stories} 篇剧情（每处前后八行，共 ${picked.chars} 字）里挑出了与问题相关的行'}，'
          '按上线顺序排列；行号可以直接引用，要看前后更多内容用 read_story。');
    }
    if (footprints.isNotEmpty) {
      b.writeln('锚点在剧情里的位置：${[
        for (final f in footprints)
          f.lines == 0
              ? '${f.anchor}（原文里没有）'
              : '${f.anchor}（${f.stories} 篇 ${f.lines} 行'
                  '${f.spoken == 0 ? '' : '，其中说话 ${f.spoken} 行'}）',
      ].join('；')}');
    }
    if (passages.isNotEmpty) b.writeln(renderPassages(passages, labels));
    if (records.isNotEmpty) {
      b.writeln('## 资料（片段）');
      for (final r in records) {
        b.writeln('record:${r.id} | ${r.title}'
            '${r.owner.isEmpty || r.owner == r.title ? '' : '（${r.owner}）'} | ${r.snippet}');
      }
    }
    if (located.isNotEmpty) {
      b.writeln('定位到、没有给原文的：${[
        for (final s in located.take(maxLocatedListed))
          '《${labels[s]?.label ?? fallbackStoryLabel(s)}》 $s',
      ].join('；')}'
          '${located.length > maxLocatedListed ? '；等 ${located.length} 篇' : ''}');
    }
    return b.toString().trimRight();
  }

  static const int maxLocatedListed = 20;
}

/// [passages] as the model reads them: a heading per story, `…` between
/// runs of one story.
String renderPassages(
  List<CoveragePassage> passages,
  Map<String, StoryCatalogEntry> labels,
) {
  final b = StringBuffer();
  String? story;
  for (final p in passages) {
    if (p.storyId != story) {
      story = p.storyId;
      b.writeln(
          '## 《${labels[story]?.label ?? fallbackStoryLabel(story)}》 $story',);
    } else {
      b.writeln('…');
    }
    for (final l in p.lines) {
      b.writeln(
          formatStoryLine(l.lineIndex, l.speaker, l.content, kind: l.kind),);
    }
  }
  return b.toString().trimRight();
}

class CoverageBuilder {
  CoverageBuilder(this.store);

  final GameDataRetrieval store;

  /// Lines either side of an anchor's line.
  static const int defaultContext = 2;

  /// Two anchors at most this many lines apart are one scene.
  static const int sceneLines = 6;

  /// Stories one collection may give before every collection had its turn.
  static const int perCollection = 3;

  /// Characters one story may give.
  static const int defaultPerStoryChars = 3000;

  static const int maxAnchors = 6;

  static const int recordsGiven = 4;

  /// Gathers material for [anchors] up to [budgetChars] characters.
  /// [hinted]: stories a search already found, which count a little more.
  /// [context] lines either side of each anchor line, at most
  /// [perStoryChars] characters a story.
  Future<Coverage> build(
    List<String> anchors, {
    int budgetChars = 30000,
    Set<String> hinted = const {},
    int context = defaultContext,
    int perStoryChars = defaultPerStoryChars,
  }) async {
    final names = <String>{
      for (final a in anchors)
        if (a.trim().isNotEmpty) a.trim(),
    }.take(maxAnchors).toList();

    // S2: where each anchor is.
    final at = <String, Map<String, List<AnchorLine>>>{};
    final footprints = <AnchorFootprint>[];
    for (final name in names) {
      final lines = await store.anchorLines(name);
      final byStory = <String, List<AnchorLine>>{};
      for (final l in lines) {
        (byStory[l.storyId] ??= []).add(l);
      }
      at[name] = byStory;
      footprints.add(
        AnchorFootprint(
          name,
          lines.length,
          byStory.length,
          lines.where((l) => l.spoken).length,
        ),
      );
    }
    // A rarer anchor says more about where to look.
    final weight = {
      for (final name in names)
        name: 1 / (math.log(2 + at[name]!.length) / math.ln2),
    };

    // S3: score the stories.
    final score = <String, double>{};
    final scenes = <String, List<(int, double)>>{};
    final storyIds = {for (final m in at.values) ...m.keys};
    for (final s in storyIds) {
      var total = hinted.contains(s) ? 0.5 : 0.0;
      final marks = <(int, String)>[];
      for (final name in names) {
        final lines = at[name]![s];
        if (lines == null) continue;
        total += weight[name]! * (1 + math.log(lines.length));
        marks.addAll([for (final l in lines) (l.lineIndex, name)]);
      }
      marks.sort((a, b) => a.$1.compareTo(b.$1));
      // Scenes: a line where another anchor is within [sceneLines] lines.
      final found = <(int, double)>[];
      for (var i = 0; i < marks.length; i++) {
        final here = <String>{marks[i].$2};
        for (var j = i + 1;
            j < marks.length && marks[j].$1 - marks[i].$1 <= sceneLines;
            j++) {
          here.add(marks[j].$2);
        }
        if (here.length > 1) {
          found.add((marks[i].$1, here.fold(0.0, (w, n) => w + weight[n]!)));
        }
      }
      found.sort((a, b) => b.$2.compareTo(a.$2));
      scenes[s] = found;
      total += 2 * found.take(10).fold(0.0, (w, f) => w + f.$2);
      score[s] = total;
    }
    final ranked = storyIds.toList()
      ..sort((a, b) {
        final c = score[b]!.compareTo(score[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    final labels = await store.storyCatalogEntries(ranked);

    // S3–S4: choose stories and their lines, collections taking turns.
    final passages = <CoveragePassage>[];
    final given = <String>{};
    final perCollectionGiven = <String, int>{};
    var chars = 0;
    // Up to [perCollection] stories from each collection, then any.
    for (final cap in [perCollection, null]) {
      for (final s in ranked) {
        if (chars >= budgetChars) break;
        if (given.contains(s)) continue;
        final collection = labels[s]?.collectionId ?? s;
        if (cap != null && (perCollectionGiven[collection] ?? 0) >= cap) {
          continue;
        }
        final centers = [
          for (final f in scenes[s]!) f.$1,
          ..._rarestFirst(s, names, at, weight),
        ];
        final room = math.min(perStoryChars, budgetChars - chars);
        final cut = await _cut(s, centers, room, context);
        if (cut.isEmpty) continue;
        given.add(s);
        perCollectionGiven[collection] =
            (perCollectionGiven[collection] ?? 0) + 1;
        passages.addAll(cut);
        chars += cut.fold(0, (n, p) => n + p.chars);
      }
    }
    passages.sort((a, b) {
      if (a.storyId == b.storyId) return a.first.compareTo(b.first);
      final ea = labels[a.storyId];
      final eb = labels[b.storyId];
      if (ea == null || eb == null) {
        return ea == null && eb == null
            ? a.storyId.compareTo(b.storyId)
            : ea == null
                ? 1
                : -1;
      }
      final c =
          compareStoryReleaseKeys(storyReleaseKey(ea), storyReleaseKey(eb));
      return c != 0 ? c : a.storyId.compareTo(b.storyId);
    });

    final records = names.isEmpty
        ? const <RecordHit>[]
        : await store.searchRecordsLike(
            names,
            limit: recordsGiven,
            weights: weight,
          );
    return Coverage(
      footprints: footprints,
      passages: passages,
      located: [
        for (final s in ranked)
          if (!given.contains(s)) s,
      ],
      records: records,
      labels: labels,
    );
  }

  /// [s]'s anchor lines, the rarest anchor's first.
  static List<int> _rarestFirst(
    String s,
    List<String> names,
    Map<String, Map<String, List<AnchorLine>>> at,
    Map<String, double> weight,
  ) {
    final order = [...names]..sort((a, b) => weight[b]!.compareTo(weight[a]!));
    return [
      for (final name in order)
        for (final l in at[name]![s] ?? const <AnchorLine>[]) l.lineIndex,
    ];
  }

  /// The lines around [centers] (in that order of preference) of [s], at
  /// most [room] characters, as runs in line order.
  Future<List<CoveragePassage>> _cut(
    String s,
    List<int> centers,
    int room,
    int context,
  ) async {
    final wanted = <int>{};
    final texts = <int, StoryLineEntry>{};
    var chars = 0;
    for (final c in centers) {
      if (chars >= room) break;
      final first = math.max(0, c - context);
      final last = c + context;
      final missing = [
        for (var i = first; i <= last; i++)
          if (!wanted.contains(i)) i,
      ];
      if (missing.isEmpty) continue;
      if (!missing.every(texts.containsKey)) {
        final page = await store.readStoryLines(
          storyId: s,
          startLine: first,
          endLine: last,
          maxLines: last - first + 1,
        );
        for (final l in page.lines) {
          texts[l.lineIndex] = l;
        }
      }
      for (final i in missing) {
        final l = texts[i];
        if (l == null) continue;
        wanted.add(i);
        chars += l.content.length + 8;
      }
    }
    final sorted = wanted.toList()..sort();
    final out = <CoveragePassage>[];
    var run = <StoryLineEntry>[];
    for (final i in sorted) {
      if (run.isNotEmpty && i != run.last.lineIndex + 1) {
        out.add(
            CoveragePassage(s, run.first.lineIndex, run.last.lineIndex, run),);
        run = [];
      }
      run.add(texts[i]!);
    }
    if (run.isNotEmpty) {
      out.add(CoveragePassage(s, run.first.lineIndex, run.last.lineIndex, run));
    }
    return out;
  }
}

/// `gather`: [CoverageBuilder] as a tool. The first turn runs it with the
/// names the planning call wrote (`search_planner.dart`); the model may run
/// it again with other names (people it found, say).
class GatherTool extends AgentTool {
  GatherTool(this.store, this.seen, {this.picker});

  final GameDataRetrieval store;
  final SeenLines seen;

  /// Phase 2: when set, the material is gathered wide and the lines that
  /// bear on [question] are picked from it.
  final LinePicker? picker;

  /// The question being answered (for [picker]).
  String question = '';

  /// Characters of story text one call gives.
  static const int budgetChars = 30000;

  /// Characters of the wide gathering [picker] reads, its lines either
  /// side of an anchor line and characters a story.
  static const int wideChars = 120000;
  static const int wideContext = 8;
  static const int widePerStoryChars = 12000;

  @override
  String get name => 'gather';

  @override
  String get description =>
      '按名字取材：给出几个名字（人物、地点、组织、事件、物品在原文里的叫法），'
      '代码在剧情里找到它们出现和说话的行，优先给几个名字同时出现的场景，每个故事集先给几篇，'
      '取每处前后各两行原文（共约 ${budgetChars ~/ 10000} 万字），按上线顺序排列，'
      '末尾列出定位到但没有给原文的篇目和相关资料的片段。名字越少见越能定位；结果很长，不要用它查单个细节。';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '名字，最多 ${CoverageBuilder.maxAnchors} 个',
          },
        },
        'required': ['names'],
      };

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final raw = arguments['names'];
    final names = [
      for (final n in raw is List ? raw : [raw])
        if (n is String && n.trim().isNotEmpty) n.trim(),
    ];
    if (names.isEmpty) return '错误：names 为空';
    final builder = CoverageBuilder(store);
    final hinted = seen.stories.toSet();
    var coverage = await builder.build(
      names,
      budgetChars: budgetChars,
      hinted: hinted,
    );
    final picker = this.picker;
    if (picker != null && question.isNotEmpty) {
      final wide = await builder.build(
        names,
        budgetChars: wideChars,
        hinted: hinted,
        context: wideContext,
        perStoryChars: widePerStoryChars,
      );
      // Small enough to give whole: nothing to pick.
      if (wide.chars <= budgetChars) {
        coverage = wide;
      } else {
        final picked = await picker.pick(
          question,
          wide,
          names: names,
          fallback: coverage.passages,
          budgetChars: budgetChars,
        );
        if (picked.failed < picked.segments) {
          coverage = wide.withPicked(picked.passages);
        }
      }
    }
    coverage.register(seen);
    return coverage.render();
  }
}
