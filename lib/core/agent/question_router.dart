import '../llm/llm_client.dart';

/// Question mode for the AI Ask tab (entry consolidation, R4).
///
/// `auto` lets the [QuestionRouter] pick the workflow; the other three map
/// one-to-one to the existing agents:
///
/// - [AiMode.summarize]    -> SummaryAgent (整理已知信息)
/// - [AiMode.verify]       -> FactCheckAgent (判定说法真假)
/// - [AiMode.investigate]  -> InvestigationAgent (跨章节推理未知)
enum AiMode { auto, summarize, verify, investigate }

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

根据用户想得到什么来选择模式，而不是看表面词：
- summarize（概括）：用户想了解"已知信息"——人物/事件/组织是什么、经历、时间线、
  剧情回顾、档案资料、语音等。输出是对既有剧情的整理总结。
- verify（查证）：用户给出了一个"说法/断言"，想知道它对不对——含"对吗、真的吗、
  是不是、据说、属实、真假"等判断意图。输出是 supported/refuted 式的真假判定。
- investigate（深挖）：用户想推出"剧情没直说的信息"——跨章节因果、凶手、动机、
  伏笔、真相、谁干的、怎么发生的。输出是带证据链的推理结论。

边界示例：
- "阿米娅是谁" → summarize
- "阿米娅是罗德岛的公开领袖吗" → verify
- "米格鲁的死到底是谁造成的" → investigate
''';

  /// Routes [query] to a concrete mode (never returns [AiMode.auto]).
  ///
  /// On classification failure it falls back to [AiMode.summarize] (the most
  /// general workflow); callers should also wrap this in their own guard.
  Future<AiMode> route(String query) async {
    final response = await _llmClient.chatCompletion(
      [
        Message.system(classificationPrompt),
        Message.user(query),
      ],
      temperature: 0,
      maxTokens: 16,
    );
    final label = response.content.trim().toLowerCase();
    if (label.contains('verify')) return AiMode.verify;
    if (label.contains('investigate')) return AiMode.investigate;
    return AiMode.summarize;
  }
}
