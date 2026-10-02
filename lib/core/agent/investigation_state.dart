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
  /// survives the 2-observation window. Oldest dropped beyond [maxOutlines].
  final Map<String, String> outlines = {};
  static const int maxOutlines = 2;

  /// R14: stories whose read lines were inherited from the previous turn of
  /// the conversation.
  final Set<String> priorReadStories = {};

  /// One read chapter: the line segments the tool ACTUALLY returned (R12).
  final List<ReadEntry> reads = [];

  /// R12 evidence notebook: line-anchored facts extracted from READ pages.
  /// Quotes are copied from the returned story lines by code (never written
  /// by the model), so the writer cites real text.
  final List<EvidenceNote> notes = [];

  /// Upper bound of [notes] kept in state (oldest dropped first).
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

  String _serialize() {
    final buffer = StringBuffer();
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
      buffer.writeln('已看梗概（官方章节简介，按游戏内顺序；只是定位线索）:');
      for (final outline in outlines.values) {
        buffer.writeln(outline);
      }
    }
    if (reads.isNotEmpty) {
      buffer.writeln(
        priorReadStories.isEmpty
            ? '已读:'
            : '已读（含上一轮对话已读的原文，可直接引用，不必重读）:',
      );
      for (final r in reads) {
        final label = storyEntries[r.storyId]?.label;
        buffer.writeln(
          '  ${r.storyId}${label == null ? '' : '［$label］'}:'
          '${r.segments.map((s) => '${s.start}-${s.end}').join(',')}',
        );
      }
    }
    if (notes.isNotEmpty) {
      buffer.writeln('证据笔记:');
      for (final n in notes) {
        buffer.writeln('  ${n.storyId}:${n.line} ${n.fact} 「${n.quote}」');
      }
    }
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

  /// R14: collections of READ chapters whose outline was not fetched yet.
  List<({String id, String label})> get collectionsWithoutOutline {
    final result = <({String id, String label})>[];
    for (final r in reads) {
      final entry = storyEntries[r.storyId];
      if (entry == null || outlines.containsKey(entry.collectionId)) continue;
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
    outlines.remove(collectionId);
    outlines[collectionId] = compact;
    while (outlines.length > maxOutlines) {
      outlines.remove(outlines.keys.first);
    }
  }

  /// Full serialization injected into the planner request.
  String serialize() {
    final body = _serialize();
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

  /// Adds evidence notes, skipping exact duplicates and keeping the newest
  /// [maxNotes].
  void addNotes(Iterable<EvidenceNote> newNotes) {
    for (final note in newNotes) {
      final duplicate = notes.any((n) =>
          n.storyId == note.storyId && n.line == note.line && n.fact == note.fact,);
      if (!duplicate) notes.add(note);
    }
    if (notes.length > maxNotes) {
      notes.removeRange(0, notes.length - maxNotes);
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
