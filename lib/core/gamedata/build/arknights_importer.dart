/// Arknights GameData importer shared by the desktop CLI builder and the
/// in-app builder (R0: extracted from `tools/build_gamedata_database.dart`).
///
/// Reads `zh_CN/gamedata` from Kengxxiao/ArknightsGameData and writes the
/// schema 2 tables through a `sqflite`-compatible [Database]. The four import
/// stages have no data dependencies between them, so callers may reorder or
/// run them in isolation for incremental updates.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/rag/chunker.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

/// Whitelisted JSON text keys collected by the structured importer.
const _textKeys = {  'name',
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

/// Import spec of one whitelisted structured excel table.
class _StructuredTableSpec {
  const _StructuredTableSpec({
    required this.sourcePath,
    required this.roots,
    required this.category,
    required this.subtype,
    required this.contentType,
    required this.entityType,
  });
  final String sourcePath;
  final List<String> roots;
  final String category;
  final String subtype;
  final String contentType;
  final String entityType;
}

/// The 15 structured excel tables imported by the importer (order matters for
/// progress reporting only; stages are independent).
const List<_StructuredTableSpec> _structuredTableSpecs = [
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/item_table.json',
    roots: ['items', 'expItems', 'potentialItems', 'apSupplies'],
    category: 'world_item',
    subtype: 'item',
    contentType: 'item_description',
    entityType: 'item',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/skin_table.json',
    roots: ['charSkins', 'brandList'],
    category: 'world_item',
    subtype: 'skin',
    contentType: 'skin_description',
    entityType: 'skin',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/medal_table.json',
    roots: ['medalList', 'medalTypeData'],
    category: 'world_item',
    subtype: 'medal',
    contentType: 'medal_description',
    entityType: 'medal',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/uniequip_table.json',
    roots: ['equipDict'],
    category: 'operator',
    subtype: 'module',
    contentType: 'operator_module',
    entityType: 'operator_module',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/enemy_handbook_table.json',
    roots: ['enemyData', 'raceData'],
    category: 'enemy',
    subtype: 'profile',
    contentType: 'enemy_profile',
    entityType: 'enemy',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/stage_table.json',
    roots: ['stages'],
    category: 'stage',
    subtype: 'stage',
    contentType: 'stage_description',
    entityType: 'stage',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/zone_table.json',
    roots: ['zones', 'zoneMetaData'],
    category: 'stage',
    subtype: 'zone',
    contentType: 'zone_description',
    entityType: 'zone',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/campaign_table.json',
    roots: ['campaigns', 'campaignGroups', 'campaignZones'],
    category: 'stage',
    subtype: 'campaign',
    contentType: 'campaign_description',
    entityType: 'campaign',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/activity_table.json',
    roots: ['basicInfo', 'activity', 'missionData', 'missionGroup'],
    category: 'activity',
    subtype: 'basic_info',
    contentType: 'activity_basic_info',
    entityType: 'activity',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/retro_table.json',
    roots: ['retroActList', 'retroTrailList', 'ruleData'],
    category: 'activity',
    subtype: 'archive',
    contentType: 'activity_archive',
    entityType: 'activity_archive',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/mission_table.json',
    roots: ['missions', 'missionGroups'],
    category: 'activity',
    subtype: 'mission',
    contentType: 'activity_mission',
    entityType: 'mission',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/roguelike_table.json',
    roots: ['itemTable', 'stages', 'zones', 'choices', 'endings'],
    category: 'roguelike',
    subtype: 'mechanic',
    contentType: 'roguelike_mechanic',
    entityType: 'roguelike',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/roguelike_topic_table.json',
    roots: ['topics', 'details', 'modules'],
    category: 'roguelike',
    subtype: 'topic',
    contentType: 'roguelike_topic',
    entityType: 'roguelike_topic',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/sandbox_table.json',
    roots: ['sandboxActTables', 'itemDatas'],
    category: 'sandbox',
    subtype: 'mechanic',
    contentType: 'sandbox_mechanic',
    entityType: 'sandbox',
  ),
  _StructuredTableSpec(
    sourcePath: 'zh_CN/gamedata/excel/sandbox_perm_table.json',
    roots: ['basicInfo', 'detail', 'itemData'],
    category: 'sandbox',
    subtype: 'item',
    contentType: 'sandbox_item',
    entityType: 'sandbox_item',
  ),
];

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
    await _importStructuredTextTables();
    await _importStories();
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

  /// Re-imports a single structured excel table by its repo-relative
  /// `sourcePath` (e.g. `zh_CN/gamedata/excel/activity_table.json`).
  ///
  /// Throws [StateError] for paths outside the whitelisted tables.
  Future<void> importStructuredTable(String sourcePath) async {
    final matches = _structuredTableSpecs
        .where((item) => item.sourcePath == sourcePath)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw StateError('Not a whitelisted structured table: $sourcePath');
    }
    final spec = matches.first;
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    await _importJsonCollection(
      zh,
      sourcePath: spec.sourcePath,
      roots: spec.roots,
      category: spec.category,
      subtype: spec.subtype,
      contentType: spec.contentType,
      entityType: spec.entityType,
    );
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

  Future<void> _importCharacterVoices() async {
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

  Future<void> _importStructuredTextTables() async {
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    for (var i = 0; i < _structuredTableSpecs.length; i++) {
      final spec = _structuredTableSpecs[i];
      await _importJsonCollection(
        zh,
        sourcePath: spec.sourcePath,
        roots: spec.roots,
        category: spec.category,
        subtype: spec.subtype,
        contentType: spec.contentType,
        entityType: spec.entityType,
      );
      onProgress?.call('structured', i + 1, _structuredTableSpecs.length);
    }
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
      final rawId = rawIdFromMap(data) ?? inheritedId;
      final texts = collectTextSections(data);
      if (rawId != null && texts.isNotEmpty) {
        final title = titleFromMap(data) ?? rawId;
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
            NormalizedRecord(
              category: category,
              subtype: subtype,
              contentType: contentType,
              entityId: '$entityType:$rawId',
              entityName: title,
              parentId: parentIdFromMap(data),
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

  Future<void> _importStories() async {
    final zh = Directory(p.join(sourceDir.path, 'zh_CN'));
    final storyRoot = Directory(p.join(zh.path, 'gamedata', 'story'));
    if (!await storyRoot.exists()) return;

    final files = await storyRoot
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.txt'))
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
    final lines = _parseStoryLines(raw);
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stats.storyLines++;
      }

      final text = lines
          .map((line) => line.speaker == null
              ? line.content
              : '${line.speaker}: ${line.content}',)
          .join('\n');
      final chunks = _chunker.chunkBySliding(text, pageTitle: storyId);
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        final chunk = chunks[chunkIndex];
        await _insertRecord(
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
          ),
        );
      }
    });
  }

  List<StoryLine> _parseStoryLines(String raw) {
    final lines = <StoryLine>[];
    final speakerPattern = RegExp(r'^\[name="([^"]+)"\](.*)$');

    for (final original in raw.split('\n')) {
      final line = original.trim();
      if (line.isEmpty) continue;

      final speakerMatch = speakerPattern.firstMatch(line);
      if (speakerMatch != null) {
        final content = cleanStoryText(speakerMatch.group(2) ?? '');
        if (content.isNotEmpty) {
          lines.add(StoryLine(speakerMatch.group(1), content));
        }
        continue;
      }

      if (line.startsWith('[')) continue;
      final content = cleanStoryText(line);
      if (content.isNotEmpty) {
        lines.add(StoryLine(null, content));
      }
    }
    return lines;
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

  Future<void> _insertRecord(Transaction txn, NormalizedRecord record) async {
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

class StoryLine {
  const StoryLine(this.speaker, this.content);
  final String? speaker;
  final String content;
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
  });
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

List<TextSection> collectTextSections(Map<String, dynamic> data) {
  final sections = <TextSection>[];

  void visit(Object? value, String path) {
    if (value is String) {
      final key = path.split('.').last;
      final text = value.trim();
      if (_textKeys.contains(key) && containsChinese(text)) {
        sections.add(TextSection(key, cleanStructuredText(text)));
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
            entry.value, path.isEmpty ? '${entry.key}' : '$path.${entry.key}',);
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

String? rawIdFromMap(Map<String, dynamic> data) {
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

String? titleFromMap(Map<String, dynamic> data) {
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
    if (containsChinese(value)) return cleanStructuredText(value);
  }
  return null;
}

String? parentIdFromMap(Map<String, dynamic> data) {
  const keys = [
    'activityId',
    'actId',
    'topicId',
    'zoneId',
    'stageId',
    'charId',
  ];
  final rawId = rawIdFromMap(data);
  for (final key in keys) {
    final value = '${data[key] ?? ''}'.trim();
    if (value.isNotEmpty && value != rawId) return value;
  }
  return null;
}

bool containsChinese(String text) =>
    text.runes.any((rune) => rune >= 0x4e00 && rune <= 0x9fff);

String cleanStructuredText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(r'\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

String cleanStoryText(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
