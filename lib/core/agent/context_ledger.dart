import 'dart:convert';

import 'lore_tools.dart' show SeenLines;

/// Original text still present in each tool-result message.
class ContextLedger {
  ContextLedger();

  factory ContextLedger.fromJson(Map<String, dynamic> json) {
    final ledger = ContextLedger();
    for (final item in json['messages'] as List) {
      final m = item as Map<String, dynamic>;
      ledger.record(
        m['index'] as int,
        SeenLines.fromJson(m['shown'] as Map<String, dynamic>),
        step: m['step'] as int,
        callKey: m['call_key'] as String,
        contextDescriptions: (m['context_descriptions'] as List? ?? [])
            .cast<String>(),
      );
    }
    return ledger;
  }

  Map<String, dynamic> toJson() => {
        'messages': [
          for (final e in _messages.entries)
            {
              'index': e.key,
              'shown': e.value.shown.toJson(),
              'step': e.value.step,
              'call_key': e.value.callKey,
              if (e.value.contextDescriptions.isNotEmpty)
                'context_descriptions': e.value.contextDescriptions.toList()
                  ..sort(),
            },
        ],
      };

  ContextLedger remap(Map<int, int> oldToNew) {
    final ledger = ContextLedger();
    for (final e in _messages.entries) {
      final index = oldToNew[e.key];
      if (index != null) {
        ledger.record(
          index,
          e.value.shown,
          step: e.value.step,
          callKey: e.value.callKey,
          contextDescriptions: e.value.contextDescriptions,
        );
      }
    }
    return ledger;
  }

  void replaceWith(ContextLedger other) {
    _messages
      ..clear()
      ..addAll(other._messages);
  }

  int get lastStep =>
      _messages.values.fold(0, (n, m) => m.step > n ? m.step : n);
  final _messages = <int, ({
    SeenLines shown,
    int step,
    String callKey,
    Set<String> contextDescriptions,
  })>{};
  /// Snapshot what this message showed; later reads cannot expand it.
  void record(
    int index,
    SeenLines shown, {
    required int step,
    required String callKey,
    Iterable<String>? contextDescriptions,
  }) {
    _messages[index] =
        (
          shown: SeenLines()..addAll(shown),
          step: step,
          callKey: callKey,
          contextDescriptions: Set.of(
            contextDescriptions ?? shown.contextDescriptions,
          ),
        );
  }

  /// Remove hidden or compacted messages without affecting other copies.
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

  /// The first visible step that printed a reusable, non-citation description.
  /// Keep this on the result message so hiding or compacting that message
  /// removes the description from the context ledger too.
  int? stepOfContextDescription(String key) {
    for (final message in _messages.values) {
      if (message.contextDescriptions.contains(key)) return message.step;
    }
    return null;
  }

  bool hasContextDescription(int messageIndex, String key) =>
      _messages[messageIndex]?.contextDescriptions.contains(key) ?? false;
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
  return steps.take(3).map(contextStep).join('、') +
      (steps.length > 3 ? ' 等' : '');
}

String contextStep(int step) => step == 0 ? '纪要' : '第 $step 步';
