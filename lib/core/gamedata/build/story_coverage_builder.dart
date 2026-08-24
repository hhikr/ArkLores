/// Schema v3 deterministic coverage layer builder (R1 / AI retrieval P0).
///
/// Runs after the four-stage importer and derives, from the already-written
/// `story_lines` and `entities`/`entity_aliases` tables:
///
/// - `entity_story_mentions`: per-entity appearance runs per story
///   (consecutive hit lines merged into runs), built by a single-pass trie
///   scan of every story line. Coverage is deterministic: it does not depend
///   on how the user later phrases a query.
/// - `story_chapter_profiles`: per-story metadata (line range, speaker set,
///   entity density, triage keyword hits, extractive summary) used to choose
///   which chapters to read closely. Profiles are browsing aids, not evidence.
/// - `rare_terms`: character bigrams whose story-file document frequency is
///   at most [rareTermMaxDocFreq]. Used as the IDF basis for cross-chapter
///   detail matching (P1 `find_detail_echoes`).
///
/// `story_lines_fts` is rebuilt separately by `rebuildGamedataFts` (see
/// `gamedata_schema.dart`); this builder only fills the three data tables.
///
/// Note on false positives: the trie matches entity names and aliases at any
/// position inside a line without word segmentation, so short names (e.g. a
/// one-character alias such as "陈") can match inside unrelated words
/// ("陈述"). Mentions are coverage hints for the agent to read the actual
/// lines; they are not evidence, so a bounded amount of noise is acceptable
/// and preferred over missing real appearances.
library;

import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'arknights_importer.dart' show BuildStats, nowSeconds;
import 'gamedata_schema.dart' show gamedataGame;

/// doc_freq threshold for a character bigram to be considered "rare".
const int rareTermMaxDocFreq = 20;

/// Maximum entities recorded per story in `story_chapter_profiles`.
const int profileEntityDensityLimit = 20;

/// Minimum number of spoken lines for a story speaker to become a lightweight
/// `speaker:<name>` entity (R3 / P1 coverage extension).
const int speakerEntityMinLines = 3;

/// Triage-only keywords for `story_chapter_profiles.keyword_hits`.
///
/// Hits only flag chapters that may contain death/murder related content for
/// the investigation workflow; they are never used as evidence themselves.
const List<String> triageKeywords = [
  '死亡',
  '死去',
  '杀死',
  '杀害',
  '谋杀',
  '凶杀',
  '遇害',
  '丧生',
  '致命',
  '暗杀',
  '身亡',
  '惨死',
  '猝死',
  '凶器',
  '尸体',
  '血迹',
  '血泊',
  '毒杀',
];

/// Builds the schema v3 coverage layer tables.
class StoryCoverageBuilder {
  StoryCoverageBuilder({
    required this.db,
    required this.stats,
    this.onProgress,
  });
  final Database db;
  final BuildStats stats;

  /// Coarse per-substage progress of the coverage build (R2 UX): stages are
  /// `coverage_speakers`, `coverage_trie`, `coverage_scan` (done = chapters
  /// scanned, total = chapter count), `coverage_rare`, `coverage_profiles`
  /// (done = profiles written). Null disables reporting (desktop CLI).
  final void Function(String stage, int done, int total)? onProgress;

  Future<void> build() async {
    onProgress?.call('coverage_speakers', 0, 1);
    // R3: promote frequent story speakers without an entity row to lightweight
    // `speaker:<name>` entities so coverage includes named NPCs with dialogue.
    await _expandSpeakerEntities();
    onProgress?.call('coverage_speakers', 1, 1);

    onProgress?.call('coverage_trie', 0, 1);
    final trie = await _loadEntityTrie();
    onProgress?.call('coverage_trie', 1, 1);

    final scopes = await _loadScopes();

    // Pass A: scan story lines, write mention runs, accumulate bigram
    // document frequency and per-story profile drafts.
    final docFreq = <String, int>{};
    final lastSeen = <String, String>{};
    final drafts = <_ProfileDraft>[];

    final storyRows = await db.rawQuery(
      'SELECT story_id FROM story_scopes ORDER BY story_id',
    );
    for (var i = 0; i < storyRows.length; i++) {
      final storyRow = storyRows[i];
      final storyId = storyRow['story_id'] as String;
      final draft = await _scanStory(
        trie,
        storyId,
        scopes[storyId],
        docFreq,
        lastSeen,
      );
      if (draft != null) drafts.add(draft);
      onProgress?.call('coverage_scan', i + 1, storyRows.length);
    }

    // Pass B: rare terms (doc_freq <= rareTermMaxDocFreq).
    onProgress?.call('coverage_rare', 0, 1);
    final rareTerms = await _writeRareTerms(docFreq);
    onProgress?.call('coverage_rare', 1, 1);

    // Pass C: chapter profiles with rare-term-aware extractive summaries.
    onProgress?.call('coverage_profiles', 0, drafts.length);
    await _writeProfiles(trie, rareTerms, drafts, onProgress: onProgress);

    stats.storyProfiles = drafts.length;
    stats.rareTerms = rareTerms.length;
  }

  /// Promotes frequent story speakers to lightweight entities when no real
  /// entity owns the name (R3 / P1 coverage extension).
  ///
  /// A `speaker:<name>` entity is created (entity_type `speaker`, canonical
  /// alias) so the trie scan covers named NPCs with dialogue. Real entities
  /// always win: no speaker entity is created when the name matches an
  /// existing entity name or alias.
  Future<void> _expandSpeakerEntities() async {
    final rows = await db.rawQuery(
      'SELECT speaker, COUNT(*) AS c FROM story_lines '
      "WHERE speaker IS NOT NULL AND TRIM(speaker) != '' "
      'GROUP BY speaker HAVING c >= ?',
      [speakerEntityMinLines],
    );
    for (final row in rows) {
      final name = '${row['speaker']}'.trim();
      if (name.isEmpty || name.length > 40) continue;
      final exists = await db.rawQuery(
        'SELECT 1 FROM entities WHERE name = ? LIMIT 1',
        [name],
      );
      if (exists.isNotEmpty) continue;
      final aliasExists = await db.rawQuery(
        'SELECT 1 FROM entity_aliases WHERE alias = ? LIMIT 1',
        [name],
      );
      if (aliasExists.isNotEmpty) continue;
      final id = 'speaker:$name';
      await db.insert(
        'entities',
        {
          'id': id,
          'name': name,
          'aliases': jsonEncode(const <String>[]),
          'entity_type': 'speaker',
          'source_type': 'story_speaker',
          'game': gamedataGame,
          'source_path': 'zh_CN/gamedata/story',
          'updated_at': nowSeconds(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        'entity_aliases',
        {
          'alias': name,
          'entity_id': id,
          'alias_type': 'canonical',
          'confidence': 1.0,
          'source_path': 'zh_CN/gamedata/story',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<_EntityTrie> _loadEntityTrie() async {    final trie = _EntityTrie();
    final entityRows = await db.rawQuery('SELECT id, name FROM entities');
    for (final row in entityRows) {
      final id = row['id'] as String;
      final name = '${row['name'] ?? ''}'.trim();
      if (name.isNotEmpty) trie.insert(name, id);
    }
    final aliasRows = await db.rawQuery(
      'SELECT alias, entity_id FROM entity_aliases',
    );
    for (final row in aliasRows) {
      final alias = '${row['alias'] ?? ''}'.trim();
      final entityId = '${row['entity_id'] ?? ''}'.trim();
      if (alias.isNotEmpty && entityId.isNotEmpty) {
        trie.insert(alias, entityId);
      }
    }
    return trie;
  }

  Future<Map<String, ({String scopeType, String scopeId})>> _loadScopes() async {
    final rows = await db.rawQuery(
      'SELECT story_id, scope_type, scope_id FROM story_scopes',
    );
    return {
      for (final row in rows)
        '${row['story_id']}': (
          scopeType: '${row['scope_type']}',
          scopeId: '${row['scope_id']}',
        ),
    };
  }

  Future<_ProfileDraft?> _scanStory(
    _EntityTrie trie,
    String storyId,
    ({String scopeType, String scopeId})? scope,
    Map<String, int> docFreq,
    Map<String, String> lastSeen,
  ) async {
    final rows = await db.rawQuery(
      'SELECT line_index, speaker, content '
      'FROM story_lines WHERE story_id = ? ORDER BY line_index',
      [storyId],
    );
    if (rows.isEmpty) return null;

    final entityLines = <String, List<int>>{};
    final entityAlias = <String, String>{};
    final speakers = <String>{};
    final keywordHits = <String, int>{};
    final storyBigrams = <String>{};
    var firstLine = 0;
    var lastLine = 0;
    var isFirst = true;

    for (final row in rows) {
      final lineIndex = (row['line_index'] as num?)?.toInt() ?? 0;
      if (isFirst) {
        firstLine = lineIndex;
        isFirst = false;
      }
      lastLine = lineIndex;
      final speaker = '${row['speaker'] ?? ''}'.trim();
      if (speaker.isNotEmpty) speakers.add(speaker);
      final content = '${row['content'] ?? ''}';

      // A character's appearances include their dialogue lines, where the
      // name lives in the speaker field rather than the content. Scan the
      // rendered "speaker content" text for mentions; bigrams and triage
      // keywords are derived from content only.
      final scanText = speaker.isEmpty ? content : '$speaker $content';
      final hits = _matchEntityHits(trie, scanText);
      for (final hit in hits) {
        for (final entityId in hit.entityIds) {
          final lines = entityLines.putIfAbsent(entityId, () => <int>[]);
          if (lines.isEmpty || lines.last != lineIndex) {
            lines.add(lineIndex);
            entityAlias.putIfAbsent(entityId, () => hit.matchedText);
          }
        }
      }

      for (final keyword in triageKeywords) {
        if (content.contains(keyword)) {
          keywordHits[keyword] = (keywordHits[keyword] ?? 0) + 1;
        }
      }

      storyBigrams.addAll(extractCharacterBigrams(content));
    }

    // Write mention runs for this story.
    var mentionRows = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in entityLines.entries) {
        for (final run in mergeMentionRuns(entry.value)) {
          batch.insert(
            'entity_story_mentions',
            {
              'entity_id': entry.key,
              'story_id': storyId,
              'scope_id': _scopeKey(scope),
              'line_start': run.$1,
              'line_end': run.$2,
              'mention_count': run.$3,
              'matched_alias': entityAlias[entry.key],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          mentionRows++;
        }
      }
      await batch.commit(noResult: true);
    });
    stats.storyCoverageMentions += mentionRows;

    // Update bigram document frequency (distinct stories only).
    for (final bigram in storyBigrams) {
      final current = docFreq[bigram] ?? 0;
      if (current == 0) {
        docFreq[bigram] = 1;
        lastSeen[bigram] = storyId;
      } else if (current <= rareTermMaxDocFreq &&
          lastSeen[bigram] != storyId) {
        final next = current + 1;
        docFreq[bigram] = next;
        lastSeen[bigram] = storyId;
        if (next > rareTermMaxDocFreq) {
          // No longer rare; stop tracking to bound memory.
          lastSeen.remove(bigram);
        }
      }
    }

    return _ProfileDraft(
      storyId: storyId,
      scopeType: scope?.scopeType,
      scopeId: scope?.scopeId,
      title: storyId.split('/').last,
      lineStart: firstLine,
      lineEnd: lastLine,
      speakers: speakers.toList()..sort(),
      keywordHits: keywordHits,
    );
  }

  Future<Set<String>> _writeRareTerms(Map<String, int> docFreq) async {
    final rareTerms = <String>{};
    final entries = docFreq.entries
        .where((entry) => entry.value <= rareTermMaxDocFreq)
        .toList(growable: false);
    for (var i = 0; i < entries.length; i += 5000) {
      final chunk = entries.sublist(
        i,
        i + 5000 > entries.length ? entries.length : i + 5000,
      );
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final entry in chunk) {
          batch.insert(
            'rare_terms',
            {'term': entry.key, 'doc_freq': entry.value},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          rareTerms.add(entry.key);
        }
        await batch.commit(noResult: true);
      });
    }
    return rareTerms;
  }

  Future<void> _writeProfiles(
    _EntityTrie trie,
    Set<String> rareTerms,
    List<_ProfileDraft> drafts, {
    void Function(String stage, int done, int total)? onProgress,
  }) async {
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      onProgress?.call('coverage_profiles', i + 1, drafts.length);
      final rows = await db.rawQuery(
        'SELECT line_index, speaker, content '
        'FROM story_lines WHERE story_id = ? ORDER BY line_index',
        [draft.storyId],
      );
      var bestScore = -1;
      String? bestContent;
      for (final row in rows) {
        final speaker = '${row['speaker'] ?? ''}'.trim();
        final content = '${row['content'] ?? ''}';
        final scanText = speaker.isEmpty ? content : '$speaker $content';
        final score = _lineScore(trie, rareTerms, content, scanText);
        if (score > bestScore) {
          bestScore = score;
          bestContent = content;
        }
      }

      final densityRows = await db.rawQuery(
        'SELECT entity_id, SUM(mention_count) AS count '
        'FROM entity_story_mentions '
        'WHERE story_id = ? GROUP BY entity_id '
        'ORDER BY count DESC LIMIT ?',
        [draft.storyId, profileEntityDensityLimit],
      );
      final density = {
        for (final row in densityRows)
          '${row['entity_id']}': (row['count'] as num?)?.toInt() ?? 0,
      };

      await db.insert(
        'story_chapter_profiles',
        {
          'story_id': draft.storyId,
          'scope_id': _scopeKey(
            (scopeType: draft.scopeType, scopeId: draft.scopeId),
          ),
          'title': draft.title,
          'line_start': draft.lineStart,
          'line_end': draft.lineEnd,
          'speaker_set': jsonEncode(draft.speakers),
          'entity_density': jsonEncode(density),
          'summary':
              bestContent != null ? _capSummary(bestContent) : null,
          'keyword_hits': jsonEncode(draft.keywordHits),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  int _lineScore(
    _EntityTrie trie,
    Set<String> rareTerms,
    String content,
    String scanText,
  ) {
    var entityHits = 0;
    for (final hit in _matchEntityHits(trie, scanText)) {
      entityHits += hit.entityIds.length;
    }
    var rareCount = 0;
    for (final bigram in extractCharacterBigrams(content)) {
      if (rareTerms.contains(bigram)) rareCount++;
    }
    return entityHits * 2 + rareCount;
  }

  String _capSummary(String content) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 200) return normalized;
    return '${normalized.substring(0, 200)}…';
  }

  String _scopeKey(({String? scopeType, String? scopeId})? scope) {
    if (scope == null) return 'unknown';
    final type = scope.scopeType;
    final id = scope.scopeId;
    if (type == null || type.isEmpty) return 'unknown';
    if (id == null || id.isEmpty) return type;
    return '$type:$id';
  }
}

/// Matches the trie at every position and returns deduplicated entity hits.
List<_EntityHit> _matchEntityHits(_EntityTrie trie, String content) {
  final hits = <_EntityHit>[];
  for (var start = 0; start < content.length; start++) {
    final hit = trie.matchAt(content, start);
    if (hit != null) hits.add(hit);
  }
  return hits;
}

/// Merges consecutive hit line indexes into runs.
///
/// A run is a maximal span of lines where consecutive hits are at most one
/// line apart. Returns (line_start, line_end, mention_count) triples.
List<(int, int, int)> mergeMentionRuns(List<int> lineIndexes) {
  final sorted = [...lineIndexes]..sort();
  final runs = <(int, int, int)>[];
  if (sorted.isEmpty) return runs;
  var start = sorted.first;
  var end = sorted.first;
  var count = 1;
  for (var i = 1; i < sorted.length; i++) {
    final line = sorted[i];
    if (line - end <= 1) {
      end = line;
      count++;
    } else {
      runs.add((start, end, count));
      start = line;
      end = line;
      count = 1;
    }
  }
  runs.add((start, end, count));
  return runs;
}

/// Extracts all CJK character bigrams from [text] (no segmentation).
///
/// Only bigrams made of two CJK ideographs are kept; punctuation, digits and
/// Latin characters are skipped. This keeps `rare_terms` and the summary
/// scoring focused on Chinese vocabulary.
Set<String> extractCharacterBigrams(String text) {
  final runes = text.runes.toList(growable: false);
  final bigrams = <String>{};
  for (var i = 0; i + 1 < runes.length; i++) {
    if (!_isCjk(runes[i]) || !_isCjk(runes[i + 1])) continue;
    bigrams.add(String.fromCharCodes([runes[i], runes[i + 1]]));
  }
  return bigrams;
}

bool _isCjk(int rune) => rune >= 0x4e00 && rune <= 0x9fff;

class _EntityTrie {
  final _TrieNode _root = _TrieNode();

  void insert(String text, String entityId) {
    var node = _root;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      node = node.children.putIfAbsent(char, () => _TrieNode());
    }
    if (!node.entityIds.contains(entityId)) {
      node.entityIds.add(entityId);
    }
  }

  /// Longest-match lookup at [start]; null when nothing matches.
  _EntityHit? matchAt(String content, int start) {
    var node = _root;
    String? bestText;
    List<String>? bestIds;
    for (var i = start; i < content.length; i++) {
      final next = node.children[content[i]];
      if (next == null) break;
      node = next;
      if (node.entityIds.isNotEmpty) {
        bestText = content.substring(start, i + 1);
        bestIds = node.entityIds;
      }
    }
    if (bestText == null || bestIds == null) return null;
    return _EntityHit(bestText, bestIds);
  }
}

class _TrieNode {
  final Map<String, _TrieNode> children = {};
  final List<String> entityIds = [];
}

class _EntityHit {
  const _EntityHit(this.matchedText, this.entityIds);
  final String matchedText;
  final List<String> entityIds;
}

class _ProfileDraft {
  const _ProfileDraft({
    required this.storyId,
    required this.scopeType,
    required this.scopeId,
    required this.title,
    required this.lineStart,
    required this.lineEnd,
    required this.speakers,
    required this.keywordHits,
  });
  final String storyId;
  final String? scopeType;
  final String? scopeId;
  final String title;
  final int lineStart;
  final int lineEnd;
  final List<String> speakers;
  final Map<String, int> keywordHits;
}
