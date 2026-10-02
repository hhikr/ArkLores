/// Query planning and evidence-scoring helpers for the GameData store.
///
/// Pure functions: intent normalization (语音/秘录/模组/肉鸽 …), content
/// type inference, FTS query building, story-intent detection and proximity
/// scoring. Kept separate from the store so retrieval behavior is testable
/// without a database connection.
library;

String candidateMatchType(int? rank) {
  switch (rank) {
    case 0:
      return 'name_exact';
    case 1:
      return 'canonical_alias_exact';
    case 2:
      return 'alias_exact';
    case 3:
      return 'name_like';
    case 4:
      return 'alias_like';
    default:
      return 'unknown';
  }
}

bool detectStoryIntent(String query) {
  return query.contains(RegExp(r'(主线|剧情|故事|时间线|事件|章节|关卡|行动)'));
}

class GameDataQueryPlan {

  const GameDataQueryPlan({
    required this.originalQuery,
    required this.entityQuery,
    required this.searchQueries,
    required this.effectiveContentType,
    required this.hasStoryIntent,
  });

  factory GameDataQueryPlan.from(
    String query, {
    String? explicitContentType,
  }) {
    final original = query.trim();
    final normalized = original.replaceAll(RegExp(r'\s+'), ' ');
    final inferredContentType = explicitContentType?.trim().isNotEmpty == true
        ? explicitContentType!.trim()
        : inferContentType(normalized);
    final entityQuery = entityFocusedQuery(normalized);
    final queries = <String>{
      normalized,
      if (entityQuery.isNotEmpty) entityQuery,
      ...expandedQueryAliases(normalized),
      ...expandedQueryAliases(entityQuery),
    }.where((value) => value.trim().isNotEmpty).toList(growable: false);

    return GameDataQueryPlan(
      originalQuery: original,
      entityQuery: entityQuery.isEmpty ? normalized : entityQuery,
      searchQueries: queries,
      effectiveContentType: inferredContentType,
      hasStoryIntent: detectStoryIntent(normalized),
    );
  }
  final String originalQuery;
  final String entityQuery;
  final List<String> searchQueries;
  final String? effectiveContentType;
  final bool hasStoryIntent;
}

String? inferContentType(String query) {
  if (query.contains('语音')) return 'operator_voice';
  if (query.contains('秘录')) return 'operator_record_story';
  if (query.contains('模组')) return 'operator_module';
  if (query.contains('档案')) return 'operator_handbook_profile';
  if (query.contains('敌人')) return 'enemy_profile';
  return null;
}

String entityFocusedQuery(String query) {
  var focused = query;
  for (final term in queryIntentTerms) {
    focused = focused.replaceAll(term, ' ');
  }
  return focused.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> expandedQueryAliases(String query) {
  if (query.trim().isEmpty) return const [];
  final expanded = <String>{};
  if (query.contains('肉鸽')) {
    expanded.add(query.replaceAll('肉鸽', '集成战略'));
    expanded.add('$query 集成战略 傀影与猩红孤钻 水月与深蓝之树 探索者的银凇止境 萨卡兹的无终奇语');
  }
  if (query.contains('集成战略')) {
    expanded.add('$query 肉鸽');
  }
  if (query.contains('收藏品')) {
    expanded.add('$query relic collection');
  }
  if (query.contains('语音')) {
    expanded.add(query.replaceAll('语音', 'operator_voice charword'));
  }
  if (query.contains('档案')) {
    expanded.add(query.replaceAll('档案', 'operator_handbook_profile handbook'));
  }
  if (query.contains('秘录')) {
    expanded.add(query.replaceAll('秘录', 'operator_record_story story_review'));
  }
  if (query.contains('模组')) {
    expanded.add(query.replaceAll('模组', 'operator_module uniequip'));
  }
  return expanded.toList(growable: false);
}

const queryIntentTerms = {
  '语音',
  '档案',
  '秘录',
  '模组',
  '主线',
  '剧情',
  '故事',
  '时间线',
  '事件',
  '章节',
  '关卡',
  '行动',
  '相关',
  '梗概',
  '介绍',
};

List<String> storySearchTerms(
  String query, {
  required Set<String> entityNames,
}) {
  final terms = <String>[];
  final normalized = query.trim();

  for (final entityName in entityNames) {
    final clean = entityName.trim();
    if (clean.isNotEmpty && normalized.contains(clean)) {
      terms.add(clean);
    }
  }

  if (terms.isEmpty) {
    terms.addAll(
      normalized
          .split(RegExp(r'\s+'))
          .map((term) => term.trim())
          .where((term) => term.isNotEmpty)
          .where((term) => !isStoryIntentTerm(term)),
    );
  }

  return terms.toSet().take(3).toList(growable: false);
}

bool isStoryIntentTerm(String term) {
  return const {
    '主线',
    '剧情',
    '故事',
    '时间线',
    '事件',
    '章节',
    '关卡',
    '行动',
    '相关',
    '梗概',
  }.contains(term);
}

String rankingReason(String retrievalType) {
  if (retrievalType == 'entity_document') {
    return 'entity document exact match; highest priority for summaries';
  }
  if (retrievalType == 'entity_exact') {
    return 'exact entity match; authoritative structured GameData record';
  }
  if (retrievalType == 'summary_story_context') {
    return 'summary mode story context for the resolved entity';
  }
  if (retrievalType == 'entity_chunks') {
    return 'structured entity chunk match';
  }
  if (retrievalType == 'entity_records') {
    return 'structured entity raw record match';
  }
  if (retrievalType == 'entity_document_fts') {
    return 'entity document full-text match';
  }
  if (retrievalType == 'entity_document_like') {
    return 'entity document keyword fallback';
  }
  if (retrievalType == 'fts') {
    return 'lore chunk full-text match';
  }
  if (retrievalType.endsWith('_like') || retrievalType == 'record_like') {
    return 'keyword fallback match';
  }
  return 'structured GameData match';
}

String ftsQuery(String query) {
  final terms = searchTerms(query)
      .map((term) => term.replaceAll('"', '""'))
      .toList(growable: false);
  if (terms.isEmpty) return '""';
  return terms.map((term) => '"$term"').join(' ');
}

List<String> searchTerms(String query) {
  return query
      .trim()
      .split(RegExp(r'\s+'))
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

int evidenceProximity(
  String content, {
  required List<String> names,
  required List<String> terms,
}) {
  var closest = content.length;
  for (final name in names) {
    final nameOffsets = allOffsets(content, name);
    for (final term in terms) {
      for (final termOffset in allOffsets(content, term)) {
        for (final nameOffset in nameOffsets) {
          final distance = (nameOffset - termOffset).abs();
          if (distance < closest) closest = distance;
        }
      }
    }
  }
  return closest;
}

Iterable<int> allOffsets(String content, String term) sync* {
  var offset = 0;
  while (offset < content.length) {
    final match = content.indexOf(term, offset);
    if (match < 0) return;
    yield match;
    offset = match + term.length;
  }
}

