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

  // 1. Chunk every story with the app's deterministic chunker.
  final stories = await db.rawQuery(
    "SELECT story_id, CASE WHEN scope_id IS NULL OR scope_id = '' "
    "THEN scope_type ELSE scope_type || ':' || scope_id END AS scope_key "
    'FROM story_scopes ORDER BY story_id',
  );
  final selected = limitStories == null ? stories : stories.take(limitStories);
  final chunks = <StoryChunk>[];
  for (final row in selected) {
    final storyId = '${row['story_id']}';
    final lines = await db.rawQuery(
      'SELECT line_index, speaker, content FROM story_lines '
      'WHERE story_id = ? ORDER BY line_index',
      [storyId],
    );
    chunks.addAll(chunkStory(storyId, row['scope_key'] as String?, [
      for (final l in lines)
        ChunkLine(
          (l['line_index'] as num).toInt(),
          l['speaker'] as String?,
          '${l['content'] ?? ''}',
        ),
    ]),);
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
    final batch = txn.batch();
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
  stdout.writeln('Wrote ${chunks.length} vectors to $storyChunkVectorsTable '
      'in ${watch.elapsed.inSeconds}s.');
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
