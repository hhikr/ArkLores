// Writes what the story order reads from the Endfield level data as one JSON
// file, so two readings (the client's binary dump and AKEDatabase's JSON) can
// be compared script by script:
//
//   dart run tools/dump_endfield_level_data.dart --data=<Data/Json> \
//     --missions=<MissionRuntimeAsset dir> --out=<file.json>
import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/endfield/endfield_level_data.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_stories.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    for (final a in args) {
      if (a.startsWith('--$name=')) return a.substring(name.length + 3);
    }
    return null;
  }

  final defs = EndfieldStoryImporter.loadMissionDefinitions(Directory(arg('missions')!));
  final data = EndfieldLevelData.read(
    Directory(arg('data')!),
    questIds: {for (final d in defs.values) ...((d['questDic'] as Map?) ?? const {}).keys.map((k) => '$k')},
    missionIds: defs.keys.toSet(),
  );
  Object? v(Vec3? x) => x == null ? null : [x.$1, x.$2, x.$3];
  final out = {
    'scripts': {
      for (final s in data.scripts.values)
        s.key: {
          'chains': [
            for (final c in s.chains)
              {
                'root': c.root,
                'items': c.items,
                'depth': c.depth,
                'trigger': v(c.trigger),
                'size': c.size,
                'sphere': c.sphere,
                'after': c.after,
                'quest': c.quest,
              },
          ],
          'entities': {for (final e in s.entities.entries) e.key: v(e.value)},
          'npcs': s.npcs,
          'waits': {for (final e in s.waits.entries) '${e.key}': {'after': e.value.after, 'quest': e.value.quest}},
          'chainInfo': {
            for (final e in s.chainInfo.entries)
              '${e.key}': {'header': e.value.header, 'staged': e.value.staged, 'gait': e.value.gait, 'npcs': e.value.npcs},
          },
          'moves': s.moves,
          'stages': s.stages,
        },
    },
    'segments': {
      for (final e in data.segments.entries)
        e.key: [
          for (final x in e.value)
            {
              'when': x.when,
              'arg': x.arg,
              'cond': x.cond == null ? null : [x.cond!.$1, x.cond!.$2, x.cond!.$3],
              'on': x.on,
              'by': x.by,
            },
        ],
    },
    'subData': {
      for (final e in data.subData.entries)
        e.key: [
          for (final x in e.value)
            {'file': x.file, 'pos': v(x.pos), 'questsBefore': x.questsBefore, 'zone': x.zone, 'zoneStep': x.zoneStep},
        ],
    },
    'groups': {
      for (final e in data.groups.entries)
        e.key: [
          for (final x in e.value) {'owner': x.owner, 'mission': x.mission, 'op': x.op, 'state': x.state, 'file': x.file},
        ],
    },
  };
  await File(arg('out')!).writeAsString(const JsonEncoder.withIndent(' ').convert(out));
  stdout.writeln('scripts ${data.scripts.length}, segments ${data.segments.length}, '
      'sub-data ${data.subData.length}, groups ${data.groups.length}');
}
