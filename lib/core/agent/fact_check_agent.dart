import 'dart:async';

import '../llm/llm_client.dart';
import 'agent_prompts.dart';
import 'react_loop.dart';
import 'tools/agent_tool.dart';
import 'tools/search_local_lore.dart';
import 'tools/tool_registry.dart';

enum FactCheckVerdict { supported, refuted, uncertain, unavailable }

extension FactCheckVerdictWireValue on FactCheckVerdict {
  String get wireValue => name;
}

class FactCheckAgent {
  final LLMClient _llmClient;
  final AgentTool _searchTool;

  FactCheckAgent({required LLMClient llmClient, AgentTool? searchTool})
      : _llmClient = llmClient,
        _searchTool = searchTool ?? SearchLocalLoreTool();

  Stream<ReActEvent> checkClaim({
    required String claim,
    List<Message> history = const [],
  }) {
    final registry = ToolRegistry()..register(_searchTool);
    final loop = ReActLoop(
      llmClient: _llmClient,
      toolRegistry: registry,
      maxIterations: 5,
    );
    return loop.run(
      systemPrompt: buildAgentPrompt(factCheckInstructions),
      chatHistory: history,
      userQuery: claim,
      agentName: 'FactCheck',
      finalAnswerTransform: (answer, observations) {
        final verdict = validateFactCheckVerdict(answer, observations);
        return _withValidatedVerdict(answer, verdict);
      },
    );
  }
}

FactCheckVerdict validateFactCheckVerdict(
  String answer,
  Iterable<String> observations,
) {
  final match = RegExp(
    r'\[FACT_CHECK_VERDICT:(supported|refuted|uncertain|unavailable)\]',
    caseSensitive: false,
  ).firstMatch(answer);
  final requested = FactCheckVerdict.values.firstWhere(
    (value) => value.name == match?.group(1)?.toLowerCase(),
    orElse: () => FactCheckVerdict.uncertain,
  );
  final joined = observations.join('\n');
  final hasGameDataEvidence = joined.contains('Source Kind: GameData') &&
      joined.contains('=== Result #');
  final hasScopedDirectCandidate =
      joined.contains('Evidence Scope Match: yes') &&
          joined.contains('Evidence Level: direct candidate');
  final noCoverage = joined.isEmpty ||
      joined.contains('No matching GameData result') ||
      joined.contains('GameData knowledge DB is not installed');

  if (requested == FactCheckVerdict.supported ||
      requested == FactCheckVerdict.refuted) {
    if (hasScopedDirectCandidate) return requested;
    return hasGameDataEvidence
        ? FactCheckVerdict.uncertain
        : FactCheckVerdict.unavailable;
  }
  if (requested == FactCheckVerdict.uncertain &&
      !hasGameDataEvidence &&
      noCoverage) {
    return FactCheckVerdict.unavailable;
  }
  return requested;
}

String _withValidatedVerdict(String answer, FactCheckVerdict verdict) {
  final marker = RegExp(
    r'\[FACT_CHECK_VERDICT:(supported|refuted|uncertain|unavailable)\]\s*',
    caseSensitive: false,
  );
  return '[FACT_CHECK_VERDICT:${verdict.wireValue}]\n${answer.replaceFirst(marker, '').trim()}';
}

FactCheckVerdict? parseFactCheckVerdict(String content) {
  final match = RegExp(
    r'\[FACT_CHECK_VERDICT:(supported|refuted|uncertain|unavailable)\]',
    caseSensitive: false,
  ).firstMatch(content);
  final value = match?.group(1)?.toLowerCase();
  if (value == null) return null;
  return FactCheckVerdict.values.firstWhere((item) => item.name == value);
}
