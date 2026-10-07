/// 0.12: writes an Endfield knowledge base — the same schema as the
/// Arknights one (schema 5), every id in the `ef/` namespace (`game.dart`),
/// `game = 'endfield'` on every row.
///
/// The importer ([EndfieldImporter]) decides what goes in; this class only
/// knows how a story, a text record, an entity, a collection, an entry, a
/// binding and a catalog row are written, and how the derived layers are
/// rebuilt at the end (coverage, FTS, manifest).
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../../../rag/chunker.dart';
import '../../game.dart';
import '../../story_catalog.dart';
import '../arknights_importer.dart' show BuildStats, nowSeconds, stableContentId;
import '../gamedata_build_service.dart' show countManifest;
import '../gamedata_schema.dart';
import '../story_coverage_builder.dart';

/// Game id recorded on Endfield rows.
const String endfieldGame = 'endfield';

/// Where the Endfield data came from (manifest and records).
const String endfieldSourceLabel = 'Arknights: Endfield client (local unpack)';

/// One line of an Endfield story as written.
class EndfieldLine {
  const EndfieldLine(this.content, {this.speaker, this.kind = 'dialogue'});

  final String? speaker;
  final String content;

  /// `story_lines.kind`: dialogue, narration, subtitle, document, choice,
  /// title, system.
  final String kind;
}

class EndfieldWriter {
  EndfieldWriter(this.db, {BuildStats? stats}) : stats = stats ?? BuildStats();

  final Database db;
  final BuildStats stats;
  final Chunker _chunker = const Chunker();

  /// Story ids written so far (a story is written once).
  final Set<String> _stories = {};
  int _catalogSort = 0;

  Future<void> createSchema({required String sourceVersion}) async {
    await createGamedataSchema(db);
    await db.execute(storyCatalogDdl);
    await writeGamedataManifest(db, {
      'schema_version': '$gamedataSchemaVersion',
      'language': gamedataLanguage,
      'game': endfieldGame,
      'source_endfield': endfieldSourceLabel,
      'source_endfield_version': sourceVersion,
      'built_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// `ef/<raw>.txt`: the story id of an Endfield conversation.
  static String storyIdOf(String raw) {
    final id = endfieldId(raw);
    return id.endsWith('.txt') ? id : '$id.txt';
  }

  /// A collection (a shelf's unit: a chapter, a mission line, …). [kind]
  /// and [id] are given without the `ef/` namespace.
  Future<void> collection({
    required String id,
    required String kind,
    required String name,
    String? parentId,
    int? sortKey,
    int? startTime,
    String? sourcePath,
  }) =>
      db.insert(
        'collections',
        {
          'id': endfieldId(id),
          'kind': endfieldId(kind),
          'name': name,
          // An entry id (<type>:ef/…) is already in the namespace.
          'parent_id': parentId == null || gameOfId(parentId) == Game.endfield
              ? parentId
              : endfieldId(parentId),
          'sort_key': sortKey,
          'start_time': startTime,
          'source_path': sourcePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// A story: its scope, its lines, its retrieval chunks, its entry and (when
  /// [collectionName] is given) its catalog row. Returns its story id, or
  /// null when it had no line or was written already.
  Future<String?> story({
    required String rawId,
    required String name,
    required List<EndfieldLine> lines,
    required String collectionId,
    required String sourcePath,
    String? collectionName,
    String? collectionType,
    String? code,
    String? group,
    String? synopsis,
    int? sortKey,
  }) async {
    final storyId = storyIdOf(rawId);
    final kept = [
      for (final l in lines)
        if (l.content.trim().isNotEmpty) l,
    ];
    if (kept.isEmpty || !_stories.add(storyId)) return null;
    final collection = endfieldId(collectionId);
    final entryId = 'story:$storyId';
    await db.transaction((txn) async {
      await txn.insert(
        'story_scopes',
        {
          'story_id': storyId,
          'scope_type': 'mission',
          'scope_id': collection,
          'source_path': sourcePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (var i = 0; i < kept.length; i++) {
        final line = kept[i];
        await txn.insert(
          'story_lines',
          {
            'id': stableContentId('endfield:story_line:$storyId:$i'),
            'game': endfieldGame,
            'story_id': storyId,
            'event_id': collection,
            'speaker': _blankToNull(line.speaker),
            'content': line.content.trim(),
            'line_index': i,
            'language': gamedataLanguage,
            'source_path': sourcePath,
            'kind': line.kind,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stats.storyLines++;
      }
      final text = kept
          .where((l) => l.kind != 'system')
          .map((l) => _blankToNull(l.speaker) == null
              ? l.content.trim()
              : '${l.speaker!.trim()}: ${l.content.trim()}',)
          .join('\n');
      final chunks = _chunker.chunkBySliding(text, pageTitle: name);
      for (var c = 0; c < chunks.length; c++) {
        await _record(
          txn,
          category: 'story',
          subtype: 'dialog',
          contentType: 'endfield_story',
          title: name,
          section: '剧情文本',
          content: chunks[c].content,
          sourcePath: sourcePath,
          rawId: '$storyId:$c',
          parentId: storyId,
          parentType: 'story_file',
          entryId: entryId,
          collectionId: collection,
          storyId: storyId,
        );
      }
      await txn.insert(
        'entries',
        {
          'id': entryId,
          'type': 'story',
          'name': name,
          'code': code,
          'collection_id': collection,
          'group_name': group,
          'sort_key': sortKey,
          'raw_id': storyId,
          'source_path': sourcePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (collectionName != null) {
        await txn.insert(
          storyCatalogTable,
          {
            'story_id': storyId,
            'collection_id': collection,
            'collection_name': collectionName,
            'collection_type': collectionType ?? '${endfieldCollectionTypePrefix}STORY',
            'story_code': code,
            'story_name': name,
            'avg_tag': null,
            'story_sort': sortKey ?? _catalogSort++,
            'synopsis': _blankToNull(synopsis),
            'synopsis_path': null,
            'start_time': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return storyId;
  }

  /// A non-story entry with its text (a document, a character profile, an
  /// item …). [rawId] is without the namespace; the entry id is
  /// `<type>:ef/<rawId>`. Returns the entry id.
  Future<String> entry({
    required String type,
    required String rawId,
    required String name,
    required String sourcePath,
    String? collectionId,
    String? group,
    String? code,
    int? sortKey,
    String? entityId,
    List<({String section, String text})> texts = const [],
    String category = 'world',
    String? contentType,
  }) async {
    final raw = endfieldId(rawId);
    final entryId = '$type:$raw';
    final collection = collectionId == null ? null : endfieldId(collectionId);
    String? firstRecord;
    await db.transaction((txn) async {
      for (final (i, t) in texts.indexed) {
        final id = await _record(
          txn,
          category: category,
          subtype: type,
          contentType: contentType ?? 'endfield_$type',
          title: name,
          section: t.section,
          content: t.text,
          sourcePath: sourcePath,
          rawId: texts.length == 1 ? raw : '$raw#$i',
          entryId: entryId,
          collectionId: collection,
          entityId: entityId,
          entityName: entityId == null ? null : name,
        );
        firstRecord ??= id;
      }
      await txn.insert(
        'entries',
        {
          'id': entryId,
          'type': type,
          'name': name,
          'code': code,
          'collection_id': collection,
          'group_name': group,
          'sort_key': sortKey,
          'entity_id': entityId,
          'raw_id': raw,
          'record_id': firstRecord,
          'source_path': sourcePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return entryId;
  }

  /// A binding between two entries (both full entry ids).
  Future<void> link(String src, String relation, String dst, String source) =>
      db.insert(
        'entry_links',
        {'src': src, 'relation': relation, 'dst': dst, 'source_path': source},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  /// A named entity (a character, an NPC, a place) the coverage layer finds
  /// in the stories by its name and [aliases]. Returns its id.
  Future<String> entity({
    required String rawId,
    required String name,
    required String type,
    required String sourcePath,
    Iterable<String> aliases = const [],
  }) async {
    final id = endfieldId(rawId);
    final names = {
      name.trim(),
      for (final a in aliases)
        if (a.trim().length >= 2) a.trim(),
    }..removeWhere((n) => n.isEmpty);
    await db.transaction((txn) async {
      await txn.insert(
        'entities',
        {
          'id': id,
          'name': name.trim(),
          'aliases': '[${names.map((n) => '"${n.replaceAll('"', r'\"')}"').join(',')}]',
          'entity_type': type,
          'source_type': 'endfield_$type',
          'game': endfieldGame,
          'source_path': sourcePath,
          'updated_at': nowSeconds(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final n in names) {
        await txn.insert(
          'entity_aliases',
          {
            'alias': n,
            'entity_id': id,
            'alias_type': n == name.trim() ? 'canonical' : 'alias',
            'confidence': 1.0,
            'source_path': sourcePath,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    stats.entities++;
    return id;
  }

  /// An entity's summary document (`entity_documents`), for the entity
  /// search the coverage layer and the agent's `sql` read.
  Future<void> entityDocument({
    required String entityId,
    required String name,
    required String type,
    required String content,
    required String sourcePath,
  }) async {
    if (content.trim().isEmpty) return;
    await db.insert(
      'entity_documents',
      {
        'id': stableContentId('endfield:doc:$entityId'),
        'game': endfieldGame,
        'language': gamedataLanguage,
        'entity_id': entityId,
        'entity_name': name,
        'entity_type': type,
        'document_type': 'profile',
        'title': name,
        'summary': content.length > 200 ? content.substring(0, 200) : content,
        'content': content.trim(),
        'source_paths': sourcePath,
        'updated_at': nowSeconds(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.entityDocuments++;
  }

  /// Coverage layer, FTS and the count manifest (the last step).
  Future<void> finish() async {
    await StoryCoverageBuilder(db: db, stats: stats).build();
    await rebuildGamedataFts(db);
    await stats.refreshFrom(db);
    await writeGamedataManifest(db, countManifest(stats));
  }

  Future<String> _record(
    Transaction txn, {
    required String category,
    required String subtype,
    required String contentType,
    required String content,
    required String sourcePath,
    String? title,
    String? section,
    String? rawId,
    String? parentId,
    String? parentType,
    String? entryId,
    String? collectionId,
    String? entityId,
    String? entityName,
    String? storyId,
  }) async {
    final clean = content.trim();
    final id = endfieldId(
      stableContentId(
        [endfieldGame, contentType, rawId ?? '', title ?? '', section ?? '', clean]
            .join(':'),
      ),
    );
    if (clean.isEmpty) return id;
    await txn.insert(
      'normalized_records',
      {
        'id': id,
        'game': endfieldGame,
        'language': gamedataLanguage,
        'category': category,
        'subtype': subtype,
        'content_type': contentType,
        'entity_id': entityId,
        'entity_name': entityName,
        'parent_id': parentId,
        'parent_type': parentType,
        'title': title,
        'section': section,
        'content': clean,
        'source_path': sourcePath,
        'raw_id': rawId,
        'source_repo': endfieldSourceLabel,
        'updated_at': nowSeconds(),
        'entry_id': entryId,
        'collection_id': collectionId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.normalizedRecords++;
    await txn.insert(
      'lore_chunks',
      {
        'id': stableContentId('endfield:chunk:$id'),
        'game': endfieldGame,
        'source_type': storyId != null ? 'game_story' : 'game_data',
        'content_category': category,
        'content_subtype': subtype,
        'content_type': contentType,
        'entity_id': entityId,
        'story_id': storyId,
        'scope_type': storyId != null ? 'mission' : null,
        'scope_id': storyId != null ? collectionId : null,
        'page_title': title ?? rawId ?? 'Endfield',
        'section': section ?? subtype,
        'content': clean,
        'source_path': sourcePath,
        'language': gamedataLanguage,
        'updated_at': nowSeconds(),
        'raw_id': rawId,
        'retrieval_hint': contentType,
        'entry_id': entryId,
        'collection_id': collectionId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.loreChunks++;
    if (storyId != null) {
      stats.storyChunks++;
    } else {
      stats.structuredChunks++;
    }
    return id;
  }
}

String? _blankToNull(String? s) =>
    s == null || s.trim().isEmpty ? null : s.trim();
