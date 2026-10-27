import 'dart:ui' as ui;

import 'package:arklores/shared/theme/motion.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'slider snaps equally, emits changes during drag, saves on release, haptics',
      (tester) async {
    var value = 0.0;
    final changes = <double>[];
    final ends = <double>[];
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppSlider(
                value: value,
                max: 6,
                divisions: 6,
                semanticValue: '32k',
                onChanged: (next) {
                  setState(() => value = next);
                  changes.add(next);
                },
                onChangeEnd: ends.add,
              ),
            ),
          ),
        ),
      ),
    );
    final slider = find.byType(AppSlider);
    final rect = tester.getRect(slider);
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(value, 3);
    expect(ends, [3]);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.moveTo(Offset(rect.right - 14, rect.center.dy));
    await tester.pump();
    expect(value, 6);
    expect(ends, [3]);
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byType(TweenAnimationBuilder<double>),
          )
          .duration,
      Duration.zero,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(ends, [3, 6]);
    expect(changes.length, greaterThan(1));
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(slider)
          .getSemanticsData()
          .hasAction(SemanticsAction.decrease),
      isTrue,
    );
    tester.binding.platformDispatcher.onSemanticsActionEvent!(
        ui.SemanticsActionEvent(
            nodeId: tester.getSemantics(slider).id,
            type: SemanticsAction.decrease,
            viewId: tester.view.viewId,),);
    await tester.pumpAndSettle();
    expect(value, 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(value, 4);
    semantics.dispose();
  });

  testWidgets(
      'external value and track taps animate, reduced motion is immediate',
      (tester) async {
    Widget host(double value, bool reduced) => ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(body: AppSlider(value: value, onChanged: (_) {})),
            ),
          ),
        );
    await tester.pumpWidget(host(0, false));
    final thumb = find.byKey(const ValueKey('app-slider-thumb'));
    final left = tester.getTopLeft(thumb).dx;
    await tester.pumpWidget(host(1, false));
    expect(tester.getTopLeft(thumb).dx, left);
    await tester.pump(const Duration(milliseconds: 50));
    final middle = tester.getTopLeft(thumb).dx;
    expect(middle, greaterThan(left));
    await tester.pump(Motion.row);
    expect(tester.getTopLeft(thumb).dx, greaterThan(middle));
    await tester.pumpWidget(host(0, true));
    await tester.pump();
    expect(tester.getTopLeft(thumb).dx, left);
    expect(tester.getSize(find.byType(AppSlider)).height, 48);
  });
}
