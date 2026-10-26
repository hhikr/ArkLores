import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/gamedata_schema.dart';

/// Writes the channel file (`gamedata_channel.json`) the app reads to find
/// official knowledge bases uploaded after it was built, from
/// `tools/release_gamedata.env`. Upload the result to the `gamedata-channel`
/// Release (replacing the asset there) with every data release, after the
/// knowledge-base assets themselves are uploaded.
///
///   dart run tools/write_gamedata_channel.dart [--output=build/gamedata_channel.json]
void main(List<String> args) {
  final output = args
          .where((a) => a.startsWith('--output='))
          .map((a) => a.substring('--output='.length))
          .firstOrNull ??
      'build/gamedata_channel.json';
  final env = <String, String>{
    for (final line in File('tools/release_gamedata.env').readAsLinesSync())
      if (RegExp(r'^([A-Z0-9_]+)=(.*)$').firstMatch(line.trim()) case final m?)
        m.group(1)!: m.group(2)!.trim(),
  };
  final minBuild = int.tryParse(env['GAMEDATA_MIN_APP_BUILD'] ?? '');
  Map<String, Object> asset(String prefix) {
    final url = env['${prefix}_DB_URL'] ?? '';
    final sha = env['${prefix}_DB_SHA256'] ?? '';
    if (url.isEmpty || sha.isEmpty) {
      throw StateError(
          'tools/release_gamedata.env has no ${prefix}_DB_URL / ${prefix}_DB_SHA256',);
    }
    return {
      'url': url,
      'sha256': sha,
      if ((env['${prefix}_DB_COMMIT'] ?? '').isNotEmpty)
        'commit': env['${prefix}_DB_COMMIT']!,
      if ((env['${prefix}_DB_COMMIT_DATE'] ?? '').isNotEmpty)
        'commit_date': env['${prefix}_DB_COMMIT_DATE']!,
      'schema_version': gamedataSchemaVersion,
      if (minBuild != null) 'min_app_build': minBuild,
    };
  }

  final channel = <String, Object?>{
    'arknights': asset('GAMEDATA'),
    'endfield': asset('ENDFIELD'),
  };
  String? option(String name) => args
      .where((a) => a.startsWith('--$name='))
      .map((a) => a.substring(name.length + 3))
      .firstOrNull;
  final url = option('portraits-url');
  final sha = option('portraits-sha256');
  if (url != null || sha != null) {
    if (url == null || url.isEmpty || sha == null || sha.isEmpty) {
      throw ArgumentError(
          'Both --portraits-url and --portraits-sha256 are required',);
    }
    channel['arknights_portraits'] = {
      'url': url,
      'sha256': sha,
      'size': int.parse(option('portraits-size') ?? '0'),
      'kb_commit': option('portraits-kb-commit') ?? '',
      'pack_version': 1,
      'min_app_build': 43,
    };
  } else if (File(output).existsSync()) {
    final previous = jsonDecode(File(output).readAsStringSync());
    if (previous is Map && previous.containsKey('arknights_portraits')) {
      channel['arknights_portraits'] = previous['arknights_portraits'];
    }
  }
  File(output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(channel)}\n',);
  stdout.writeln('wrote $output');
}
