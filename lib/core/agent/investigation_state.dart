/// Structured investigation state for the planner loop (R8, M-B).
///
/// Replaces the free-text LoopMemory block: instead of a growing text blob,
/// the state is a compact structured snapshot that the planner loop serializes
/// into every request. Because the state is bounded (few hundred chars) and
/// independent of how many tools were called, the planner's context does not
/// grow with the investigation — so nothing needs truncating.
///
/// State is maintained by CODE (the executor parses tool DATA blocks), not by
/// the model, so it never drifts or loses the "what have I done" facts that
/// caused the 103-iteration repeat loop.
library;

import '../gamedata/story_catalog.dart';

class InvestigationState {
  /// R14: catalog entries (readable chapter names, collection) of the story
  /// ids in state, filled by the executor; absent for uncatalogued stories.
  final Map<String, StoryCatalogEntry> storyEntries = {};

  /// Story ids already looked up without a catalog entry.
  final Set<String> _labelMisses = {};

  /// R14: compact outlines (collection id → chapter list with synopses) the
  /// planner fetched with OUTLINE, kept in state so the whole-story picture
  /// survives the 2-observation window. R16: every outline stays as a
  /// chapter index with read marks; only the [maxOutlines] most recent keep
  /// the synopses of their unread chapters (a planner that lost the index
  /// re-opened the same outlines up to 13 times in one turn).
  final Map<String, String> outlines = {};
  static const int maxOutlines = 3;

  /// R16: story id → digest of what the read lines of that chapter tell
  /// (question-independent), so the planner knows what it has read.
  final Map<String, String> digests = {};

  /// R16: the planner's latest `# …` plan note; continuity only, never used
  /// for any decision.
  String plan = '';

  /// R16: short passages the planner asked to see again and again, kept in
  /// state so it has them in front of it (live: the same 24 lines asked
  /// for ten times).
  final List<({String storyId, int first, int last, List<String> rows})>
      pinned = [];

  int get pinnedLineCount => pinned.fold(0, (n, p) => n + p.rows.length);

  bool isPinned(String storyId, int first, int last) => pinned.any(
        (p) => p.storyId == storyId && p.first <= first && p.last >= last,
      );

  /// R16: tool steps used / allowed in this run (0 budget: not shown).
  int stepsUsed = 0;
  int stepBudget = 0;

  /// R16: the reading plan drafted at the start of the run (collections /
  /// chapters to read, in order). A checklist for the non-thinking planner;
  /// an item is ticked once its collection was outlined or read from.
  final List<PlanItem> readingPlan = [];

  /// Collections this run read from. An outline alone does not count: it
  /// is a map of the collection, not its text (live: a plan item was
  /// ticked by OUTLINE and its one relevant chapter never read).
  Set<String> get touchedCollections => {
        for (final r in reads)
          if (storyEntries[r.storyId] case final entry?) entry.collectionId,
      };

  bool _planItemDone(PlanItem item, Set<String> touched) {
    final id = item.collectionId;
    if (id != null &&
        (touched.contains(id) || reads.any((r) => r.storyId.contains('/$id/')))) {
      return true;
    }
    // Items naming a chapter file count once it was read.
    return reads.any((r) => item.text.contains(r.storyId));
  }

  /// Plan items not done yet.
  List<PlanItem> get pendingPlanItems {
    final touched = touchedCollections;
    return [
      for (final item in readingPlan)
        if (!_planItemDone(item, touched)) item,
    ];
  }

  /// R15: every collection outlined in this run, including outlines
  /// dropped from [outlines] — the missing-outline hint must not send the
  /// planner back to one it has seen (a live run ping-ponged between three
  /// collections with two outline slots).
  final Set<String> outlinedCollections = {};

  /// R14: stories whose read lines were inherited from the previous turn of
  /// the conversation.
  final Set<String> priorReadStories = {};

  /// R15: catalog collections / chapters the question names verbatim.
  final List<NamedStoryTarget> namedTargets = [];

  /// R15: names in the question that the previous turn never mentioned
  /// (the question changed topic; nothing was inherited).
  final Set<String> newTopicNames = {};

  /// R16: people named in the question (question context); the writer's
  /// source gives their lines priority.
  final List<String> questionNames = [];

  /// R15: name → COVER overview (every collection the person appears in,
  /// release order) of the people named in the question.
  final Map<String, String> entityOverviews = {};

  /// R15: spellings a search found nowhere in the DB → the similar names
  /// it suggested ('' when none). A live run re-searched a misspelt name
  /// eight times with other scopes after the first search had already
  /// pointed to the right spelling.
  final Map<String, String> missingTerms = {};

  /// Records the "not in the DB" notes of a FIND / COVER observation.
  void noteMissingTerms(String observation) {
    for (final m in _missingTermPattern.allMatches(observation)) {
      missingTerms[m.group(1)!] = (m.group(2) ?? '').trim();
    }
  }

  static final RegExp _missingTermPattern = RegExp(
    '库中没有“([^”]+)”这个写法(?:；字形或读音相近的名字：([^。]+))?',
  );

  /// One read chapter: the line segments the tool ACTUALLY returned (R12).
  final List<ReadEntry> reads = [];

  /// R12 evidence notebook: line-anchored facts extracted from READ pages.
  /// Quotes are copied from the returned story lines by code (never written
  /// by the model), so the writer cites real text.
  final List<EvidenceNote> notes = [];

  /// Notes shown to the planner (R16: older chapters fold beyond this; no
  /// note is dropped, the writer always sees all of them).
  static const int maxNotes = 40;

  /// Appearance rows collected per entity (COLLECT).
  final List<EvidenceEntry> evidence = [];

  /// Mapped scopes / story-id lists.
  final Set<String> mapped = {};

  /// R12: executed FIND/COVER searches -> top story ids they returned, so the
  /// model sees what it already searched (it re-ran `FIND 王冠` 8 times when
  /// only the last 2 observations were visible).
  final Map<String, List<String>> searchLog = {};

  /// The disambiguated target entity (id + name), set by the executor when a
  /// SEARCH hits multiple candidates (R10). Removes the need for the model to
  /// re-resolve the same ambiguous name every turn.
  String? _targetEntityId;
  String? _targetEntityName;

  /// R11: original query names already mapped to a resolved entity id, so the
  /// executor can auto-inject the id when the model searches the same name
  /// again (no repeated disambiguation).
  final Map<String, String> _searchedNames = {};

  /// R11: entity ids already chosen as the target (via disambiguation or
  /// RESELECT). Passed to the disambiguation helper as exclusions so it never
  /// re-picks a candidate that was already tried.
  final List<String> _attemptedEntityIds = [];

  /// R11: candidate list of the last disambiguation (id -> name), so RESELECT
  /// can switch to another candidate without a new search.
  final Map<String, String> _candidateNames = {};

  String _serialize({bool allNotes = false, bool writer = false}) {
    final buffer = StringBuffer();
    if (!writer && stepBudget > 0) {
      final left = stepBudget - stepsUsed;
      buffer.writeln('步数: 已用 $stepsUsed / $stepBudget'
          '${left <= lowBudgetSteps ? '（只剩 ${left < 0 ? 0 : left} 步：先 READ 目录里'
              '最关键的未读章节，然后 ANSWER）' : ''}');
    }
    if (!writer && readingPlan.isNotEmpty) {
      final touched = touchedCollections;
      buffer.writeln('阅读计划（开局制定，按顺序；✓ 为已读其中章节，只看过梗概不算；'
          '可按读到的内容调整）:');
      for (final item in readingPlan) {
        buffer.writeln(
          '  ${_planItemDone(item, touched) ? '✓' : '·'} ${item.text}',
        );
      }
    }
    if (!writer && plan.isNotEmpty) buffer.writeln('当前计划: $plan');
    if (!writer && pinned.isNotEmpty) {
      buffer.writeln('重点原文（你反复要看的段落，常驻在这里，不必再 READ）:');
      for (final p in pinned) {
        buffer.writeln('  ${p.storyId} ${p.first}-${p.last}:');
        for (final row in p.rows) {
          buffer.writeln('    $row');
        }
      }
    }
    if (namedTargets.isNotEmpty) {
      buffer.writeln('问题提到的故事: ${namedTargets.map((t) {
        final pending = !outlinedCollections.contains(t.collectionId);
        return '《${t.label}》（${t.storyId ?? t.collectionId}'
            '${t.releaseMonth == null ? '' : '，上线 ${t.releaseMonth}'}'
            '${t.storyId == null ? '，${t.chapters} 章' : ''}'
            '${pending ? '，可 OUTLINE ${t.collectionId}' : ''}）';
      }).join('、')}');
    }
    for (final overview in entityOverviews.entries) {
      buffer.writeln('${overview.key} 的${_overviewWithReads(overview.value)}');
    }
    if (missingTerms.isNotEmpty) {
      buffer.writeln('库中没有的写法（再搜也不会有结果）: ${missingTerms.entries.map(
        (e) => e.value.isEmpty ? e.key : '${e.key}（相近：${e.value}）',
      ).join('；')}');
    }
    if (newTopicNames.isNotEmpty) {
      buffer.writeln('本问提到上一轮没有涉及的: ${newTopicNames.join('、')}'
          '——按本问重新定位，不沿用上一轮的故事范围');
    }
    if (_targetEntityId != null) {
      buffer.writeln(
        '目标实体: $_targetEntityId'
        '${_targetEntityName == null ? '' : '（$_targetEntityName）'}',
      );
    }
    if (_searchedNames.isNotEmpty) {
      buffer.writeln(
        '已消歧名字: ${_searchedNames.entries.map((e) => '${e.key}->${e.value}').join(', ')}',
      );
    }
    if (outlines.isNotEmpty) {
      buffer.writeln('已看梗概（故事集章节目录，按游戏内顺序；✓ 为已读区间；'
          '未读章节附官方简介，只是定位线索）:');
      for (final entry in outlines.entries) {
        buffer.writeln(
          isOutlineFolded(entry.key)
              ? _renderOutline(entry.value, withSynopses: false, folded: entry.key)
              : _renderOutline(entry.value, withSynopses: true),
        );
      }
    }
    _writeChapters(buffer, allNotes: allNotes);
    if (evidence.isNotEmpty) {
      buffer.writeln('证据:');
      for (final e in evidence) {
        buffer.writeln(
          '  ${e.entityId}: ${e.evidenceRows}行, scopes=${e.scopes.join(",")}',
        );
      }
    }
    if (mapped.isNotEmpty) {
      buffer.writeln('已查地图: ${mapped.join(", ")}');
    }
    if (searchLog.isNotEmpty) {
      buffer.writeln('已检索:');
      for (final entry in searchLog.entries) {
        buffer.writeln(
          '  ${entry.key} → '
          '${entry.value.isEmpty ? '无结果' : entry.value.join(', ')}',
        );
      }
    }
    final pending = collectionsWithoutOutline;
    if (pending.isNotEmpty) {
      buffer.writeln(
        '提示: 已读章节所属故事集尚未看梗概: '
        '${pending.map((c) => '《${c.label}》(OUTLINE ${c.id})').join('、')}',
      );
    }
    return buffer.toString().trimRight();
  }

  /// R16: steps left at which the state starts saying how few remain.
  static const int lowBudgetSteps = 3;

  static final RegExp _outlineRow = RegExp(r'^(\s+\d+\. .+ \| )(\S+)( ←)?$');

  /// Outlines shown as a full chapter index (R16: the most recent ones);
  /// older ones fold to their read chapters.
  static const int fullOutlines = 2;

  /// Whether the outline of [collectionId] is in state but folded.
  bool isOutlineFolded(String collectionId) =>
      outlines.containsKey(collectionId) &&
      !outlines.keys.toList().reversed.take(fullOutlines).contains(collectionId);

  /// An outline as a chapter index: read chapters get `✓ <segments>` and
  /// lose their synopsis; with [withSynopses] false every synopsis is left
  /// out. A [folded] outline (its collection id) keeps only the header and
  /// the read chapters — a run over eight collections re-sent eight full
  /// indexes (~12k characters) with every planner step (live).
  String _renderOutline(
    String compact, {
    required bool withSynopses,
    String? folded,
  }) {
    final out = <String>[];
    var skipSynopsis = false;
    var hidden = 0;
    for (final line in compact.split('\n')) {
      final row = _outlineRow.firstMatch(line);
      if (row != null) {
        final segments = segmentsText(row.group(2)!);
        skipSynopsis = !withSynopses || segments.isNotEmpty;
        if (folded != null && segments.isEmpty) {
          hidden++;
          continue;
        }
        out.add('${row.group(1)}${row.group(2)}${row.group(3) ?? ''}'
            '${segments.isEmpty ? '' : ' ✓ $segments'}');
        continue;
      }
      if (line.startsWith('      ') && skipSynopsis) continue;
      out.add(line);
    }
    if (folded != null && hidden > 0) {
      out.add('   （其余 $hidden 章已折叠；需要时再 OUTLINE $folded，不占步数）');
    }
    return out.join('\n');
  }

  /// `0-120,200-260` for the read segments of [storyId] ('' when unread).
  String segmentsText(String storyId) {
    final index = reads.indexWhere((r) => r.storyId == storyId);
    if (index < 0) return '';
    return reads[index].segments.map((s) => '${s.start}-${s.end}').join(',');
  }

  /// R16: read chapters with their digest and notes. Notes of the most
  /// recently read chapters are shown up to [maxNotes]; older chapters fold
  /// theirs into a count instead of losing them ([allNotes] shows all).
  void _writeChapters(StringBuffer buffer, {required bool allNotes}) {
    final storyIds = <String>{
      for (final r in reads) r.storyId,
      for (final n in notes) n.storyId,
    }.toList();
    if (storyIds.isEmpty) return;
    final byStory = <String, List<EvidenceNote>>{};
    for (final n in notes) {
      byStory.putIfAbsent(n.storyId, () => []).add(n);
    }
    // Newest chapters first get the shown-note budget.
    final shown = <String, int>{};
    var budget = allNotes ? 1 << 30 : maxNotes;
    for (final id in storyIds.reversed) {
      final count = byStory[id]?.length ?? 0;
      final take = count < budget ? count : budget;
      shown[id] = take;
      budget -= take;
    }
    buffer.writeln(
      priorReadStories.isEmpty
          ? '已读章节（原文会完整交给写答案的环节，不必重读）:'
          : '已读章节（含上一轮对话已读的原文，可直接引用，不必重读）:',
    );
    for (final id in storyIds) {
      final label = storyEntries[id]?.label;
      final prior = priorReadStories.contains(id) ? '（上一轮已读）' : '';
      buffer.writeln(
        '  $id${label == null ? '' : '［$label］'}:${segmentsText(id)}$prior',
      );
      final digest = digests[id];
      if (digest != null && digest.isNotEmpty) {
        buffer.writeln('    摘要: $digest');
      }
      final chapterNotes = byStory[id] ?? const <EvidenceNote>[];
      final take = shown[id] ?? 0;
      for (final n in chapterNotes.skip(chapterNotes.length - take)) {
        buffer.writeln('    $id:${n.line} ${n.fact} 「${n.quote}」');
      }
      final folded = chapterNotes.length - take;
      if (folded > 0) {
        buffer.writeln('    （另有 $folded 条笔记已折叠，写答案时完整使用）');
      } else if (chapterNotes.isEmpty && digests.containsKey(id)) {
        buffer.writeln('    （没有与问题直接相关的行）');
      }
    }
  }

  /// R16: records the digest of a READ page of [storyId]; several reads of
  /// one chapter join their digests.
  void noteDigest(String storyId, String digest) {
    final text = digest.trim();
    final previous = digests[storyId];
    if (previous == null || previous.isEmpty) {
      digests[storyId] = text;
    } else if (text.isNotEmpty && !previous.contains(text)) {
      digests[storyId] = '$previous；$text';
    }
  }

  static final RegExp _overviewRow =
      RegExp(r'^\s*\d+\. (.+?)（([^，）]+)[，）].*?: (\d+) 章，提及 (\d+) 次');

  /// Chapters of collection [id] this run read from.
  int readChaptersIn(String id) => reads
      .where((r) =>
          storyEntries[r.storyId]?.collectionId == id ||
          r.storyId.contains('/$id/'),)
      .length;

  /// An overview with the read share of each collection appended
  /// (`（已读 1/8 章）`), so the planner sees how much of a collection it has
  /// covered, not only whether it opened it.
  String _overviewWithReads(String overview) => [
        for (final line in overview.split('\n'))
          if (_overviewRow.firstMatch(line) case final m?)
            readChaptersIn(m.group(2)!.trim()) > 0
                ? '$line（已读 ${readChaptersIn(m.group(2)!.trim())}/${m.group(3)} 章）'
                : line
          else
            line,
      ].join('\n');

  /// R16: rows of the question people's overviews whose collection this run
  /// read less than half of (by chapters the person appears in; an outline
  /// alone is not reading) — at least [minMentions] mentions, the [limit]
  /// with the most mentions in unread chapters, kept in overview (story)
  /// order. Live: a collection with eight chapters of the person was left
  /// after one, because one read ticked it.
  List<String> untouchedOverviewRows({int minMentions = 5, int limit = 6}) {
    final rows = <({String text, double unread, int order})>[];
    for (final overview in entityOverviews.values) {
      for (final line in overview.split('\n')) {
        final m = _overviewRow.firstMatch(line);
        if (m == null) continue;
        final id = m.group(2)!.trim();
        final chapters = int.parse(m.group(3)!);
        final mentions = int.parse(m.group(4)!);
        final read = readChaptersIn(id);
        if (read * 2 >= chapters || mentions < minMentions) continue;
        if (rows.any((r) => r.text.contains('（$id'))) continue;
        final text = line.trim().replaceFirst(RegExp(r'^\d+\. '), '');
        rows.add((
          text: read == 0 ? text : '$text（已读 $read/$chapters 章）',
          unread: mentions * (chapters - read) / chapters,
          order: rows.length,
        ),);
      }
    }
    final top = ([...rows]..sort((a, b) => b.unread.compareTo(a.unread)))
        .take(limit)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return [for (final r in top) r.text];
  }

  /// R14: collections of READ chapters whose outline was not fetched yet.
  List<({String id, String label})> get collectionsWithoutOutline {
    final result = <({String id, String label})>[];
    for (final r in reads) {
      final entry = storyEntries[r.storyId];
      if (entry == null || outlinedCollections.contains(entry.collectionId)) {
        continue;
      }
      if (result.any((c) => c.id == entry.collectionId)) continue;
      result.add((id: entry.collectionId, label: entry.collectionLabel));
    }
    return result;
  }

  /// Story ids in state (reads, notes, search results) not yet labelled.
  Set<String> get storyIdsWithoutLabel => {
        for (final r in reads) r.storyId,
        for (final n in notes) n.storyId,
        for (final ids in searchLog.values) ...ids,
      }
        ..removeAll(storyEntries.keys)
        ..removeAll(_labelMisses);

  /// Records catalog lookups for [requested] ids ([found] may be partial).
  void addStoryEntries(
    Iterable<String> requested,
    Map<String, StoryCatalogEntry> found,
  ) {
    storyEntries.addAll(found);
    for (final id in requested) {
      if (!found.containsKey(id)) _labelMisses.add(id);
    }
  }

  /// Records an OUTLINE result for [collectionId].
  void noteOutline(String collectionId, String compact) {
    if (collectionId.trim().isEmpty || compact.trim().isEmpty) return;
    outlinedCollections.add(collectionId);
    outlines.remove(collectionId);
    outlines[collectionId] = compact;
  }

  /// Full serialization injected into the planner request.
  String serialize() {
    final body = _serialize();
    return body.isEmpty ? '(尚无调查进展)' : body;
  }

  /// R16: the state for the answer writer: every note, no step counter or
  /// plan (they are about searching, not about the answer).
  String serializeForWriter() {
    final body = _serialize(allNotes: true, writer: true);
    return body.isEmpty ? '(尚无调查进展)' : body;
  }

  // ── code-maintained mutations ──────────────────────────────────────

  /// Records the executor-resolved target entity (R10).
  void setTargetEntity(String entityId, String name) {
    _targetEntityId = entityId;
    _targetEntityName = name;
    if (!_attemptedEntityIds.contains(entityId)) {
      _attemptedEntityIds.add(entityId);
    }
  }

  // ── R11 code-maintained protocol ─────────────────────────────────

  /// Returns the target entity id (null when not yet resolved).
  String? get targetEntityId => _targetEntityId;
  String? get targetEntityName => _targetEntityName;

  /// Maps an original query name to a resolved entity id, so later searches
  /// of the same name auto-inject the id.
  void noteSearchedName(String name, String entityId) {
    if (name.trim().isEmpty || entityId.trim().isEmpty) return;
    _searchedNames[name.trim()] = entityId;
  }

  /// Whether [name] already resolved to an entity in this investigation.
  String? searchedNameTarget(String name) => _searchedNames[name.trim()];

  /// Records the candidate list of the last disambiguation (for RESELECT).
  void setCandidateNames(Map<String, String> idToName) {
    _candidateNames
      ..clear()
      ..addAll(idToName);
  }

  /// Candidate ids (excluding [current]) of the last disambiguation.
  List<String> candidateIds({String? excluding}) => [
        for (final id in _candidateNames.keys)
          if (id != excluding) id,
      ];

  String? candidateName(String entityId) => _candidateNames[entityId];

  /// True when [entityId] was already chosen as target during this
  /// investigation (used by RESELECT to refuse re-picking tried candidates).
  bool wasAttempted(String entityId) => _attemptedEntityIds.contains(entityId);

  /// Records that lines [startLine]..[endLine] (inclusive) of [storyId] were
  /// actually returned by a read. Overlapping or adjacent segments merge;
  /// gaps stay gaps (R12: a min..max merge marked unread lines as read).
  void noteRead(String storyId, int startLine, int endLine) {
    final start = startLine <= endLine ? startLine : endLine;
    final end = startLine <= endLine ? endLine : startLine;
    final index = reads.indexWhere((r) => r.storyId == storyId);
    final segments = [
      if (index >= 0) ...reads[index].segments,
      LineSegment(start, end),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <LineSegment>[];
    for (final s in segments) {
      if (merged.isNotEmpty && s.start <= merged.last.end + 1) {
        final last = merged.removeLast();
        merged.add(LineSegment(last.start, s.end > last.end ? s.end : last.end));
      } else {
        merged.add(s);
      }
    }
    final entry = ReadEntry(storyId: storyId, segments: merged);
    if (index >= 0) {
      reads[index] = entry;
    } else {
      reads.add(entry);
    }
  }

  /// Stories any FIND/COVER has surfaced so far.
  final Set<String> discoveredStories = {};

  /// Records an executed FIND/COVER and the story ids it surfaced. Only
  /// [leads] — stories with a literal match — count as discovered: a
  /// semantic-only neighbour always exists, so counting those let a
  /// fruitless run look productive forever (R13 negative live case).
  void noteSearchLog(
    String key,
    List<String> storyIds, {
    Iterable<String>? leads,
  }) {
    if (key.trim().isEmpty) return;
    searchLog[key.trim()] = storyIds;
    discoveredStories.addAll(leads ?? storyIds);
  }

  /// R12 progress fingerprint: changes whenever the investigation learned
  /// something new (lines read, notes, newly surfaced stories, evidence,
  /// maps, target). A search that only re-surfaces known stories is NOT
  /// progress (a live run re-phrased one fruitless FIND 15 times).
  String get progressFingerprint {
    var readLines = 0;
    for (final r in reads) {
      for (final s in r.segments) {
        readLines += s.end - s.start + 1;
      }
    }
    final evidenceRows = evidence.fold<int>(0, (sum, e) => sum + e.evidenceRows);
    return '$readLines|${notes.length}|${discoveredStories.length}|$evidenceRows|'
        '${mapped.length}|${outlines.keys.join(',')}|$_targetEntityId';
  }

  /// Whether every line in [start]..[end] of [storyId] was already read.
  bool wasRangeRead(String storyId, int start, int end) {
    final index = reads.indexWhere((r) => r.storyId == storyId);
    if (index < 0) return false;
    return reads[index].segments.any((s) => s.start <= start && s.end >= end);
  }

  /// R14: first line at or after [from] of [storyId] that was not read yet
  /// (segments are merged and sorted), so a READ overlapping what was read
  /// continues where reading stopped instead of re-reading.
  int firstUnreadLine(String storyId, int from) {
    final index = reads.indexWhere((r) => r.storyId == storyId);
    if (index < 0) return from;
    var line = from;
    for (final s in reads[index].segments) {
      if (s.start <= line && s.end >= line) line = s.end + 1;
    }
    return line;
  }

  /// Whether line [line] of [storyId] lies inside an actually-read segment.
  bool wasLineRead(String storyId, int line) {
    final index = reads.indexWhere((r) => r.storyId == storyId);
    if (index < 0) return false;
    return reads[index].segments.any((s) => line >= s.start && line <= s.end);
  }

  /// Adds evidence notes, skipping exact duplicates. R16: nothing is
  /// dropped (silently losing old notes made the planner re-read them).
  void addNotes(Iterable<EvidenceNote> newNotes) {
    for (final note in newNotes) {
      final duplicate = notes.any((n) =>
          n.storyId == note.storyId && n.line == note.line && n.fact == note.fact,);
      if (!duplicate) notes.add(note);
    }
  }

  void noteMapped(String key) {
    if (key.trim().isNotEmpty) mapped.add(key.trim());
  }

  void noteEvidence(
    String entityId, {
    required int evidenceRows,
    required List<String> scopes,
  }) {
    final index = evidence.indexWhere((e) => e.entityId == entityId);
    if (index < 0) {
      evidence.add(EvidenceEntry(
        entityId: entityId,
        evidenceRows: evidenceRows,
        scopes: scopes,
      ),);
      return;
    }
    final e = evidence[index];
    final merged = <String>{...e.scopes, ...scopes}.toList()..sort();
    evidence[index] = EvidenceEntry(
      entityId: entityId,
      evidenceRows: e.evidenceRows + evidenceRows,
      scopes: merged,
    );
  }
}

/// R16: one item of the reading plan (`我们明日见（act18mini）：…`).
class PlanItem {
  const PlanItem(this.text, {this.collectionId});
  final String text;

  /// The collection id written in the item, when there is one.
  final String? collectionId;

  static final RegExp _line = RegExp(r'^\s*(?:[-*·•]|\d+[.、)])\s*(.+?)\s*$');
  static final RegExp _id = RegExp(r'[（(]\s*([A-Za-z][\w\-]*)\s*[）)]');

  /// Items of a plan reply (list lines only), at most [limit].
  static List<PlanItem> parse(String raw, {int limit = 10}) {
    final items = <PlanItem>[];
    for (final line in raw.split('\n')) {
      final m = _line.firstMatch(line);
      if (m == null) continue;
      final text = m.group(1)!;
      final clipped = text.length > 80 ? '${text.substring(0, 80)}…' : text;
      items.add(PlanItem(clipped, collectionId: _id.firstMatch(text)?.group(1)));
      if (items.length >= limit) break;
    }
    return items;
  }
}

/// One read chapter in state: the line segments actually returned.
class ReadEntry {
  const ReadEntry({required this.storyId, required this.segments});
  final String storyId;
  final List<LineSegment> segments;
}

/// An inclusive line range.
class LineSegment {
  const LineSegment(this.start, this.end);
  final int start;
  final int end;
}

/// One line-anchored fact from a read page (R12 evidence notebook).
class EvidenceNote {
  const EvidenceNote({
    required this.storyId,
    required this.line,
    required this.fact,
    required this.quote,
  });
  final String storyId;
  final int line;

  /// The extractor's one-sentence statement of what this line shows.
  final String fact;

  /// Original line text copied by code from the read page.
  final String quote;
}

/// Appearance rows collected for one entity.
class EvidenceEntry {
  const EvidenceEntry({
    required this.entityId,
    required this.evidenceRows,
    required this.scopes,
  });
  final String entityId;
  final int evidenceRows;
  final List<String> scopes;
}
