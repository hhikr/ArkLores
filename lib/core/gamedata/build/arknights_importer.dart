/// Arknights GameData importer shared by the desktop CLI builder and the
/// in-app builder (R0: extracted from `tools/build_gamedata_database.dart`).
///
/// Reads `zh_CN/gamedata` from Kengxxiao/ArknightsGameData and writes the
/// schema 5 tables through a `sqflite`-compatible [Database]. The import
/// stages (operators, voices, entries, stories) have no data dependencies
/// between them, so callers may reorder or run them in isolation for
/// incremental updates. Operators, voices and stories are imported here;
/// every other table becomes entries through `EntryImporter`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/entry_importer.dart';
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_script.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

/// Imports Arknights GameData into an open [Database].
class ArknightsImporter {
  ArknightsImporter({
    required this.sourceDir,
    required this.db,
    required this.stats,
    required this.storyLimit,
    this.onProgress,
  });
  final Directory sourceDir;
  final Database db;
  final BuildStats stats;

  /// When > 0, imports only the first N story txt files (smoke tests).
  final int storyLimit;

  /// Optional coarse progress callback: (stage, done, total).
  ///
  /// Stages: `profiles`, `voices`, `structured`, `stories`. `total` is 0 when
  /// unknown. Used by the in-app builder to drive progress UI; never invoked
  /// for per-file re-import entry points.
  final void Function(String stage, int done, int total)? onProgress;
  final Chunker _chunker = const Chunker();

  Future<void> importAll() async {
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    if (!await zh.exists()) {
      throw StateError('Missing zh_CN directory: ${zh.path}');
    }
    await importCharacterTables();
    await importVoiceTable();
    await importEntries();
    await _importStories();
  }

  /// The importer of the entry layer (every table except operators, voices
  /// and stories).
  late final EntryImporter entryImporter = EntryImporter(this);

  /// Imports the whole entry layer: tables, levels and the owners
  /// (`collections`). Derived entries (stories) are added by
  /// [EntryImporter.rebuildDerived] once the stories and the catalog exist.
  Future<void> importEntries() async {
    onProgress?.call('structured', 0, 1);
    await entryImporter.importAllTables();
    onProgress?.call('structured', 1, 1);
  }

  /// Re-imports the character profile stage (character_table.json +
  /// handbook_info_table.json + aggregated entity documents).
  ///
  /// Idempotent: rows are upserted by stable content-derived ids.
  Future<void> importCharacterTables() async {
    onProgress?.call('profiles', 0, 0);
    await _importCharacterProfiles();
    onProgress?.call('profiles', 1, 1);
  }

  /// Re-imports the operator voice stage (charword_table.json).
  Future<void> importVoiceTable() async {
    onProgress?.call('voices', 0, 0);
    await _importCharacterVoices();
    onProgress?.call('voices', 1, 1);
  }

  /// Re-imports one story file by its repo-relative path
  /// (e.g. `zh_CN/gamedata/story/activities/act21mini/level_x.txt`).
  Future<void> importStoryFile(String relativePath) async {
    final file = File(p.join(sourceDir.path, relativePath));
    if (!await file.exists()) {
      throw StateError('Missing story file: $relativePath');
    }
    await _importStoryFile(file, relativePath);
  }

  Future<void> _importCharacterProfiles() async {
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    final characterTable = await readJsonMap(
      p.join(zh.path, 'gamedata', 'excel', 'character_table.json'),
    );
    final handbookInfo = await readJsonMap(
      p.join(zh.path, 'gamedata', 'excel', 'handbook_info_table.json'),
    );
    final handbookDict =
        (handbookInfo['handbookDict'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final sourcePath = 'zh_CN/gamedata/excel/character_table.json';

    await db.transaction((txn) async {
      for (final entry in characterTable.entries) {
        final charId = entry.key;
        final raw = entry.value;
        if (raw is! Map) continue;
        final data = raw.cast<String, dynamic>();
        final name = '${data['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;

        final aliases = <String>{
          if ('${data['appellation'] ?? ''}'.trim().isNotEmpty)
            '${data['appellation']}'.trim(),
          if ('${data['displayNumber'] ?? ''}'.trim().isNotEmpty)
            '${data['displayNumber']}'.trim(),
        }.toList();
        final documentSections = <TextSection>[];

        await txn.insert(
          'entities',
          {
            'id': charId,
            'name': name,
            'aliases': jsonEncode(aliases),
            'entity_type': 'operator',
            'source_type': 'operator_profile',
            'game': gamedataGame,
            'source_path': sourcePath,
            'updated_at': nowSeconds(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stats.entities++;
        await _insertEntityAliases(
          txn,
          entityId: charId,
          canonicalName: name,
          aliases: aliases,
          sourcePath: sourcePath,
        );

        final basicProfile = [
          if ('${data['description'] ?? ''}'.trim().isNotEmpty)
            '${data['description']}'.trim(),
          if ('${data['itemUsage'] ?? ''}'.trim().isNotEmpty)
            '${data['itemUsage']}'.trim(),
          if ('${data['itemDesc'] ?? ''}'.trim().isNotEmpty)
            '${data['itemDesc']}'.trim(),
        ].join('\n').trim();
        if (basicProfile.isNotEmpty) {
          documentSections.add(TextSection('基础信息', basicProfile));
        }

        await _insertChunk(
          txn,
          category: 'operator',
          subtype: 'basic_profile',
          contentType: 'operator_basic_profile',
          entityId: charId,
          pageTitle: name,
          section: '基础信息',
          content: basicProfile,
          sourcePath: sourcePath,
          rawId: charId,
          retrievalHint: 'operator_profile',
          entryId: 'operator:$charId',
        );

        final handbook = handbookDict[charId];
        if (handbook is Map) {
          final storyTextAudio = handbook['storyTextAudio'];
          if (storyTextAudio is List) {
            for (final sectionRaw in storyTextAudio) {
              if (sectionRaw is! Map) continue;
              final section = '${sectionRaw['storyTitle'] ?? '档案资料'}';
              final stories = sectionRaw['stories'];
              if (stories is! List) continue;
              for (final storyRaw in stories) {
                if (storyRaw is! Map) continue;
                final text = '${storyRaw['storyText'] ?? ''}'.trim();
                if (text.isEmpty) continue;
                documentSections.add(TextSection(section, text));
                await _insertChunk(
                  txn,
                  category: 'operator',
                  subtype: 'handbook_profile',
                  contentType: 'operator_handbook_profile',
                  entityId: charId,
                  pageTitle: name,
                  section: section,
                  content: text,
                  sourcePath: 'zh_CN/gamedata/excel/handbook_info_table.json',
                  rawId: charId,
                  retrievalHint: 'operator_handbook',
                  entryId: 'operator:$charId',
                );
              }
            }
          }
        }

        await _insertEntityDocument(
          txn,
          entityId: charId,
          entityName: name,
          entityType: 'operator',
          documentType: 'operator_profile_bundle',
          title: name,
          sections: documentSections,
          sourcePaths: const [
            'zh_CN/gamedata/excel/character_table.json',
            'zh_CN/gamedata/excel/handbook_info_table.json',
          ],
          sourceRecordIds: [charId],
        );
        if (documentSections.isNotEmpty) {
          await insertEntry(
            txn,
            id: 'operator:$charId',
            // Summons and deployable devices share the table with the
            // operators; the table's own `profession` tells them apart.
            type: switch ('${data['profession'] ?? ''}'.toUpperCase()) {
              'TOKEN' => 'token',
              'TRAP' => 'trap',
              _ => 'operator',
            },
            name: name,
            code: '${data['displayNumber'] ?? ''}'.trim().isEmpty
                ? null
                : '${data['displayNumber']}'.trim(),
            entityId: charId,
            rawId: charId,
            sourcePath: sourcePath,
          );
        }
      }
    });
  }

  Future<void> _importCharacterVoices() async {
    final sourcePath = 'zh_CN/gamedata/excel/charword_table.json';
    final table = await readJsonMap(p.join(sourceDir.path, sourcePath));
    final charWords =
        (table['charWords'] as Map?)?.cast<String, dynamic>() ?? const {};

    await db.transaction((txn) async {
      for (final entry in charWords.entries) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final data = raw.cast<String, dynamic>();
        final text = '${data['voiceText'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        final charId = '${data['charId'] ?? ''}'.trim();
        final title = '${data['voiceTitle'] ?? '语音'}'.trim();
        final record = NormalizedRecord(
          category: 'operator',
          subtype: 'voice',
          contentType: 'operator_voice',
          entityId: charId.isEmpty ? null : charId,
          title: title,
          section: title,
          content: text,
          sourcePath: sourcePath,
          rawId: '${data['charWordId'] ?? entry.key}',
          entryId: charId.isEmpty ? null : 'operator:$charId',
        );
        await insertRecord(txn, record);
        if (charId.isNotEmpty) {
          await _insertRelation(
            txn,
            sourceEntityId: charId,
            targetEntityId: record.id,
            relationType: 'operator_voice',
            sourcePath: sourcePath,
            rawId: record.rawId,
          );
        }
      }
    });
  }

  Future<void> _importStories() async {
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    final storyRoot = Directory(p.join(zh.path, 'gamedata', 'story'));
    if (!await storyRoot.exists()) return;

    final files = await storyRoot
        .list(recursive: true)
        .where((entity) {
          if (entity is! File || !entity.path.endsWith('.txt')) return false;
          // The upstream repo ships a `[uc]info/` tree of one-line story
          // stubs alongside the real full-text tree; importing both would
          // duplicate every story and pollute scopes/coverage with stub rows.
          final rel = p.relative(entity.path, from: storyRoot.path);
          return !rel.startsWith('[uc]info${p.separator}');
        })
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    final selected = storyLimit > 0 ? files.take(storyLimit).toList() : files;
    for (var i = 0; i < selected.length; i++) {
      final file = selected[i];
      final relativePath = p.relative(file.path, from: sourceDir.path);
      await _importStoryFile(file, relativePath);
      onProgress?.call('stories', i + 1, selected.length);
    }
  }

  Future<void> _importStoryFile(File file, String relativePath) async {
    final zhStory = p.join(sourceDir.path, 'zh_CN', 'gamedata', 'story');
    final storyId =
        p.relative(file.path, from: zhStory).replaceAll(p.separator, '/');
    final raw = await file.readAsString();
    final lines = parseStoryScript(raw);
    if (lines.isEmpty) return;
    final scope = storyScope(storyId);

    await db.transaction((txn) async {
      await txn.insert(
        'story_scopes',
        {
          'story_id': storyId,
          'scope_type': scope.$1,
          'scope_id': scope.$2,
          'source_path': relativePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        await txn.insert(
          'story_lines',
          {
            'id': stableContentId('arknights:story_line:$storyId:$i'),
            'game': gamedataGame,
            'story_id': storyId,
            'event_id': scope.$1 == 'activity' ? scope.$2 : null,
            'speaker': line.speaker,
            'content': line.content,
            'line_index': i,
            'language': gamedataLanguage,
            'source_path': relativePath,
            'kind': line.kind.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stats.storyLines++;
      }

      // Tutorial and guide popups are story lines (readable, queryable) but
      // not retrieval text of the story.
      final text = lines
          .where((line) => line.kind != StoryLineKind.system)
          .map((line) => line.speaker == null
              ? line.content
              : '${line.speaker}: ${line.content}',)
          .join('\n');
      final chunks = _chunker.chunkBySliding(text, pageTitle: storyId);
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        final chunk = chunks[chunkIndex];
        await insertRecord(
          txn,
          NormalizedRecord(
            category: storyCategory(storyId),
            subtype: storySubtype(storyId),
            contentType: storyContentType(storyId),
            parentId: storyId,
            parentType: 'story_file',
            title: storyId,
            section: '剧情文本',
            speaker: null,
            content: chunk.content,
            sourcePath: relativePath,
            rawId: '$storyId:$chunkIndex',
            lineStart: null,
            lineEnd: null,
            entryId: 'story:$storyId',
          ),
        );
      }
    });
  }

  /// Reads a JSON object file of the source tree.
  Future<Map<String, dynamic>> readJsonMap(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Missing required GameData file: $path');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw StateError('Expected JSON object: $path');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<void> _insertChunk(
    Transaction txn, {
    required String category,
    required String subtype,
    required String contentType,
    required String pageTitle,
    required String section,
    required String content,
    required String sourcePath,
    String? entityId,
    String? storyId,
    int? lineStart,
    int? lineEnd,
    String? rawId,
    String? retrievalHint,
    String? entryId,
    String? collectionId,
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    final sourceType = category == 'story' || contentType.endsWith('_story')
        ? 'game_story'
        : 'game_data';
    final scope = storyId == null ? null : storyScope(storyId);
    final id = stableContentId([
      gamedataGame,
      contentType,
      entityId ?? '',
      storyId ?? '',
      rawId ?? '',
      pageTitle,
      section,
      clean,
    ].join(':'),);
    await txn.insert(
      'lore_chunks',
      {
        'id': id,
        'game': gamedataGame,
        'source_type': sourceType,
        'content_category': category,
        'content_subtype': subtype,
        'content_type': contentType,
        'entity_id': entityId,
        'story_id': storyId,
        'scope_type': scope?.$1,
        'scope_id': scope?.$2,
        'page_title': pageTitle,
        'section': section,
        'content': clean,
        'source_path': sourcePath,
        'line_start': lineStart,
        'line_end': lineEnd,
        'language': gamedataLanguage,
        'updated_at': nowSeconds(),
        'raw_id': rawId,
        'retrieval_hint': retrievalHint,
        'entry_id': entryId,
        'collection_id': collectionId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.loreChunks++;
    if (sourceType == 'game_story') {
      stats.storyChunks++;
    } else if (category == 'operator') {
      stats.profileChunks++;
    } else {
      stats.structuredChunks++;
    }
  }

  /// Inserts one citable record (and its retrieval chunk).
  Future<void> insertRecord(Transaction txn, NormalizedRecord record) async {
    final clean = record.content.trim();
    if (clean.isEmpty) return;
    await txn.insert(
      'normalized_records',
      {
        'id': record.id,
        'game': gamedataGame,
        'language': gamedataLanguage,
        'category': record.category,
        'subtype': record.subtype,
        'content_type': record.contentType,
        'entity_id': record.entityId,
        'entity_name': record.entityName,
        'parent_id': record.parentId,
        'parent_type': record.parentType,
        'title': record.title,
        'section': record.section,
        'speaker': record.speaker,
        'content': clean,
        'source_path': record.sourcePath,
        'raw_id': record.rawId,
        'line_start': record.lineStart,
        'line_end': record.lineEnd,
        'source_repo': arknightsSourceRepoUrl,
        'source_commit': null,
        'updated_at': nowSeconds(),
        'entry_id': record.entryId,
        'collection_id': record.collectionId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.normalizedRecords++;
    await _insertChunk(
      txn,
      category: record.category,
      subtype: record.subtype,
      contentType: record.contentType,
      entityId: record.entityId,
      pageTitle:
          record.title ?? record.entityName ?? record.rawId ?? 'GameData',
      section: record.section ?? record.subtype,
      content: clean,
      sourcePath: record.sourcePath,
      lineStart: record.lineStart,
      lineEnd: record.lineEnd,
      rawId: record.rawId,
      storyId: record.parentType == 'story_file' ? record.parentId : null,
      retrievalHint: record.contentType,
      entryId: record.entryId,
      collectionId: record.collectionId,
    );
  }

  /// Adds (or replaces) one entry row.
  Future<void> insertEntry(
    Transaction txn, {
    required String id,
    required String type,
    required String sourcePath,
    String? name,
    String? code,
    String? collectionId,
    String? groupName,
    int? sortKey,
    String? entityId,
    String? rawId,
    String? recordId,
  }) async {
    await txn.insert(
      'entries',
      {
        'id': id,
        'type': type,
        'name': name,
        'code': code,
        'collection_id': collectionId,
        'group_name': groupName,
        'sort_key': sortKey,
        'entity_id': entityId,
        'raw_id': rawId,
        'record_id': recordId,
        'source_path': sourcePath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.entries++;
  }

  /// Adds one directed link between two entries.
  Future<void> insertLink(
    Transaction txn, {
    required String src,
    required String relation,
    required String dst,
    required String sourcePath,
  }) async {
    await txn.insert(
      'entry_links',
      {
        'src': src,
        'relation': relation,
        'dst': dst,
        'source_path': sourcePath,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    stats.entryLinks++;
  }

  /// Adds or replaces an entity (the name index of aliases and coverage).
  Future<void> upsertEntity(
    Transaction txn, {
    required String id,
    required String name,
    required String entityType,
    required String sourceType,
    required String sourcePath,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    await txn.insert(
      'entities',
      {
        'id': id,
        'name': cleanName,
        'aliases': jsonEncode(const <String>[]),
        'entity_type': entityType,
        'source_type': sourceType,
        'game': gamedataGame,
        'source_path': sourcePath,
        'updated_at': nowSeconds(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.entities++;
    await _insertEntityAliases(
      txn,
      entityId: id,
      canonicalName: cleanName,
      aliases: const [],
      sourcePath: sourcePath,
    );
  }

  Future<void> _insertEntityAliases(
    Transaction txn, {
    required String entityId,
    required String canonicalName,
    required List<String> aliases,
    required String sourcePath,
  }) async {
    final generatedAliases = <String>{
      ...aliases,
      ..._generatedAliases(canonicalName),
    };
    final entries = <({String alias, String type, double confidence})>[
      (alias: canonicalName.trim(), type: 'canonical', confidence: 1.0),
      for (final alias in generatedAliases)
        if (alias.trim().isNotEmpty)
          (alias: alias.trim(), type: 'alias', confidence: 0.8),
    ];
    for (final entry in entries) {
      await txn.insert(
        'entity_aliases',
        {
          'alias': entry.alias,
          'entity_id': entityId,
          'alias_type': entry.type,
          'confidence': entry.confidence,
          'source_path': sourcePath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  List<String> _generatedAliases(String canonicalName) {
    final name = canonicalName.trim();
    if (name.isEmpty) return const [];

    final aliases = <String>{};
    final delimiterIndex = name.indexOf(RegExp(r'[，,（(「『“]'));
    if (delimiterIndex > 1) {
      aliases.add(name.substring(0, delimiterIndex).trim());
    }
    final quotedPrefix = RegExp(r'^([^「『“”"]+)[「『“"].+[」』”"]$')
        .firstMatch(name)
        ?.group(1)
        ?.trim();
    if (quotedPrefix != null && quotedPrefix.length > 1) {
      aliases.add(quotedPrefix);
    }
    aliases.remove(name);
    return aliases.toList(growable: false);
  }

  Future<void> _insertRelation(
    Transaction txn, {
    required String sourceEntityId,
    required String targetEntityId,
    required String relationType,
    required String sourcePath,
    String? rawId,
  }) async {
    await txn.insert(
      'entity_relations',
      {
        'id': stableContentId([
          sourceEntityId,
          targetEntityId,
          relationType,
          rawId ?? '',
        ].join(':'),),
        'source_entity_id': sourceEntityId,
        'target_entity_id': targetEntityId,
        'relation_type': relationType,
        'source_path': sourcePath,
        'raw_id': rawId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.entityRelations++;
  }

  Future<void> _insertEntityDocument(
    Transaction txn, {
    required String entityId,
    required String entityName,
    required String entityType,
    required String documentType,
    required String title,
    required List<TextSection> sections,
    required List<String> sourcePaths,
    required List<String> sourceRecordIds,
  }) async {
    final cleanSections = sections
        .where((section) => section.content.trim().isNotEmpty)
        .toList(growable: false);
    if (cleanSections.isEmpty) return;

    final content = cleanSections
        .map((section) => '## ${section.section}\n${section.content.trim()}')
        .join('\n\n')
        .trim();
    await txn.insert(
      'entity_documents',
      {
        'id': stableContentId('$gamedataGame:$documentType:$entityId'),
        'game': gamedataGame,
        'language': gamedataLanguage,
        'entity_id': entityId,
        'entity_name': entityName,
        'entity_type': entityType,
        'document_type': documentType,
        'title': title,
        'summary': cleanSections.first.content.trim(),
        'content': content,
        'source_paths': jsonEncode(sourcePaths),
        'source_record_ids': jsonEncode(sourceRecordIds),
        'updated_at': nowSeconds(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.entityDocuments++;
  }
}

/// Derives a stable record id from content fields (SHA-1 hex, 40 chars).
///
/// The same source data always yields the same id; used for idempotent
/// re-imports and (future) incremental updates. Not a security hash.
String stableContentId(String value) =>
    sha1.convert(utf8.encode(value)).toString();

int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

(String, String) storyScope(String storyId) {
  final parts = storyId.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length >= 2 && parts.first == 'activities') {
    return ('activity', parts[1]);
  }
  if (parts.length >= 2 && parts.first == 'obt') {
    // Group main story, memory, rogue, sandbox, tutorial, ... under
    // `obt:<group>` (e.g. obt/main -> obt:main) instead of lumping them
    // all under obt:obt.
    return ('obt', parts[1]);
  }
  if (parts.isNotEmpty) return (parts.first, parts.first);
  return ('story', storyId);
}

String storyCategory(String storyId) {
  if (storyId.contains('/rogue/') || storyId.contains('/roguelike/')) {
    return 'roguelike';
  }
  if (storyId.contains('/sandbox')) return 'sandbox';
  return 'story';
}

String storySubtype(String storyId) {
  if (storyId.contains('/memory/')) return 'operator_record_story';
  if (storyId.startsWith('activities/')) return 'activity_story';
  if (storyId.contains('/main/')) return 'main_story';
  if (storyId.contains('/rogue/') || storyId.contains('/roguelike/')) {
    if (storyId.contains('/month_chat_')) return 'monthly_squad';
    return 'story';
  }
  if (storyId.contains('/sandbox')) return 'story';
  if (storyId.contains('/guide/') || storyId.contains('/tutorial/')) {
    return 'tutorial_story';
  }
  return 'story';
}

String storyContentType(String storyId) {
  final subtype = storySubtype(storyId);
  if (subtype == 'operator_record_story') return 'operator_record_story';
  if (subtype == 'activity_story') return 'activity_story';
  if (subtype == 'main_story') return 'main_story';
  if (storyCategory(storyId) == 'roguelike') {
    if (subtype == 'monthly_squad') return 'roguelike_monthly_squad';
    return 'roguelike_story';
  }
  if (storyCategory(storyId) == 'sandbox') return 'sandbox_story';
  return subtype;
}

class TextSection {
  const TextSection(this.section, this.content);
  final String section;
  final String content;
}

class NormalizedRecord {
  const NormalizedRecord({
    required this.category,
    required this.subtype,
    required this.contentType,
    required this.content,
    required this.sourcePath,
    this.entityId,
    this.entityName,
    this.parentId,
    this.parentType,
    this.title,
    this.section,
    this.speaker,
    this.rawId,
    this.lineStart,
    this.lineEnd,
    this.entryId,
    this.collectionId,
  });

  /// The entry this record's text belongs to (`entries.id`).
  final String? entryId;

  /// The collection that owns the entry (`collections.id`).
  final String? collectionId;
  final String category;
  final String subtype;
  final String contentType;
  final String? entityId;
  final String? entityName;
  final String? parentId;
  final String? parentType;
  final String? title;
  final String? section;
  final String? speaker;
  final String content;
  final String sourcePath;
  final String? rawId;
  final int? lineStart;
  final int? lineEnd;

  String get id => stableContentId([
        gamedataGame,
        category,
        subtype,
        contentType,
        entityId ?? '',
        rawId ?? '',
        section ?? '',
        content,
      ].join(':'),);
}

/// Build progress counters. Incremented by the importer and used by the CLI
/// and the in-app builder to report row counts and manifest entries.
class BuildStats {
  int entities = 0;
  int storyLines = 0;
  int normalizedRecords = 0;
  int entityRelations = 0;
  int entityDocuments = 0;
  int loreChunks = 0;
  int profileChunks = 0;
  int storyChunks = 0;
  int structuredChunks = 0;

  // Schema v5 entry layer.
  int entries = 0;
  int collections = 0;
  int entryLinks = 0;

  // Schema v3 coverage layer (StoryCoverageBuilder).
  int storyCoverageMentions = 0;
  int storyProfiles = 0;
  int rareTerms = 0;

  Map<String, int> toJson() => {
        'entities': entities,
        'storyLines': storyLines,
        'normalizedRecords': normalizedRecords,
        'entityRelations': entityRelations,
        'entityDocuments': entityDocuments,
        'loreChunks': loreChunks,
        'profileChunks': profileChunks,
        'storyChunks': storyChunks,
        'structuredChunks': structuredChunks,
        'entries': entries,
        'collections': collections,
        'entryLinks': entryLinks,
        'storyCoverageMentions': storyCoverageMentions,
        'storyProfiles': storyProfiles,
        'rareTerms': rareTerms,
      };

  Future<void> refreshFrom(Database db) async {
    entities = firstInt(await db.rawQuery('SELECT COUNT(*) FROM entities'));
    storyLines =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM story_lines'));
    normalizedRecords = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM normalized_records'),
    );
    entityRelations = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM entity_relations'),
    );
    entityDocuments = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM entity_documents'),
    );
    loreChunks =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM lore_chunks'));
    storyChunks = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM lore_chunks WHERE source_type = 'game_story'",
      ),
    );
    profileChunks = firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM lore_chunks WHERE content_category = 'operator'",
      ),
    );
    structuredChunks = loreChunks - storyChunks - profileChunks;
    entries = firstInt(await db.rawQuery('SELECT COUNT(*) FROM entries'));
    collections =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM collections'));
    entryLinks =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM entry_links'));
    storyCoverageMentions = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM entity_story_mentions'),
    );
    storyProfiles = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM story_chapter_profiles'),
    );
    rareTerms =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM rare_terms'));
  }
}

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

