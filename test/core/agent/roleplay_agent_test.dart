import 'dart:io';

import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/roleplay_agent.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/amiya_fixture.dart';
import '../../support/fake_llm.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(useSqfliteFfi);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('roleplay_agent');
    dbPath = '${dir.path}/arklores_gamedata_zh.db';
  });
  tearDown(() => deleteTempDir(dir));

  RoleplayAgent agent({AgentTool? searchTool, ScriptedLLM? llm}) {
    final store = GameDataKnowledgeStore(dbPath: dbPath);
    addTearDown(store.close);
    return RoleplayAgent(
      llmClient: llm ?? ScriptedLLM([reactFinal('x')]),
      gameDataStore: store,
      searchTool: searchTool,
    );
  }

  test('resolves one character to a stable entity id', () async {
    await createAmiyaDb(dbPath);
    final result = await agent().resolveCharacter('阿米娅');
    expect(result.status, CharacterResolutionStatus.resolved);
    expect(result.character?.entityId, amiyaId);
    expect(result.character?.name, '阿米娅');
  });

  test('a shared alias needs disambiguation', () async {
    await createAmiyaDb(dbPath, extra: addAmbiguousAmiya);
    final result = await agent().resolveCharacter('Amiya');
    expect(result.status, CharacterResolutionStatus.ambiguous);
    expect(result.candidates, hasLength(2));
  });

  test('without a knowledge base resolution is unavailable', () async {
    final result = await agent().resolveCharacter('阿米娅');
    expect(result.status, CharacterResolutionStatus.unavailable);
  });

  test('a reply searches the character first and states the rules', () async {
    await createAmiyaDb(dbPath);
    final tool = _CaptureTool();
    final llm = ScriptedLLM([
      reactAction('search_local_lore',
          '{"query":"切尔诺伯格 任务","entity_id":"char_002_amiya"}',
          thought: '检索任务记忆。',),
      reactFinal('……我记得那次行动。', thought: '已依据资料回应。'),
    ]);
    const character = GameDataEntityCandidate(
      entityId: amiyaId,
      name: '阿米娅',
      entityType: 'operator',
      sourceType: 'operator_handbook_profile',
      matchedAlias: '阿米娅',
      matchType: 'name_exact',
      confidence: 1,
    );

    final events = await agent(searchTool: tool, llm: llm)
        .reply(
          character: character,
          userMessage: '还记得切尔诺伯格的任务吗？',
          scene: '2030 年庆典',
          isFirstTurn: true,
        )
        .toList();

    // The search stays bound to the character whatever the model passed.
    expect(tool.lastArgs?['entity_id'], amiyaId);
    final systemPrompt = llm.received.first.first.content;
    expect(systemPrompt, contains('秘录、模组'));
    expect(systemPrompt, contains('NOT GameData evidence'));
    expect(systemPrompt, contains('不得用模型记忆补齐'));
    expect(events.where((e) => e.type == ReActEventType.toolCall), isNotEmpty);
  });
}

class _CaptureTool extends AgentTool {
  Map<String, dynamic>? lastArgs;

  @override
  String get name => 'search_local_lore';

  @override
  String get description => 'Capture tool arguments for tests.';

  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    lastArgs = Map.of(arguments);
    return 'captured';
  }
}
