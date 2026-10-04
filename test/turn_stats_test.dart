import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/turn_stats.dart';
import 'package:arklores/core/llm/llm_client.dart' show MessageRole;
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatting', () {
    test('token counts', () {
      expect(formatTokenCount(950), '950');
      expect(formatTokenCount(14000), '14.0k');
      expect(formatTokenCount(38200), '38.2k');
      expect(formatTokenCount(381562), '382k');
      expect(formatTokenCount(1500000), '1.5M');
    });

    test('elapsed time', () {
      expect(formatElapsed(const Duration(seconds: 42)), '42s');
      expect(formatElapsed(const Duration(seconds: 360)), '6m00s');
      expect(formatElapsed(const Duration(seconds: 262)), '4m22s');
    });
    test('cache rate needs input and a reported cache', () {
      expect(const TurnStats().cacheRate, isNull);
      expect(const TurnStats(promptTokens: 100).cacheRate, isNull);
      expect(
        const TurnStats(promptTokens: 200, cachedPromptTokens: 150).cacheRate,
        0.75,
      );
    });

    test('json round trip', () {
      const stats = TurnStats(
        calls: 14,
        promptTokens: 381562,
        cachedPromptTokens: 332736,
        completionTokens: 11665,
        elapsed: Duration(milliseconds: 262000),
        rateLimitRetries: 2,
        rateLimitSleep: Duration(seconds: 7),
      );
      final back = TurnStats.fromJson(stats.toJson().cast<String, dynamic>());
      expect(back.calls, 14);
      expect(back.elapsed, const Duration(seconds: 262));
      expect(back.rateLimitSleep, const Duration(seconds: 7));
      expect(back.promptTokens, 381562);
    });
  });

  group('the line under an answer', () {
    Future<void> pump(WidgetTester tester, TurnStats? stats, {Locale? locale}) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: locale ?? const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ChatBubble(
                    message: ChatMessage(
                      id: 'a',
                      role: MessageRole.assistant,
                      content: '一段回答。',
                      stats: stats,
                      timestamp: DateTime(2026),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('shows tokens, cache share, calls and time', (tester) async {
      await pump(
        tester,
        const TurnStats(
          calls: 14,
          promptTokens: 381562,
          cachedPromptTokens: 332736,
          completionTokens: 11665,
          elapsed: Duration(seconds: 262),
        ),
      );
      expect(
        find.text('in 382k · out 11.7k · cache 87% · 14 calls · 4m22s'),
        findsOneWidget,
      );
    });

    testWidgets('a provider without usage shows what it has', (tester) async {
      await pump(
        tester,
        const TurnStats(calls: 3, elapsed: Duration(seconds: 9)),
      );
      expect(find.text('3 calls · 9s'), findsOneWidget);
    });

    testWidgets('the same in English', (tester) async {
      await pump(
        tester,
        const TurnStats(
          calls: 2,
          promptTokens: 1200,
          completionTokens: 300,
          elapsed: Duration(seconds: 65),
        ),
        locale: const Locale('en'),
      );
      expect(find.text('in 1.2k · out 300 · 2 calls · 1m05s'), findsOneWidget);
    });
    testWidgets('no stats, no line', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const ValueKey('usage-line')), findsNothing);
    });
  });
}
