import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'the rail runs down with the body as it opens, stays open, and goes '
      'with it; the head does not move', (tester) async {
    var open = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topLeft,
                child: FoldBlock(
                  headKey: const ValueKey('head'),
                  open: open,
                  onTap: () => setState(() => open = !open),
                  head: const SizedBox(height: 48, width: 300),
                  body: () => const SizedBox(height: 200, width: 300),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final rail = find.descendant(
      of: find.byType(TraceRail),
      matching: find.byType(ColoredBox),
    );
    double length() => tester.getSize(rail).height;
    expect(length(), 0);
    final head = tester.getTopLeft(find.byKey(const ValueKey('head')));

    await tester.tap(find.byKey(const ValueKey('head')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final midway = length();
    expect(midway, greaterThan(0));
    expect(midway, lessThan(248), reason: 'it extends, it does not appear');
    await tester.pumpAndSettle();
    expect(length(), 248, reason: 'the head and the body');
    await tester.pump(const Duration(seconds: 2));
    expect(length(), 248, reason: 'it stays while open');
    expect(tester.getTopLeft(find.byKey(const ValueKey('head'))), head);
    expect(tester.getSize(rail).width, traceRailWidth);

    await tester.tap(find.byKey(const ValueKey('head')));
    await tester.pumpAndSettle();
    expect(length(), 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey('head'))), head);
  });
}
