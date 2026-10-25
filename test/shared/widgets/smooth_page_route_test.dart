// The push as a frosted pane: the new page is not built while the pane
// comes in, is built behind it once it covers the screen, and the pane then
// clears where it is; going back needs no pane; reduced motion shows the
// page at once.
import 'package:arklores/shared/theme/motion.dart';
import 'package:arklores/shared/widgets/smooth_page_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counted extends StatelessWidget {
  const _Counted(this.builds);
  final List<int> builds;
  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const Text('pushed page');
  }
}

void main() {
  Widget app({bool reduced = false}) => ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: SmoothPageTransitionsBuilder(),
              },
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: const Scaffold(body: Text('first page')),
        ),
      );

  /// The cover's horizontal position, as a share of the screen: 1 off to
  /// the right, 0 over the screen, -1 gone to the left; null without one.
  double? coverAt(WidgetTester tester) {
    final cover = find.byKey(shutterCoverKey);
    if (cover.evaluate().isEmpty) return null;
    return tester.widget<FractionalTranslation>(cover).translation.dx;
  }

  testWidgets('the page is built only under the shut cover, then uncovered',
      (tester) async {
    await tester.pumpWidget(app());
    final builds = <int>[];
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(smoothPageRoute<void>(builder: (_) => _Counted(builds)));
    await tester.pump();
    await tester.pump(Motion.coverIn ~/ 2);
    expect(builds, isEmpty, reason: 'not built while the cover closes');
    expect(coverAt(tester), inExclusiveRange(0, 1));
    await tester.pump(Motion.coverIn);
    expect(builds, isNotEmpty, reason: 'built once the screen is covered');
    expect(coverAt(tester), 0, reason: 'still covered on that first frame');
    await tester.pump();
    await tester.pump(Motion.reveal ~/ 2);
    expect(coverAt(tester), 0, reason: 'clearing where it is');
    // Clearing steps through pictures blurred once, not a blur redone each
    // frame.
    final pane = find.byKey(shutterCoverKey);
    expect(
      find.descendant(of: pane, matching: find.byType(RawImage)),
      findsWidgets,
    );
    expect(
      find.descendant(of: pane, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    // A frame that takes long holds the clearing back; it does not jump.
    await tester.pump(Motion.reveal * 2);
    expect(coverAt(tester), 0, reason: 'one slow frame, still clearing');
    await tester.pumpAndSettle();
    expect(coverAt(tester), isNull);
    expect(find.text('pushed page'), findsOneWidget);

    // Back: the page below is there at once, no cover.
    nav.pop();
    await tester.pump();
    await tester.pump(Motion.shutterOut ~/ 2);
    expect(coverAt(tester), isNull);
    await tester.pumpAndSettle();
    expect(find.text('pushed page'), findsNothing);
    expect(find.text('first page'), findsOneWidget);
  });

  testWidgets('with reduced motion the page is there at once', (tester) async {
    await tester.pumpWidget(app(reduced: true));
    final builds = <int>[];
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(smoothPageRoute<void>(builder: (_) => _Counted(builds)));
    await tester.pump();
    await tester.pump();
    expect(builds, isNotEmpty);
    expect(coverAt(tester), isNull);
  });
}
