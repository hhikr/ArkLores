/// Live probe of the provider's concurrency behaviour (opt-in, costs a few
/// cents): one tiny request alone, then [ARKLORES_PROBE_PARALLEL] (default 5)
/// of them at once with 429 retries off. Shows whether the key's limit
/// serialises requests, answers 429, or lets them run side by side.
///
///   ARKLORES_RUN_LIVE_PROBE=true flutter test test/live/concurrency_probe_live_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ask_pipeline_live_test.dart' show readApiInfo;

void main() {
  final env = Platform.environment;
  final enabled = env['ARKLORES_RUN_LIVE_PROBE']?.toLowerCase() == 'true';
  final parallel = int.tryParse(env['ARKLORES_PROBE_PARALLEL'] ?? '') ?? 5;
  final api = readApiInfo(File('tools/api_info'));
  final out = Directory(env['ARKLORES_LIVE_OUT'] ?? 'build/live_sessions/probe')
      .absolute;

  Future<Map<String, Object?>> one(OpenAICompatibleClient client, int i) async {
    final start = DateTime.now();
    String outcome;
    int? status;
    try {
      final r = await client.chatCompletion(
        [Message.user('回复两个字：好的。')],
        maxTokens: 64,
      );
      outcome = 'ok';
      status = 200;
      return {
        'i': i,
        'outcome': outcome,
        'status': status,
        'ms': DateTime.now().difference(start).inMilliseconds,
        'completion_tokens': r.completionTokens,
      };
    } on LLMException catch (e) {
      outcome = e.message;
      status = e.statusCode;
    }
    return {
      'i': i,
      'outcome': outcome,
      'status': status,
      'ms': DateTime.now().difference(start).inMilliseconds,
    };
  }

  test(
    'concurrency probe',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null; // flutter_test blocks real HTTP
      addTearDown(() => HttpOverrides.global = previous);
      final client = OpenAICompatibleClient(
        config: api,
        reasoning: ReasoningLevel.off,
        rateLimitBackoff: const [], // see raw 429s
      );
      addTearDown(client.dispose);
      final alone = await one(client, 0);
      final started = DateTime.now();
      final together = await Future.wait([
        for (var i = 1; i <= parallel; i++) one(client, i),
      ]);
      final report = {
        'model': api.chatModel,
        'alone': alone,
        'parallel': together,
        'parallel_wall_ms': DateTime.now().difference(started).inMilliseconds,
      };
      out.createSync(recursive: true);
      File('${out.path}/probe.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(report));
    },
    skip: !enabled || api.chatApiKey.isEmpty
        ? 'Set ARKLORES_RUN_LIVE_PROBE=true (and tools/api_info).'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
