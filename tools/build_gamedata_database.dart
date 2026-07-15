/// Builds ArkLores GameData SQLite database from community unpack repositories.
///
/// Initial scope: Chinese Arknights data from Kengxxiao/ArknightsGameData.
///
/// Usage:
///   dart run tools/build_gamedata_database.dart \
///     --arknights-source=/path/to/ArknightsGameData \
///     --output=build/gamedata \
///     --force
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _schemaVersion = 2;
const _language = 'zh';
const _game = 'arknights';

const _textKeys = {
  'name',
  'description',
  'desc',
  'usage',
  'storyText',
  'voiceText',
  'voiceTitle',
  'title',
  'subtitle',
  'content',
  'text',
  'itemDesc',
  'itemUsage',
  'teamDes',
  'teamFlavorDesc',
  'endingDescription',
  'changeEndingDesc',
  'eliteDesc',
  'taskDes',
  'unlockCondDesc',
  'obtainApproach',
  'lineText',
  'getMethod',
  'dangerLevel',
  'displayDesc',
  'displayName',
  'zoneNameFirst',
  'zoneNameSecond',
  'textDesc',
  'storyName',
  'storyTitle',
  'storyIntro',
  'storySetName',
  'groupName',
  'groupDesc',
  'skinName',
  'skinGroupName',
  'brandName',
  'dialog',
  'medalName',
  'uniEquipName',
  'uniEquipDesc',
  'specialEquipDesc',
  'subProfessionName',
  'topicName',
  'itemName',
  'buffName',
  'buffEffectDesc',
};

void main(List<String> args) async {
  sqfliteFfiInit();
  final cfg = _Config.parse(args);

  final out = Directory(p.absolute(cfg.outputDir));
  if (await out.exists()) {
    if (!cfg.force) {
      stderr.writeln(
        'Output directory exists. Use --force to rebuild: ${cfg.outputDir}',
      );
      exit(1);
    }
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);

  final dbPath = p.join(out.path, 'arklores_gamedata_zh.db');
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  final stats = _BuildStats();

  try {
    await _createSchema(db);
    await _writeManifest(
      db,
      {
        'schema_version': '$_schemaVersion',
        'language': _language,
        'source_arknights_repo':
            'https://github.com/Kengxxiao/ArknightsGameData',
        'source_arknights_branch': 'master',
        'source_arknights_commit': await _gitCommit(cfg.arknightsSource),
        'built_at': DateTime.now().toUtc().toIso8601String(),
      },
    );

    final importer = _ArknightsImporter(
      sourceDir: Directory(cfg.arknightsSource),
      db: db,
      stats: stats,
      storyLimit: cfg.storyLimit,
    );
    await importer.importAll();

    await db.execute(
        "INSERT INTO entity_documents_fts(entity_documents_fts) VALUES('rebuild')");
    await db.execute(
        "INSERT INTO lore_chunks_fts(lore_chunks_fts) VALUES('rebuild')");
    await stats.refreshFrom(db);
    await _writeManifest(
      db,
      {
        'entity_count': '${stats.entities}',
        'story_line_count': '${stats.storyLines}',
        'normalized_record_count': '${stats.normalizedRecords}',
        'entity_document_count': '${stats.entityDocuments}',
        'lore_chunk_count': '${stats.loreChunks}',
        'arknights_profile_chunk_count': '${stats.profileChunks}',
        'arknights_story_chunk_count': '${stats.storyChunks}',
        'arknights_structured_chunk_count': '${stats.structuredChunks}',
      },
    );
  } finally {
    await db.close();
  }

  final manifest = {
    'schemaVersion': _schemaVersion,
    'language': _language,
    'database': {
      'fileName': 'arklores_gamedata_zh.db.gz',
      'uncompressedFileName': 'arklores_gamedata_zh.db',
      'delivery': 'release-asset',
    },
    'sources': {
      'arknights': {
        'repo': 'https://github.com/Kengxxiao/ArknightsGameData',
        'branch': 'master',
        'commit': await _gitCommit(cfg.arknightsSource),
        'languagePath': 'zh_CN',
      },
    },
    'counts': stats.toJson(),
  };
  await File(p.join(out.path, 'gamedata_manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  await File(p.join(out.path, 'gamedata_build_report.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'status': 'ok',
      'database': dbPath,
      'counts': stats.toJson(),
    }),
    flush: true,
  );

  stdout.writeln('GameData DB built: $dbPath');
  stdout.writeln('Entities: ${stats.entities}');
  stdout.writeln('Entity documents: ${stats.entityDocuments}');
  stdout.writeln('Story lines: ${stats.storyLines}');
  stdout.writeln('Lore chunks: ${stats.loreChunks}');
}

Future<void> _createSchema(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE gamedata_manifest (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE entities (
      id           TEXT PRIMARY KEY,
      name         TEXT NOT NULL,
      aliases      TEXT,
      entity_type  TEXT NOT NULL,
      source_type  TEXT NOT NULL,
      game         TEXT NOT NULL,
      source_path  TEXT,
      game_version TEXT,
      updated_at   INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE entity_aliases (
      alias       TEXT NOT NULL,
      entity_id   TEXT NOT NULL,
      alias_type  TEXT NOT NULL,
      confidence  REAL NOT NULL DEFAULT 1.0,
      source_path TEXT,
      PRIMARY KEY (alias, entity_id, alias_type),
      FOREIGN KEY (entity_id) REFERENCES entities(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE story_lines (
      id          TEXT PRIMARY KEY,
      game        TEXT NOT NULL,
      story_id    TEXT NOT NULL,
      episode_id  TEXT,
      event_id    TEXT,
      speaker     TEXT,
      content     TEXT NOT NULL,
      line_index  INTEGER,
      language    TEXT NOT NULL DEFAULT 'zh',
      source_path TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE normalized_records (
      id               TEXT PRIMARY KEY,
      game             TEXT NOT NULL,
      language         TEXT NOT NULL DEFAULT 'zh',
      category         TEXT NOT NULL,
      subtype          TEXT NOT NULL,
      content_type     TEXT NOT NULL,
      entity_id        TEXT,
      entity_name      TEXT,
      parent_id        TEXT,
      parent_type      TEXT,
      title            TEXT,
      section          TEXT,
      speaker          TEXT,
      content          TEXT NOT NULL,
      source_path      TEXT NOT NULL,
      raw_id           TEXT,
      line_start       INTEGER,
      line_end         INTEGER,
      source_repo      TEXT,
      source_commit    TEXT,
      game_version     TEXT,
      updated_at       INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE entity_relations (
      id               TEXT PRIMARY KEY,
      source_entity_id TEXT NOT NULL,
      target_entity_id TEXT NOT NULL,
      relation_type    TEXT NOT NULL,
      source_path      TEXT,
      raw_id           TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE entity_documents (
      id                TEXT PRIMARY KEY,
      game              TEXT NOT NULL,
      language          TEXT NOT NULL DEFAULT 'zh',
      entity_id         TEXT NOT NULL,
      entity_name       TEXT NOT NULL,
      entity_type       TEXT NOT NULL,
      document_type     TEXT NOT NULL,
      title             TEXT NOT NULL,
      summary           TEXT,
      content           TEXT NOT NULL,
      source_paths      TEXT,
      source_record_ids TEXT,
      updated_at        INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE story_scopes (
      story_id    TEXT PRIMARY KEY,
      scope_type  TEXT NOT NULL,
      scope_id    TEXT NOT NULL,
      source_path TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE lore_chunks (
      id             TEXT PRIMARY KEY,
      game           TEXT NOT NULL,
      source_type    TEXT NOT NULL,
      content_category TEXT,
      content_subtype  TEXT,
      content_type     TEXT,
      entity_id      TEXT,
      story_id       TEXT,
      scope_type     TEXT,
      scope_id       TEXT,
      page_title     TEXT,
      section        TEXT,
      content        TEXT NOT NULL,
      source_path    TEXT,
      source_url     TEXT,
      line_start     INTEGER,
      line_end       INTEGER,
      speaker        TEXT,
      language       TEXT NOT NULL DEFAULT 'zh',
      game_version   TEXT,
      updated_at     INTEGER,
      raw_id         TEXT,
      retrieval_hint TEXT
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE entity_documents_fts USING fts5(
      entity_name,
      entity_type,
      document_type,
      title,
      summary,
      content,
      content='entity_documents',
      content_rowid='rowid',
      tokenize='trigram'
    )
  ''');
  await db.execute('''
    CREATE VIRTUAL TABLE lore_chunks_fts USING fts5(
      page_title,
      section,
      speaker,
      content,
      content='lore_chunks',
      content_rowid='rowid'
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_entities_name ON entities(name)',
  );
  await db.execute(
    'CREATE INDEX idx_normalized_records_type ON normalized_records(content_type)',
  );
  await db.execute(
    'CREATE INDEX idx_normalized_records_entity ON normalized_records(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_source_type ON lore_chunks(source_type)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_content_type ON lore_chunks(content_type)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_entity_id ON lore_chunks(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_scope ON lore_chunks(scope_type, scope_id)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_aliases_alias ON entity_aliases(alias)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_aliases_entity ON entity_aliases(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_documents_entity ON entity_documents(entity_id)',
  );
  await db.execute(
    'CREATE INDEX idx_entity_documents_type ON entity_documents(document_type)',
  );
}

Future<void> _writeManifest(Database db, Map<String, String> values) async {
  for (final entry in values.entries) {
    await db.insert(
      'gamedata_manifest',
      {'key': entry.key, 'value': entry.value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

Future<String> _gitCommit(String path) async {
  final result = await Process.run(
    'git',
    ['-C', path, 'rev-parse', 'HEAD'],
  );
  if (result.exitCode != 0) return 'unknown';
  return (result.stdout as String).trim();
}

class _ArknightsImporter {
  final Directory sourceDir;
  final Database db;
  final _BuildStats stats;
  final int storyLimit;
  final Chunker _chunker = const Chunker();

  _ArknightsImporter({
    required this.sourceDir,
    required this.db,
    required this.stats,
    required this.storyLimit,
  });

  Future<void> importAll() async {
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    if (!await zh.exists()) {
      throw StateError('Missing zh_CN directory: ${zh.path}');
    }
    await _importCharacterProfiles(zh);
    await _importCharacterVoices(zh);
    await _importStructuredTextTables(zh);
    await _importStories(zh);
  }

  Future<void> _importCharacterProfiles(Directory zh) async {
    final characterTable = await _readJsonMap(
      p.join(zh.path, 'gamedata', 'excel', 'character_table.json'),
    );
    final handbookInfo = await _readJsonMap(
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
        final documentSections = <_TextSection>[];

        await txn.insert(
          'entities',
          {
            'id': charId,
            'name': name,
            'aliases': jsonEncode(aliases),
            'entity_type': 'operator',
            'source_type': 'operator_profile',
            'game': 'arknights',
            'source_path': sourcePath,
            'updated_at': _nowSeconds(),
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
          documentSections.add(_TextSection('基础信息', basicProfile));
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
                documentSections.add(_TextSection(section, text));
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
      }
    });
  }

  Future<void> _importCharacterVoices(Directory zh) async {
    final sourcePath = 'zh_CN/gamedata/excel/charword_table.json';
    final table = await _readJsonMap(p.join(sourceDir.path, sourcePath));
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
        final record = _NormalizedRecord(
          category: 'operator',
          subtype: 'voice',
          contentType: 'operator_voice',
          entityId: charId.isEmpty ? null : charId,
          title: title,
          section: title,
          content: text,
          sourcePath: sourcePath,
          rawId: '${data['charWordId'] ?? entry.key}',
        );
        await _insertRecord(txn, record);
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

  Future<void> _importStructuredTextTables(Directory zh) async {
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/item_table.json',
      roots: const ['items', 'expItems', 'potentialItems', 'apSupplies'],
      category: 'world_item',
      subtype: 'item',
      contentType: 'item_description',
      entityType: 'item',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/skin_table.json',
      roots: const ['charSkins', 'brandList'],
      category: 'world_item',
      subtype: 'skin',
      contentType: 'skin_description',
      entityType: 'skin',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/medal_table.json',
      roots: const ['medalList', 'medalTypeData'],
      category: 'world_item',
      subtype: 'medal',
      contentType: 'medal_description',
      entityType: 'medal',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/uniequip_table.json',
      roots: const ['equipDict'],
      category: 'operator',
      subtype: 'module',
      contentType: 'operator_module',
      entityType: 'operator_module',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/enemy_handbook_table.json',
      roots: const ['enemyData', 'raceData'],
      category: 'enemy',
      subtype: 'profile',
      contentType: 'enemy_profile',
      entityType: 'enemy',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/stage_table.json',
      roots: const ['stages'],
      category: 'stage',
      subtype: 'stage',
      contentType: 'stage_description',
      entityType: 'stage',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/zone_table.json',
      roots: const ['zones', 'zoneMetaData'],
      category: 'stage',
      subtype: 'zone',
      contentType: 'zone_description',
      entityType: 'zone',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/campaign_table.json',
      roots: const ['campaigns', 'campaignGroups', 'campaignZones'],
      category: 'stage',
      subtype: 'campaign',
      contentType: 'campaign_description',
      entityType: 'campaign',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/activity_table.json',
      roots: const ['basicInfo', 'activity', 'missionData', 'missionGroup'],
      category: 'activity',
      subtype: 'basic_info',
      contentType: 'activity_basic_info',
      entityType: 'activity',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/retro_table.json',
      roots: const ['retroActList', 'retroTrailList', 'ruleData'],
      category: 'activity',
      subtype: 'archive',
      contentType: 'activity_archive',
      entityType: 'activity_archive',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/mission_table.json',
      roots: const ['missions', 'missionGroups'],
      category: 'activity',
      subtype: 'mission',
      contentType: 'activity_mission',
      entityType: 'mission',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/roguelike_table.json',
      roots: const ['itemTable', 'stages', 'zones', 'choices', 'endings'],
      category: 'roguelike',
      subtype: 'mechanic',
      contentType: 'roguelike_mechanic',
      entityType: 'roguelike',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/roguelike_topic_table.json',
      roots: const ['topics', 'details', 'modules'],
      category: 'roguelike',
      subtype: 'topic',
      contentType: 'roguelike_topic',
      entityType: 'roguelike_topic',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/sandbox_table.json',
      roots: const ['sandboxActTables', 'itemDatas'],
      category: 'sandbox',
      subtype: 'mechanic',
      contentType: 'sandbox_mechanic',
      entityType: 'sandbox',
    );
    await _importJsonCollection(
      zh,
      sourcePath: 'zh_CN/gamedata/excel/sandbox_perm_table.json',
      roots: const ['basicInfo', 'detail', 'itemData'],
      category: 'sandbox',
      subtype: 'item',
      contentType: 'sandbox_item',
      entityType: 'sandbox_item',
    );
  }

  Future<void> _importJsonCollection(
    Directory zh, {
    required String sourcePath,
    required List<String> roots,
    required String category,
    required String subtype,
    required String contentType,
    required String entityType,
  }) async {
    final table = await _readJsonMap(p.join(sourceDir.path, sourcePath));
    await db.transaction((txn) async {
      for (final root in roots) {
        final node = table[root];
        await _walkStructuredEntries(
          txn,
          node,
          sourcePath: sourcePath,
          root: root,
          category: category,
          subtype: subtype,
          contentType: contentType,
          entityType: entityType,
        );
      }
    });
  }

  Future<void> _walkStructuredEntries(
    Transaction txn,
    Object? node, {
    required String sourcePath,
    required String root,
    required String category,
    required String subtype,
    required String contentType,
    required String entityType,
    String? inheritedId,
  }) async {
    if (node is Map) {
      final data = node.cast<String, dynamic>();
      final rawId = _rawIdFromMap(data) ?? inheritedId;
      final texts = _collectTextSections(data);
      if (rawId != null && texts.isNotEmpty) {
        final title = _titleFromMap(data) ?? rawId;
        await _upsertEntity(
          txn,
          id: '$entityType:$rawId',
          name: title,
          entityType: entityType,
          sourceType: contentType,
          sourcePath: sourcePath,
        );
        for (final text in texts) {
          await _insertRecord(
            txn,
            _NormalizedRecord(
              category: category,
              subtype: subtype,
              contentType: contentType,
              entityId: '$entityType:$rawId',
              entityName: title,
              parentId: _parentIdFromMap(data),
              parentType: category,
              title: title,
              section: text.section,
              content: text.content,
              sourcePath: sourcePath,
              rawId: rawId,
            ),
          );
        }
        return;
      }
      for (final entry in data.entries) {
        await _walkStructuredEntries(
          txn,
          entry.value,
          sourcePath: sourcePath,
          root: root,
          category: category,
          subtype: subtype,
          contentType: contentType,
          entityType: entityType,
          inheritedId: entry.key,
        );
      }
      return;
    }

    if (node is List) {
      for (var i = 0; i < node.length; i++) {
        await _walkStructuredEntries(
          txn,
          node[i],
          sourcePath: sourcePath,
          root: root,
          category: category,
          subtype: subtype,
          contentType: contentType,
          entityType: entityType,
          inheritedId: '$root:$i',
        );
      }
    }
  }

  Future<void> _importStories(Directory zh) async {
    final storyRoot = Directory(p.join(zh.path, 'gamedata', 'story'));
    if (!await storyRoot.exists()) return;

    final files = await storyRoot
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.txt'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    final selected = storyLimit > 0 ? files.take(storyLimit).toList() : files;
    for (final file in selected) {
      await _importStoryFile(zh, file);
    }
  }

  Future<void> _importStoryFile(Directory zh, File file) async {
    final relativePath = p.relative(file.path, from: sourceDir.path);
    final storyId = p
        .relative(file.path, from: p.join(zh.path, 'gamedata', 'story'))
        .replaceAll(p.separator, '/');
    final raw = await file.readAsString();
    final lines = _parseStoryLines(raw);
    if (lines.isEmpty) return;
    final scope = _storyScope(storyId);

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
            'id': _stableId('arknights:story_line:$storyId:$i'),
            'game': 'arknights',
            'story_id': storyId,
            'event_id': scope.$1 == 'activity' ? scope.$2 : null,
            'speaker': line.speaker,
            'content': line.content,
            'line_index': i,
            'language': _language,
            'source_path': relativePath,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stats.storyLines++;
      }

      final text = lines
          .map((line) => line.speaker == null
              ? line.content
              : '${line.speaker}: ${line.content}')
          .join('\n');
      final chunks = _chunker.chunkBySliding(text, pageTitle: storyId);
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        final chunk = chunks[chunkIndex];
        await _insertRecord(
          txn,
          _NormalizedRecord(
            category: _storyCategory(storyId),
            subtype: _storySubtype(storyId),
            contentType: _storyContentType(storyId),
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
          ),
        );
      }
    });
  }

  List<_StoryLine> _parseStoryLines(String raw) {
    final lines = <_StoryLine>[];
    final speakerPattern = RegExp(r'^\[name="([^"]+)"\](.*)$');

    for (final original in raw.split('\n')) {
      final line = original.trim();
      if (line.isEmpty) continue;

      final speakerMatch = speakerPattern.firstMatch(line);
      if (speakerMatch != null) {
        final content = _cleanStoryText(speakerMatch.group(2) ?? '');
        if (content.isNotEmpty) {
          lines.add(_StoryLine(speakerMatch.group(1), content));
        }
        continue;
      }

      if (line.startsWith('[')) continue;
      final content = _cleanStoryText(line);
      if (content.isNotEmpty) {
        lines.add(_StoryLine(null, content));
      }
    }
    return lines;
  }

  String _cleanStoryText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<Map<String, dynamic>> _readJsonMap(String path) async {
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
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    final sourceType = category == 'story' || contentType.endsWith('_story')
        ? 'game_story'
        : 'game_data';
    final scope = storyId == null ? null : _storyScope(storyId);
    final id = _stableId([
      'arknights',
      contentType,
      entityId ?? '',
      storyId ?? '',
      rawId ?? '',
      pageTitle,
      section,
      clean,
    ].join(':'));
    await txn.insert(
      'lore_chunks',
      {
        'id': id,
        'game': _game,
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
        'language': _language,
        'updated_at': _nowSeconds(),
        'raw_id': rawId,
        'retrieval_hint': retrievalHint,
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

  Future<void> _insertRecord(
    Transaction txn,
    _NormalizedRecord record,
  ) async {
    final clean = record.content.trim();
    if (clean.isEmpty) return;
    await txn.insert(
      'normalized_records',
      {
        'id': record.id,
        'game': _game,
        'language': _language,
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
        'source_repo': 'https://github.com/Kengxxiao/ArknightsGameData',
        'source_commit': null,
        'updated_at': _nowSeconds(),
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
    );
  }

  Future<void> _upsertEntity(
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
        'game': _game,
        'source_path': sourcePath,
        'updated_at': _nowSeconds(),
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
        'id': _stableId([
          sourceEntityId,
          targetEntityId,
          relationType,
          rawId ?? '',
        ].join(':')),
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
    required List<_TextSection> sections,
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
        'id': _stableId('$_game:$documentType:$entityId'),
        'game': _game,
        'language': _language,
        'entity_id': entityId,
        'entity_name': entityName,
        'entity_type': entityType,
        'document_type': documentType,
        'title': title,
        'summary': cleanSections.first.content.trim(),
        'content': content,
        'source_paths': jsonEncode(sourcePaths),
        'source_record_ids': jsonEncode(sourceRecordIds),
        'updated_at': _nowSeconds(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.entityDocuments++;
  }
}

(String, String) _storyScope(String storyId) {
  final parts = storyId.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length >= 2 && parts.first == 'activities') {
    return ('activity', parts[1]);
  }
  if (parts.isNotEmpty) return (parts.first, parts.first);
  return ('story', storyId);
}

class _StoryLine {
  final String? speaker;
  final String content;

  const _StoryLine(this.speaker, this.content);
}

class _TextSection {
  final String section;
  final String content;

  const _TextSection(this.section, this.content);
}

class _NormalizedRecord {
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

  const _NormalizedRecord({
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
  });

  String get id => _stableId([
        _game,
        category,
        subtype,
        contentType,
        entityId ?? '',
        rawId ?? '',
        section ?? '',
        content,
      ].join(':'));
}

List<_TextSection> _collectTextSections(Map<String, dynamic> data) {
  final sections = <_TextSection>[];

  void visit(Object? value, String path) {
    if (value is String) {
      final key = path.split('.').last;
      final text = value.trim();
      if (_textKeys.contains(key) && _containsChinese(text)) {
        sections.add(_TextSection(key, _cleanStructuredText(text)));
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        visit(value[i], '$path.$i');
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        visit(
            entry.value, path.isEmpty ? '${entry.key}' : '$path.${entry.key}');
      }
    }
  }

  visit(data, '');
  final seen = <String>{};
  return [
    for (final section in sections)
      if (section.content.isNotEmpty &&
          seen.add('${section.section}\n${section.content}'))
        section,
  ];
}

String? _rawIdFromMap(Map<String, dynamic> data) {
  const keys = [
    'id',
    'charId',
    'charWordId',
    'itemId',
    'enemyId',
    'raceId',
    'stageId',
    'zoneId',
    'campaignId',
    'activityId',
    'missionId',
    'topicId',
    'medalId',
    'skinId',
    'uniEquipId',
  ];
  for (final key in keys) {
    final value = '${data[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? _titleFromMap(Map<String, dynamic> data) {
  const keys = [
    'name',
    'appellation',
    'title',
    'voiceTitle',
    'itemName',
    'medalName',
    'skinName',
    'uniEquipName',
    'topicName',
    'zoneNameFirst',
    'zoneNameSecond',
    'displayName',
    'storyName',
    'groupName',
  ];
  for (final key in keys) {
    final value = '${data[key] ?? ''}'.trim();
    if (_containsChinese(value)) return _cleanStructuredText(value);
  }
  return null;
}

String? _parentIdFromMap(Map<String, dynamic> data) {
  const keys = [
    'activityId',
    'actId',
    'topicId',
    'zoneId',
    'stageId',
    'charId',
  ];
  final rawId = _rawIdFromMap(data);
  for (final key in keys) {
    final value = '${data[key] ?? ''}'.trim();
    if (value.isNotEmpty && value != rawId) return value;
  }
  return null;
}

bool _containsChinese(String text) =>
    text.runes.any((rune) => rune >= 0x4e00 && rune <= 0x9fff);

String _cleanStructuredText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(r'\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

String _storyCategory(String storyId) {
  if (storyId.contains('/rogue/') || storyId.contains('/roguelike/')) {
    return 'roguelike';
  }
  if (storyId.contains('/sandbox')) return 'sandbox';
  return 'story';
}

String _storySubtype(String storyId) {
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

String _storyContentType(String storyId) {
  final subtype = _storySubtype(storyId);
  if (subtype == 'operator_record_story') return 'operator_record_story';
  if (subtype == 'activity_story') return 'activity_story';
  if (subtype == 'main_story') return 'main_story';
  if (_storyCategory(storyId) == 'roguelike') {
    if (subtype == 'monthly_squad') return 'roguelike_monthly_squad';
    return 'roguelike_story';
  }
  if (_storyCategory(storyId) == 'sandbox') return 'sandbox_story';
  return subtype;
}

class _BuildStats {
  int entities = 0;
  int storyLines = 0;
  int normalizedRecords = 0;
  int entityRelations = 0;
  int entityDocuments = 0;
  int loreChunks = 0;
  int profileChunks = 0;
  int storyChunks = 0;
  int structuredChunks = 0;

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
      };

  Future<void> refreshFrom(Database db) async {
    entities = _firstInt(await db.rawQuery('SELECT COUNT(*) FROM entities'));
    storyLines =
        _firstInt(await db.rawQuery('SELECT COUNT(*) FROM story_lines'));
    normalizedRecords = _firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM normalized_records'),
    );
    entityRelations = _firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM entity_relations'),
    );
    entityDocuments = _firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM entity_documents'),
    );
    loreChunks =
        _firstInt(await db.rawQuery('SELECT COUNT(*) FROM lore_chunks'));
    storyChunks = _firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM lore_chunks WHERE source_type = 'game_story'",
      ),
    );
    profileChunks = _firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM lore_chunks WHERE content_category = 'operator'",
      ),
    );
    structuredChunks = loreChunks - storyChunks - profileChunks;
  }
}

int _firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

class _Config {
  final String arknightsSource;
  final String outputDir;
  final bool force;
  final int storyLimit;

  const _Config({
    required this.arknightsSource,
    required this.outputDir,
    required this.force,
    required this.storyLimit,
  });

  static _Config parse(List<String> args) {
    String? arknightsSource;
    var outputDir = 'build/gamedata';
    var force = false;
    var storyLimit = 0;

    for (final arg in args) {
      if (arg.startsWith('--arknights-source=')) {
        arknightsSource = arg.substring('--arknights-source='.length);
      } else if (arg.startsWith('--output=')) {
        outputDir = arg.substring('--output='.length);
      } else if (arg == '--force') {
        force = true;
      } else if (arg.startsWith('--story-limit=')) {
        storyLimit = int.parse(arg.substring('--story-limit='.length));
      } else if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      } else {
        stderr.writeln('Unknown argument: $arg');
        _printUsageAndExit(exitCode: 1);
      }
    }

    if (arknightsSource == null || arknightsSource.trim().isEmpty) {
      stderr.writeln('Missing --arknights-source');
      _printUsageAndExit(exitCode: 1);
    }

    return _Config(
      arknightsSource: arknightsSource,
      outputDir: outputDir,
      force: force,
      storyLimit: storyLimit,
    );
  }

  static Never _printUsageAndExit({int exitCode = 0}) {
    stdout.writeln('''
Usage:
  dart run tools/build_gamedata_database.dart \\
    --arknights-source=/path/to/ArknightsGameData \\
    --output=build/gamedata \\
    --force

Options:
  --story-limit=N  Import only N story txt files for smoke tests.
''');
    exit(exitCode);
  }
}

String _stableId(String value) => sha1.convert(utf8.encode(value)).toString();

int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
