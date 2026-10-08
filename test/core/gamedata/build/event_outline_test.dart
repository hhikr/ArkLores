import 'package:arklores/core/gamedata/build/event_outline.dart';
import 'package:arklores/features/library/library_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EventChoice c(String title, String next, [String text = '', String own = '']) =>
    (title: title, text: text, next: next, own: own);

void main() {
  group('eventOutline', () {
    String said(String key) => {'a': '甲说。', 'b': '乙说。', 'c': ''}[key] ?? '';

    test('options carry the text after choosing them', () {
      expect(
        eventOutline([c('左', 'a'), c('右', 'b', '说明'), c('走', 'c')], said),
        '- **左**\n甲说。\n- **右**：说明\n乙说。\n- **走**',
      );
    });

    test('the scene numbered like a choice is said first, then the one it '
        'leads to', () {
      expect(
        eventOutline([c('拿', 'a', '', 'b')], said),
        '- **拿**\n乙说。\n甲说。',
      );
    });

    test('a choice naming no scene opens a layer for the choices after it', () {
      expect(
        eventOutline([c('开始', ''), c('拿', 'a'), c('放', 'b')], said),
        '- **开始**\n-- **拿**\n甲说。\n-- **放**\n乙说。',
      );
    });

    test('variants of one outcome are listed once; the same words are '
        'not repeated within a layer', () {
      expect(
        eventOutline([c('拿', 'a'), c('拿', 'a'), c('取', 'a')], said),
        '- **拿**\n甲说。\n- **取**\n（结果同上）',
      );
    });

    test('a layer that repeats an earlier one word for word is dropped', () {
      final out = eventOutline([
        c('开始', ''),
        c('拿', 'a'),
        c('再来', ''),
        c('拿', 'a'),
        c('再来', ''),
        c('拿', 'a'),
      ], said,);
      expect(
        out,
        '- **开始**\n'
        '-- **拿**\n甲说。\n'
        '-- **再来**',
      );
    });
  });

  testWidgets('event options fold, one layer inside the other', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EventText(
                '## 事件\n开场。\n\n'
                '## 选项\n- **开始**\n-- **拿**\n甲说。\n-- **放**',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('开场。'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('甲说。'), findsNothing);
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    expect(find.text('拿'), findsOneWidget);
    expect(find.text('放'), findsOneWidget);
    expect(find.text('甲说。'), findsNothing);
    await tester.tap(find.text('拿'));
    await tester.pumpAndSettle();
    expect(find.text('甲说。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
