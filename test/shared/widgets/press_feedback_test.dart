// Tap feedback: a pressed surface sinks and springs back; a drag lets it
// go; a disabled one does nothing.
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
}
