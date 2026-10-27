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
///     [--story-art-url=… --story-art-sha256=… --story-art-size=… --story-art-kb-commit=…]
///
/// The portrait pack entry (`arknights_story_art`) comes from the env's
/// STORY_ART_* values, or the options above; with neither, the entry already
/// in the output file is kept.
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
  // The portrait pack (0.20): from the env like the knowledge bases
  // (STORY_ART_URL / _SHA256 / _SIZE / _KB_COMMIT); an option overrides the
  // env value of the same name.
  String? option(String name) =>
      args
          .where((a) => a.startsWith('--$name='))
          .map((a) => a.substring(name.length + 3))
          .firstOrNull ??
      env[name.toUpperCase().replaceAll('-', '_')];
  final url = option('story-art-url');
  final sha = option('story-art-sha256');
  if ((url ?? '').isNotEmpty || (sha ?? '').isNotEmpty) {
    if (url == null || url.isEmpty || sha == null || sha.isEmpty) {
      throw ArgumentError(
          'Both the portrait pack URL and SHA-256 are required',);
    }
    channel['arknights_story_art'] = {
      'url': url,
      'sha256': sha,
      'size': int.parse(option('story-art-size') ?? '0'),
      'kb_commit': option('story-art-kb-commit') ?? '',
      'pack_version': 2,
      'min_app_build': 43,
    };
  } else if (File(output).existsSync()) {
    final previous = jsonDecode(File(output).readAsStringSync());
    if (previous is Map && previous.containsKey('arknights_story_art')) {
      channel['arknights_story_art'] = previous['arknights_story_art'];
    }
  }
  File(output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(channel)}\n',);
  stdout.writeln('wrote $output');
}
