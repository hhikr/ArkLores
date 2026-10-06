/// What an incremental update changed, for the user and for the developer.
///
/// Computed from the database before and after the update plus the list of
/// changed source files, so it needs no extra bookkeeping while importing.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'source/arknights_source_client.dart';

/// Chinese name of an entry type for the update report (the type itself when
/// unknown).
String entryTypeLabel(String type) => switch (type) {
      'story' => '剧情',
      'operator' => '干员',
      'enemy' => '敌人',
      'stage' => '关卡',
      'zone' => '章节',
      'item' => '物品',
      'skin' => '皮肤',
      'medal' => '勋章',
      'module' => '模组',
      'activity' => '活动',
      'activity_text' => '活动文本',
      'worldview' => '世界观',
      'mail' => '邮件',
      'roguelike_item' => '肉鸽收藏品',
      'roguelike_scene' => '肉鸽事件',
      'sandbox_event' => '生息演算事件',
      'sandbox_stage' => '生息演算关卡',
      'roguelike_choice' => '肉鸽选项',
      'roguelike_ending' => '肉鸽结局',
      'roguelike_stage' => '肉鸽关卡',
      _ when type.startsWith('archive_') => '活动档案',
      _ => type,
    };

/// A cheap summary of a knowledge base used to diff two states.
class DbSnapshot {
  const DbSnapshot({
    required this.entriesByType,
    required this.collections,
    required this.storyLines,
    required this.vectors,
    required this.storiesWithVectors,
  });

  /// Entries per `entries.type`.
  final Map<String, int> entriesByType;

  /// `collections.id` → name.
  final Map<String, String> collections;
  final int storyLines;

  /// Rows of `story_chunk_vectors` (0 when the table is absent).
  final int vectors;
  final int storiesWithVectors;

  static Future<DbSnapshot> take(DatabaseExecutor db) async {
    final hasEntries = await _hasTable(db, 'entries');
    final byType = <String, int>{};
    if (hasEntries) {
      for (final r in await db.rawQuery(
        'SELECT type, COUNT(*) AS n FROM entries GROUP BY type',
      )) {
        byType['${r['type']}'] = (r['n'] as num).toInt();
      }
    }
    final collections = <String, String>{};
    if (await _hasTable(db, 'collections')) {
      for (final r in await db.rawQuery('SELECT id, name FROM collections')) {
        collections['${r['id']}'] = '${r['name'] ?? r['id']}';
      }
    }
    final lines = await db.rawQuery('SELECT COUNT(*) AS n FROM story_lines');
    var vectors = 0, stories = 0;
    if (await _hasTable(db, 'story_chunk_vectors')) {
      final v = await db.rawQuery(
        'SELECT COUNT(*) AS n, COUNT(DISTINCT story_id) AS s '
        'FROM story_chunk_vectors',
      );
      vectors = (v.first['n'] as num).toInt();
      stories = (v.first['s'] as num).toInt();
    }
    return DbSnapshot(
      entriesByType: byType,
      collections: collections,
      storyLines: (lines.first['n'] as num).toInt(),
      vectors: vectors,
      storiesWithVectors: stories,
    );
  }

  static Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
        [name],
      ))
          .isNotEmpty;
}

/// The result of one incremental update.
class UpdateReport {
  const UpdateReport({
    required this.storyAdded,
    required this.storyChanged,
    required this.storyRemoved,
    required this.changedTables,
    required this.levelFiles,
    required this.storyLineDelta,
    required this.entryDelta,
    required this.newCollections,
    required this.vectorsDropped,
  });

  factory UpdateReport.compute({
    required DbSnapshot before,
    required DbSnapshot after,
    required List<SourceFileChange> changes,
  }) {
    final summary = SourceChangeSummary.of(changes);
    final delta = <String, int>{};
    for (final type in {
      ...before.entriesByType.keys,
      ...after.entriesByType.keys,
    }) {
      final d = (after.entriesByType[type] ?? 0) - (before.entriesByType[type] ?? 0);
      if (d != 0) delta[type] = d;
    }
    return UpdateReport(
      storyAdded: summary.storyAdded,
      storyChanged: summary.storyChanged,
      storyRemoved: summary.storyRemoved,
      changedTables: summary.tables,
      levelFiles: summary.levelFiles,
      storyLineDelta: after.storyLines - before.storyLines,
      entryDelta: delta,
      newCollections: [
        for (final e in after.collections.entries)
          if (!before.collections.containsKey(e.key)) e.value,
      ],
      vectorsDropped: before.vectors > after.vectors
          ? before.vectors - after.vectors
          : 0,
    );
  }

  factory UpdateReport.fromJson(Map<String, Object?> json) => UpdateReport(
        storyAdded: (json['storyAdded'] as num?)?.toInt() ?? 0,
        storyChanged: (json['storyChanged'] as num?)?.toInt() ?? 0,
        storyRemoved: (json['storyRemoved'] as num?)?.toInt() ?? 0,
        changedTables: [
          for (final t in (json['changedTables'] as List? ?? const [])) '$t',
        ],
        levelFiles: (json['levelFiles'] as num?)?.toInt() ?? 0,
        storyLineDelta: (json['storyLineDelta'] as num?)?.toInt() ?? 0,
        entryDelta: {
          for (final e in ((json['entryDelta'] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num).toInt(),
        },
        newCollections: [
          for (final c in (json['newCollections'] as List? ?? const [])) '$c',
        ],
        vectorsDropped: (json['vectorsDropped'] as num?)?.toInt() ?? 0,
      );

  final int storyAdded;
  final int storyChanged;
  final int storyRemoved;

  /// File names of the data tables that changed.
  final List<String> changedTables;
  final int levelFiles;
  final int storyLineDelta;

  /// New minus old entries per type (only types that changed).
  final Map<String, int> entryDelta;

  /// Names of the collections (activities, topics …) the update added.
  final List<String> newCollections;

  /// Vectors removed because their story changed; they are the vectors the
  /// user can regenerate ([VectorPlan]).
  final int vectorsDropped;

  int get storyFiles => storyAdded + storyChanged + storyRemoved;

  Map<String, Object?> toJson() => {
        'storyAdded': storyAdded,
        'storyChanged': storyChanged,
        'storyRemoved': storyRemoved,
        'changedTables': changedTables,
        'levelFiles': levelFiles,
        'storyLineDelta': storyLineDelta,
        'entryDelta': entryDelta,
        'newCollections': newCollections,
        'vectorsDropped': vectorsDropped,
      };

  /// A plain-text summary (the developer CLI prints it).
  String describe() {
    final lines = <String>[
      'Story files: +$storyAdded added, $storyChanged changed, '
          '-$storyRemoved removed (story lines ${_signed(storyLineDelta)})',
      if (changedTables.isNotEmpty) 'Tables: ${changedTables.join(', ')}',
      if (levelFiles > 0) 'Level files: $levelFiles',
      if (entryDelta.isNotEmpty)
        'Entries: ${[
          for (final e in (entryDelta.entries.toList()
            ..sort((a, b) => b.value.abs().compareTo(a.value.abs()))))
            '${e.key} ${_signed(e.value)}',
        ].join(', ')}',
      if (newCollections.isNotEmpty)
        'New: ${newCollections.take(12).join(', ')}'
            '${newCollections.length > 12 ? ' …' : ''}',
      if (vectorsDropped > 0) 'Vectors dropped (changed stories): $vectorsDropped',
    ];
    return lines.join('\n');
  }

  static String _signed(int n) => n >= 0 ? '+$n' : '$n';
}
