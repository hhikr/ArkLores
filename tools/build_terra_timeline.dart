/// Adds (or replaces) the optional Terra timeline of an Arknights knowledge
/// base in place (`terra_timeline*` tables, `lib/core/gamedata/terra_timeline.dart`),
/// from PRTS Wiki's "泰拉年表" (CC BY-NC-SA 4.0). Nothing else changes; the
/// manifest gets `terra_timeline_revision`.
///
/// By default the page is fetched from the PRTS MediaWiki API (one request,
/// the project's User-Agent); `--wikitext=<file>` reads a saved copy
/// instead (`--revision=<id>` then says which revision it is).
///
/// Usage:
/// ```text
/// dart run tools/build_terra_timeline.dart --db=<path.db> [--wikitext=<file> --revision=<id>] [--dry-run]
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/terra_timeline_importer.dart';
import 'package:arklores/core/gamedata/terra_timeline.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  String? dbPath;
  String? wikitextPath;
  String? revision;
  var dryRun = false;
  for (final arg in args) {
    if (arg.startsWith('--db=')) dbPath = arg.substring(5);
    if (arg.startsWith('--wikitext=')) wikitextPath = arg.substring(11);
    if (arg.startsWith('--revision=')) revision = arg.substring(11);
    if (arg == '--dry-run') dryRun = true;
    if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'dart run tools/build_terra_timeline.dart --db=<db> '
        '[--wikitext=<file> --revision=<id>] [--dry-run]',
      );
      return;
    }
  }
  if (dbPath == null) {
    stderr.writeln('Missing --db (see --help).');
    exit(64);
  }
  if (!File(dbPath).existsSync()) {
    stderr.writeln('DB not found: $dbPath');
    exit(66);
  }

  String wikitext;
  if (wikitextPath != null) {
    wikitext = await File(wikitextPath).readAsString();
  } else {
    final page = await _fetch();
    wikitext = page.wikitext;
    revision = page.revision;
  }
  final events = parseTerraTimeline(wikitext);
  if (events.isEmpty) {
    stderr.writeln('No events parsed; the page format may have changed.');
    exit(65);
  }

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(File(dbPath).absolute.path);
  try {
    if (dryRun) {
      final index = await StoryLinkIndex.load(db);
      var links = 0;
      var mapped = 0;
      for (final e in events) {
        for (final s in e.sources) {
          final t = s.target;
          if (t != null && RegExp(r'/(BEG|END|NBT)\b').hasMatch(t)) links++;
          if (t != null && index.mapStoryLink(t) != null) mapped++;
        }
      }
      stdout.writeln('Dry run: ${events.length} events, story links $links, '
          'tied to a story $mapped (revision ${revision ?? '?'}).');
      return;
    }
    final report = await writeTerraTimeline(db, events, revision: revision);
    if (revision != null) {
      await db.insert(
        'gamedata_manifest',
        {'key': 'terra_timeline_revision', 'value': revision},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    stdout.writeln('Terra timeline (revision ${revision ?? '?'}): $report.');
  } finally {
    await db.close();
  }
}

Future<({String wikitext, String revision})> _fetch() async {
  final uri = Uri.https('prts.wiki', '/api.php', {
    'action': 'parse',
    'page': terraTimelinePage,
    'prop': 'wikitext|revid',
    'format': 'json',
    'formatversion': '2',
  });
  // PRTS refuses browser-like agents; it asks clients to say who they are
  // (as the app does, `wiki_sources.dart`).
  const headers = {
    'User-Agent':
        'ArkLores-build (knowledge base; +https://github.com/hhikr/ArkLores)',
  };
  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    stderr.writeln('PRTS answered ${response.statusCode}.');
    exit(69);
  }
  final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final parse = json['parse'] as Map?;
  if (parse == null) {
    stderr.writeln('PRTS gave no page: ${json['error'] ?? json}');
    exit(69);
  }
  return (
    wikitext: '${parse['wikitext']}',
    revision: '${parse['revid']}',
  );
}
