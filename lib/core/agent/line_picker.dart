/// Picking the lines the answer needs from a wide gathering (unified
/// refactor, phase 2: S5).
///
/// The gathering of phase 1 gives two lines either side of each place a
/// name is; what happens between those places fell through (live,
/// 2026-10-19: two of four gold lines sat in such gaps, and the model,
/// handed the material, read nothing more). Here the material is gathered
/// wide — eight lines either side — and cut into a few segments in reading
/// order; one call per segment, with no tools, writes the line ranges that
/// bear on the question. Code copies those lines (with a line either side)
/// to the answering model, which reads only story text, never a summary.
///
/// The rules are the same for every question: the call is told what to
/// pick, not where (CLAUDE.md R13).
library;

import 'dart:math' as math;

import '../gamedata/game_retrieval.dart';
import '../llm/llm_client.dart';
import 'coverage.dart';
import 'lore_agent_prompts.dart';

/// What [LinePicker.pick] made of a wide gathering.
class PickedLines {
  PickedLines(this.passages, {required this.segments, required this.failed});

  /// In the order of the gathering.
  final List<CoveragePassage> passages;
  final int segments;

  /// Segments whose call failed; their stories got [fallback]'s lines.
  final int failed;
}

class LinePicker {
  LinePicker(
    this.client, {
    this.segmentChars = 20000,
    this.maxSegments = 6,
    this.timeout = const Duration(seconds: 60),
    this.maxTokens = 1024,
  });

  final LLMClient client;

  /// Characters of material one call reads (more when the gathering would
  /// need more than [maxSegments] calls).
  final int segmentChars;
  final int maxSegments;
  final Duration timeout;
  final int maxTokens;

  /// Lines given either side of a picked range.
  static const int context = 1;

  /// The lines of [wide] that bear on [question], at most [budgetChars]
  /// characters. A segment whose call fails gives [fallback]'s passages of
  /// its stories instead.
  Future<PickedLines> pick(
    String question,
    Coverage wide, {
    List<String> names = const [],
    List<CoveragePassage> fallback = const [],
    int budgetChars = 30000,
  }) async {
    final segments = splitSegments(wide.passages);
    final answers = await Future.wait([
      for (final (i, seg) in segments.indexed)
        _ask(
          loreLinePickRequest(
            question,
            renderPassages(seg, wide.labels),
            names: names,
            index: i + 1,
            count: segments.length,
          ),
        ),
    ]);
    final share = budgetChars ~/ math.max(1, segments.length);
    final picks = <List<List<(String, int)>>>[];
    var failed = 0;
    for (final (i, seg) in segments.indexed) {
      final raw = answers[i];
      if (raw == null) {
        failed++;
        final stories = {for (final p in seg) p.storyId};
        picks.add([
          for (final p in fallback)
            if (stories.contains(p.storyId))
              [for (final l in p.lines) (p.storyId, l.lineIndex)],
        ]);
        continue;
      }
      picks.add(_ranges(raw, seg));
    }

    // Each segment its share first, in the order its call ranked the
    // ranges; what is left over goes to the ranges still waiting.
    final texts = <(String, int), StoryLineEntry>{};
    for (final p in [...wide.passages, ...fallback]) {
      for (final l in p.lines) {
        texts[(p.storyId, l.lineIndex)] = l;
      }
    }
    final chosen = <(String, int)>{};
    var total = 0;
    final next = List.filled(picks.length, 0);
    // [cap] alone in the first pass (one segment's long range does not
    // starve the next), the whole budget in the second.
    void take(int s, int cap) {
      var used = 0;
      while (next[s] < picks[s].length && used < cap && total < budgetChars) {
        final range = picks[s][next[s]++];
        for (final k in range) {
          if (!chosen.add(k)) continue;
          final n = (texts[k]?.content.length ?? 0) + 8;
          used += n;
          total += n;
        }
      }
    }

    for (var s = 0; s < picks.length; s++) {
      final before = total;
      total = 0;
      take(s, share);
      total += before;
    }
    for (var s = 0; s < picks.length; s++) {
      take(s, budgetChars);
    }

    final byStory = <String, List<int>>{};
    for (final k in chosen) {
      (byStory[k.$1] ??= []).add(k.$2);
    }
    final order = <String>{for (final p in wide.passages) p.storyId};
    final passages = <CoveragePassage>[];
    for (final s in order) {
      final lines = (byStory[s] ?? const <int>[]).toList()..sort();
      var run = <StoryLineEntry>[];
      for (final i in lines) {
        if (run.isNotEmpty && i != run.last.lineIndex + 1) {
          passages.add(
            CoveragePassage(s, run.first.lineIndex, run.last.lineIndex, run),
          );
          run = [];
        }
        run.add(texts[(s, i)]!);
      }
      if (run.isNotEmpty) {
        passages.add(
          CoveragePassage(s, run.first.lineIndex, run.last.lineIndex, run),
        );
      }
    }
    return PickedLines(passages, segments: segments.length, failed: failed);
  }

  /// [passages] cut into segments of whole stories in their order, each
  /// about [segmentChars] characters, at most [maxSegments].
  List<List<CoveragePassage>> splitSegments(List<CoveragePassage> passages) {
    final total = passages.fold(0, (n, p) => n + p.chars);
    final size = math.max(segmentChars, (total / maxSegments).ceil());
    final out = <List<CoveragePassage>>[];
    var current = <CoveragePassage>[];
    var chars = 0;
    var i = 0;
    while (i < passages.length) {
      final story = passages[i].storyId;
      final group = <CoveragePassage>[];
      while (i < passages.length && passages[i].storyId == story) {
        group.add(passages[i++]);
      }
      final n = group.fold(0, (m, p) => m + p.chars);
      if (current.isNotEmpty && chars + n > size) {
        out.add(current);
        current = [];
        chars = 0;
      }
      current.addAll(group);
      chars += n;
    }
    if (current.isNotEmpty) out.add(current);
    return out;
  }

  Future<String?> _ask(String request) async {
    try {
      final result = await client.chatCompletion(
        [
          Message.system(loreLinePickPrompt),
          Message.user(request),
        ],
        temperature: 0.2,
        maxTokens: maxTokens,
      ).timeout(timeout);
      return result.content;
    } catch (_) {
      return null;
    }
  }

  /// The ranges [raw] names, in its order, each a list of line keys of
  /// [segment] with [context] lines either side. Lines outside the segment
  /// are dropped.
  static List<List<(String, int)>> _ranges(String raw, List<CoveragePassage> segment) {
    final present = <String, Set<int>>{};
    for (final p in segment) {
      (present[p.storyId] ??= {}).addAll(p.lines.map((l) => l.lineIndex));
    }
    final out = <List<(String, int)>>[];
    for (final m in _range.allMatches(raw)) {
      final story = m.group(1)!;
      final lines = present[story];
      if (lines == null) continue;
      var a = int.parse(m.group(2)!);
      var b = int.tryParse(m.group(3) ?? '') ?? a;
      if (b < a) (a, b) = (b, a);
      // A range far longer than a segment is a misreading; keep its start.
      if (b - a > 200) b = a + 200;
      final keys = [
        for (var i = a - context; i <= b + context; i++)
          if (lines.contains(i)) (story, i),
      ];
      if (keys.isNotEmpty) out.add(keys);
    }
    return out;
  }

  static final RegExp _range =
      RegExp(r'([\w\-/\.\[\]]+\.txt)\s*[:：]\s*L?(\d+)(?:\s*[-–~]\s*L?(\d+))?');
}
