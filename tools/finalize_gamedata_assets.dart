import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbFileName = 'arklores_gamedata_zh.db';
const _gzFileName = 'arklores_gamedata_zh.db.gz';

/// Finalizes release assets in `--output`: gzips the DB when the `.gz` is
/// missing (portable, no external gzip needed), writes sizes and SHA-256
/// into the manifest/report, and copies the optional vector-table metadata
/// from the DB's own `gamedata_manifest` table. A manifest JSON is derived
/// from that table when the build step did not leave one behind.
Future<void> main(List<String> args) async {
  final output = _argValue(args, '--output') ?? 'build/gamedata_mobile';
  final outDir = Directory(output).absolute;
  final dbFile = File(p.join(outDir.path, _dbFileName));
  final gzFile = File(p.join(outDir.path, _gzFileName));
  final manifestFile = File(p.join(outDir.path, 'gamedata_manifest.json'));
  final reportFile = File(p.join(outDir.path, 'gamedata_build_report.json'));

  if (!await dbFile.exists()) {
    throw StateError('Missing database: ${dbFile.path}');
  }
  if (!await gzFile.exists()) {
    stdout.writeln('Compressing ${dbFile.path} ...');
    await dbFile.openRead().transform(gzip.encoder).pipe(gzFile.openWrite());
  }

  final dbMeta = await _readDbManifest(dbFile.path);

  final dbBytes = await dbFile.length();
  final gzBytes = await gzFile.length();
  final dbSha = await _sha256Of(dbFile);
  final gzSha = await _sha256Of(gzFile);

  final manifest = await manifestFile.exists()
      ? (jsonDecode(await manifestFile.readAsString()) as Map)
          .cast<String, dynamic>()
      : _manifestFromDb(dbMeta.values);
  final embedding = dbMeta.embedding;
  if (embedding != null) manifest['embedding'] = embedding;
  final database = (manifest['database'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  database
    ..['fileName'] = _gzFileName
    ..['uncompressedFileName'] = _dbFileName
    ..['delivery'] = 'release-asset'
    ..['sha256'] = gzSha
    ..['uncompressedSha256'] = dbSha
    ..['compressedBytes'] = gzBytes
    ..['uncompressedBytes'] = dbBytes;
  manifest['database'] = database;
  manifest['finalizedAt'] = DateTime.now().toUtc().toIso8601String();

  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );

  if (await reportFile.exists()) {
    final report = (jsonDecode(await reportFile.readAsString()) as Map)
        .cast<String, dynamic>();
    report['assets'] = {
      _dbFileName: {
        'bytes': dbBytes,
        'sha256': dbSha,
      },
      _gzFileName: {
        'bytes': gzBytes,
        'sha256': gzSha,
      },
    };
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
  }

  stdout.writeln('Finalized GameData assets: ${outDir.path}');
  stdout.writeln('$_dbFileName $dbBytes bytes sha256=$dbSha');
  stdout.writeln('$_gzFileName $gzBytes bytes sha256=$gzSha');
}

class _DbMeta {
  const _DbMeta(this.values, this.embedding);
  final Map<String, String> values;
  final Map<String, dynamic>? embedding;
}

Future<_DbMeta> _readDbManifest(String path) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final values = <String, String>{
      for (final row in await db.query('gamedata_manifest'))
        '${row['key']}': '${row['value']}',
    };
    Map<String, dynamic>? embedding;
    final hasVectors = (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'story_chunk_vectors'",
    ))
        .isNotEmpty;
    if (hasVectors && values.containsKey('embedding_model')) {
      final count = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_chunk_vectors',
      ))
          .first['c'];
      embedding = {
        'model': values['embedding_model'],
        'dims': int.tryParse(values['embedding_dims'] ?? ''),
        'chunking': values['embedding_chunking'],
        'vectorCount': count,
        'optional': true,
      };
    }
    return _DbMeta(values, embedding);
  } finally {
    await db.close();
  }
}

Map<String, dynamic> _manifestFromDb(Map<String, String> values) {
  return {
    'schemaVersion': values['schema_version'],
    'language': values['language'],
    'builtAt': values['built_at'],
    'database': <String, dynamic>{},
    'sources': {
      'arknights': {
        'repo': values['source_arknights_repo'],
        'branch': values['source_arknights_branch'],
        'commit': values['source_arknights_commit'],
        'languagePath': 'zh_CN',
      },
    },
    'counts': {
      for (final e in values.entries)
        if (e.key.endsWith('_count')) e.key: int.tryParse(e.value) ?? e.value,
    },
  };
}

Future<String> _sha256Of(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}
