import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/agent/fact_check_agent.dart';
import 'package:arklores/core/agent/investigation_agent.dart';
import 'package:arklores/core/agent/question_router.dart';
import 'package:arklores/core/agent/summary_agent.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuestionRouter (LLM pre-classification)', () {
    test('routes to verify / investigate / summarize by label', () async {
      Future<AiMode> routeWith(String label) async {
        final router = QuestionRouter(
          llmClient: _LabelLLMClient(label),
        );
        return (await router.route('测试问题')).mode;
      }

      expect(await routeWith('verify'), AiMode.verify);
      expect(await routeWith('investigate'), AiMode.investigate);
      expect(await routeWith('summarize'), AiMode.summarize);
      // Unknown output falls back to the most general workflow.
      expect(await routeWith('garbage text'), AiMode.summarize);
    });

    test('route result carries the raw classification output', () async {
      final router = QuestionRouter(llmClient: _LabelLLMClient('investigate'));
      final result = await router.route('测试问题');
      expect(result.mode, AiMode.investigate);
      expect(result.rawResponse, 'investigate');
      expect(result.error, isNull);
    });

    test('route failure falls back to summarize and reports the error',
        () async {
      final router = QuestionRouter(llmClient: _ThrowingLLMClient());
      final result = await router.route('测试问题');
      expect(result.mode, AiMode.summarize);
      expect(result.rawResponse, isEmpty);
      expect(result.error, isNotNull);
    });
  });

  group('AskChatNotifier auto routing', () {
    test('routes a verify-intent question through the fact-check workflow',
        () async {
      final mock = _AutoRouteLLMClient();
      final notifier = AskChatNotifier(
        summaryAgent: SummaryAgent(llmClient: mock),
        factCheckAgent: FactCheckAgent(llmClient: mock),
        investigationAgent: InvestigationAgent(llmClient: mock),
        router: QuestionRouter(llmClient: mock),
        configReader: () => const LLMConfig(),
      );

      await notifier.sendMessage(
        '阿米娅是罗德岛的公开领袖吗',
        mode: AiMode.auto,
      );

      // The router classified it as verify, so the answer goes through the
      // fact-check transform. Without an installed DB the tool returns "not
      // installed", so the verdict transform legitimately downgrades to
      // unavailable — the assertion targets routing + verdict parsing, not
      // the evidence outcome.
      expect(mock.routeCallCount, 1);
      final last = notifier.state.last;
      expect(last.content, contains('[FACT_CHECK_VERDICT:unavailable]'));
      expect(last.factCheckVerdict, FactCheckVerdict.unavailable);
      expect(last.isError, isFalse);
    });

    test('pinned summarize mode skips the router', () async {
      final mock = _AutoRouteLLMClient();
      final notifier = AskChatNotifier(
        summaryAgent: SummaryAgent(llmClient: mock),
        factCheckAgent: FactCheckAgent(llmClient: mock),
        investigationAgent: InvestigationAgent(llmClient: mock),
        router: QuestionRouter(llmClient: mock),
        configReader: () => const LLMConfig(),
      );

      await notifier.sendMessage('阿米娅是谁', mode: AiMode.summarize);

      expect(mock.routeCallCount, 0);
      final last = notifier.state.last;
      expect(last.content, contains('她是罗德岛的公开领袖'));
      expect(last.factCheckVerdict, isNull);
    });
  });
}

class _LabelLLMClient extends LLMClient {
  _LabelLLMClient(this.label);
  final String label;

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return label;
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}

class _ThrowingLLMClient extends LLMClient {
  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    throw const LLMException('boom');
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    throw const LLMException('boom');
  }
}

/// First route call answers `verify`; agent calls drive a tool step then a
/// final answer. Route vs agent calls are distinguished by the system prompt.
class _AutoRouteLLMClient extends LLMClient {
  int routeCallCount = 0;
  int _agentCallCount = 0;

  bool _isRouteCall(List<Message> messages) =>
      messages.first.content.contains('模式分类器');

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    if (_isRouteCall(messages)) {
      routeCallCount++;
      return 'verify';
    }
    _agentCallCount++;
    if (_agentCallCount == 1) {
      // First agent step: perform one tool call so loops with
      // minimumToolCalls >= 1 can proceed.
      return '''
Thought: 我需要检索证据。
Action: search_local_lore
Action Input: {"query": "阿米娅", "search_mode": "evidence", "scope_id": "activity:x", "entity_id": "char_002_amiya"}
''';
    }
    return '''
Thought: 证据充分。
Final Answer: [FACT_CHECK_VERDICT:supported]
支持：阿米娅是罗德岛的公开领袖。她是罗德岛的公开领袖。
''';
  }

  @override
  Future<String> chatStream(
    List<Message> messages, {
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    return chat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
      stop: stop,
    );
  }
}
