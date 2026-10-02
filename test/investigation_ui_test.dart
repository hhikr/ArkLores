import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/story_answer.dart';
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
  group('story answer UI parsing helpers', () {
    test('parses the legacy coverage line of old sessions', () {
      final line = parseCoverageReportLine(
        'Coverage: read=2 | mapped=1 | skipped=0',
      );
      expect(line, isNotNull);
      expect(line!.read, '2');
      expect(line.mapped, '1');
      expect(line.skipped, '0');
    });

    test('extracts line references and strips markers', () {
      final content =
          '${formatStoryAnswerEnvelope(StoryAnswerStatus.answered, confidence: '0.8')}\n'
          '证据：activities/act_fixture/level_fixture_c5.txt:0 与 '
          'activities/act_fixture/level_fixture_c1.txt:2。\n\n'
          'Coverage: read=1 | mapped=1 | skipped=0';
      expect(isStoryAnswer(content), isTrue);
      expect(extractLineReferences(content), [
        'activities/act_fixture/level_fixture_c1.txt:2',
        'activities/act_fixture/level_fixture_c5.txt:0',
      ]);
      final stripped = stripStoryAnswerMarkers(content);
      expect(stripped, isNot(contains('STORY_ANSWER')));
      expect(stripped, isNot(contains('Coverage: read=')));
      expect(stripped, contains('证据'));

      const legacy = '[INVESTIGATION_VERDICT: culprit=x | confidence=0.5 | '
          'basis=b]\n正文';
      expect(isStoryAnswer(legacy), isTrue);
      expect(stripStoryAnswerMarkers(legacy), '正文');
    });
  });

  group('story answer chat bubble rendering', () {
    Future<void> pumpBubble(WidgetTester tester, String content) async {
      final message = ChatMessage(
        id: 'story-answer',
        role: MessageRole.assistant,
        content: content,
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
    }

    testWidgets('shows status, confidence and cited lines', (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpBubble(
        tester,
        '${formatStoryAnswerEnvelope(StoryAnswerStatus.answered, confidence: '0.8')}\n'
        '答案正文。证据：activities/act_fixture/level_fixture_c5.txt:0。',
      );

      // R15: status and confidence share one line; no avatars.
      expect(find.text('已作答 · 置信度 0.8'), findsOneWidget);
      expect(find.byIcon(Icons.psychology_rounded), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
      // R15: evidence is folded to one line until tapped.
      expect(find.text('证据 1 处 · 来自 1 个故事'), findsOneWidget);
      expect(find.text('第 1 行'), findsNothing);
      await tester.tap(find.text('证据 1 处 · 来自 1 个故事'));
      await tester.pumpAndSettle();
      // Collection → chapter → line chip (no catalog in this test, so the
      // names come from the path); a single chapter starts open.
      expect(find.text('活动 act_fixture · 1 处'), findsOneWidget);
      expect(find.text('level_fixture_c5 · 1 处'), findsOneWidget);
      expect(find.text('第 1 行'), findsOneWidget);
      // R14: the body shows a readable source and a 1-based line number.
      expect(
        find.textContaining('activities/act_fixture/level_fixture_c5.txt'),
        findsNothing,
      );
      // The envelope is stripped from the markdown body.
      expect(find.textContaining('STORY_ANSWER'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders not-covered and legacy answers', (tester) async {
      await pumpBubble(
        tester,
        '${formatStoryAnswerEnvelope(StoryAnswerStatus.notCovered, confidence: '0')}\n'
        '知识库未找到相关内容。',
      );
      expect(find.textContaining('知识库未覆盖'), findsWidgets);

      await pumpBubble(
        tester,
        '[INVESTIGATION_VERDICT: culprit=unresolved | confidence=0 | '
        'basis=insufficient_evidence]\n证据不足。\n\n'
        'Coverage: read=1 | mapped=1 | skipped=0',
      );
      expect(find.textContaining('部分作答'), findsOneWidget);
      expect(find.textContaining('精读=1'), findsOneWidget);
      expect(find.textContaining('INVESTIGATION_VERDICT'), findsNothing);
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
            llmClientProvider.overrideWith((ref, level) => _SilentLLMClient()),
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

      // R15: the tabs are the app bar; the mode picker is one chip in the
      // input row whose menu lists the modes with their descriptions.
      expect(find.text('AI 问答'), findsWidgets); // tab + empty-state title
      expect(find.text('角色扮演'), findsOneWidget); // Roleplay tab
      expect(find.text('自动'), findsOneWidget); // mode chip
      expect(find.text('概括'), findsNothing);
      expect(find.textContaining('直接问任何剧情问题'), findsOneWidget);
      await tester.tap(find.byTooltip('回答方式'));
      await tester.pumpAndSettle();
      expect(find.text('概括'), findsOneWidget);
      expect(find.text('查证'), findsOneWidget);
      expect(find.text('深挖'), findsOneWidget);
      expect(find.textContaining('判定一个说法的真假'), findsOneWidget);
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
}
