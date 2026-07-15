import 'dart:io';

import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/tools/search_local_lore.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final apiInfo = _readApiInfo(File('tools/api_info'));
  final apiKey = apiInfo['API_KEY'] ?? '';
  final apiModel = apiInfo['MODEL'] ?? '';
  final apiUrl = apiInfo['URL'] ?? '';
  final liveEnabled =
      Platform.environment['ARKLORES_RUN_LIVE_CHAT']?.toLowerCase() == 'true';
  final dbPath = Platform.environment['ARKLORES_GAMEDATA_DB'] ??
      'build/gamedata_mobile/arklores_gamedata_zh.db';
  final skipReason = !liveEnabled
      ? 'Set ARKLORES_RUN_LIVE_CHAT=true to run external Chat QA.'
      : apiKey.isEmpty || apiModel.isEmpty || apiUrl.isEmpty
          ? 'Live Chat QA requires tools/api_info with API_KEY, MODEL, and URL.'
          : false;

  late OpenAICompatibleClient client;
  late FactCheckAgent agent;
  late HttpOverrides? previousHttpOverrides;

  setUpAll(() {
    if (skipReason != false) return;
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final db = File(dbPath).absolute;
    if (!db.existsSync()) {
      fail('GameData DB does not exist: ${db.path}');
    }
    client = OpenAICompatibleClient(
      config: LLMConfig(
        chatBaseUrl: apiUrl,
        chatApiKey: apiKey,
        chatModel: apiModel,
      ),
      timeout: const Duration(seconds: 90),
    );
    agent = FactCheckAgent(
      llmClient: client,
      searchTool: SearchLocalLoreTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: db.path),
      ),
    );
  });

  tearDownAll(() {
    if (skipReason == false) {
      client.dispose();
      HttpOverrides.global = previousHttpOverrides;
    }
  });

  test(
    'configured provider accepts a minimal chat completion',
    () async {
      final result = await client.chatCompletion(
        [Message.user('reply OK')],
        temperature: 0.1,
        maxTokens: 64,
      );
      expect(result.content, isNotEmpty);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'finds scoped story text and explains the physical-consciousness split',
    () async {
      final result = await _runCase(
        agent,
        '丛林症结故事集中，米格鲁死掉了吗？请说明身体和意识分别发生了什么。',
      );

      final diagnostics = result.diagnostics;
      expect(result.errors, isEmpty, reason: diagnostics);
      expect(result.toolCalls, greaterThan(0));
      expect(
        result.verdict,
        FactCheckVerdict.supported,
        reason: diagnostics,
      );
      expect(
        result.observations,
        contains('scoped_story_evidence'),
        reason: diagnostics,
      );
      expect(
        result.observations,
        contains('activities/act21mini/level_act21mini_st'),
      );
      expect(result.answer, contains('死'));
      expect(result.answer, contains('意识'));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'does not invent support for an uncovered future claim',
    () async {
      final result = await _runCase(agent, '罗德岛在2030年公开举办过庆典吗？');

      final diagnostics = result.diagnostics;
      expect(result.errors, isEmpty, reason: diagnostics);
      expect(result.toolCalls, greaterThan(0), reason: diagnostics);
      expect(
        result.verdict,
        anyOf(FactCheckVerdict.uncertain, FactCheckVerdict.unavailable),
        reason: diagnostics,
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Map<String, String> _readApiInfo(File file) {
  if (!file.existsSync()) return const {};
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) values[key] = value;
  }
  return values;
}

Future<_LiveResult> _runCase(FactCheckAgent agent, String claim) async {
  final observations = StringBuffer();
  final answer = StringBuffer();
  final errors = <String>[];
  var toolCalls = 0;
  await for (final event in agent.checkClaim(claim: claim)) {
    if (event.type == ReActEventType.toolCall) toolCalls++;
    if (event.type == ReActEventType.toolObservation) {
      observations.writeln(event.content);
    }
    if (event.type == ReActEventType.finalAnswerToken) {
      answer.write(event.content);
    }
    if (event.type == ReActEventType.error) errors.add(event.content);
  }
  final content = answer.toString();
  return _LiveResult(
    verdict: parseFactCheckVerdict(content),
    answer: content,
    observations: observations.toString(),
    toolCalls: toolCalls,
    errors: errors,
  );
}

class _LiveResult {
  final FactCheckVerdict? verdict;
  final String answer;
  final String observations;
  final int toolCalls;
  final List<String> errors;

  const _LiveResult({
    required this.verdict,
    required this.answer,
    required this.observations,
    required this.toolCalls,
    required this.errors,
  });

  String get diagnostics => [
        ...errors,
        'tool calls: $toolCalls',
        'observations: $observations',
        'answer: $answer',
      ].join('\n');
}
