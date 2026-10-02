/// Evidence bookkeeping and answer constraints shared by all ReAct Agents.
///
/// Tracks which source kinds actually appeared in tool observations, so the
/// final answer cannot claim Wiki / Book / GameData evidence that was never
/// retrieved. Also owns the fallback prompt and the source-guard post-check.
library;

class EvidenceSummary {
  bool hasGameData = false;
  bool hasWiki = false;
  bool hasBook = false;
  int emptyOrErrorObservationCount = 0;

  void addError() => emptyOrErrorObservationCount++;

  void addObservation(String observation) {
    if (observation.contains('Source Kind: GameData')) {
      hasGameData = true;
    }
    if (observation.contains('Source Type: wiki')) {
      hasWiki = true;
    }
    if (observation.contains('Source Type: book') ||
        observation.contains('Book ID:')) {
      hasBook = true;
    }
    if (observation.contains('No matching records found') ||
        observation.contains('No matching GameData result found') ||
        observation.contains('No scoped direct candidate found') ||
        observation.contains('Evidence search requires both') ||
        observation.contains('No confident GameData result') ||
        observation.contains('Error:') ||
        observation.contains('Error occurred') ||
        observation.contains('Error executing tool')) {
      emptyOrErrorObservationCount++;
    }
  }
}

String buildFallbackPrompt(EvidenceSummary evidence) {
  return '''
Please summarize all findings and output your Final Answer now.

Verified evidence summary for this ReAct session:
- GameData evidence available: ${evidence.hasGameData ? 'yes' : 'no'}
- Wiki evidence available: ${evidence.hasWiki ? 'yes' : 'no'}
- Book evidence available: ${evidence.hasBook ? 'yes' : 'no'}
- Empty/error observations seen: ${evidence.emptyOrErrorObservationCount}

Use only facts that appear in the Observation messages above.
Do not add well-known lore, inferred timeline events, or background knowledge unless the same concrete names/events appear in Observation content.
If an event, chapter, faction, battle, or character relationship was not retrieved, say it was not retrieved instead of filling it from memory.
Do not claim Wiki evidence exists unless an Observation contains "Source Type: wiki".
Do not claim Book evidence exists unless an Observation contains "Source Type: book" or "Book ID:".
Do not claim GameData evidence exists unless an Observation contains "Source Kind: GameData".
Treat "No matching records found", "No matching GameData result found", "No confident GameData result", and tool errors as absence of evidence, not as supporting evidence.
If a requested detail was not found in the verified evidence, say the current knowledge base did not retrieve it.
''';
}

/// Appends a visible warning when the answer claims a source kind that never
/// appeared in the session observations.
String applySourceGuard(String content, EvidenceSummary evidence) {
  final warnings = <String>[];
  if (!evidence.hasWiki && _mentionsWikiEvidence(content)) {
    warnings.add(
      'This answer mentions Wiki evidence, but this session did not retrieve any observation with Source Type: wiki.',
    );
  }
  if (!evidence.hasBook && _mentionsBookEvidence(content)) {
    warnings.add(
      'This answer mentions Book evidence, but this session did not retrieve any observation with Source Type: book or Book ID.',
    );
  }
  if (!evidence.hasGameData && _mentionsGameDataEvidence(content)) {
    warnings.add(
      'This answer mentions GameData evidence, but this session did not retrieve any observation with Source Kind: GameData.',
    );
  }
  if (warnings.isEmpty) return content;

  return [
    content.trim(),
    '',
    '> Source warning: ${warnings.join(' ')}',
  ].join('\n');
}

bool _mentionsWikiEvidence(String content) {
  return RegExp(r'(Wiki|维基|PRTS)', caseSensitive: false).hasMatch(content);
}

bool _mentionsBookEvidence(String content) {
  return RegExp(r'(\bBook\b|书籍资料|用户导入)', caseSensitive: false)
      .hasMatch(content);
}

bool _mentionsGameDataEvidence(String content) {
  return RegExp(r'(GameData|游戏原始文本|解包数据)', caseSensitive: false)
      .hasMatch(content);
}
