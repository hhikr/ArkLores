/// Builds ArkLores GameData SQLite database from community unpack repositories.
///
/// Initial scope: Chinese Arknights data from Kengxxiao/ArknightsGameData.
///
/// Usage:
///   dart run tool/build_gamedata_database.dart \
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

const _schemaVersion = 1;
const _language = 'zh';
const _profileId = 'builtin:builtin-embedding';

void main(List<String> args) async {
  sqfliteFfiInit();
  final cfg = _Config.parse(args);

  final out = Directory(cfg.outputDir);
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
        'embedding_profile_id': _profileId,
        'embedding_status': 'pending',
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
        "INSERT INTO lore_chunks_fts(lore_chunks_fts) VALUES('rebuild')");
    await _writeManifest(
      db,
      {
        'entity_count': '${stats.entities}',
        'story_line_count': '${stats.storyLines}',
        'lore_chunk_count': '${stats.loreChunks}',
        'arknights_profile_chunk_count': '${stats.profileChunks}',
        'arknights_story_chunk_count': '${stats.storyChunks}',
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
    'embedding': {
      'profileId': _profileId,
      'status': 'pending',
      'dimension': 512,
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
      'nextStep': 'Run tool/embed_gamedata_database.py before publishing.',
    }),
    flush: true,
  );

  stdout.writeln('GameData DB built: $dbPath');
  stdout.writeln('Entities: ${stats.entities}');
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
    CREATE TABLE lore_chunks (
      id             TEXT PRIMARY KEY,
      game           TEXT NOT NULL,
      source_type    TEXT NOT NULL,
      entity_id      TEXT,
      story_id       TEXT,
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
      retrieval_hint TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE chunk_embeddings (
      chunk_id   TEXT NOT NULL,
      profile_id TEXT NOT NULL,
      dimension  INTEGER NOT NULL,
      embedding  BLOB NOT NULL,
      PRIMARY KEY (chunk_id, profile_id),
      FOREIGN KEY (chunk_id) REFERENCES lore_chunks(id)
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
    'CREATE INDEX idx_lore_chunks_source_type ON lore_chunks(source_type)',
  );
  await db.execute(
    'CREATE INDEX idx_lore_chunks_entity_id ON lore_chunks(entity_id)',
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

        await _insertChunk(
          txn,
          sourceType: 'operator_profile',
          entityId: charId,
          pageTitle: name,
          section: '基础信息',
          content: [
            if ('${data['description'] ?? ''}'.trim().isNotEmpty)
              '${data['description']}'.trim(),
            if ('${data['itemUsage'] ?? ''}'.trim().isNotEmpty)
              '${data['itemUsage']}'.trim(),
            if ('${data['itemDesc'] ?? ''}'.trim().isNotEmpty)
              '${data['itemDesc']}'.trim(),
          ].join('\n'),
          sourcePath: sourcePath,
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
                await _insertChunk(
                  txn,
                  sourceType: 'operator_profile',
                  entityId: charId,
                  pageTitle: name,
                  section: section,
                  content: text,
                  sourcePath: 'zh_CN/gamedata/excel/handbook_info_table.json',
                  retrievalHint: 'operator_handbook',
                );
              }
            }
          }
        }
      }
    });
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

    await db.transaction((txn) async {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        await txn.insert(
          'story_lines',
          {
            'id': _stableId('arknights:story_line:$storyId:$i'),
            'game': 'arknights',
            'story_id': storyId,
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
      for (final chunk in chunks) {
        await _insertChunk(
          txn,
          sourceType: 'game_story',
          storyId: storyId,
          pageTitle: storyId,
          section: '剧情文本',
          content: chunk.content,
          sourcePath: relativePath,
          lineStart: null,
          lineEnd: null,
          retrievalHint: 'story_text',
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
    required String sourceType,
    required String pageTitle,
    required String section,
    required String content,
    required String sourcePath,
    String? entityId,
    String? storyId,
    int? lineStart,
    int? lineEnd,
    String? retrievalHint,
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    final id = _stableId([
      'arknights',
      sourceType,
      entityId ?? '',
      storyId ?? '',
      pageTitle,
      section,
      clean,
    ].join(':'));
    await txn.insert(
      'lore_chunks',
      {
        'id': id,
        'game': 'arknights',
        'source_type': sourceType,
        'entity_id': entityId,
        'story_id': storyId,
        'page_title': pageTitle,
        'section': section,
        'content': clean,
        'source_path': sourcePath,
        'line_start': lineStart,
        'line_end': lineEnd,
        'language': _language,
        'updated_at': _nowSeconds(),
        'retrieval_hint': retrievalHint,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    stats.loreChunks++;
    if (sourceType == 'game_story') {
      stats.storyChunks++;
    } else {
      stats.profileChunks++;
    }
  }
}

class _StoryLine {
  final String? speaker;
  final String content;

  const _StoryLine(this.speaker, this.content);
}

class _BuildStats {
  int entities = 0;
  int storyLines = 0;
  int loreChunks = 0;
  int profileChunks = 0;
  int storyChunks = 0;

  Map<String, int> toJson() => {
        'entities': entities,
        'storyLines': storyLines,
        'loreChunks': loreChunks,
        'profileChunks': profileChunks,
        'storyChunks': storyChunks,
      };
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
  dart run tool/build_gamedata_database.dart \\
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
