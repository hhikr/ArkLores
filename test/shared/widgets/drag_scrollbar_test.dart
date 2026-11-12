// The scrollbar of a fixed window (the thinking, the portrait thumbnails):
// the thumb shows where the view is, also as the content grows, and dragging
// it or tapping the strip scrolls.
import 'package:arklores/shared/widgets/drag_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plain_theme.dart';

void main() {
  late ScrollController controller;
  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  Future<void> pump(WidgetTester tester, int lines) => tester.pumpWidget(
        ProviderScope(
          overrides: [plainThemeOverride()],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 200,
                  child: DragScrollbar(
                    controller: controller,
                    child: ListView(
                      controller: controller,
                      itemExtent: 20,
                      children: [for (var i = 0; i < lines; i++) Text('第$i行')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Rect thumb(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('drag-scrollbar-thumb')));

  testWidgets('nothing is drawn while everything fits', (tester) async {
    await pump(tester, 5);
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-scrollbar')), findsNothing);
  });

  testWidgets('the thumb has the share in view and follows the view',
      (tester) async {
    await pump(tester, 40); // 800 high in a 200 window
    await tester.pump();
    final top = tester.getTopLeft(find.byType(DragScrollbar)).dy;
    expect(thumb(tester).height, closeTo(50, 0.5));
    expect(thumb(tester).top, closeTo(top, 0.5));

    controller.jumpTo(600); // the end
    await tester.pump();
    expect(thumb(tester).bottom, closeTo(top + 200, 0.5));

    controller.jumpTo(300); // half way
    await tester.pump();
    expect(thumb(tester).top, closeTo(top + 75, 0.5));
  });

  testWidgets('the thumb shrinks as the content grows, without a scroll',
      (tester) async {
    await pump(tester, 20);
    await tester.pump();
    expect(thumb(tester).height, closeTo(100, 0.5));
    await pump(tester, 40);
    await tester.pump();
    await tester.pump();
    expect(thumb(tester).height, closeTo(50, 0.5));
    expect(controller.offset, 0);
  });

  testWidgets('dragging the thumb scrolls, a tap on the strip pages',
      (tester) async {
    await pump(tester, 40);
    await tester.pump();
    // The thumb travels 150 for 600 of content.
    await tester.drag(
      find.byKey(const ValueKey('drag-scrollbar')),
      const Offset(0, 75),
    );
    await tester.pump();
    expect(controller.offset, closeTo(300, 1));

    controller.jumpTo(0);
    await tester.pump();
    final strip = tester.getRect(find.byKey(const ValueKey('drag-scrollbar')));
    await tester.tapAt(Offset(strip.center.dx, strip.bottom - 5));
    await tester.pump();
    expect(controller.offset, closeTo(180, 1)); // nine tenths of the window
  });
}
