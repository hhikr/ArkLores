/// 0.14: the first searches of a question, written by a small model call of
/// its own (prompt: `loreSearchPlanPrompt`).
///
/// Before, code searched with the question as typed and with words it cut
/// out of it: fragments of clauses, an earlier question's words crowding out
/// the new one's, two words glued into a wiki query that found nothing. The
/// model knows how the stories name things; code only runs what it writes.
/// Only the searches and their results enter the conversation of the agent
/// that answers.
library;

import 'dart:convert';

/// The searches to run before the first turn.
class SearchPlan {
  const SearchPlan(this.queries, {this.wiki});

  /// `search` queries (space-separated words), at most [maxPlannedSearches].
  final List<String> queries;

  /// What to look for on the wikis (a page name or a noun), if anything.
  final String? wiki;
}

const int maxPlannedSearches = 3;

/// The plan in a model's reply, or null when it holds none. Tolerant of a
/// code block or text around the object, of one string where a list is
/// asked for, and of more searches than asked (the first ones are kept).
SearchPlan? parseSearchPlan(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  List<String> texts(Object? value) => [
        for (final item in value is List ? value : [value])
          if (item is String && item.trim().isNotEmpty)
            item.trim().replaceAll(RegExp(r'\s+'), ' '),
      ];
  final queries = <String>{
    for (final q in texts(decoded['search']))
      q.runes.length <= 80 ? q : String.fromCharCodes(q.runes.take(80)),
  }.take(maxPlannedSearches).toList();
  if (queries.isEmpty) return null;
  final wiki = texts(decoded['wiki']);
  return SearchPlan(queries, wiki: wiki.isEmpty ? null : wiki.first);
}
