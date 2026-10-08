// Builds the optional `story_chunk_vectors` table (R12 vector recall) into a
// GameData DB: chunks every story with the app's `chunkStory`, embeds chunks
// with the app's `OpenAICompatibleEmbeddingClient`, quantizes with the app's
// `quantize`, and records model/dims/chunking in `gamedata_manifest`.
//
// Resumable and reproducible: vectors are cached by a hash of
// (model, dims, chunk text) in a side SQLite file, so a rerun only embeds new
// or changed chunks and an unchanged corpus yields identical rows.
//
//   dart run tools/build_story_embeddings.dart \
//     --db=build/gamedata_mobile/arklores_gamedata_zh.db [--limit-stories=50]
//
// Endpoint/key default to the gitignored tools/embedding-apiKey.csv
// (openAiCompatible, apiKey); override with --url/--key/--model/--dims.
// Never commit an API key.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final dbPath = File(
    _arg(args, '--db') ?? 'build/gamedata_mobile/arklores_gamedata_zh.db',
  ).absolute.path;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('DB not found: $dbPath');
    exitCode = 2;
    return;
  }
  final csv = _readKeyCsv(File('tools/embedding-apiKey.csv'));
  final config = EmbeddingConfig(
    baseUrl: _arg(args, '--url') ?? csv['openAiCompatible'] ?? '',
    apiKey: _arg(args, '--key') ?? csv['apiKey'] ?? '',
    model: _arg(args, '--model') ?? 'qwen3.7-text-embedding',
    dimensions: int.tryParse(_arg(args, '--dims') ?? '') ?? 512,
  );
  if (!config.isValid) {
    stderr.writeln('No embedding config: provide tools/embedding-apiKey.csv '
        'or --url/--key/--model.');
    exitCode = 2;
    return;
  }
  final limitStories = int.tryParse(_arg(args, '--limit-stories') ?? '');
  final concurrency = int.tryParse(_arg(args, '--concurrency') ?? '') ?? 4;
  final cachePath = File(
    _arg(args, '--cache') ??
        'build/embedding_cache/${config.model}_${config.dimensions}.db',
  ).absolute.path;
  Directory(File(cachePath).parent.path).createSync(recursive: true);

  final db = await databaseFactoryFfi.openDatabase(dbPath);
  final cache = await databaseFactoryFfi.openDatabase(cachePath);
  await cache.execute(
    'CREATE TABLE IF NOT EXISTS vectors '
    '(hash TEXT PRIMARY KEY, scale REAL NOT NULL, vec BLOB NOT NULL)',
  );

  // 1. Chunk every story with the app's deterministic chunker. With
  // --migrate-from=<older db with vectors>, the older database's vectors are
  // moved onto the new line numbers first (rows of stories whose older lines
  // all find their counterpart in the new lines), and only the lines the
  // older database did not have are chunked and embedded.
  final stories = await db.rawQuery(
    "SELECT story_id, CASE WHEN scope_id IS NULL OR scope_id = '' "
    "THEN scope_type ELSE scope_type || ':' || scope_id END AS scope_key "
    'FROM story_scopes ORDER BY story_id',
  );
  final selected = limitStories == null ? stories : stories.take(limitStories);
  final migrateFrom = _arg(args, '--migrate-from');
  final dryRun = args.contains('--dry-run');
  final migrator = migrateFrom == null
      ? null
      : await _Migrator.open(File(migrateFrom).absolute.path);
  final hasKind = (await db.rawQuery('PRAGMA table_info(story_lines)'))
      .any((c) => c['name'] == 'kind');
  final migrated = <Map<String, Object?>>[];
  final chunks = <StoryChunk>[];
  var alignedStories = 0, partialStories = 0;
  for (final row in selected) {
    final storyId = '${row['story_id']}';
    final scopeKey = row['scope_key'] as String?;
    final lines = await db.rawQuery(
      'SELECT line_index, speaker, content${hasKind ? ', kind' : ''} '
      'FROM story_lines WHERE story_id = ? ORDER BY line_index',
      [storyId],
    );
    final covered = <int>{};
    if (migrator != null) {
      final result = await migrator.migrate(storyId, scopeKey, lines);
      migrated.addAll(result.rows);
      covered.addAll(result.coveredLines);
      if (result.hadOldLines) {
        result.fullyAligned ? alignedStories++ : partialStories++;
      }
    }
    // Tutorial and guide text is not part of any story: never embedded.
    chunks.addAll(chunkStory(storyId, scopeKey, [
      for (final l in lines)
        if (!covered.contains((l['line_index'] as num).toInt()) &&
            l['kind'] != 'system')
          ChunkLine(
            (l['line_index'] as num).toInt(),
            l['speaker'] as String?,
            '${l['content'] ?? ''}',
            isBreak: l['kind'] == sectionLineKind,
          ),
    ]),);
  }
  if (migrator != null) {
    stdout.writeln('Migrated ${migrated.length} vectors from $migrateFrom '
        '(stories fully aligned: $alignedStories, partly: $partialStories).');
    await migrator.close();
  }
  final hashes = [
    for (final c in chunks) _hash('${config.model}|${config.dimensions}|${c.text}'),
  ];
  stdout.writeln('Stories: ${selected.length}  chunks: ${chunks.length}  '
      'model: ${config.model}@${config.dimensions}');

  // 2. Embed chunks missing from the cache.
  final cached = {
    for (final r in await cache.rawQuery('SELECT hash FROM vectors')) '${r['hash']}',
  };
  final pending = <int>[
    for (var i = 0; i < chunks.length; i++)
      if (!cached.contains(hashes[i])) i,
  ];
  final pendingChars =
      pending.fold<int>(0, (sum, i) => sum + chunks[i].text.length);
  stdout.writeln('Cached: ${chunks.length - pending.length}  to embed: '
      '${pending.length} ($pendingChars chars)');
  if (dryRun) {
    stdout.writeln('Dry run: nothing embedded, nothing written.');
    await cache.close();
    await db.close();
    return;
  }

  final client = OpenAICompatibleEmbeddingClient(config: config);
  final batches = <List<int>>[
    for (var i = 0; i < pending.length; i += OpenAICompatibleEmbeddingClient.maxBatch)
      pending.sublist(
        i,
        i + OpenAICompatibleEmbeddingClient.maxBatch > pending.length
            ? pending.length
            : i + OpenAICompatibleEmbeddingClient.maxBatch,
      ),
  ];
  final watch = Stopwatch()..start();
  var done = 0;
  var next = 0;
  Future<void> worker() async {
    while (next < batches.length) {
      final batch = batches[next++];
      final vectors = await client.embed([for (final i in batch) chunks[i].text]);
      await cache.transaction((txn) async {
        for (var k = 0; k < batch.length; k++) {
          final q = quantize(vectors[k]);
          await txn.insert(
            'vectors',
            {
              'hash': hashes[batch[k]],
              'scale': q.scale,
              'vec': Uint8List.view(q.values.buffer),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      done += batch.length;
      if (done % 2000 < batch.length || done == pending.length) {
        final rate = done / (watch.elapsedMilliseconds / 1000 + 1e-9);
        stdout.writeln('  embedded $done/${pending.length} '
            '(${rate.toStringAsFixed(1)} chunks/s)');
      }
    }
  }

  try {
    await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
  } finally {
    client.dispose();
  }

  // 3. Rewrite the vector table from the cache and stamp the manifest.
  final vectorsByHash = <String, Map<String, Object?>>{};
  for (final r in await cache.rawQuery('SELECT hash, scale, vec FROM vectors')) {
    vectorsByHash['${r['hash']}'] = r;
  }
  await db.transaction((txn) async {
    await txn.execute('DROP TABLE IF EXISTS $storyChunkVectorsTable');
    await txn.execute(storyChunkVectorsDdl);
    await txn.execute(storyChunkVectorsIndexDdl);
    final batch = txn.batch();
    for (final row in migrated) {
      batch.insert(storyChunkVectorsTable, row,
          conflictAlgorithm: ConflictAlgorithm.replace,);
    }
    for (var i = 0; i < chunks.length; i++) {
      final v = vectorsByHash[hashes[i]]!;
      batch.insert(storyChunkVectorsTable, {
        'chunk_id': chunks[i].chunkId,
        'story_id': chunks[i].storyId,
        'scope_id': chunks[i].scopeId,
        'line_start': chunks[i].lineStart,
        'line_end': chunks[i].lineEnd,
        'scale': v['scale'],
        'vec': v['vec'],
      });
    }
    await batch.commit(noResult: true);
    for (final entry in {
      manifestEmbeddingModel: config.model,
      manifestEmbeddingDims: '${config.dimensions}',
      manifestEmbeddingChunking: chunkingSignature,
    }.entries) {
      await txn.insert(
        'gamedata_manifest',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
  await cache.close();
  await db.close();
  stdout.writeln('Wrote ${chunks.length + migrated.length} vectors '
      '(${migrated.length} migrated) to $storyChunkVectorsTable '
      'in ${watch.elapsed.inSeconds}s.');
}

/// Result of moving one story's older vectors onto the new line numbers.
class _Migration {
  _Migration(this.rows, this.coveredLines, this.hadOldLines, this.fullyAligned);
  final List<Map<String, Object?>> rows;

  /// New line numbers that have a counterpart in the older database.
  final Set<int> coveredLines;
  final bool hadOldLines;
  final bool fullyAligned;
}

/// Moves vectors from an older knowledge base onto a newer one.
///
/// The text of a story can change between builds without changing its
/// meaning (an upstream update replaced `......` by `……` throughout), so the
/// content hash cache cannot find the old vectors. Instead each older line
/// is matched with its counterpart in the new lines in order (ellipsis runs,
/// blanks and edge spaces ignored) and an older chunk is kept when its first
/// and last lines both have a counterpart; the vector (a locating hint)
/// moves with the new line range.
class _Migrator {
  _Migrator._(this._old);

  final Database _old;

  static Future<_Migrator> open(String path) async =>
      _Migrator._(await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      ),);

  Future<void> close() => _old.close();

  // Older builds also kept the script's literal `\n` (now a real line
  // break): the same text, written differently.
  static String _norm(String? s) => (s ?? '')
      .replaceAll(RegExp(r'\\[nrt]'), '')
      .replaceAll(RegExp(r'\.{3,}|…+'), '…')
      .replaceAll(RegExp(r'\s+'), '');

  Future<_Migration> migrate(
    String storyId,
    String? scopeKey,
    List<Map<String, Object?>> newLines,
  ) async {
    final oldLines = await _old.rawQuery(
      'SELECT line_index, speaker, content FROM story_lines '
      'WHERE story_id = ? ORDER BY line_index',
      [storyId],
    );
    if (oldLines.isEmpty) return _Migration(const [], <int>{}, false, false);
    final map = <int, int>{};
    var j = 0;
    for (final r in newLines) {
      if (j >= oldLines.length) break;
      if (_norm('${r['content']}') == _norm('${oldLines[j]['content']}') &&
          _norm(r['speaker'] as String?) ==
              _norm(oldLines[j]['speaker'] as String?)) {
        map[(oldLines[j]['line_index'] as num).toInt()] =
            (r['line_index'] as num).toInt();
        j++;
      }
    }
    final vectors = await _old.rawQuery(
      'SELECT line_start, line_end, scale, vec FROM story_chunk_vectors '
      'WHERE story_id = ?',
      [storyId],
    );
    final rows = <Map<String, Object?>>[];
    for (final v in vectors) {
      final start = map[(v['line_start'] as num).toInt()];
      final end = map[(v['line_end'] as num).toInt()];
      if (start == null || end == null || end < start) continue;
      rows.add({
        'chunk_id': '$storyId#$start-$end',
        'story_id': storyId,
        'scope_id': scopeKey,
        'line_start': start,
        'line_end': end,
        'scale': v['scale'],
        'vec': v['vec'],
      });
    }
    return _Migration(rows, map.values.toSet(), true, j == oldLines.length);
  }
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}

Map<String, String> _readKeyCsv(File file) {
  if (!file.existsSync()) return const {};
  return {
    for (final line in file.readAsLinesSync())
      if (line.contains(','))
        line.substring(0, line.indexOf(',')).trim():
            line.substring(line.indexOf(',') + 1).trim(),
  };
}

/// FNV-1a 64-bit over UTF-8 (stable across runs; VM ints wrap mod 2^64).
String _hash(String text) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(text)) {
    h = (h ^ b) * 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
