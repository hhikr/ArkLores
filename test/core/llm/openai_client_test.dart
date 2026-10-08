// The OpenAI-compatible client: thinking fields per provider, provider
// quirks, rate limits, SSE streaming and input checks.
import 'dart:async';
import 'dart:convert';

import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
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

  group('SSE stream', () {
    OpenAICompatibleClient client(
      MockClientStreamHandler handler, {
      Duration idle = const Duration(seconds: 5),
      void Function(ChatCompletionResult)? onCompletion,
    }) =>
        OpenAICompatibleClient(
          config: const LLMConfig(chatApiKey: 'test-key'),
          httpClient: MockClient.streaming(handler),
          streamIdleTimeout: idle,
          onCompletion: onCompletion,
        );

    String event(Map<String, dynamic> json) => 'data: ${jsonEncode(json)}\n\n';
    Map<String, dynamic> delta({String? content, String? reasoning}) => {
          'choices': [
            {
              'delta': {
                if (content != null) 'content': content,
                if (reasoning != null) 'reasoning_content': reasoning,
              },
            },
          ],
        };

    test('joins lines and characters split across network chunks', () async {
      final body = utf8.encode([
        event(delta(reasoning: '先想一想')),
        event(delta(content: '甲的')),
        event(delta(content: '来历')),
        event({
          'choices': [
            {'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
          ],
        }),
        event({
          'choices': <dynamic>[],
          'usage': {
            'prompt_tokens': 100,
            'completion_tokens': 20,
            'prompt_cache_hit_tokens': 60,
          },
        }),
        'data: [DONE]\n\n',
      ].join(),);
      // 7-byte chunks cut both SSE lines and multi-byte characters.
      final chunks = [
        for (var i = 0; i < body.length; i += 7)
          body.sublist(i, i + 7 > body.length ? body.length : i + 7),
      ];
      ChatCompletionResult? metered;
      Map<String, dynamic>? sent;
      final c = client(
        (request, _) async {
          sent = jsonDecode((request as http.Request).body)
              as Map<String, dynamic>;
          return http.StreamedResponse(Stream.fromIterable(chunks), 200);
        },
        onCompletion: (r) => metered = r,
      );
      final deltas = await c.streamCompletion([Message.user('q')]).toList();
      expect(deltas.map((d) => d.content).join(), '甲的来历');
      expect(deltas.map((d) => d.reasoningContent).join(), '先想一想');
      expect(deltas.last.done, isTrue);
      expect(deltas.last.finishReason, 'stop');
      expect(deltas.last.promptTokens, 100);
      expect(deltas.last.cachedPromptTokens, 60);
      expect(metered!.content, '甲的来历');
      expect(sent!['stream'], isTrue);
      expect(sent!['stream_options'], {'include_usage': true});
    });

    test('a stalled stream fails after the idle timeout', () async {
      final controller = StreamController<List<int>>();
      controller.add(utf8.encode(event(delta(content: '开头'))));
      final c = client(
        (_, __) async => http.StreamedResponse(controller.stream, 200),
        idle: const Duration(milliseconds: 50),
      );
      await expectLater(
        c.streamCompletion([Message.user('q')]).toList(),
        throwsA(isA<LLMException>()
            .having((e) => e.message, 'message', contains('timed out')),),
      );
      await controller.close();
    });

    test('a provider rejecting streaming is asked again without it', () async {
      final bodies = <Map<String, dynamic>>[];
      final c = client((request, _) async {
        final body =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        bodies.add(body);
        if (body['stream'] == true) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"bad"}}')),
            400,
          );
        }
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {'content': '整段答案'},
                'finish_reason': 'stop',
              },
            ],
          }),),),
          200,
        );
      });
      final text = (await c.streamCompletion([Message.user('q')]).toList())
          .map((d) => d.content)
          .join();
      expect(text, '整段答案');
      // First without `stream_options` (some providers reject only that),
      // then without streaming.
      expect(bodies, hasLength(3));
      expect(bodies[1]['stream'], isTrue);
      expect(bodies[1].containsKey('stream_options'), isFalse);
      expect(bodies.last.containsKey('stream'), isFalse);
    });

    test('other errors are reported, not retried without streaming', () async {
      final c = client(
        (_, __) async => http.StreamedResponse(
          Stream.value(
              utf8.encode('{"error":{"message":"Insufficient Balance"}}'),),
          402,
        ),
      );
      await expectLater(
        c.streamCompletion([Message.user('q')]).toList(),
        throwsA(isA<LLMException>().having((e) => e.statusCode, 'status', 402)),
      );
    });
  });

  // Gemini's OpenAI-compatible API and relays (new-api / one-api style)
  // answer in shapes GLM and deepseek never used.
  group('other providers and relays', () {
    const tools = [
      {
        'type': 'function',
        'function': {'name': 'sql', 'parameters': <String, dynamic>{}},
      },
    ];
    const config = LLMConfig(chatApiKey: 'test-key', chatModel: 'some-model');
    String event(Map<String, dynamic> json) => 'data: ${jsonEncode(json)}\n\n';
    OpenAICompatibleClient streaming(String body, {int status = 200}) =>
        OpenAICompatibleClient(
          config: config,
          httpClient: MockClient.streaming(
            (request, _) async =>
                http.StreamedResponse(Stream.value(utf8.encode(body)), status),
          ),
        );
    String textOf(List<CompletionDelta> deltas) =>
        deltas.map((d) => d.content).join();

    test('a stream request answered with a plain completion body', () async {
      final deltas = await streaming(jsonEncode({
        'choices': [
          {
            'finish_reason': 'tool_calls',
            'message': {
              'content': null,
              'tool_calls': [
                {
                  'id': 'a',
                  'type': 'function',
                  'function': {'name': 'sql', 'arguments': '{"q":1}'},
                },
                {
                  'id': 'b',
                  'type': 'function',
                  'function': {'name': 'grep', 'arguments': '{}'},
                },
              ],
            },
          },
        ],
      }),).streamTurn([Message.user('q')], tools: tools).toList();
      final done = deltas.last;
      expect(done.toolCalls.map((c) => c.name), ['sql', 'grep']);
      expect(done.toolCalls.first.arguments, '{"q":1}');
      expect(done.finishReason, 'tool_calls');
    });

    test('chunks one per line without "data:", or as a JSON array', () async {
      final chunks = [
        {
          'choices': [
            {
              'delta': {'content': '甲'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '乙'},
              'finish_reason': 'stop',
            },
          ],
        },
      ];
      final lines = await streaming(chunks.map(jsonEncode).join('\n'))
          .streamTurn([Message.user('q')]).toList();
      expect(textOf(lines), '甲乙');
      expect(lines.last.finishReason, 'stop');
      final array = await streaming(jsonEncode(chunks))
          .streamTurn([Message.user('q')]).toList();
      expect(textOf(array), '甲乙');
    });

    test('a body nobody can read is reported with its start, as status 200',
        () async {
      await expectLater(
        streaming('Bad gateway, try later')
            .streamTurn([Message.user('q')]).toList(),
        throwsA(isA<LLMException>()
            .having((e) => e.message, 'message', contains('Bad gateway, try'))
            .having((e) => e.statusCode, 'status', 200),),
      );
    });

    test('a 404 names its status and what to check', () async {
      await expectLater(
        streaming('{"error":{"message":"Resource not found"}}', status: 404)
            .streamTurn([Message.user('q')]).toList(),
        throwsA(isA<LLMException>()
            .having((e) => e.message, 'message', contains('(HTTP 404)'))
            .having((e) => e.message, 'message', contains('Resource not found'))
            .having((e) => e.message, 'message', contains('分组')),),
      );
    });

    test('a web page instead of an API answer points at the Base URL',
        () async {
      await expectLater(
        streaming('<!doctype html><html><title>Relay</title></html>')
            .streamTurn([Message.user('q')]).toList(),
        throwsA(isA<LLMException>()
            .having((e) => e.message, 'message', contains('Base URL'))
            .having((e) => e.message, 'message', contains('/v1')),),
      );
    });

    test('an error inside a 200 stream is reported', () async {
      await expectLater(
        streaming(event({
          'error': {'message': 'upstream overloaded'},
        }),).streamTurn([Message.user('q')]).toList(),
        throwsA(isA<LLMException>().having(
          (e) => e.message,
          'message',
          contains('upstream overloaded'),
        ),),
      );
    });

    test('text as a list of parts, reasoning under "reasoning"', () async {
      final deltas = await streaming([
        event({
          'choices': [
            {
              'delta': {
                'reasoning': '想',
                'content': [
                  {'type': 'thinking', 'text': '不显示'},
                  {'type': 'text', 'text': '甲'},
                ],
              },
            },
          ],
        }),
        event({
          'choices': [
            {
              'delta': {'content': '乙'},
              'finish_reason': 'stop',
            },
          ],
        }),
        'data: [DONE]\n\n',
      ].join(),).streamTurn([Message.user('q')]).toList();
      expect(textOf(deltas), '甲乙');
      expect(deltas.map((d) => d.reasoningContent).join(), '想');
    });

    test('unnumbered streamed calls are told apart by their ids', () async {
      Map<String, dynamic> call(String id, String name, String args) => {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'id': id,
                      'function': {'name': name, 'arguments': args},
                    },
                  ],
                },
              },
            ],
          };
      final done = (await streaming([
        event(call('a', 'sql', '{"q":1}')),
        event(call('b', 'grep', '{"p":2}')),
      ].join(),).streamTurn([Message.user('q')], tools: tools).toList())
          .last;
      expect(done.toolCalls.map((c) => c.arguments), ['{"q":1}', '{"p":2}']);
    });

    test('a request that did not ask for a stream answered with one',
        () async {
      final client = OpenAICompatibleClient(
        config: config,
        httpClient: MockClient((request) async => http.Response.bytes(
              utf8.encode([
                event({
                  'choices': [
                    {
                      'delta': {'content': '答'},
                    },
                  ],
                }),
                event({
                  'choices': [
                    {
                      'delta': {'content': '案'},
                      'finish_reason': 'stop',
                    },
                  ],
                }),
              ].join(),),
              200,
            ),),
      );
      final result = await client.chatCompletion([Message.user('q')]);
      expect(result.content, '答案');
      expect(result.finishReason, 'stop');
    });

    test('empty text of a tool-call turn is sent as null after a rejection',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAICompatibleClient(
        config: config,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          final turn = (body['messages'] as List)[1] as Map;
          return turn['content'] == ''
              ? http.Response(
                  '{"error":{"message":"contents.parts must not be empty"}}',
                  400,
                )
              : http.Response.bytes(
                  utf8.encode(jsonEncode({
                    'choices': [
                      {
                        'message': {'content': '好'},
                      },
                    ],
                  }),),
                  200,
                );
        }),
      );
      final history = [
        Message.user('q'),
        Message.assistantToolCalls(
          '',
          const [ToolCall(id: 'a', name: 'sql', arguments: '{}')],
        ),
        Message.toolResult('a', 'rows'),
      ];
      expect((await client.chatCompletion(history)).content, '好');
      expect(bodies, hasLength(2));
      expect(((bodies.last['messages'] as List)[1] as Map)['content'], isNull);
      // Remembered: the next request is right the first time.
      await client.chatCompletion(history);
      expect(bodies, hasLength(3));
    });

    test('GPT-5: max_completion_tokens and no temperature after rejections',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final client = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key', chatModel: 'gpt-5.4'),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          if (body.containsKey('max_tokens')) {
            return http.Response(
              '{"error":{"message":"Unsupported parameter: \'max_tokens\' is '
              'not supported with this model. Use \'max_completion_tokens\' '
              'instead."}}',
              400,
            );
          }
          if (body.containsKey('temperature')) {
            return http.Response(
              '{"error":{"message":"Unsupported value: \'temperature\' does '
              'not support 0.3 with this model."}}',
              400,
            );
          }
          return http.Response('{"choices":[{"message":{"content":"ok"}}]}', 200);
        }),
      );
      final result =
          await client.chatCompletion([Message.user('q')], temperature: 0.3);
      expect(result.content, 'ok');
      expect(bodies, hasLength(3));
      expect(bodies.last['max_completion_tokens'], 2048);
      expect(bodies.last['reasoning_effort'], 'low');
      // Remembered for the next requests.
      await client.chatCompletion([Message.user('q')]);
      expect(bodies, hasLength(4));
    });

    test('Gemini: thinking kept short (it counts against max_tokens)', () {
      const gemini = LLMConfig(
        chatBaseUrl:
            'https://generativelanguage.googleapis.com/v1beta/openai',
        chatModel: 'gemini-2.5-pro',
      );
      const relayed = LLMConfig(
        chatBaseUrl: 'https://relay.example.com/v1',
        chatModel: 'gemini-3-flash',
      );
      for (final c in [gemini, relayed]) {
        expect(
          OpenAICompatibleClient.reasoningFieldsFor(c, ReasoningLevel.off),
          {'reasoning_effort': 'low'},
        );
      }
    });
  });

  test('pasted text that is not an API key is refused before any request',
      () async {
    final client = OpenAICompatibleClient(
      config: const LLMConfig(chatApiKey: '截图中的完整报错具体内容为：下载失败'),
      httpClient: MockClient(
          (request) async => http.Response('should not be called', 500),),
    );
    expect(
      () => client.chatCompletion([Message.user('test')]),
      throwsA(isA<LLMException>().having(
        (e) => e.message,
        'message',
        contains('Please paste only the API key'),
      ),),
    );
  });
}