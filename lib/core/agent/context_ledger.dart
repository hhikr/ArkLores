import 'dart:convert';

import 'lore_tools.dart' show SeenLines;

/// Original text still present in each tool-result message.
class ContextLedger {
  final _messages = <int, ({SeenLines shown, int step, String callKey})>{};
  /// Snapshot what this message showed; later reads cannot expand it.
  void record(int index, SeenLines shown,
      {required int step, required String callKey,}) {
    _messages[index] =
        (shown: SeenLines()..addAll(shown), step: step, callKey: callKey);
  }

  /// Remove hidden or folded messages without affecting other copies.
  void forget(Iterable<int> indexes) {
    for (final index in indexes) {
      _messages.remove(index);
    }
  }

  void clear() => _messages.clear();
  Set<int> stepsShowing(String storyId, int line) => {
        for (final m in _messages.values)
          if (m.shown.covers(storyId, line, line)) m.step,
      };
  bool lineInContext(String storyId, int line) =>
      stepsShowing(storyId, line).isNotEmpty;
  bool recordInContext(String id) => stepOfRecord(id) != null;
  int? stepOfRecord(String id) {
    for (final m in _messages.values) {
      if (m.shown.recordIsWhole(id)) return m.step;
    }
    return null;
  }

  int? stepOfCall(String callKey) {
    for (final m in _messages.values) {
      if (m.callKey == callKey) return m.step;
    }
    return null;
  }
}

/// Recursively sort object keys; preserve meaningful array order.
String canonicalCallKey(String tool, Map<String, dynamic> arguments) {
  Object? sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(value[key])};
    }
    if (value is List) return value.map(sorted).toList();
    return value;
  }

  return '$tool|${jsonEncode(sorted(arguments))}';
}

String contextSteps(ContextLedger ledger, String id, Iterable<int> lines) {
  final steps = {for (final line in lines) ...ledger.stepsShowing(id, line)}
      .toList()
    ..sort();
  return '${steps.take(3).join('、')}${steps.length > 3 ? ' 等' : ''}';
}
