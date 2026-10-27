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
import 'package:arklores/core/gamedata/build/text_harvest.dart' show cleanRichText;
import 'package:arklores/core/gamedata/story_vectors.dart' show storyChunkVectorsTable;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import 'portrait_index.dart';
import 'story_art_index.dart';

/// Removes everything a story file wrote: its lines, scope and vectors. [path] is the repo-relative path
/// (`zh_CN/gamedata/story/<story id>`). The entry layer is rebuilt separately
/// (`EntryImporter.rebuildDerived`).
Future<void> deleteStoryRows(Database db, String path) async {
  final storyId = path.substring('zh_CN/gamedata/story/'.length);
  await deletePortraitRows(db, storyId);
  await deleteStoryArtRows(db, storyId);
  // Databases built on Windows hold the backslash spelling of the path.
  final paths = {path, path.replaceAll('/', r'\')}.toList();
  final marks = List.filled(paths.length, '?').join(',');
  await db.delete('story_scopes', where: 'story_id = ?', whereArgs: [storyId]);
  await db.delete('story_lines', where: 'story_id = ?', whereArgs: [storyId]);
  await db.delete(
    'normalized_records',
    where: 'source_path IN ($marks) OR (parent_type = ? AND parent_id = ?)',
    whereArgs: [...paths, 'story_file', storyId],
  );
  // Optional vectors (R12) of a changed story point at the old line numbers;
  // drop them so semantic recall never hints at stale ranges. Other stories
  // keep their vectors (the in-app build cannot embed).
  final hasVectors = (await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [storyChunkVectorsTable],
  ))
      .isNotEmpty;
  if (hasVectors) {
    await db.delete(
      storyChunkVectorsTable,
      where: 'story_id = ?',
      whereArgs: [storyId],
    );
  }
}
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

  /// Parses every story file of the source again and re-imports the ones
  /// whose lines differ from what the database holds (after a change to the
  /// script parser). Returns the repo-relative paths that changed. The
  /// coverage layer and the entry layer need rebuilding afterwards.
  Future<List<String>> reimportChangedStories({
    void Function(int done, int total)? onProgress,
  }) async {
    final storyRoot = Directory(
      p.join(sourceDir.path, 'zh_CN', 'gamedata', 'story'),
    );
    if (!await storyRoot.exists()) return const [];
    final files = <File>[
      await for (final e in storyRoot.list(recursive: true))
        if (e is File &&
            e.path.endsWith('.txt') &&
            !p
                .relative(e.path, from: storyRoot.path)
                .startsWith('[uc]info${p.separator}'))
          e,
    ]..sort((a, b) => a.path.compareTo(b.path));
    // A signature of the stored lines of every story.
    final stored = <String, String>{};
    String? current;
    var bytes = <int>[];
    void flush() {
      final id = current;
      if (id != null) stored[id] = sha1.convert(bytes).toString();
      bytes = <int>[];
    }

    for (final r in await db.rawQuery(
      'SELECT story_id, kind, speaker, content FROM story_lines '
      'ORDER BY story_id, line_index',
    )) {
      final id = '${r['story_id']}';
      if (id != current) {
        flush();
        current = id;
      }
      bytes.addAll(
        utf8.encode('${r['kind']}|${r['speaker']}|${r['content']}\n'),
      );
    }
    flush();

    final changed = <String>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final storyId = p
          .relative(file.path, from: storyRoot.path)
          .replaceAll(p.separator, '/');
      final parsed = parseStoryScript(await file.readAsString());
      final signature = parsed.isEmpty
          ? null
          : sha1
              .convert(
                utf8.encode(
                  [
                    for (final l in parsed)
                      '${l.kind.value}|${l.speaker}|${l.content}\n',
                  ].join(),
                ),
              )
              .toString();
      if (signature != stored[storyId]) {
        final relative = p
            .relative(file.path, from: sourceDir.path)
            .replaceAll(p.separator, '/');
        await deleteStoryRows(db, relative);
        await _importStoryFile(file, relative);
        changed.add(relative);
      }
      onProgress?.call(i + 1, files.length);
    }
    return changed;
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
        await _linkCharacterRefs(txn, charId, data, sourcePath);

        // Cleaned like every table text: markup off, the table's literal
        // `\n` a line break.
        final basicProfile = [
          for (final field in ['description', 'itemUsage', 'itemDesc'])
            if (cleanRichText('${data[field] ?? ''}').isNotEmpty)
              cleanRichText('${data[field]}'),
        ].join('\n').trim();
        if (basicProfile.isNotEmpty) {
          documentSections.add(TextSection('基础信息', basicProfile));
        }

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
      await _linkSamePerson(txn);
    });
  }

  /// Operators that are one person (the table's `spCharGroups`: the first of
  /// a group is the original, the others its alternate versions). Each
  /// alternate points at the original with `same_person`. The tables do not
  /// say whether an alternate is a later stage of the same story or a
  /// what-if; that is for the archives to say.
  Future<void> _linkSamePerson(Transaction txn) async {
    const path = 'zh_CN/gamedata/excel/char_meta_table.json';
    if (!File(p.join(sourceDir.path, path)).existsSync()) return;
    final meta = await readJsonMap(p.join(sourceDir.path, path));
    final groups = meta['spCharGroups'];
    if (groups is! Map) return;
    for (final group in groups.entries) {
      final members = group.value;
      if (members is! List) continue;
      for (final member in members) {
        if ('$member' == '${group.key}') continue;
        await insertLink(
          txn,
          src: 'operator:$member',
          relation: 'same_person',
          dst: 'operator:${group.key}',
          sourcePath: path,
        );
      }
    }
  }

  /// What a character's own row names: the summons and devices it deploys
  /// (`displayTokenDict`, `overrideTokenKey` of its skills: `summoned_by`, from
  /// the summon to the character) and its potential items (the token of the
  /// operator, the folder an activity gives it: `belongs_to`). Ends that are
  /// not entries are dropped when the entry layer is derived.
  Future<void> _linkCharacterRefs(
    Transaction txn,
    String charId,
    Map<String, dynamic> data,
    String sourcePath,
  ) async {
    final profession = '${data['profession'] ?? ''}'.toUpperCase();
    if (profession != 'TOKEN' && profession != 'TRAP') {
      final summons = <String>{
        if (data['displayTokenDict'] is Map)
          for (final k in (data['displayTokenDict'] as Map).keys) '$k',
        for (final s in (data['skills'] as List? ?? const []))
          if (s is Map && '${s['overrideTokenKey'] ?? ''}'.isNotEmpty)
            '${s['overrideTokenKey']}',
      };
      for (final token in summons) {
        await insertLink(
          txn,
          src: 'operator:$token',
          relation: 'summoned_by',
          dst: 'operator:$charId',
          sourcePath: sourcePath,
        );
      }
    }
    for (final key in const [
      'potentialItemId',
      'activityPotentialItemId',
      'classicPotentialItemId',
    ]) {
      final item = '${data[key] ?? ''}'.trim();
      if (item.isEmpty || item == 'null') continue;
      await insertLink(
        txn,
        src: 'item:$item',
        relation: 'belongs_to',
        dst: 'operator:$charId',
        sourcePath: sourcePath,
      );
    }
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
          contentType: operatorVoiceContentType,
          entityId: charId.isEmpty ? null : charId,
          title: title,
          section: title,
          content: text,
          sourcePath: sourcePath,
          rawId: '${data['charWordId'] ?? entry.key}',
          entryId: charId.isEmpty ? null : 'operator:$charId',
        );
        await insertRecord(txn, record);
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
    final parsed = parseStoryScriptWithArt(raw);
    final lines = parsed.lines;
    if (lines.isEmpty) return;
    final scope = storyScope(storyId);

    await db.transaction((txn) async {
      await ensurePortraitTables(txn);
      await ensureStoryArtTable(txn);
      await deleteStoryArtRows(txn, storyId);
      await writeStoryArtRows(txn, storyId, parsed.art);
      await deletePortraitRows(txn, storyId);
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
        if (line.portrait != null) {
          await txn.insert(storyLinePortraitsTable, {
            'story_id': storyId, 'line_index': i, 'sprite': line.portrait,
          });
        }
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

  /// Inserts one citable record.
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

/// `content_type` of an operator's voice line. The voice table gives the
/// operator's id only; the name is filled in from the table of names
/// (`EntryImporter.rebuildDerived`).
const String operatorVoiceContentType = 'operator_voice';

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
  int entityDocuments = 0;

  // Schema v5 entry layer.
  int entries = 0;
  int collections = 0;
  int entryLinks = 0;

  Map<String, int> toJson() => {
        'entities': entities,
        'storyLines': storyLines,
        'normalizedRecords': normalizedRecords,
        'entityDocuments': entityDocuments,
        'entries': entries,
        'collections': collections,
        'entryLinks': entryLinks,
      };

  Future<void> refreshFrom(Database db) async {
    entities = firstInt(await db.rawQuery('SELECT COUNT(*) FROM entities'));
    storyLines =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM story_lines'));
    normalizedRecords = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM normalized_records'),
    );
    entityDocuments = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM entity_documents'),
    );
    entries = firstInt(await db.rawQuery('SELECT COUNT(*) FROM entries'));
    collections =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM collections'));
    entryLinks =
        firstInt(await db.rawQuery('SELECT COUNT(*) FROM entry_links'));
  }
}

int firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

