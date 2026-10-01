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
class InvestigationState {
  /// Stages (S0..S8) completed so far, in order, deduplicated.
  final List<String> stages = [];

  /// One read chapter: the line segments the tool ACTUALLY returned (R12).
  final List<ReadEntry> reads = [];

  /// R12 evidence notebook: line-anchored facts extracted from READ pages.
  /// Quotes are copied from the returned story lines by code (never written
  /// by the model), so the writer cites real text.
  final List<EvidenceNote> notes = [];

  /// Upper bound of [notes] kept in state (oldest dropped first).
  static const int maxNotes = 30;

  /// Evidence sets collected per suspect entity.
  final List<EvidenceEntry> evidence = [];

  /// Mapped scopes / story-id lists (for S2 bookkeeping).
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

  /// R11: how many times each search key (name or id) was repeated, plus the
  /// count of consecutive no-result searches PER KEY (R12: a global counter
  /// penalized a fresh query for earlier queries' misses) — used by the
  /// executor to break repeated dead loops deterministically.
  final Map<String, int> _searchRepeatCount = {};
  final Map<String, int> _consecutiveNoResult = {};

  /// R11: search keys for which the executor already ran a coverage fallback.
  /// A repeated SEARCH of such a key means the model ignored the enumerated
  /// appearances — the executor terminates instead of looping.
  final Set<String> _coverageFallbackKeys = {};

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
    if (stages.isNotEmpty) buffer.writeln('阶段: ${stages.join(",")}');
    if (reads.isNotEmpty) {
      buffer.writeln('已读:');
      for (final r in reads) {
        buffer.writeln(
          '  ${r.storyId}:${r.segments.map((s) => '${s.start}-${s.end}').join(',')}',
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
    return buffer.toString().trimRight();
  }

  /// Full serialization injected into the planner request.
  String serialize() {
    final body = _serialize();
    return body.isEmpty ? '(尚无调查进展)' : body;
  }

  // ── code-maintained mutations ──────────────────────────────────────

  void noteStage(String stage) {
    if (!stages.contains(stage)) stages.add(stage);
  }

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

  // ── R11.1 search progress tracking ──────────────────────────────────
  // Death-loop detection now ONLY triggers on "no progress": a search that
  // returns fresh results resets the counts, so repeated-but-productive
  // searches are never mis-terminated. Counts are keyed by the canonical
  // entity id when the executor resolves one, and RESELECT resets the id it
  // switches to so each candidate investigates from its own baseline.

  /// Last observation produced per search key (for "content changed" checks).
  final Map<String, String> _lastSearchObservation = {};

  /// Records the outcome of one search. [hadResult] true AND [contentChanged]
  /// true (fresh content) resets both counters — a genuinely productive
  /// search. [hadResult] true but [contentChanged] false (same hit set as the
  /// previous call) counts as a repeat: the model keeps polling the same data
  /// with no new information, which is a dead loop (R11.2). [hadResult] false
  /// bumps the per-key repeat count and the consecutive no-result counter.
  void noteSearchProgress({
    required String key,
    required bool hadResult,
    required bool contentChanged,
  }) {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    if (hadResult && contentChanged) {
      _consecutiveNoResult[normalized] = 0;
      _searchRepeatCount[normalized] = 0;
    } else {
      if (!hadResult) {
        _consecutiveNoResult[normalized] =
            (_consecutiveNoResult[normalized] ?? 0) + 1;
      }
      _searchRepeatCount[normalized] =
          (_searchRepeatCount[normalized] ?? 0) + 1;
    }
  }

  /// Stores the raw observation for [key] (for content-change detection).
  void noteSearchObservation(String key, String observation) {
    if (key.trim().isNotEmpty) _lastSearchObservation[key.trim()] = observation;
  }

  /// Whether [observation] differs from the last one seen for [key]; always
  /// true when [key] was never observed before.
  bool hasSearchContentChanged(String key, String observation) {
    final normalized = key.trim();
    if (normalized.isEmpty) return true;
    final prev = _lastSearchObservation[normalized];
    return prev == null || prev != observation;
  }

  /// Number of times [key] was searched without fresh progress.
  int searchRepeatCount(String key) => _searchRepeatCount[key.trim()] ?? 0;

  /// Consecutive searches of [key] that produced no result.
  int consecutiveNoResult(String key) => _consecutiveNoResult[key.trim()] ?? 0;

  /// Marks [key] as already coverage-fallen-back; a later SEARCH of the same
  /// key with no progress hits the terminal branch instead of looping.
  void noteCoverageFallback(String key) {
    if (key.trim().isNotEmpty) _coverageFallbackKeys.add(key.trim());
  }

  bool hasCoverageFallback(String key) =>
      _coverageFallbackKeys.contains(key.trim());

  /// Resets the search-tracking entries for a single [entityId] — called when
  /// RESELECT switches the target so a newly selected candidate investigates
  /// from its own baseline instead of inheriting a previous candidate's counts.
  void resetSearchTrackingFor(String entityId) {
    final normalized = entityId.trim();
    if (normalized.isEmpty) return;
    _searchRepeatCount.remove(normalized);
    _lastSearchObservation.remove(normalized);
    _coverageFallbackKeys.remove(normalized);
    _consecutiveNoResult.remove(normalized);
  }

  /// True when the investigation has made non-search progress (read chapters
  /// or collected evidence) — used to decide "decline to terminate, guide to
  /// COLLECT/VERDICT" vs "no progress at all -> unresolved".
  bool get hasReadOrEvidence => reads.isNotEmpty ||
      evidence.any((e) => e.evidenceRows > 0);

  void resetSearchTracking() {
    _searchRepeatCount.clear();
    _consecutiveNoResult.clear();
    _coverageFallbackKeys.clear();
    _lastSearchObservation.clear();
  }

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

  /// Records an executed FIND/COVER and the story ids it surfaced.
  void noteSearchLog(String key, List<String> storyIds) {
    if (key.trim().isEmpty) return;
    searchLog[key.trim()] = storyIds;
  }

  /// R12 progress fingerprint: changes whenever the investigation learned
  /// something new (lines read, notes, searches, evidence, maps, target).
  String get progressFingerprint {
    var readLines = 0;
    for (final r in reads) {
      for (final s in r.segments) {
        readLines += s.end - s.start + 1;
      }
    }
    final evidenceRows = evidence.fold<int>(0, (sum, e) => sum + e.evidenceRows);
    return '$readLines|${notes.length}|${searchLog.length}|$evidenceRows|'
        '${mapped.length}|$_targetEntityId';
  }

  /// Whether every line in [start]..[end] of [storyId] was already read.
  bool wasRangeRead(String storyId, int start, int end) {
    final index = reads.indexWhere((r) => r.storyId == storyId);
    if (index < 0) return false;
    return reads[index].segments.any((s) => s.start <= start && s.end >= end);
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

/// Evidence collected for one suspect.
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
