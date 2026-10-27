import 'package:arklores/core/agent/context_ledger.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/material_tools.dart';
import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a missing material lookup reports the id without lookup instructions',
      () {
    final snapshot = MaterialSnapshot(const [], const [], const []);
    final result = snapshot.read(
      'material:missing@version',
      0,
      12,
      (id, paragraph) {},
    );

    expect(result, '没有这份已启用资料或该版本：material:missing@version。');
    expect(result, isNot(contains('先用 search')));
    expect(
      ReadMaterialTool(snapshot, SeenLines()).description,
      contains('找不到 id 时按名字用 search'),
    );
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

    ledger.forget([10]);
    expect(render(), contains(policy));

    expect(render(withLedger: false), contains(policy));
    expect(render(withLedger: false), contains(policy));
  });
}
