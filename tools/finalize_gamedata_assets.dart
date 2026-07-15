import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _dbFileName = 'arklores_gamedata_zh.db';
const _gzFileName = 'arklores_gamedata_zh.db.gz';

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
    throw StateError('Missing compressed database: ${gzFile.path}');
  }
  if (!await manifestFile.exists()) {
    throw StateError('Missing manifest: ${manifestFile.path}');
  }

  final dbBytes = await dbFile.length();
  final gzBytes = await gzFile.length();
  final dbSha = await _sha256Of(dbFile);
  final gzSha = await _sha256Of(gzFile);

  final manifest = (jsonDecode(await manifestFile.readAsString()) as Map)
      .cast<String, dynamic>();
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
