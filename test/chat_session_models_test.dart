import 'package:arklores/core/agent/chat_session_models.dart';
import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/question_router.dart';
import 'package:arklores/core/agent/react_loop.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatSessionFile JSON round-trip', () {
    test('preserves turns, router records, iterations and verdict', () {
      final session = ChatSessionFile(
        sessionId: 'sid-1',
        createdAt: DateTime(2026, 8, 24, 10, 0),
        updatedAt: DateTime(2026, 8, 24, 10, 5),
        title: '标题',
        turns: [
          ChatSessionTurn(
            turn: 1,
            timestamp: DateTime(2026, 8, 24, 10, 1),
            query: '问题',
            userMode: AiMode.auto,
            effectiveMode: AiMode.investigate,
            router: RouterRecord(
              rawResponse: 'investigate',
              error: null,
            ),
            model: 'deepseek-v4-flash',
            baseUrl: 'https://api.deepseek.com/v1',
            iterations: [
              ReActIterationRecord(
                iteration: 1,
                rawResponse: 'Thought: 调查。\nAction: read_story_lines',
                thought: '调查。',
                action: 'read_story_lines',
                actionInput: '{"story_id": "s1"}',
                tool: 'read_story_lines',
                toolArgs: const {'story_id': 's1'},
                observation: 'Story: s1\n0 | 角色A | 台词',
              ),
            ],
            answer: '结论',
            status: ChatTurnStatus.completed,
            durationMs: 99,
            memory: '## 调查记忆\n已读章节: s1:0-103; s2:0-86',
          ),
          ChatSessionTurn(
            turn: 2,
            timestamp: DateTime(2026, 8, 24, 10, 2),
            query: '第二个问题',
            userMode: AiMode.verify,
            effectiveMode: AiMode.verify,
            model: 'deepseek-v4-flash',
            baseUrl: 'https://api.deepseek.com/v1',
            answer: '[FACT_CHECK_VERDICT:refuted]\n不成立',
            verdict: FactCheckVerdict.refuted,
            status: ChatTurnStatus.error,
            error: 'LLM Error: boom',
            durationMs: 5,
          ),
        ],
      );

      final decoded = ChatSessionFile.decode(session.encode());
      expect(decoded.sessionId, 'sid-1');
      expect(decoded.turns, hasLength(2));

      final turn1 = decoded.turns[0];
      expect(turn1.userMode, AiMode.auto);
      expect(turn1.effectiveMode, AiMode.investigate);
      expect(turn1.router!.rawResponse, 'investigate');
      expect(turn1.router!.error, isNull);
      expect(turn1.iterations.single.rawResponse,
          contains('Thought: 调查。'),);
      expect(turn1.iterations.single.toolArgs, {'story_id': 's1'});
      expect(turn1.verdict, isNull);
      expect(turn1.memory, contains('已读章节: s1:0-103'));

      final turn2 = decoded.turns[1];
      expect(turn2.router, isNull);
      expect(turn2.verdict, FactCheckVerdict.refuted);
      expect(turn2.status, ChatTurnStatus.error);
      expect(turn2.error, 'LLM Error: boom');
      expect(turn2.durationMs, 5);
    });

    test('tolerates missing optional fields', () {
      final session = ChatSessionFile.decode('''
      {
        "format": "arklores_chat_session",
        "version": 1,
        "session_id": "x",
        "created_at": "2026-08-24T10:00:00.000",
        "updated_at": "2026-08-24T10:00:00.000",
        "title": "t",
        "turns": [
          {
            "turn": 1,
            "timestamp": "2026-08-24T10:00:00.000",
            "query": "q",
            "user_mode": "summarize",
            "effective_mode": "summarize",
            "model": "m",
            "base_url": "b"
          }
        ]
      }
      ''');
      expect(session.turns.single.iterations, isEmpty);
      expect(session.turns.single.answer, '');
      expect(session.turns.single.status, ChatTurnStatus.completed);
      expect(session.turns.single.verdict, isNull);
    });
  });

  group('chatTurnToMessages / chatSessionToMessages', () {
    test('rebuilds user + assistant messages with ReAct steps', () {
      final session = ChatSessionFile(
        sessionId: 's',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        title: 't',
        turns: [
          ChatSessionTurn(
            turn: 1,
            timestamp: DateTime(2026, 8, 24, 10),
            query: '问题一',
            userMode: AiMode.summarize,
            effectiveMode: AiMode.summarize,
            model: 'm',
            baseUrl: 'b',
            iterations: [
              ReActIterationRecord(
                iteration: 1,
                rawResponse: 'raw',
                thought: '思考',
                action: 'search_local_lore',
                actionInput: '{"query": "阿米娅"}',
                tool: 'search_local_lore',
                toolArgs: const {'query': '阿米娅'},
                observation: '观察结果',
              ),
            ],
            answer: '回答一',
            status: ChatTurnStatus.completed,
          ),
        ],
      );

      final messages = chatSessionToMessages(session);
      expect(messages, hasLength(2));
      expect(messages[0].role, MessageRole.user);
      expect(messages[0].content, '问题一');
      expect(messages[1].role, MessageRole.assistant);
      expect(messages[1].content, '回答一');
      expect(messages[1].isStreaming, isFalse);
      expect(messages[1].isError, isFalse);
      expect(messages[1].steps, hasLength(3));
      expect(messages[1].steps[0].type, ReActEventType.thought);
      expect(messages[1].steps[0].content, '思考');
      expect(messages[1].steps[1].type, ReActEventType.toolCall);
      expect(messages[1].steps[1].toolName, 'search_local_lore');
      expect(messages[1].steps[2].type, ReActEventType.toolObservation);
      expect(messages[1].steps[2].content, '观察结果');
    });

    test('error turns rebuild as error assistant messages', () {
      final messages = chatTurnToMessages(
        ChatSessionTurn(
          turn: 1,
          timestamp: DateTime(2026),
          query: 'q',
          userMode: AiMode.verify,
          effectiveMode: AiMode.verify,
          model: 'm',
          baseUrl: 'b',
          answer: '',
          status: ChatTurnStatus.error,
          error: 'LLM Error: boom',
        ),
        'a1',
      );
      expect(messages[1].isError, isTrue);
      expect(messages[1].content, '');
    });

    test('canceled turns rebuild as normal (non-error) messages', () {
      final messages = chatTurnToMessages(
        ChatSessionTurn(
          turn: 1,
          timestamp: DateTime(2026),
          query: 'q',
          userMode: AiMode.auto,
          effectiveMode: AiMode.summarize,
          model: 'm',
          baseUrl: 'b',
          status: ChatTurnStatus.canceled,
          error: '[ASK_CANCELED]',
        ),
        'a2',
      );
      expect(messages[1].isError, isFalse);
    });
  });
}
