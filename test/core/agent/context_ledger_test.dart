import 'dart:convert';

import 'package:arklores/core/agent/context_ledger.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('step lists are sorted, unique and capped at three', () {
    final ledger = ContextLedger();
    for (final n in [5, 1, 3, 2]) {
      ledger.record(n, SeenLines()..add('a', 0), step: n, callKey: '$n');
    }
    expect(contextSteps(ledger, 'a', [0, 0]), '第 1 步、第 2 步、第 3 步 等');
  });

  test('record snapshots, overlap, forget and clear', () {
    final ledger = ContextLedger();
    final shown = SeenLines()
      ..addRange('a', 0, 2)
      ..addRecord('r');
    ledger.record(2, shown, step: 1, callKey: 'first');
    shown.add('a', 9);
    ledger.record(4, SeenLines()..add('a', 2), step: 3, callKey: 'second');
    expect(ledger.stepsShowing('a', 2), {1, 3});
    expect(ledger.lineInContext('a', 9), isFalse);
    expect(ledger.recordInContext('r'), isTrue);
    expect(ledger.stepOfRecord('r'), 1);
    expect(ledger.stepOfCall('first'), 1);
    ledger.forget([2, 99]);
    expect(ledger.stepsShowing('a', 2), {3});
    expect(ledger.lineInContext('a', 0), isFalse);
    expect(ledger.recordInContext('r'), isFalse);
    expect(ledger.stepOfCall('first'), isNull);
    ledger.clear();
    expect(ledger.lineInContext('a', 2), isFalse);
  });
  test('context descriptions follow visible result messages', () {
    const key = 'material-source-policy:manual';
    final shown = SeenLines()..addContextDescription(key);
    final ledger = ContextLedger()
      ..record(4, shown, step: 7, callKey: 'search');
    expect(ledger.stepOfContextDescription(key), 7);
    expect(SeenLines.fromJson(shown.toJson()).contextDescriptions, isEmpty);

    final restored = ContextLedger.fromJson(
      jsonDecode(jsonEncode(ledger.toJson())) as Map<String, dynamic>,
    );
    expect(restored.stepOfContextDescription(key), 7);
    final remapped = restored.remap({4: 0});
    expect(remapped.stepOfContextDescription(key), 7);
    remapped.forget([0]);
    expect(remapped.stepOfContextDescription(key), isNull);
  });
  test('partial records are not whole and readonly accessors cannot mutate',
      () {
    final shown = SeenLines()
      ..addRecord('r', partial: true)
      ..add('a', 1);
    final ledger = ContextLedger()..record(0, shown, step: 1, callKey: 'x');
    expect(ledger.recordInContext('r'), isFalse);
    expect(shown.recordIds, ['r']);
    expect(shown.recordIsWhole('missing'), isFalse);
    expect(() => shown.lineEntries.single.value.add(2), throwsUnsupportedError);
    shown.addRecord('r');
    expect(shown.recordIsWhole('r'), isTrue);
    expect(ledger.recordInContext('r'), isFalse);
  });
  test('canonical calls sort nested objects including objects in arrays', () {
    expect(
        canonicalCallKey('x', {
          'b': [
            {'z': 1, 'a': 2},
          ],
          'a': {'y': 1, 'x': 2},
        }),
        canonicalCallKey('x', {
          'a': {'x': 2, 'y': 1},
          'b': [
            {'a': 2, 'z': 1},
          ],
        }),);
    expect(
        canonicalCallKey('x', {
          'a': [1, 2],
        }),
        isNot(canonicalCallKey('x', {
          'a': [2, 1],
        }),),);
  });
}
