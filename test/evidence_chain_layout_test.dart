// The folded sources under an answer point, opened: sources of one story
// collection share one header, its chapters sit indented under it, and the
// line chips of a chapter stay on that chapter's row.
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/llm/llm_client.dart' show MessageRole;
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _c5 = 'activities/act_fixture/level_fixture_c5.txt';
const _c6 = 'activities/act_fixture/level_fixture_c6.txt';
const _other = 'activities/act_other/level_other_c1.txt';

Future<void> _pump(WidgetTester tester, String answer) async {
  tester.view.physicalSize = const Size(640, 1280);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatBubble(
              message: ChatMessage(
                id: 'a',
                role: MessageRole.assistant,
                content: '[STORY_ANSWER: status=answered]\n$answer',
                timestamp: DateTime(2026),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('evidence-toggle')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chapters of one collection share a header and are indented',
      (tester) async {
    await _pump(tester, '一件事。 `$_c5:0-1` `$_c5:9` `$_c6:3`');

    // The collection name: once in the pill, once as the group header.
    expect(find.text('活动 act_fixture'), findsNWidgets(2));
    final c5 = find.text('level_fixture_c5');
    final c6 = find.text('level_fixture_c6');
    expect(c5, findsOneWidget);
    expect(c6, findsOneWidget);
    // The chapters are indented under the collection header.
    final header = find.text('活动 act_fixture').last;
    expect(
      tester.getTopLeft(c5).dx,
      greaterThan(tester.getTopLeft(header).dx + 6),
    );
    // Both ranges of the first chapter sit together (the test font is as wide
    // as it is tall, so a long name may push them onto its next line).
    final chip1 = find.byKey(const ValueKey('chain:$_c5:0-1'));
    final chip2 = find.byKey(const ValueKey('chain:$_c5:9'));
    expect(chip1, findsOneWidget);
    expect(chip2, findsOneWidget);
    expect(tester.getCenter(chip1).dy, tester.getCenter(chip2).dy);
    expect(tester.getCenter(chip1).dy - tester.getCenter(c5).dy, lessThan(30));
    // The second chapter follows close below (a compact card).
    final gap =
        tester.getCenter(find.byKey(const ValueKey('chain:$_c6:3'))).dy -
            tester.getCenter(chip1).dy;
    expect(gap, inInclusiveRange(18, 60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single chapter is one line: collection · chapter and chips',
      (tester) async {
    await _pump(tester, '一件事。 `$_c5:0-1`');
    final chip = find.byKey(const ValueKey('chain:$_c5:0-1'));
    final label = find.textContaining('level_fixture_c5');
    expect(label, findsOneWidget);
    expect(tester.getCenter(chip).dy - tester.getCenter(label).dy, lessThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('different collections each get their own header',
      (tester) async {
    await _pump(tester, '一件事。 `$_c5:0` `$_other:2`');
    // The pill lists both collections; each has its own group line.
    expect(find.textContaining('活动 act_fixture'), findsWidgets);
    expect(find.textContaining('act_other'), findsWidgets);
    expect(find.textContaining('level_fixture_c5'), findsOneWidget);
    expect(find.textContaining('level_other_c1'), findsOneWidget);
    expect(find.byKey(const ValueKey('chain:$_c5:0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chain:$_other:2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
