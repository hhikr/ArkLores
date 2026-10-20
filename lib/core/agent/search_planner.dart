/// 0.14: the first steps of a question, written by a small model call of
/// its own (prompt: `loreSearchPlanPrompt`): searches, and since the
/// questions that only name a collection ("what came before it"), a
/// collection's outline or a wiki search.
///
/// Before, code searched with the question as typed and with words it cut
/// out of it: fragments of clauses, an earlier question's words crowding out
/// the new one's, two words glued into a wiki query that found nothing. The
/// model knows how the stories name things; code only runs what it writes.
/// Only the searches and their results enter the conversation of the agent
/// that answers.
///
/// Phase 1 of the unified refactor (2026-10-18, the developer's call): the
/// plan also names the question's anchors, and code gathers the story lines
/// around them (`gather`, `coverage.dart`) as one more step of the first
/// turn.
library;

import 'dart:convert';

/// The steps to run before the first turn.
class SearchPlan {
  const SearchPlan(
    this.queries, {
    this.wiki,
    this.outlines = const [],
    this.wikiSearches = const [],
    this.anchors = const [],
  });

  /// `search` queries (space-separated words), at most [maxPlannedSearches].
  final List<String> queries;

  /// What the first `search` looks for on the wikis (a page name or a
  /// noun), if anything.
  final String? wiki;

  /// Collections to `outline` (names), at most [maxPlannedOutlines].
  final List<String> outlines;

  /// `wiki_search` queries, at most [maxPlannedWikiSearches].
  final List<String> wikiSearches;

  /// Names to `gather` around, at most [maxPlannedAnchors]. Not counted in
  /// [maxPlannedSteps].
  final List<String> anchors;
}

const int maxPlannedSearches = 3;
const int maxPlannedOutlines = 2;
const int maxPlannedWikiSearches = 2;
const int maxPlannedAnchors = 6;

/// Steps of all kinds together; beyond it outlines are kept first, then
/// searches, then wiki searches.
const int maxPlannedSteps = 4;

/// The plan in a model's reply, or null when it holds no step. Tolerant of
/// a code block or text around the object, of one string where a list is
/// asked for, and of more steps than asked (the first ones are kept).
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
  final plan = decoded;
  List<String> texts(Object? value) => [
        for (final item in value is List ? value : [value])
          if (item is String && item.trim().isNotEmpty)
            item.trim().replaceAll(RegExp(r'\s+'), ' '),
      ];
  List<String> steps(String field, int most) => <String>{
        for (final q in texts(plan[field]))
          q.runes.length <= 80 ? q : String.fromCharCodes(q.runes.take(80)),
      }.take(most).toList();
  final outlines = steps('outline', maxPlannedOutlines);
  final queries = steps('search', maxPlannedSearches)
      .take(maxPlannedSteps - outlines.length)
      .toList();
  final wikiSearches = steps('wiki_search', maxPlannedWikiSearches)
      .take(maxPlannedSteps - outlines.length - queries.length)
      .toList();
  final anchors = <String>{
    for (final a in texts(plan['anchors']))
      if (a.runes.length <= 20) a,
  }.take(maxPlannedAnchors).toList();
  if (queries.isEmpty &&
      outlines.isEmpty &&
      wikiSearches.isEmpty &&
      anchors.isEmpty) {
    return null;
  }
  final wiki = texts(plan['wiki']);
  return SearchPlan(
    queries,
    wiki: wiki.isEmpty ? null : wiki.first,
    outlines: outlines,
    wikiSearches: wikiSearches,
    anchors: anchors,
  );
}
