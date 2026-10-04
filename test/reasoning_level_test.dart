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

    test('zhipu GLM: thinking cannot be off; the effort is low / high / max',
        () {
      const zai = LLMConfig(
        chatBaseUrl: 'https://api.z.ai/api/paas/v4',
        chatModel: 'glm-flash',
      );
      const bigmodel = LLMConfig(
        chatBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        chatModel: 'some-model',
      );
      const glmElsewhere = LLMConfig(
        chatBaseUrl: 'https://proxy.example.com/v1',
        chatModel: 'GLM-flash',
      );
      for (final c in [zai, bigmodel, glmElsewhere]) {
        expect(fields(c, ReasoningLevel.off), {'reasoning_effort': 'low'});
        expect(fields(c, ReasoningLevel.low), {'reasoning_effort': 'high'});
        expect(fields(c, ReasoningLevel.high), {'reasoning_effort': 'max'});
      }
      // A host that merely ends in "z.ai" is not Zhipu.
      expect(
        fields(
          const LLMConfig(chatBaseUrl: 'https://xyz.ai/v1', chatModel: 'm'),
          ReasoningLevel.off,
        ),
        isEmpty,
      );
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
    // The default provider is Zhipu GLM: the lowest effort, no switch.
    expect(body!['reasoning_effort'], 'low');
    expect(body!.containsKey('thinking'), isFalse);
  });

  group('provider quirks in the request', () {
    const tools = [
      {
        'type': 'function',
        'function': {'name': 'sql', 'parameters': <String, dynamic>{}},
      },
    ];

    Future<Map<String, dynamic>> lastTurnBody(LLMConfig config) async {
      Map<String, dynamic>? body;
      final client = OpenAICompatibleClient(
        config: config,
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
      // A plain response to a stream request falls back to the
      // non-streaming body; the request is what is checked.
      await client
          .streamTurn([Message.user('q')], tools: tools, toolChoice: 'none')
          .drain<void>();
      return body!;
    }

    test('tool_choice none is sent, except to Zhipu (only "auto" there)',
        () async {
      final deepseek = await lastTurnBody(
        const LLMConfig(
          chatApiKey: 'test-key',
          chatBaseUrl: 'https://api.deepseek.com/v1',
          chatModel: 'deepseek-v4-flash',
        ),
      );
      expect(deepseek['tool_choice'], 'none');
      final glm = await lastTurnBody(
        const LLMConfig(
          chatApiKey: 'test-key',
          chatBaseUrl: 'https://api.z.ai/api/paas/v4',
          chatModel: 'glm-flash',
        ),
      );
      expect(glm.containsKey('tool_choice'), isFalse);
      expect(glm['tool_stream'], isTrue);
      expect(deepseek.containsKey('tool_stream'), isFalse);
      expect(glm['tools'], isNotEmpty);
      expect(glm['reasoning_effort'], 'low');
      expect(glm.containsKey('thinking'), isFalse);
    });

    test(
        'reasoning fields the model rejects (Zhipu says only "Invalid API '
        'parameter") are dropped once and not sent again', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAICompatibleClient(
        config: const LLMConfig(
          chatApiKey: 'test-key',
          chatBaseUrl: 'https://api.z.ai/api/paas/v4',
          chatModel: 'glm-5.3-flash',
        ),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('reasoning_effort')) {
            return http.Response(
              '{"error":{"code":"1210","message":"Invalid API parameter, please check the documentation."}}',
              400,
            );
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok', 'reasoning_content': 'r'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
          );
        }),
      );
      expect((await client.chatCompletion([Message.user('q')])).content, 'ok');
      expect(bodies, hasLength(2));
      await client.chatCompletion([Message.user('q')]);
      expect(bodies, hasLength(3));
      expect(bodies.last.containsKey('reasoning_effort'), isFalse);
    });

    test('streamed tool calls: arguments joined, a repeated name kept once',
        () async {
      String chunk(Map<String, dynamic> call) =>
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {
                  'tool_calls': [call],
                },
              },
            ],
          })}\n\n';
      final client = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key'),
        httpClient: MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            Stream.value(utf8.encode([
              chunk({
                'index': 0,
                'id': 'c1',
                'function': {'name': 'sql', 'arguments': '{"q":'},
              }),
              chunk({
                'index': 0,
                'function': {'name': 'sql', 'arguments': '"x"}'},
              }),
              'data: [DONE]\n\n',
            ].join(),),),
            200,
          ),
        ),
      );
      final done = (await client
              .streamTurn([Message.user('q')], tools: tools)
              .toList())
          .last;
      expect(done.toolCalls, hasLength(1));
      expect(done.toolCalls.single.name, 'sql');
      expect(done.toolCalls.single.arguments, '{"q":"x"}');
    });

    test('a provider rejecting stream_options still streams without it',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key'),
        httpClient: MockClient.streaming((request, bodyStream) async {
          final body = jsonDecode(await bodyStream.bytesToString())
              as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('stream_options')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"error":{"message":"unknown field"}}')),
              400,
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(
              'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
              'data: [DONE]\n\n',
            ),),
            200,
          );
        }),
      );
      final text = await client
          .streamCompletion([Message.user('q')])
          .map((d) => d.content)
          .join();
      expect(text, 'ok');
      expect(bodies, hasLength(2));
      expect(bodies.last['stream'], isTrue);
      await client.streamCompletion([Message.user('q')]).drain<void>();
      expect(bodies, hasLength(3));
      expect(bodies.last.containsKey('stream_options'), isFalse);
    });

    MockClient rateLimited(int failures, List<int> calls) =>
        MockClient((request) async {
          calls.add(1);
          if (calls.length <= failures) {
            return http.Response('{"error":{"message":"too many"}}', 429);
          }
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
        });

    test('429 is retried after a wait, then reported', () async {
      final calls = <int>[];
      final client = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key'),
        httpClient: rateLimited(2, calls),
        rateLimitBackoff: const [Duration.zero, Duration.zero],
      );
      final result = await client.chatCompletion([Message.user('q')]);
      expect(result.content, 'ok');
      expect(calls, hasLength(3));

      final stubborn = <int>[];
      final failing = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key'),
        httpClient: rateLimited(99, stubborn),
        rateLimitBackoff: const [Duration.zero],
      );
      await expectLater(
        failing.chatCompletion([Message.user('q')]),
        throwsA(
          isA<LLMException>().having((e) => e.statusCode, 'status', 429),
        ),
      );
      expect(stubborn, hasLength(2));
    });

    test('a rate-limited stream is retried too', () async {
      final calls = <int>[];
      final client = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key'),
        httpClient: MockClient.streaming((request, _) async {
          calls.add(1);
          if (calls.length == 1) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{}')),
              429,
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(
              'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
              'data: [DONE]\n\n',
            ),),
            200,
          );
        }),
        rateLimitBackoff: const [Duration.zero],
      );
      final text = await client
          .streamCompletion([Message.user('q')])
          .map((d) => d.content)
          .join();
      expect(text, 'ok');
      expect(calls, hasLength(2));
    });
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
