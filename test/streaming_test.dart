// R16: streamed output — SSE parsing, the writer's token stream (with the
// citation rewrite and the final replace), the ReAct live preview, update
// coalescing and the live status UI.
import 'dart:async';
import 'dart:convert';

import 'package:arklores/core/agent/chat_message.dart';
import 'package:arklores/core/agent/chat_notifier_base.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/tool_registry.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:arklores/features/ai/widgets/chat_bubble.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SSE client', () {
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
      final body = utf8.encode(
        event(delta(reasoning: '先想一想')) +
            event(delta(content: '特蕾西娅')) +
            event(delta(content: '之死')) +
            event({
              'choices': [
                {'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
              ],
            }) +
            event({
              'choices': <dynamic>[],
              'usage': {
                'prompt_tokens': 100,
                'completion_tokens': 20,
                'prompt_cache_hit_tokens': 60,
              },
            }) +
            event({'choices': <dynamic>[]}).replaceFirst(
              RegExp(r'\{.*\}'),
              '[DONE]',
            ),
      );
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
      expect(deltas.map((d) => d.content).join(), '特蕾西娅之死');
      expect(deltas.map((d) => d.reasoningContent).join(), '先想一想');
      expect(deltas.last.done, isTrue);
      expect(deltas.last.finishReason, 'stop');
      expect(deltas.last.promptTokens, 100);
      expect(deltas.last.cachedPromptTokens, 60);
      expect(metered!.content, '特蕾西娅之死');
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
        throwsA(
          isA<LLMException>()
              .having((e) => e.message, 'message', contains('timed out')),
        ),
      );
      await controller.close();
    });

    test('a provider rejecting streaming is asked again without it', () async {
      final bodies = <Map<String, dynamic>>[];
      final c = OpenAICompatibleClient(
        config: const LLMConfig(chatApiKey: 'test-key'),
        httpClient: MockClient.streaming((request, _) async {
          final body = jsonDecode((request as http.Request).body)
              as Map<String, dynamic>;
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
        }),
      );
      final text = (await c.streamCompletion([Message.user('q')]).toList())
          .map((d) => d.content)
          .join();
      expect(text, '整段答案');
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('stream'), isFalse);
    });

    test('other errors are reported, not retried without streaming', () async {
      final c = client(
        (_, __) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"Insufficient Balance"}}')),
          402,
        ),
      );
      await expectLater(
        c.streamCompletion([Message.user('q')]).toList(),
        throwsA(isA<LLMException>().having((e) => e.statusCode, 'status', 402)),
      );
    });
  });

  group('ReAct live preview', () {
    test('text after "Final Answer:" streams live, then is replaced',
        () async {
      final events = await ReActLoop(
        llmClient: _StreamingReact([
          ['Thought: 好。\nFinal', ' Answer: 你', '好，博士。'],
        ]),
        toolRegistry: ToolRegistry(),
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      final live = events
          .where((e) => e.type == ReActEventType.finalAnswerToken)
          .map((e) => e.content)
          .join();
      expect(live, '你好，博士。');
      expect(
        events.any((e) => e.type == ReActEventType.finalAnswerReplace),
        isTrue,
      );
      expect(finalAnswerOf(events), '你好，博士。');
    });

    test('a refused early answer is cleared before the next step', () async {
      final events = await ReActLoop(
        llmClient: _StreamingReact([
          ['Thought: 直接答。\nFinal Answer: 太早了'],
          [
            'Thought: 查一下。\nAction: lookup\nAction Input: {"query": "x"}',
          ],
          ['Thought: 好。\nFinal Answer: 查过了'],
        ]),
        toolRegistry: ToolRegistry()..register(_LookupTool()),
        minimumToolCalls: 1,
      ).run(systemPrompt: 's', chatHistory: [], userQuery: 'q').toList();
      final types = events.map((e) => e.type).toList();
      expect(types, contains(ReActEventType.finalAnswerReset));
      expect(finalAnswerOf(events), '查过了');
    });
  });

  testWidgets('the coalescer flushes once per interval and on demand',
      (tester) async {
    var flushes = 0;
    final coalescer = StreamCoalescer(
      () => flushes++,
      interval: const Duration(milliseconds: 60),
    );
    for (var i = 0; i < 10; i++) {
      coalescer.schedule();
    }
    expect(flushes, 0);
    await tester.pump(const Duration(milliseconds: 70));
    expect(flushes, 1);
    coalescer.schedule();
    coalescer.flushNow();
    expect(flushes, 2);
    await tester.pump(const Duration(milliseconds: 70));
    expect(flushes, 2);
  });

  group('live answer UI', () {
    Future<void> pump(WidgetTester tester, ChatMessage message) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ChatBubble(message: message)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the current step, the thinking and the text without citations',
        (tester) async {
      await pump(
        tester,
        ChatMessage(
          id: 'a',
          role: MessageRole.assistant,
          content: '结论（activities/act_fixture/level_fixture_c5.txt:0）\n'
              '[COVERAGE: fu',
          isStreaming: true,
          liveStatus: '正在撰写答案',
          reasoning: '先比较两段原文',
          timestamp: DateTime(2026),
        ),
      );
      expect(find.text('正在撰写答案'), findsOneWidget);
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先比较两段原文'), findsOneWidget);
      expect(find.textContaining('COVERAGE'), findsNothing);
      expect(find.textContaining('.txt'), findsNothing);
      // R17b: while streaming the citation leaves the text and the chain
      // waits for the finished answer, so nothing jumps.
      expect(find.text('结论'), findsOneWidget);
      expect(find.textContaining('第 1 行'), findsNothing);
      // The thinking folds away on tap.
      await tester.tap(find.text('思考过程'));
      await tester.pump();
      expect(find.text('先比较两段原文'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// ReAct model streaming scripted chunks, one script per step.
class _StreamingReact extends LLMClient {
  _StreamingReact(this.steps);
  final List<List<String>> steps;
  var _step = 0;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      steps.last.join();

  @override
  Stream<CompletionDelta> streamCompletion(
    List<Message> messages, {
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async* {
    final chunks = steps[_step < steps.length ? _step : steps.length - 1];
    _step++;
    for (final chunk in chunks) {
      yield CompletionDelta(content: chunk);
    }
    yield const CompletionDelta(done: true, finishReason: 'stop');
  }
}

class _LookupTool extends AgentTool {
  @override
  String get name => 'lookup';
  @override
  String get description => 'looks up';
  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      };
  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async =>
      const ToolExecutionResult(observation: 'found');
}
