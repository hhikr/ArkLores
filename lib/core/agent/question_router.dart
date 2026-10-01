import '../llm/llm_client.dart';

/// Question mode for the AI Ask tab (entry consolidation, R4).
///
/// `auto` lets the [QuestionRouter] pick the workflow; the other three map
/// one-to-one to the existing agents:
///
/// - [AiMode.summarize]    -> SummaryAgent (梗概)
/// - [AiMode.verify]       -> FactCheckAgent (核查一个说法)
/// - [AiMode.investigate]  -> InvestigationAgent (直接回答一个具体问题)
///
/// Since R13 all three run the same retrieval pipeline; the mode only picks
/// the answer format.
enum AiMode { auto, summarize, verify, investigate }

/// Outcome of one routing decision.
///
/// Carries the concrete [mode] plus the router LLM's raw classification
/// output (untruncated) and any error, so session records can capture how
/// auto routing decided.
class RouteResult {
  const RouteResult({
    required this.mode,
    this.rawResponse = '',
    this.error,
  });

  final AiMode mode;
  final String rawResponse;
  final String? error;

  bool get failed => error != null;
}

/// LLM-based question router for the Ask tab.
///
/// A single lightweight classification call decides which agent workflow fits
/// the question. The prompt separates the three modes by *what the user wants*
/// (summarize known info / judge a claim / reason about the unknown), not by
/// surface keywords, so the routing stays robust across wordings.
class QuestionRouter {
  QuestionRouter({required LLMClient llmClient}) : _llmClient = llmClient;
  final LLMClient _llmClient;

  /// Classification prompt. The mode responsibilities are deliberately crisp
  /// and mode-separated so the router picks by intent.
  static const String classificationPrompt = '''
你是明日方舟剧情问题的模式分类器。只输出一个单词，不要任何其他文字。

根据用户想要的回答形式来选择模式，而不是看表面词：
- summarize（概括）：用户想要关于某个人物/事件/组织/章节的整体梗概——是什么、
  经历、时间线、剧情回顾。输出是概述 + 时间线。
- verify（查证）：用户给出了一个"说法/断言"，想知道它对不对——含"对吗、真的吗、
  是不是、据说、属实"等判断意图。输出是真假判定。
- investigate（深挖）：用户问了一个具体问题，想要直接答案——谁、为什么、怎样、
  在哪、何时、有什么关系。输出是直接回答 + 证据。

边界示例：
- "阿米娅是谁" → summarize
- "阿米娅是罗德岛的公开领袖吗" → verify
- "<某角色>最后怎么样了" → investigate
- "<某角色>和<另一角色>是什么关系" → investigate
''';

  /// Routes [query] to a concrete mode (never returns [AiMode.auto]).
  ///
  /// On classification failure (LLM error, empty or truncated response) it
  /// falls back to [AiMode.summarize] (the most general workflow) and reports
  /// the failure on the result, so callers can surface it instead of treating
  /// it as a successful "summarize" decision.
  Future<RouteResult> route(String query) async {
    try {
      final response = await _llmClient.chatCompletion(
        [
          Message.system(classificationPrompt),
          Message.user(query),
        ],
        temperature: 0,
        // Reasoning providers spend tokens on hidden reasoning before the
        // visible label; 16 was too small and produced empty content.
        maxTokens: 256,
      );
      final raw = response.content;
      if (raw.trim().isEmpty) {
        return RouteResult(
          mode: AiMode.summarize,
          error: 'empty classification response',
        );
      }
      if (response.wasTruncated) {
        return RouteResult(
          mode: AiMode.summarize,
          error: 'truncated classification response',
        );
      }
      final label = raw.trim().toLowerCase();
      final mode = label.contains('verify')
          ? AiMode.verify
          : label.contains('investigate')
              ? AiMode.investigate
              : AiMode.summarize;
      return RouteResult(mode: mode, rawResponse: raw);
    } catch (e) {
      return RouteResult(mode: AiMode.summarize, error: '$e');
    }
  }
}
