/// Layered memory for the ReAct loop (M1, "分层记忆").
///
/// Replaces the old "replay the whole observation history" scheme: instead of
/// resending every past Observation (context grows linearly with iterations),
/// the loop keeps:
///   L2  a small recent window of raw turns (see [recentWindowSize]) for
///       direct reasoning, and
///   L1  this compact memory block: a code-maintained index of what was read /
///       mapped / collected, plus per-iteration Thought notes (the model's own
///       conclusions, which survive trimming).
///
/// No information is lost to a budget: raw text lives in the session record,
/// and the memory block lets the model re-fetch anything it needs. The block
/// itself has a generous guardrail ([maxMemoryChars]); in practice 64
/// iterations produce only ~64 short lines.
class LoopMemory {
  /// How many recent turns (assistant + observation pairs) stay in the LLM
  /// request as raw text. Older turns are replaced by the memory block.
  static const int recentWindowSize = 2;

  /// Guardrail for the memory block size. Trimming here keeps the newest
  /// entries and says so; it never silently hides facts — the index is a
  /// pointer, the data itself lives in the session record / database.
  static const int maxMemoryChars = 8192;

  /// Max chars kept per Thought note.
  static const int maxThoughtNoteChars = 200;

  final List<String> _readIndex = [];
  final Set<String> _mappedScopes = {};
  final Set<String> _evidenceCollected = {};
  final List<String> _thoughtNotes = [];

  /// Records a successful `read_story_lines` call.
  ///
  /// Consecutive pages of the same story merge into one entry with the widest
  /// line range, so repeated paging does not bloat the index.
  void noteRead(String storyId, int startLine, int endLine) {
    final key = storyId;
    final start = startLine < 0 ? 0 : startLine;
    final end = endLine < start ? start : endLine;
    final existingIndex = _readIndex.indexWhere(
      (entry) => entry.startsWith('$key:'),
    );
    if (existingIndex < 0) {
      _readIndex.add('$key:$start-$end');
      return;
    }
    final range = _readIndex[existingIndex].split(':').last.split('-');
    final curStart = range.length == 2 ? int.tryParse(range[0]) : null;
    final curEnd = range.length == 2 ? int.tryParse(range[1]) : null;
    final mergedStart = curStart == null ? start : (curStart < start ? curStart : start);
    final mergedEnd = curEnd == null ? end : (curEnd > end ? curEnd : end);
    _readIndex[existingIndex] = '$key:$mergedStart-$mergedEnd';
  }

  /// Records a successful `get_story_map` call (scope or story ids).
  void noteMapped(String key) {
    if (key.trim().isNotEmpty) _mappedScopes.add(key.trim());
  }

  /// Records a successful `collect_entity_evidence` call.
  void noteEvidence(String entityId) {
    if (entityId.trim().isNotEmpty) _evidenceCollected.add(entityId.trim());
  }

  /// Records the model's Thought of one iteration (its own conclusions,
  /// which survive the recent-window trim).
  void noteThought(int iteration, String thought) {
    final clean = thought.trim();
    if (clean.isEmpty) return;
    final note = clean.length <= maxThoughtNoteChars
        ? clean
        : '${clean.substring(0, maxThoughtNoteChars)}…';
    _thoughtNotes.add('[$iteration] $note');
  }

  /// True when no tool indexing happened yet (no read/map/collect).
  bool get isEmpty =>
      _readIndex.isEmpty &&
      _mappedScopes.isEmpty &&
      _evidenceCollected.isEmpty &&
      _thoughtNotes.isEmpty;

  /// Renders the memory block injected before the recent window.
  String buildBlock() {
    if (isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('## 调查记忆（已获取内容索引；如需原文可用工具复查）');
    if (_readIndex.isNotEmpty) {
      buffer.writeln('已读章节: ${_readIndex.join('; ')}');
    }
    if (_mappedScopes.isNotEmpty) {
      buffer.writeln('已查地图: ${(_mappedScopes.toList()..sort()).join(', ')}');
    }
    if (_evidenceCollected.isNotEmpty) {
      buffer.writeln(
        '已收集证据: ${(_evidenceCollected.toList()..sort()).join(', ')}',
      );
    }
    if (_thoughtNotes.isNotEmpty) {
      buffer
        ..writeln('调查要点:')
        ..writeln(_thoughtNotes.join('\n'));
    }
    var text = buffer.toString().trimRight();
    if (text.length > maxMemoryChars) {
      text = '${text.substring(text.length - maxMemoryChars)}\n'
          '（记忆超限，更早条目已省略；可用工具复查）';
    }
    return text;
  }
}
