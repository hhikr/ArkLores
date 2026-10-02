// Live Ask-pipeline harness (R12): runs questions through the SAME provider
// graph and code path as the app's Ask page — AskChatNotifier.sendMessage
// -> QuestionRouter (auto) -> Summary / Fact-check / Investigation agent ->
// GameDataKnowledgeStore -> ChatSessionStore — and writes session JSON in
// the exact format of the app's `chat_sessions/` (and `logs/`) files.
//
// Only what main.dart injects at startup is overridden (chat API config,
// embedding config, session log toggle) plus the two platform paths (DB
// file, session directory). The
// SQL engine is sqflite FFI instead of the Android plugin; every Dart class
// on the path is app code.
//
// Opt-in (never runs in the normal suite):
//   ARKLORES_RUN_LIVE_ASK=true
//   ARKLORES_LIVE_QUERIES="问题1||问题2"      (or ARKLORES_LIVE_EVAL=<json>)
//   ARKLORES_LIVE_MODE=auto|investigate|summarize|verify   (default auto)
//   ARKLORES_GAMEDATA_DB=<db path>  (default build/gamedata_mobile/...)
//   ARKLORES_LIVE_OUT=<dir>         (default build/live_sessions)
// API config comes from the gitignored tools/api_info (API_KEY/MODEL/URL).
//
//   flutter test test/live/ask_pipeline_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/agent_logger.dart';
import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/chat_session_store.dart';
import 'package:arklores/core/agent/question_router.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'live_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final enabled = env['ARKLORES_RUN_LIVE_ASK']?.toLowerCase() == 'true';
  final api = readApiInfo(File('tools/api_info'));
  // ARKLORES_LIVE_NO_EMBEDDING=true simulates a user without an embedding key.
  final embedding = env['ARKLORES_LIVE_NO_EMBEDDING']?.toLowerCase() == 'true'
      ? defaultEmbeddingConfig
      : readEmbeddingCsv(File('tools/embedding-apiKey.csv'));
  final cases = loadLiveCases(env);
  final mode = parseAiMode(env['ARKLORES_LIVE_MODE']);
  final dbPath = File(
    env['ARKLORES_GAMEDATA_DB'] ??
        'build/gamedata_mobile/arklores_gamedata_zh.db',
  ).absolute.path;
  final outDir = Directory(env['ARKLORES_LIVE_OUT'] ?? 'build/live_sessions')
      .absolute;

  final Object skip = !enabled
      ? 'Set ARKLORES_RUN_LIVE_ASK=true to run the live Ask pipeline.'
      : api.chatApiKey.isEmpty
          ? 'tools/api_info needs API_KEY, MODEL and URL.'
          : cases.isEmpty
              ? 'Set ARKLORES_LIVE_QUERIES or ARKLORES_LIVE_EVAL.'
              : !File(dbPath).existsSync()
                  ? 'GameData DB not found: $dbPath'
                  : false;

  late ProviderContainer container;
  final usage = UsageMeter();
  // Cost guard: after a provider failure (402 balance, auth, network) the
  // remaining questions are skipped instead of burning more requests.
  String? providerFailure;
  HttpOverrides? previousHttpOverrides;

  setUpAll(() {
    if (skip != false) return;
    // flutter_test blocks real HTTP; the live run needs the provider.
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    outDir.createSync(recursive: true);
    AgentLogger.setEnabled(true); // = the app's "保存 AI 会话日志" on.
    container = ProviderContainer(
      overrides: [
        // What main.dart injects at startup:
        initialApiConfigProvider.overrideWithValue(api),
        initialEmbeddingConfigProvider.overrideWithValue(embedding),
        initialSessionLogsEnabledProvider.overrideWithValue(true),
        // Platform paths (the app resolves these via path_provider):
        sharedGameDataStoreProvider
            .overrideWithValue(GameDataKnowledgeStore(dbPath: dbPath)),
        chatSessionStoreProvider
            .overrideWithValue(ChatSessionStore(filePath: outDir.path)),
        // Same construction as llm_provider.dart plus a passive token meter
        // (cost control); the observer never alters results.
        llmClientProvider.overrideWith((ref) {
          final client = OpenAICompatibleClient(
            config: ref.watch(apiConfigProvider),
            onCompletion: usage.add,
          );
          ref.onDispose(client.dispose);
          return client;
        }),
        auxLlmClientProvider.overrideWith((ref) {
          final client = OpenAICompatibleClient(
            config: ref.watch(apiConfigProvider),
            reasoning: false,
            onCompletion: usage.add,
          );
          ref.onDispose(client.dispose);
          return client;
        }),
      ],
    );
  });

  tearDownAll(() {
    if (skip != false) return;
    container.dispose();
    AgentLogger.setEnabled(false);
    HttpOverrides.global = previousHttpOverrides;
  });

  for (final liveCase in cases.isEmpty ? [const LiveCase(id: '-', query: '-')] : cases) {
    test(
      'ask[${mode.name}] ${liveCase.id}: ${liveCase.query}',
      () async {
        if (providerFailure != null) {
          markTestSkipped('skipped after provider failure: $providerFailure');
          return;
        }
        final notifier = container.read(askChatProvider.notifier);
        notifier.newSession(); // one session file per question
        usage.reset();
        await notifier.sendMessage(liveCase.query, mode: mode);
        final session = notifier.currentSession;
        expect(session, isNotNull, reason: 'session recording produced no file');
        final turn = session!.turns.last;
        final report = summarizeTurn(liveCase, session, turn, usage: usage);
        File('${outDir.path}/${liveCase.id}.summary.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(report),
        );
        // ignore: avoid_print
        print(const JsonEncoder.withIndent('  ').convert(report));
        if ((turn.error ?? '').contains('LLM Error')) providerFailure = turn.error;
        // A live run must reach an answer; quality is judged from the report.
        expect(turn.status, ChatTurnStatus.completed, reason: turn.error);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}

/// [LLMConfig] from tools/api_info, as the app would load it from settings.
LLMConfig readApiInfo(File file) {
  if (!file.existsSync()) return const LLMConfig(chatApiKey: '');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final i = line.indexOf('=');
    if (i > 0) values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return LLMConfig(
    chatBaseUrl: values['URL'] ?? '',
    chatApiKey: values['API_KEY'] ?? '',
    chatModel: values['MODEL'] ?? '',
  );
}

/// [EmbeddingConfig] from the Bailian key CSV (`openAiCompatible`, `apiKey`),
/// as the app would load it from settings; app defaults when absent.
EmbeddingConfig readEmbeddingCsv(File file) {
  if (!file.existsSync()) return defaultEmbeddingConfig;
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final i = line.indexOf(',');
    if (i > 0) values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return defaultEmbeddingConfig.copyWith(
    baseUrl: values['openAiCompatible'],
    apiKey: values['apiKey'],
  );
}

AiMode parseAiMode(String? raw) => AiMode.values.firstWhere(
      (m) => m.name == raw?.trim(),
      orElse: () => AiMode.auto,
    );
