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

  String _serialize() {
    final buffer = StringBuffer();
    if (_targetEntityId != null) {
      buffer.writeln(
        '目标实体: $_targetEntityId'
        '${_targetEntityName == null ? '' : '（$_targetEntityName）'}',
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
