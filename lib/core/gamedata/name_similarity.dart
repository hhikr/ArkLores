/// R15: "did you mean" for proper names that do not occur in the knowledge
/// base (a typo such as a homophone character).
///
/// Only surface strings are compared: a suggestion says "the DB contains
/// this similar string N times", never that two names are the same person.
/// Who a name refers to is settled by the agent from the lines it reads.
library;

import 'package:lpinyin/lpinyin.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'story_catalog.dart';

/// Every name-like string of the DB with its occurrence count: story
/// speakers (spoken lines), surface forms the coverage layer matched in
/// story text (mentions), names/aliases of people-like entities (operators,
/// enemies, speakers) and catalog collection / chapter names. Tables that
/// an older DB lacks are skipped.
Future<List<NameOccurrence>> loadNameInventory(DatabaseExecutor db) async {
  Future<bool> has(String table) async => (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      ))
          .isNotEmpty;

  final inventory = <NameOccurrence>[];
  if (await has('story_lines')) {
    for (final row in await db.rawQuery(
      'SELECT speaker, COUNT(*) AS n FROM story_lines '
      "WHERE speaker IS NOT NULL AND speaker != '' GROUP BY speaker",
    )) {
      inventory.add(NameOccurrence(
        '${row['speaker']}'.trim(),
        (row['n'] as num).toInt(),
        '说话人',
      ),);
    }
  }
  if (await has('entity_story_mentions')) {
    for (final row in await db.rawQuery(
      'SELECT matched_alias, SUM(mention_count) AS n FROM entity_story_mentions '
      'WHERE matched_alias IS NOT NULL GROUP BY matched_alias',
    )) {
      inventory.add(NameOccurrence(
        '${row['matched_alias']}'.trim(),
        (row['n'] as num).toInt(),
        '剧情提及',
      ),);
    }
  }
  const peopleTypes = "('operator', 'enemy', 'speaker')";
  if (await has('entities')) {
    for (final row in await db.rawQuery(
      'SELECT name, entity_type FROM entities WHERE entity_type IN $peopleTypes',
    )) {
      inventory.add(NameOccurrence(
        '${row['name']}'.trim(),
        0,
        _entityKind('${row['entity_type']}'),
      ),);
    }
  }
  if (await has('entity_aliases') && await has('entities')) {
    for (final row in await db.rawQuery(
      'SELECT a.alias, e.entity_type FROM entity_aliases a '
      'JOIN entities e ON e.id = a.entity_id '
      'WHERE e.entity_type IN $peopleTypes',
    )) {
      inventory.add(NameOccurrence(
        '${row['alias']}'.trim(),
        0,
        _entityKind('${row['entity_type']}'),
      ),);
    }
  }
  if (await hasStoryCatalog(db)) {
    for (final row in await db.rawQuery(
      'SELECT collection_name, COUNT(*) AS n FROM $storyCatalogTable '
      'GROUP BY collection_name',
    )) {
      inventory.add(NameOccurrence(
        '${row['collection_name']}'.trim(),
        0,
        '故事集',
      ),);
    }
    for (final row in await db.rawQuery(
      'SELECT DISTINCT story_name FROM $storyCatalogTable '
      'WHERE story_name IS NOT NULL',
    )) {
      inventory.add(NameOccurrence('${row['story_name']}'.trim(), 0, '章节'));
    }
  }
  // Speaker labels and matched surface forms carry punctuation
  // (`特蕾西娅？`, `特蕾西娅，`); fold them into the bare name.
  final folded = <NameOccurrence>[];
  for (final n in inventory) {
    final bare = n.name.replaceAll(_edgePunctuation, '');
    if (bare.isNotEmpty) folded.add(NameOccurrence(bare, n.occurrences, n.kind));
  }
  return folded;
}

/// 0.14: names of [inventory] written in [text] (a question), longest
/// first; a name inside a longer one found is left out. Only speakers,
/// people and story collections count: chapter titles and the surface forms
/// matched in story text are often everyday words; one-character names and
/// speakers seen fewer than [minSpoken] times are left out too. Used to give
/// the keyword leg of a search the names a question mentions — Chinese has
/// no spaces to split it on; what is not a name is found by meaning.
List<String> namesOccurringIn(
  String text,
  List<NameOccurrence> inventory, {
  int limit = 6,
  int minSpoken = 3,
}) {
  final found = <String, int>{};
  for (final n in inventory) {
    if (n.kind == '章节' || n.kind == '剧情提及' || n.name.runes.length < 2) {
      continue;
    }
    if (n.kind == '说话人' && n.occurrences > 0 && n.occurrences < minSpoken) {
      continue;
    }
    if (!text.contains(n.name)) continue;
    found[n.name] = (found[n.name] ?? 0) + n.occurrences;
  }
  final names = found.keys.toList()
    ..sort((a, b) {
      final byLength = b.runes.length.compareTo(a.runes.length);
      return byLength != 0 ? byLength : found[b]!.compareTo(found[a]!);
    });
  final picked = <String>[];
  for (final name in names) {
    if (picked.any((p) => p.contains(name))) continue;
    picked.add(name);
    if (picked.length >= limit) break;
  }
  return picked;
}

final RegExp _edgePunctuation =
    RegExp(r'^[\s\p{P}\p{S}]+|[\s\p{P}\p{S}]+$', unicode: true);

String _entityKind(String type) => switch (type) {
      'operator' => '干员',
      'enemy' => '敌人',
      _ => '说话人',
    };

/// A name string found in the knowledge base with how often it occurs.
class NameOccurrence {
  const NameOccurrence(this.name, this.occurrences, this.kind);

  final String name;

  /// Story mentions or spoken lines (whichever is larger); 0 for names that
  /// only exist as an entity / collection name.
  final int occurrences;

  /// Where the string comes from: 说话人 / 剧情提及 / 实体 / 故事集 / 章节.
  final String kind;
}

/// A near match of a queried name.
class SimilarName {
  const SimilarName({
    required this.name,
    required this.cost,
    required this.occurrences,
    required this.kind,
  });

  final String name;
  final double cost;
  final int occurrences;
  final String kind;
}

/// Substitution cost of two different characters that share a reading.
const double homophoneCost = 0.3;

final Map<int, Set<String>> _readingCache = {};

/// Toneless pinyin readings of [char] (every reading of a polyphone); empty
/// for characters without one (Latin letters, digits, punctuation).
Set<String> readingsOf(String char) {
  final rune = char.runes.first;
  return _readingCache.putIfAbsent(rune, () {
    final readings = PinyinHelper.convertToPinyinArray(
      char,
      PinyinFormat.WITHOUT_TONE,
    );
    return {
      for (final r in readings)
        if (r.isNotEmpty && r != char) r.toLowerCase(),
    };
  });
}

/// Weighted edit distance between [a] and [b]: insert/delete 1, substitute
/// 1, or [homophoneCost] when the two characters share a reading.
double nameDistance(String a, String b) {
  final x = a.runes.map(String.fromCharCode).toList(growable: false);
  final y = b.runes.map(String.fromCharCode).toList(growable: false);
  var previous = List<double>.generate(y.length + 1, (j) => j.toDouble());
  for (var i = 1; i <= x.length; i++) {
    final current = List<double>.filled(y.length + 1, 0)..[0] = i.toDouble();
    for (var j = 1; j <= y.length; j++) {
      final substitution = x[i - 1] == y[j - 1]
          ? 0.0
          : (readingsOf(x[i - 1]).intersection(readingsOf(y[j - 1])).isEmpty
              ? 1.0
              : homophoneCost);
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + substitution,
      ].reduce((m, v) => v < m ? v : m);
    }
    previous = current;
  }
  return previous[y.length];
}

/// Names in [inventory] close to [query], best first (lowest cost, then
/// most occurrences). A name qualifies when its cost is at most
/// max(1, length × 0.5) and it shares at least one character with [query]
/// (two short names one substitution apart but with nothing in common are
/// not a typo of each other). The query itself is never returned.
List<SimilarName> rankSimilarNames(
  String query,
  Iterable<NameOccurrence> inventory, {
  int limit = 3,
}) {
  final q = query.trim();
  final length = q.runes.length;
  if (length < 2) return const [];
  final threshold = length * 0.5 < 1 ? 1.0 : length * 0.5;
  final queryChars = q.runes.toSet();
  final best = <String, SimilarName>{};
  for (final candidate in inventory) {
    final name = candidate.name;
    if (name == q) continue;
    final candidateLength = name.runes.length;
    if (candidateLength < 2 ||
        (candidateLength - length).abs() > threshold) {
      continue;
    }
    if (!name.runes.any(queryChars.contains)) continue;
    final cost = nameDistance(q, name);
    if (cost > threshold) continue;
    // One name can come from several sources: keep the largest count and
    // the most telling kind (an operator / enemy over a bare mention).
    final previous = best[name];
    best[name] = SimilarName(
      name: name,
      cost: cost,
      occurrences: previous == null || candidate.occurrences > previous.occurrences
          ? candidate.occurrences
          : previous.occurrences,
      kind: previous == null ||
              _kindRank(candidate.kind) < _kindRank(previous.kind)
          ? candidate.kind
          : previous.kind,
    );
  }
  final ranked = best.values.toList()
    ..sort((a, b) {
      final byCost = a.cost.compareTo(b.cost);
      if (byCost != 0) return byCost;
      return b.occurrences.compareTo(a.occurrences);
    });
  return ranked.take(limit).toList(growable: false);
}

int _kindRank(String kind) => switch (kind) {
      '干员' || '敌人' => 0,
      '说话人' => 1,
      '故事集' || '章节' => 2,
      _ => 3,
    };

/// One observation line listing [similar] for a [term] the DB lacks, or
/// null when there is nothing to suggest.
String? describeSimilarNames(String term, List<SimilarName> similar) {
  if (similar.isEmpty) return null;
  final listed = similar.map((s) {
    final count = s.occurrences > 0 ? '，${s.occurrences} 次' : '';
    return '${s.name}（${s.kind}$count）';
  }).join('、');
  return '库中没有“$term”这个写法；字形或读音相近的名字：$listed。'
      '这只是字符串相近，是否指同一对象要结合问题和原文判断。';
}
