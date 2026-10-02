// R16: hidden-reasoning levels per role. Every role runs without thinking;
// only the "深度思考" switch gives the answer writer a low effort.
import 'dart:convert';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/llm_provider.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('reasoningFieldsFor', () {
    const deepseek = LLMConfig(
      chatBaseUrl: 'https://api.deepseek.com/v1',
      chatModel: 'deepseek-v4-flash',
    );
    const dashscope = LLMConfig(
      chatBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      chatModel: 'qwen-plus',
    );
    const proxied = LLMConfig(
      chatBaseUrl: 'https://proxy.example.com/v1',
      chatModel: 'deepseek-chat',
    );
    const unknown = LLMConfig(
      chatBaseUrl: 'https://api.example.com/v1',
      chatModel: 'some-model',
    );
    Map<String, dynamic> fields(LLMConfig c, ReasoningLevel l) =>
        OpenAICompatibleClient.reasoningFieldsFor(c, l);

    test('deepseek: off disables thinking, low/high set the effort', () {
      expect(fields(deepseek, ReasoningLevel.off), {
        'thinking': {'type': 'disabled'},
      });
      expect(fields(deepseek, ReasoningLevel.low), {
        'thinking': {'type': 'enabled'},
        'reasoning_effort': 'low',
      });
      expect(fields(deepseek, ReasoningLevel.high)['reasoning_effort'], 'high');
      // A deepseek model behind another endpoint uses the same switch.
      expect(fields(proxied, ReasoningLevel.off), {
        'thinking': {'type': 'disabled'},
      });
    });

    test('dashscope: enable_thinking, with a budget for low', () {
      expect(fields(dashscope, ReasoningLevel.off), {'enable_thinking': false});
      expect(fields(dashscope, ReasoningLevel.low), {
        'enable_thinking': true,
        'thinking_budget': 2048,
      });
    });

    test('unknown providers get no field at any level', () {
      for (final level in ReasoningLevel.values) {
        expect(fields(unknown, level), isEmpty);
      }
    });
  });

  test('the request body carries the client level', () async {
    Map<String, dynamic>? body;
    final client = OpenAICompatibleClient(
      config: const LLMConfig(chatApiKey: 'test-key'),
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
        );
      }),
    );
    await client.chatCompletion([Message.user('q')]);
    expect(body!['thinking'], {'type': 'disabled'});
    expect(body!.containsKey('reasoning_effort'), isFalse);
  });

  group('providers', () {
    ProviderContainer container() => ProviderContainer(
          overrides: [
            initialApiConfigProvider.overrideWithValue(
              const LLMConfig(chatApiKey: 'test-key'),
            ),
          ],
        );

    test('every role defaults to no thinking', () {
      final c = container();
      addTearDown(c.dispose);
      final off = c.read(llmClientProvider(ReasoningLevel.off));
      expect((off as OpenAICompatibleClient).reasoning, ReasoningLevel.off);
      expect(c.read(deepThinkingProvider), isFalse);
    });

    test('"深度思考" hands a low-effort writer to the next question only',
        () async {
      final c = container();
      addTearDown(c.dispose);
      final low = c.read(llmClientProvider(ReasoningLevel.low));
      expect((low as OpenAICompatibleClient).reasoning, ReasoningLevel.low);
      // The notifier is not rebuilt by the switch (a rebuild would drop the
      // conversation).
      final notifier = c.read(askChatProvider.notifier);
      c.read(deepThinkingProvider.notifier).state = true;
      expect(identical(c.read(askChatProvider.notifier), notifier), isTrue);
    });
  });
}
