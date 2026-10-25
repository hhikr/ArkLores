// Tap feedback: a pressed surface sinks and springs back; a drag lets it
// go; a disabled one does nothing. PressHold: pressed at once, a quick tap
// still seen.
import 'package:arklores/shared/theme/motion.dart';
import 'package:arklores/shared/widgets/press_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  Widget app({bool enabled = true, VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressFeedback(
              enabled: enabled,
              child: InkWell(
                onTap: withHaptic(onTap ?? () {}),
                child: const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );

  testWidgets('sinks while pressed, springs back on release, taps go through',
      (tester) async {
    var taps = 0;
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      },
    );
    await tester.pumpWidget(app(onTap: () => taps++));
    expect(_scale(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkWell)),
    );
    await tester.pump();
    expect(_scale(tester), lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(taps, 1);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('a drag (a scroll starting on it) lets it go', (tester) async {
    await tester.pumpWidget(app());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkWell)),
    );
    await tester.pump();
    expect(_scale(tester), lessThan(1));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(_scale(tester), 1);
    await gesture.up();
  });

  testWidgets('disabled: no scale at all', (tester) async {
    await tester.pumpWidget(app(enabled: false));
    expect(find.byType(AnimatedScale), findsNothing);
  });

  test('withHaptic keeps a disabled control disabled', () {
    expect(withHaptic(null), isNull);
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

    testWidgets('pressed as soon as the finger lands', (tester) async {
      await tester.pumpWidget(host());
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
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
      // (the hold is measured from the touch on the real clock, so at most
      // Motion.press after the release)
      await tester.pump(Motion.press);
      expect(shown(tester), isFalse);
    });

    testWidgets('a scroll starting on it lets go at once', (tester) async {
      await tester.pumpWidget(host());
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(_Mark)));
      await tester.pump();
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
  Widget build(BuildContext context) =>
      const SizedBox(width: 120, height: 60);
}
