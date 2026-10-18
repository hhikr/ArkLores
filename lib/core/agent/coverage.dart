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
import 'lore_tools.dart';

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
  });

  final List<AnchorFootprint> footprints;

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
    if (footprints.isNotEmpty) {
      b.writeln('锚点在剧情里的位置：${[
        for (final f in footprints)
          f.lines == 0
              ? '${f.anchor}（原文里没有）'
              : '${f.anchor}（${f.stories} 篇 ${f.lines} 行'
                  '${f.spoken == 0 ? '' : '，其中说话 ${f.spoken} 行'}）',
      ].join('；')}');
    }
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

class CoverageBuilder {
  CoverageBuilder(this.store);

  final GameDataRetrieval store;

  /// Lines either side of an anchor's line.
  static const int context = 2;

  /// Two anchors at most this many lines apart are one scene.
  static const int sceneLines = 6;

  /// Stories one collection may give before every collection had its turn.
  static const int perCollection = 3;

  /// Characters one story may give.
  static const int perStoryChars = 3000;

  static const int maxAnchors = 6;

  static const int recordsGiven = 4;

  /// Gathers material for [anchors] up to [budgetChars] characters.
  /// [hinted]: stories a search already found, which count a little more.
  Future<Coverage> build(
    List<String> anchors, {
    int budgetChars = 30000,
    Set<String> hinted = const {},
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
        final cut = await _cut(s, centers, room);
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
