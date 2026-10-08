// A small ArknightsGameData-shaped source tree: three characters, one item
// and five chapters of one fictional activity. Paths are from the
// repository root (`zh_CN/gamedata/...`). The build, coverage and update
// tests all start from it.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const fixtureStoryDir = 'zh_CN/gamedata/story/activities/act_fixture';

/// Paths of the tables every build reads; they are present (empty) so the
/// importer finds a complete tree.
const _emptyTables = [
  'skin_table',
  'medal_table',
  'uniequip_table',
  'enemy_handbook_table',
  'stage_table',
  'zone_table',
  'campaign_table',
  'activity_table',
  'retro_table',
  'mission_table',
  'roguelike_table',
  'roguelike_topic_table',
  'sandbox_table',
  'sandbox_perm_table',
];

Map<String, dynamic> _character(String name, String description) => {
      'name': name,
      'appellation': '',
      'displayNumber': '',
      'description': description,
      'itemUsage': '',
      'itemDesc': '',
    };

/// The fixture files: path → content. Chapter 1 foreshadows without the
/// victim's name, chapters 2–3 point at 角色A (chapter 2 is 40 lines of one
/// speaker), chapter 4 brings the victim and 角色B together, chapter 5 is
/// 角色B's reveal.
Map<String, String> fixtureSource() {
  const excel = 'zh_CN/gamedata/excel';
  final c2 = StringBuffer();
  for (var i = 1; i <= 40; i++) {
    c2.writeln('[name="角色A"]这是第$i次否认，我什么都没做。');
  }
  return {
    '$excel/character_table.json': jsonEncode({
      'char_victim': _character('受害者', '测试受害者角色。'),
      'char_a': _character('角色A', '误导角色。'),
      'char_b': _character('角色B', '真相角色。'),
    }),
    '$excel/handbook_info_table.json': jsonEncode({'handbookDict': <String, dynamic>{}}),
    '$excel/charword_table.json': jsonEncode({'charWords': <String, dynamic>{}}),
    '$excel/item_table.json': jsonEncode({
      'items': {
        'item_001': {'id': 'item_001', 'name': '源石', 'description': '源石是泰拉世界的基石。'},
      },
    }),
    for (final name in _emptyTables) '$excel/$name.json': '{}',
    '$fixtureStoryDir/level_fixture_c1.txt':
        '[name="旁白"]那天夜里，染血的匕首在灰烬里闪着寒光。\n[name="角色A"]我什么都没看见。\n',
    '$fixtureStoryDir/level_fixture_c2.txt': '$c2',
    '$fixtureStoryDir/level_fixture_c3.txt': '[name="角色A"]受害者已经死亡，我亲眼看见那场死亡。\n',
    '$fixtureStoryDir/level_fixture_c4.txt':
        '[name="受害者"]我会回来的。\n[name="角色B"]匕首一直在我这里。\n',
    '$fixtureStoryDir/level_fixture_c5.txt':
        '[name="角色B"]当年我藏起匕首，是为了掩盖那场死亡的真相。\n',
  };
}

/// Writes [files] under [root] and returns [root].
Directory writeSourceTree(Directory root, Map<String, String> files) {
  for (final MapEntry(key: path, value: content) in files.entries) {
    final file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content, flush: true);
  }
  return root;
}
