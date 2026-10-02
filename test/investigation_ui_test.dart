import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/investigation_verdict.dart';
import 'package:arklores/core/agent/story_coverage_transform.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/features/ai/ai_chat_page.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('investigation UI parsing helpers', () {
    test('parses the verdict envelope', () {
      final envelope = parseInvestigationVerdictLine(
        '[INVESTIGATION_VERDICT: culprit=char_b | confidence=0.8 | basis=multi_hypothesis_contrast]',
      );
      expect(envelope, isNotNull);
      expect(envelope!.culprit, 'char_b');
      expect(envelope.confidence, '0.8');
      expect(envelope.basis, 'multi_hypothesis_contrast');
      expect(
        parseInvestigationVerdictLine('no verdict here'),
        isNull,
      );
    });

    test('parses the coverage line', () {
      final line = parseCoverageReportLine(
        'Coverage: read=2 | mapped=1 | skipped=0',
      );
      expect(line, isNotNull);
      expect(line!.read, '2');
      expect(line.mapped, '1');
      expect(line.skipped, '0');
    });

    test('extracts line references and strips markers', () {
      const content =
          '[INVESTIGATION_VERDICT: culprit=char_b | confidence=0.8 | basis=multi_hypothesis_contrast]\n'
          '证据链：activities/act_fixture/level_fixture_c5.txt:0 与 '
          'activities/act_fixture/level_fixture_c1.txt:2。\n\n'
          'Coverage: read=1 | mapped=1 | skipped=0';
      expect(isInvestigationAnswer(content), isTrue);
      expect(extractLineReferences(content), [
        'activities/act_fixture/level_fixture_c1.txt:2',
        'activities/act_fixture/level_fixture_c5.txt:0',
      ]);
      final stripped = stripInvestigationMarkers(content);
      expect(stripped, isNot(contains('INVESTIGATION_VERDICT')));
      expect(stripped, isNot(contains('Coverage: read=')));
      expect(stripped, contains('证据链'));
    });
  });

  group('investigation chat bubble rendering', () {
    testWidgets('shows verdict, evidence chain refs and coverage bar',
        (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final message = ChatMessage(
        id: 'investigation-answer',
        role: MessageRole.assistant,
        content:
            '[INVESTIGATION_VERDICT: culprit=char_b | confidence=0.8 | basis=multi_hypothesis_contrast]\n'
            '角色B是凶手。证据链：'
            'activities/act_fixture/level_fixture_c5.txt:0。\n\n'
            'Coverage: read=1 | mapped=1 | skipped=0',
        timestamp: DateTime(2026),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ChatBubble(message: message)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('调查结论'), findsOneWidget);
      expect(find.textContaining('char_b'), findsWidgets);
      expect(find.textContaining('置信度: 0.8'), findsOneWidget);
      expect(find.text('证据链引用'), findsOneWidget);
      expect(
        find.text('activities/act_fixture/level_fixture_c5.txt:0'),
        findsOneWidget,
      );
      expect(find.textContaining('已读范围'), findsOneWidget);
      expect(find.textContaining('精读=1'), findsOneWidget);
      // Markers are stripped from the markdown body.
      expect(find.textContaining('INVESTIGATION_VERDICT'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks unresolved verdicts with the warning accent',
        (tester) async {
      final message = ChatMessage(
        id: 'investigation-unresolved',
        role: MessageRole.assistant,
        content:
            '[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | basis=insufficient_evidence]\n'
            '证据不足。',
        timestamp: DateTime(2026),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ChatBubble(message: message)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('unresolved'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('AI page entry consolidation', () {
    testWidgets('shows two tabs with the Ask mode selector and empty state',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialApiConfigProvider.overrideWithValue(
              const LLMConfig(chatApiKey: 'test-key'),
            ),
            llmClientProvider.overrideWithValue(_SilentLLMClient()),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AiChatPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('剧情智囊'), findsOneWidget); // AppBar title
      expect(find.text('AI 问答'), findsWidgets); // tab + empty-state title
      expect(find.text('角色扮演'), findsOneWidget); // Roleplay tab
      expect(find.text('自动'), findsOneWidget); // mode chips
      expect(find.text('概括'), findsOneWidget);
      expect(find.text('查证'), findsOneWidget);
      expect(find.text('深挖'), findsOneWidget);
      expect(find.textContaining('直接问任何剧情问题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _SilentLLMClient extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return 'Final Answer: silent';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}
