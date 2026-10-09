import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/story_qa_agent.dart';
import 'package:arklores/core/agent/turn_stats.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/phone_bridge.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _user(String id, String text) => ChatMessage(
      id: id,
      role: MessageRole.user,
      content: text,
      timestamp: DateTime(2026),
    );

ChatMessage _answer(
  String id, {
  List<ReActStep> steps = const [],
  String content = '',
  String reasoning = '',
  String status = '',
  bool streaming = true,
  TurnStats? stats,
}) =>
    ChatMessage(
      id: id,
      role: MessageRole.assistant,
      content: content,
      steps: steps,
      reasoning: reasoning,
      liveStatus: status,
      isStreaming: streaming,
      stats: stats,
      timestamp: DateTime(2026),
    );

const _call = ReActStep(
  type: ReActEventType.toolCall,
  content: '',
  toolName: 'read_story',
  toolArgs: {'story_id': 'obt/main/level_main_01-01_beg'},
);
const _output = ReActStep(
  type: ReActEventType.toolObservation,
  content: '《黑暗时代·上》 obt/main/level_main_01-01_beg.txt\nL1 甲：……\nL4 乙：……',
  toolName: 'read_story',
);

void main() {
  group('BridgeTranscriber', () {
    test('sends what changed, each once, in the order the reader saw it', () {
      final t = BridgeTranscriber();
      final q = _user('u1', '问题');
      expect(
        t.update([q, _answer('a1', status: '检索中')]).map((e) => e['t']),
        ['question', 'start', 'status'],
      );

      final calls = t.update([
        q,
        _answer('a1', steps: [_call], status: '检索中', reasoning: '先读'),
      ]);
      expect(calls.map((e) => e['t']), ['step', 'think']);
      expect(calls.first['tool'], 'read_story');
      expect(calls.first['args'], {'story_id': 'obt/main/level_main_01-01_beg'});

      final read = t.update([
        q,
        _answer(
          'a1',
          steps: [_call, _output],
          reasoning: '先读开头',
          content: '[STORY_ANSWER: status=answered]\n她',
        ),
      ]);
      expect(read.map((e) => e['t']), ['output', 'think', 'answer']);
      // The output reads as the timeline does: the story's name, not its id.
      expect(read[0]['summary'], '《黑暗时代·上》 L1–4');
      expect(read[1]['text'], '开头');
      expect(read[2]['text'], '[STORY_ANSWER: status=answered]\n她');

      final done = t.update([
        q,
        _answer(
          'a1',
          steps: [_call, _output],
          reasoning: '先读开头',
          content: '[STORY_ANSWER: status=answered]\n她来了。',
          streaming: false,
          stats: const TurnStats(
            calls: 2,
            promptTokens: 1000,
            cachedPromptTokens: 0,
            completionTokens: 100,
            elapsed: Duration(seconds: 7),
          ),
        ),
      ]);
      expect(done.map((e) => e['t']), ['answer', 'done']);
      expect(done[0]['text'], '来了。');
      expect(done[1]['status'], 'answered');
      // The answer as shown: without the envelope line.
      expect(done[1]['answer'], '她来了。');
      expect(done[1]['stats'], contains('2 calls'));

      // Nothing more once it is done.
      expect(t.update([q, _answer('a1', streaming: false)]), isEmpty);
    });

    test('what the chat held when the bridge connected is not sent again', () {
      final before = [_user('u1', '旧问题'), _answer('a1', streaming: false)];
      final t = BridgeTranscriber(before);
      expect(t.update(before), isEmpty);
      final events = t.update([...before, _user('u2', '追问'), _answer('a2')]);
      expect(events.map((e) => e['t']), ['question', 'start']);
      expect(events.first['text'], '追问');
    });

    test('a replaced answer and an error are told as such', () {
      final t = BridgeTranscriber();
      final q = _user('u1', '问题');
      t.update([q, _answer('a1', content: '第一版')]);
      final reset = t.update([q, _answer('a1', content: '重写')]);
      expect(reset.single['t'], 'answer_reset');
      final failed = t.update([
        q,
        _answer(
          'a1',
          steps: [
            const ReActStep(type: ReActEventType.error, content: '服务商返回 500'),
          ],
          content: '[ASK_ERROR]',
          streaming: false,
        ).copyWith(isError: true),
      ]);
      expect(failed.map((e) => e['t']), ['step', 'done']);
      expect(failed.last['status'], 'error');
      expect(failed.last['error'], '服务商返回 500');
    });

    test('a new conversation on the phone starts over', () {
      final t = BridgeTranscriber();
      t.update([_user('u1', '问题'), _answer('a1', streaming: false)]);
      expect(t.update(const []).single['t'], 'cleared');
      expect(t.update([_user('u2', '新问题')]).single['text'], '新问题');
    });
  });

  testWidgets('a question sent from the computer is asked and answered back',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    // flutter_test answers every HTTP request with 400; the bridge needs a
    // real connection.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final server = await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    final events = <Map<String, dynamic>>[];
    final done = Completer<void>();
    server!.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final event = jsonDecode(data as String) as Map<String, dynamic>;
        events.add(event);
        if (event['t'] == 'hello' && events.length == 1) {
          socket.add(jsonEncode({
            'cmd': 'ask',
            'text': '她是谁',
            'options': {'wiki': false},
          }),);
        }
        if (event['t'] == 'done' && !done.isCompleted) done.complete();
      });
    });
    final fake = _ScriptedAsk();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialApiConfigProvider.overrideWithValue(
            const LLMConfig(
              chatModel: 'test-model',
              chatBaseUrl: 'https://example.com/v1',
            ),
          ),
          askChatProvider.overrideWith((ref) => fake),
        ],
        child: PhoneBridgeHost(
          port: server.port,
          child: const SizedBox(),
        ),
      ),
    );
    // The bridge runs in the test's zone: let real time pass between pumps.
    for (var i = 0; i < 1000 && !done.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done.isCompleted, isTrue);
    await tester.runAsync(() => server.close(force: true));
    await tester.pumpWidget(const SizedBox());
    // The reconnect wait of the closed bridge.
    await tester.pump(const Duration(seconds: 6));

    expect(fake.asked, ['她是谁']);
    expect(events.first['model'], 'test-model');
    final kinds = events.map((e) => e['t']).toList();
    expect(
      kinds.where((k) => k != 'hello' && k != 'session'),
      ['question', 'start', 'step', 'output', 'answer', 'done'],
    );
    expect(events.firstWhere((e) => e['t'] == 'done')['answer'], '她来了。');
    // The options sent with the question are the app's options now.
    expect(
      events.where((e) => e['t'] == 'hello').last['options'],
      contains('wiki=0'),
    );
  });
}

/// Answers every question with one read and a fixed answer, through the
/// chat state the bridge watches.
class _ScriptedAsk extends AskChatNotifier {
  _ScriptedAsk()
      : super(
          agent: StoryQaAgent(
            llmClient: _NoLLM(),
            gameDataStore: GameDataKnowledgeStore(dbPath: 'unused.db'),
          ),
          configReader: () => const LLMConfig(),
        );

  final List<String> asked = [];

  @override
  Future<void> sendMessage(String text) async {
    asked.add(text);
    final q = _user('u${asked.length}', text);
    final id = 'a${asked.length}';
    state = [...state, q, _answer(id)];
    await Future<void>.delayed(Duration.zero);
    state = [...state.take(state.length - 1), _answer(id, steps: [_call])];
    await Future<void>.delayed(Duration.zero);
    state = [
      ...state.take(state.length - 1),
      _answer(
        id,
        steps: [_call, _output],
        content: '[STORY_ANSWER: status=answered]\n她来了。',
        streaming: false,
      ),
    ];
  }
}

class _NoLLM extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) =>
      throw UnimplementedError();

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) =>
      throw UnimplementedError();
}
