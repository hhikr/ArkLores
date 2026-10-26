import 'package:arklores/shared/theme/motion.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:arklores/shared/widgets/press_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'withHaptic keeps disabled controls disabled',
    () => expect(withHaptic(null), isNull),
  );
  testWidgets(
      'scroll on PressRow never shifts content or paints its trace in any frame',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                PressRow(
                  onTap: () {},
                  child:
                      const SizedBox(key: ValueKey('row-content'), height: 70),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    void check() {
      final row = find.byType(PressRow);
      final containers = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: row,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .toList();
      expect(containers.first.transform!.getTranslation().x, 0);
      for (final transform in tester.widgetList<Transform>(
        find.descendant(of: row, matching: find.byType(Transform)),
      )) {
        expect(transform.transform.getTranslation().x, 0);
      }
      // The trace rail has not started down the row.
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.descendant(of: row, matching: find.byType(TraceRail)),
                matching: find.byType(ColoredBox),
              ),
            )
            .height,
        0,
      );
    }

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('row-content'))),
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      check();
    }
    await gesture.moveBy(const Offset(0, -30));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      check();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    check();
  });
  group('PressHold', () {
    // In a list, where a tap's own onTapDown waits 100 ms for a drag.
    Widget host({bool enabled = true, VoidCallback? onTap}) => MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                _Holder(enabled: enabled, onTap: onTap ?? () {}),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        );
    bool shown(WidgetTester tester) =>
        tester.widget<_Mark>(find.byType(_Mark)).pressed;

    testWidgets('pressed only after a stationary touch survives 100 ms',
        (tester) async {
      await tester.pumpWidget(host());
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
      expect(shown(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(shown(tester), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a quick tap stays pressed for Motion.press, then lets go',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(onTap: () => taps++));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pump();
      expect(taps, 1);
      expect(shown(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 99));
      expect(shown(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shown(tester), isFalse);
    });

    testWidgets('a scroll starting on it lets go at once', (tester) async {
      await tester.pumpWidget(host());
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
      expect(shown(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(shown(tester), isTrue);
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(shown(tester), isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('disabled: never pressed', (tester) async {
      await tester.pumpWidget(host(enabled: false));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
      expect(shown(tester), isFalse);
      await gesture.up();
    });

    testWidgets('PressBuilder: the same for a part without state',
        (tester) async {
      var taps = 0;
      Widget built({required bool enabled}) => MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  PressBuilder(
                    enabled: enabled,
                    builder: (context, down) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                      child: _Mark(pressed: down),
                    ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          );
      await tester.pumpWidget(built(enabled: true));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
      expect(shown(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(shown(tester), isTrue);
      await gesture.up();
      await tester.pump();
      expect(taps, 1);
      expect(shown(tester), isTrue);
      await tester.pump(Motion.press);
      expect(shown(tester), isFalse);

      await tester.pumpWidget(built(enabled: false));
      final again =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
      expect(shown(tester), isFalse);
      await again.up();
    });
  });
}

class _Holder extends StatefulWidget {
  const _Holder({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_Holder> createState() => _HolderState();
}

class _HolderState extends State<_Holder> with PressHold<_Holder> {
  @override
  Widget build(BuildContext context) => pressListener(
        enabled: widget.enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: _Mark(pressed: pressed),
        ),
      );
}

class _Mark extends StatelessWidget {
  const _Mark({required this.pressed});

  final bool pressed;

  @override
  Widget build(BuildContext context) => const SizedBox(width: 120, height: 60);
}
