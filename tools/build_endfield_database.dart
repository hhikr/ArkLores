// 0.12: builds the Endfield knowledge base (`arklores_endfield_zh.db`) from a
// local unpack of the game client.
//
//   dart run tools/build_endfield_database.dart \
//     --tables=<dir with the decoded game tables, e.g. <kit>/export_full/game/Table> \
//     [--missions=<a JsonData dump's Data/Json/MissionRuntimeAsset>] \
//     [--trees=<TextAsset dir>[;<TextAsset dir> …]] \
//     [--clips=<MonoBehaviour dir>[;<MonoBehaviour dir> …]] \
//     [--chapters=<MonoBehaviour dir>[;<MonoBehaviour dir> …]] \
//     [--data=<a JsonData dump's Data/Json> --step-order=<mission,…|all>] \
//     [--only-missions=<mission,…>] \
//     [--version=<client version>] \
//     --output=build/endfield [--force]
//
// The tables give the operator archives, the PRTS archive, enemy, weapon and
// item flavour text and the conversations; the mission definitions (a JSON
// data dump's MissionRuntimeAsset) name and shelve the missions; the dialog
// trees (`dlg_…` TextAssets; StreamingAssets first, then Persistent) give
// the order of each conversation's lines and choices, and the cutscene clips
// (`DialogTrunkPlayableAsset`/`DialogOptionPlayableAsset` MonoBehaviours)
// the order of the lines a cutscene shows. With `--data` (the hot-update
// layer's dump, which holds the whole set) the stories of the missions in
// `--step-order` are laid out along their steps from the level scripts and
// the levels' mission sub-data; where each conversation went and why is
// written to `story_order_report.md` next to the database. `--only-missions`
// writes those missions' stories and no others (to review a few). Use
// tools/unpack_endfield.ps1 to unpack and build in one go.
// See docs/GAMEDATA_BUILD_PIPELINE.md (Endfield) and
// docs/KNOWLEDGE_BASE_LESSONS.md.
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/endfield/endfield_dialog_tree.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_importer.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_level_data.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_stories.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_tables.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_writer.dart';
import 'package:arklores/core/gamedata/build/gamedata_db_validator.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  String? arg(String name) {
    for (final a in args) {
      if (a.startsWith('--$name=')) return a.substring(name.length + 3);
    }
    return null;
  }

  final tablesDir = arg('tables');
  final output = arg('output') ?? 'build/endfield';
  if (tablesDir == null) {
    stderr.writeln('usage: --tables=<dir> [--story=<dir>] --output=<dir> [--force]');
    exit(64);
  }
  final out = Directory(p.absolute(output));
  if (await out.exists()) {
    if (!args.contains('--force')) {
      stderr.writeln('Output exists; use --force: $output');
      exit(1);
    }
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);
  final dbPath = p.join(out.path, Game.endfield.dbFileName);
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  final watch = Stopwatch()..start();
  void log(String m) => stdout.writeln('[${watch.elapsed.inSeconds}s] $m');
  try {
    final writer = EndfieldWriter(db);
    await writer.createSchema(sourceVersion: arg('version') ?? 'unknown');
    final tables = EndfieldTables(Directory(tablesDir));
    // The mission definitions first: a text's region can come from the
    // level of the mission its id names.
    final missionsDir = arg('missions');
    final missions = missionsDir == null
        ? const <String, EndfieldMission>{}
        : EndfieldStoryImporter.loadMissions(Directory(missionsDir), tables);
    log('missions defined: ${missions.length}');
    final importer = EndfieldImporter(tables, writer, log: log, missions: missions);
    await importer.importTables();
    final trees = EndfieldStoryImporter.loadDialogTrees([
      for (final d in (arg('trees') ?? '').split(';'))
        if (d.trim().isNotEmpty) Directory(d.trim()),
    ]);
    log('dialog trees: ${trees.length}');
    final timelines = loadTimelineLines([
      for (final d in (arg('clips') ?? '').split(';'))
        if (d.trim().isNotEmpty) Directory(d.trim()),
    ]);
    log('conversations with cutscene lines: ${timelines.length}');
    final chapters = EndfieldStoryImporter.loadChapters([
      for (final d in (arg('chapters') ?? '').split(';'))
        if (d.trim().isNotEmpty) Directory(d.trim()),
    ]);
    log('chapters: ${chapters.length}');
    Set<String> list(String? value) => {
          for (final x in (value ?? '').split(',')) if (x.trim().isNotEmpty) x.trim(),
        };
    final stepOrder = list(arg('step-order'));
    final only = arg('only-missions') == null ? null : list(arg('only-missions'));
    final definitions = missionsDir == null
        ? const <String, Map<String, dynamic>>{}
        : EndfieldStoryImporter.loadMissionDefinitions(Directory(missionsDir));
    EndfieldLevelData? levelData;
    if (arg('data') case final data? when stepOrder.isNotEmpty) {
      levelData = EndfieldLevelData.read(
        Directory(data),
        questIds: {
          for (final d in definitions.values) ...((d['questDic'] as Map?) ?? const {}).keys.map((k) => '$k'),
        },
        missionIds: definitions.keys.toSet(),
      );
      log('level scripts: ${levelData.scripts.length}, segments switched: ${levelData.segments.length}, '
          'sub-data conversations: ${levelData.subData.length}');
    }
    final report = StringBuffer();
    final stories = EndfieldStoryImporter(
      tables,
      writer,
      importer,
      log: log,
      missions: missions,
      dialogTrees: trees,
      timelineLines: timelines,
      chapters: chapters,
      playedBy: missionsDir == null
          ? const {}
          : EndfieldStoryImporter.loadPlayedConversations(Directory(missionsDir)),
      levelData: levelData,
      missionDefinitions: definitions,
      stepOrder: stepOrder,
      onlyMissions: only,
      orderReport: report,
    );
    await stories.importDialogTables();
    if (report.isNotEmpty) {
      await File(p.join(out.path, 'story_order_report.md')).writeAsString(report.toString());
    }
    log('derived layers');
    await writer.finish();
    await validateGameDataDatabase(db);
    final manifest = {
      for (final r in await db.query('gamedata_manifest'))
        '${r['key']}': '${r['value']}',
    };
    await File(p.join(out.path, 'gamedata_manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'game': 'endfield',
        'database': {'fileName': '${Game.endfield.dbFileName}.gz'},
        'manifest': manifest,
      }),
    );
    log('done: $dbPath');
    log('story lines ${manifest['story_line_count']}, records '
        '${manifest['normalized_record_count']}, entities ${manifest['entity_count']}');
  } finally {
    await db.close();
  }
}
