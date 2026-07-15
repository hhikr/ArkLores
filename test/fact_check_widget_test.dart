import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/roleplay_agent.dart';
import 'package:arklores/core/agent/roleplay_session_store.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/features/ai/widgets/roleplay_tab.dart';
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

  testWidgets('roleplay tab renders setup and conversation states',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = RoleplayNotifier(
      RoleplayAgent(llmClient: _SilentLLMClient()),
      const RoleplaySessionStore(filePath: '/tmp/arklores-roleplay-test.json'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleplayProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: RoleplayTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择角色'), findsOneWidget);
    expect(find.text('解析角色并开始'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.state = RoleplayState(
      character: const GameDataEntityCandidate(
        entityId: 'char_002_amiya',
        name: '阿米娅',
        entityType: 'operator',
        sourceType: 'operator_handbook_profile',
        sourcePath: 'zh_CN/gamedata/excel/handbook_info_table.json',
        matchedAlias: '阿米娅',
        matchType: 'name_exact',
        confidence: 1,
      ),
      scene: '测试场景',
      messages: [
        ChatMessage(
          id: 'u1',
          role: MessageRole.user,
          content: '你好',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'a1',
          role: MessageRole.assistant,
          content: '你好。',
          timestamp: DateTime(2026),
        ),
      ],
    );
    controller.state = controller.state.copyWith();
    await tester.pumpAndSettle();

    expect(find.text('阿米娅'), findsWidgets);
    expect(find.textContaining('char_002_amiya'), findsWidgets);
    expect(find.text('角色事实依据 GameData 检索；对白与舞台说明均为 AI 生成内容，不是游戏官方台词。'),
        findsOneWidget);
    expect(find.text('你好'), findsWidgets);
    expect(tester.takeException(), isNull);
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) {
    throw UnimplementedError();
  }
}
