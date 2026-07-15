import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'fact-check verdict and GameData evidence render on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final message = ChatMessage(
      id: 'answer',
      role: MessageRole.assistant,
      content: '[FACT_CHECK_VERDICT:supported]\n## 核查结论\nGameData 支持该说法。',
      factCheckVerdict: FactCheckVerdict.supported,
      steps: const [
        ReActStep(
          type: ReActEventType.toolObservation,
          content: '=== Result #1 ===\nSource Kind: GameData\n'
              'Content Type: operator_profile\n'
              'Source Path: character_table.json\nRaw ID: char_002_amiya',
        ),
      ],
      timestamp: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(child: ChatBubble(message: message)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('支持'), findsOneWidget);
    expect(find.text('GameData 证据（1）'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('GameData 证据（1）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('character_table.json'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
