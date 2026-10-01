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

  /// One read chapter: range + optional key points from the extractor.
  final List<ReadEntry> reads = [];

  /// Evidence sets collected per suspect entity.
  final List<EvidenceEntry> evidence = [];

  /// Mapped scopes / story-id lists (for S2 bookkeeping).
  final Set<String> mapped = {};

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
  /// count of consecutive no-result searches — used by the executor to break
  /// repeated dead loops deterministically.
  final Map<String, int> _searchRepeatCount = {};
  int _consecutiveNoResult = 0;

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
          '  ${r.storyId}:${r.startLine}-${r.endLine}'
          '${r.keyPoints.isEmpty ? "" : " [要点: ${r.keyPoints}]"}',
        );
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
      _consecutiveNoResult = 0;
      _searchRepeatCount[normalized] = 0;
    } else {
      _consecutiveNoResult++;
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

  /// Consecutive searches that produced no result (across the current target).
  int get consecutiveNoResult => _consecutiveNoResult;

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
    _consecutiveNoResult = 0;
  }

  /// True when the investigation has made non-search progress (read chapters
  /// or collected evidence) — used to decide "decline to terminate, guide to
  /// COLLECT/VERDICT" vs "no progress at all -> unresolved".
  bool get hasReadOrEvidence => reads.isNotEmpty ||
      evidence.any((e) => e.evidenceRows > 0);

  void resetSearchTracking() {
    _searchRepeatCount.clear();
    _consecutiveNoResult = 0;
    _coverageFallbackKeys.clear();
    _lastSearchObservation.clear();
  }

  void noteRead(String storyId, int startLine, int endLine) {
    final existing = reads.indexWhere((r) => r.storyId == storyId);
    if (existing < 0) {
      reads.add(ReadEntry(
        storyId: storyId,
        startLine: startLine,
        endLine: endLine,
      ),);
      return;
    }
    final r = reads[existing];
    final mergedStart = startLine < r.startLine ? startLine : r.startLine;
    final mergedEnd = endLine > r.endLine ? endLine : r.endLine;
    reads[existing] = ReadEntry(
      storyId: storyId,
      startLine: mergedStart,
      endLine: mergedEnd,
      keyPoints: r.keyPoints,
    );
  }

  void setKeyPoints(String storyId, String keyPoints) {
    final index = reads.indexWhere((r) => r.storyId == storyId);
    if (index < 0) return;
    final r = reads[index];
    reads[index] = ReadEntry(
      storyId: storyId,
      startLine: r.startLine,
      endLine: r.endLine,
      keyPoints: keyPoints,
    );
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

/// One read chapter in state.
class ReadEntry {
  const ReadEntry({
    required this.storyId,
    required this.startLine,
    required this.endLine,
    this.keyPoints = '',
  });
  final String storyId;
  final int startLine;
  final int endLine;
  final String keyPoints;
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
