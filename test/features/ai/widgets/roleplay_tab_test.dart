import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/roleplay_agent.dart';
import 'package:arklores/core/agent/roleplay_session_store.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart' show MessageRole;
import 'package:arklores/features/ai/widgets/roleplay_tab.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_llm.dart';
import '../../../support/temp_dir.dart';

void main() {
  testWidgets('the setup, then a conversation with its disclaimer',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('roleplay_tab');
    addTearDown(() => deleteTempDir(dir));

    final controller = RoleplayNotifier(
      RoleplayAgent(llmClient: ScriptedLLM(['unused'])),
      RoleplaySessionStore(filePath: '${dir.path}/roleplay.json'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roleplayProvider.overrideWith((ref) => controller)],
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
    await tester.pumpAndSettle();
    expect(find.text('阿米娅'), findsWidgets);
    expect(find.textContaining('char_002_amiya'), findsWidgets);
    expect(
      find.text('角色事实依据 GameData 检索；对白与舞台说明均为 AI 生成内容，不是游戏官方台词。'),
      findsOneWidget,
    );
    expect(find.text('你好'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
