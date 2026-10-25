// The main screen's bars out of the way while the wiki or Ask is read: the
// drags that hide and show them, and what moves with them (only moved).
import 'package:arklores/shared/providers/bars_provider.dart';
import 'package:arklores/shared/widgets/page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WidgetRef ref;

  Widget app({bool keyboard = false}) => ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 800),
              viewInsets: EdgeInsets.only(bottom: keyboard ? 300 : 0),
            ),
            child: Consumer(
              builder: (context, r, _) {
                ref = r;
                return Stack(
                  children: [
                    const MainTopBar(leading: Text('bar'), hides: true),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: BarsAway(
                        distance: 60,
                        child: Container(
                          key: const ValueKey('box'),
                          width: 10,
                          height: 10,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

  double shift(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('box')),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .getTranslation()
      .y;

  testWidgets('dragged on, the bars go; dragged back, they come back',
      (tester) async {
    await tester.pumpWidget(app());
    final bars = BarsFollower();
    expect(shift(tester), 0);

    bars.moved(ref, 10, atTop: false);
    await tester.pumpAndSettle();
    expect(shift(tester), 0, reason: 'a small move does nothing');

    bars.moved(ref, 30, atTop: false);
    await tester.pumpAndSettle();
    expect(shift(tester), 60, reason: 'what sits on the tab bar goes down');
    expect(
      find.text('bar').hitTestable(),
      findsNothing,
      reason: 'the top bar is up under the status bar',
    );

    bars.moved(ref, -10, atTop: false);
    await tester.pumpAndSettle();
    expect(shift(tester), 60);
    bars.moved(ref, -30, atTop: false);
    await tester.pumpAndSettle();
    expect(shift(tester), 0);
    expect(find.text('bar').hitTestable(), findsOneWidget);

    bars.moved(ref, 100, atTop: false);
    await tester.pumpAndSettle();
    expect(shift(tester), 60);
    bars.moved(ref, 0, atTop: true);
    await tester.pumpAndSettle();
    expect(shift(tester), 0, reason: 'at the top of the page');
  });

  testWidgets('with the keyboard up nothing moves', (tester) async {
    await tester.pumpWidget(app(keyboard: true));
    ref.read(barsHiddenProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(shift(tester), 0);
  });
}
