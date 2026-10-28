import 'package:arklores/core/agent/context_ledger.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/material_tools.dart';
import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('read_material preserves paragraphs and the original policy budget',
      () async {
    final snapshot = MaterialSnapshot(
      [MaterialSource(id: 's', title: '来源', enabled: true, policy: '说明' * 100)],
      [
        MaterialDocument(
          id: 'd',
          sourceId: 's',
          title: '资料',
          body: '正文',
          blocks: List.generate(8, (i) => MaterialBlock('正文$i' * 20, '')),
        ),
      ],
      const [],
    );
    final source = snapshot.sources.first;
    final key = materialSourceDescriptionKey(source.kind, source.policyVersion);
    final ledger = ContextLedger()
      ..record(0, SeenLines(),
          step: 3, callKey: 'first', contextDescriptions: [key],);
    final hits = snapshot.chunks.map((c) => MaterialHit(c, 1)).toList();
    final original = SeenLines(), deduped = SeenLines();
    final full = snapshot.render(hits, original.add, maxChars: 500);
    final pointer = snapshot.render(hits, deduped.add,
        maxChars: 500, contextDescriptionStep: ledger.stepOfContextDescription,);
    expect(deduped.toJson(), original.toJson());
    expect(full, contains('本次篇幅已满；继续读取'));
    expect(pointer, contains(full.substring(full.indexOf('本次篇幅已满'))));
    final read = ReadMaterialTool(snapshot, SeenLines(), ledger: ledger);
    final output = await read.execute({'id': snapshot.documents.first.pageId});
    expect(output, contains('来源说明同第 3 步'));
    expect(output, contains('P0'));
    expect(read.description, contains('指那一步结果里的全文'));
    ledger.clear();
    expect(await read.execute({'id': snapshot.documents.first.pageId}),
        contains(source.policy),);
  });

  test(
      'source notes point to a visible full explanation and return after forget',
      () async {
    const policy = '按资料作者的说明理解正文。';
    const kind = '设定资料';
    final snapshot = MaterialSnapshot(
      [
        const MaterialSource(
          id: 'source-a',
          title: '第一份',
          enabled: true,
          kind: kind,
          policy: policy,
        ),
        const MaterialSource(
          id: 'source-b',
          title: '第二份',
          enabled: true,
          kind: kind,
          policy: policy,
        ),
      ],
      [
        for (final (i, source) in ['source-a', 'source-b'].indexed)
          MaterialDocument(
            id: 'document-$i',
            sourceId: source,
            title: '资料 $i',
            body: '正文 $i',
            blocks: [MaterialBlock('正文 $i', '')],
          ),
      ],
      const [],
    );
    final hits = [for (final chunk in snapshot.chunks) MaterialHit(chunk, 1)];
    final ledger = ContextLedger();
    final seen = SeenLines();
    String render({bool withLedger = true}) => snapshot.render(
          hits,
          seen.add,
          contextDescriptionStep:
              withLedger ? ledger.stepOfContextDescription : null,
          onContextDescriptionPrinted:
              withLedger ? seen.addContextDescription : null,
        );

    final firstShown = SeenLines();
    final first = await SeenLines.duringCall(
      firstShown,
      () async => render(),
    );
    expect(first, contains(policy));
    expect('来源：'.allMatches(first).length, 1);
    expect(first, isNot(contains('来源说明同第')));
    ledger.record(10, firstShown, step: 2, callKey: 'search:first');

    final concurrentShown = SeenLines();
    final prepared = await SeenLines.duringCall(
      concurrentShown,
      () async => snapshot.render(
        hits,
        seen.add,
        contextDescriptionStep: (_) => null,
        onContextDescriptionPrinted: seen.addContextDescription,
      ),
    );
    final emitted = snapshot.dedupeVisibleSourceNotes(
      prepared,
      contextDescriptionStep: ledger.stepOfContextDescription,
      onContextDescriptionElided: concurrentShown.removeContextDescription,
    );
    expect(emitted, contains('来源说明同第 2 步'));
    expect(concurrentShown.contextDescriptions, isEmpty);

    final secondShown = SeenLines();
    final second = await SeenLines.duringCall(
      secondShown,
      () async => render(),
    );
    expect(second, contains('来源说明同第 2 步'));
    expect(second, isNot(contains(policy)));
    expect(secondShown.contextDescriptions, isEmpty);
    ledger.record(11, secondShown, step: 3, callKey: 'search:second');

    final key = materialSourceDescriptionKey(
        kind, snapshot.sources.first.policyVersion,);
    final restored =
        ContextLedger.fromJson(ledger.toJson()).remap({10: 20, 11: 21});
    expect(restored.stepOfContextDescription(key), 2);
    restored.forget([20]);
    expect(restored.stepOfContextDescription(key), isNull);
    ledger.forget([10]);
    expect(render(), contains(policy));

    expect(render(withLedger: false), contains(policy));
    expect(render(withLedger: false), contains(policy));
  });
}
