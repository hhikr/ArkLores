// A mission's conversations laid out along its steps from level data (the
// shapes of the client's mission definitions and level scripts; ids and
// places made up).
import 'dart:typed_data';

import 'package:arklores/core/gamedata/build/endfield/endfield_level_data.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_story_order.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart' show searchableLinesFilter, storyKindLabel, unsearchedLineKinds;
import 'package:arklores/core/gamedata/story_line_search.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> step(String id, {List<String> prev = const [], (double, double, double)? at, String? names, String? tracks}) => {
      'questId': id,
      'prevQuestIdList': prev,
      'objectiveList': [
        {
          'description': {'key': 'goal_$id'},
          'condition': names == null ? <String, dynamic>{} : {'_dialogId': {'constValue': names}},
          'trackingInfoList': [
            if (at != null) {'sceneId': 'lv1', 'trackingPos': {'x': at.$1, 'y': at.$2, 'z': at.$3}},
            if (tracks != null) {'sceneId': 'lv1', 'npcProxyId': tracks},
          ],
        },
      ],
    };

LevelScript script(String id, List<(String, Vec3)> plays, {Map<String, Vec3> objects = const {}}) {
  final s = LevelScript('lv1/$id.json');
  for (final (i, (c, at)) in plays.indexed) {
    s.chains.add(ScriptChain(
      root: i + 1,
      items: [c],
      depth: {c: 0},
      trigger: at,
      size: 3,
      sphere: 0,
      after: const [],
      quest: const [],
    ),);
  }
  s.entities.addAll(objects);
  return s;
}

void main() {
  test('step headings are neither embedded nor found by any search', () {
    expect(unsearchedLineKinds, headingLineKinds);
    expect(unembeddedLineKinds, containsAll(unsearchedLineKinds));
    expect(breakLineKinds, containsAll(unsearchedLineKinds));
    // the agent's tools show them as headings, not as narration
    for (final k in headingLineKinds) {
      expect(storyKindLabel(k), isNotNull, reason: k);
    }
  });

  test('a keyword search does not find a step heading', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE story_lines (story_id TEXT, line_index INTEGER, speaker TEXT, content TEXT, kind TEXT)');
    await db.execute('CREATE TABLE story_scopes (story_id TEXT, scope_type TEXT, scope_id TEXT)');
    for (final (i, (kind, speaker, content)) in [
      ('step', null, '与甲交谈'),
      ('dialogue', '乙', '甲去哪儿了？'),
      ('stage', null, '甲的任务'),
    ].indexed) {
      await db.insert('story_lines', {'story_id': 's1', 'line_index': i, 'speaker': speaker, 'content': content, 'kind': kind});
    }
    final hits = await queryStoryLinesLike(db, ['甲']);
    expect([for (final h in hits) for (final l in h.lines) l.content], ['甲去哪儿了？']);
    expect(await searchableLinesFilter(db), contains('NOT IN'));
    await db.close();
  });

  test('an LZ4 block: literals, then a match copying what came before', () {
    // "abc" as literals, then a match of 6 bytes from 3 back: "abcabcabc".
    final block = Uint8List.fromList([0x32, 0x61, 0x62, 0x63, 0x03, 0x00]);
    expect(String.fromCharCodes(lz4Block(block, 9)), 'abcabcabc');
  });

  test('steps follow the steps each one waits for, not their numbers alone', () {
    final m = {
      'questDic': {
        'tm1_q#2': step('tm1_q#2', prev: ['tm1_q#3']),
        'tm1_q#1': step('tm1_q#1'),
        'tm1_q#3': step('tm1_q#3', prev: ['tm1_q#1']),
      },
    };
    expect(EndfieldStoryOrder.orderedSteps(m), ['tm1_q#1', 'tm1_q#3', 'tm1_q#2']);
  });

  group('placing conversations along the route', () {
    final data = EndfieldLevelData.empty();
    // Route: (0,0,0) → (100,0,0) → (100,100,0).
    data.scripts['lv1/1001.json'] = script('1001', [('radio_tm1_1', (50.0, 1.0, 0.0)), ('dlg_tm1_1', (10.0, 0.0, 0.0))]);
    data.scripts['lv1/1002.json'] = script('1002', [('radio_tm1_2', (100.0, 50.0, 0.0))]);
    // an object right at the second step's target, where the third begins
    data.scripts['lv1/1003.json'] = script('1003', const [], objects: {'radio_tm1_4': (101.0, 2.0, 0.0)});
    data.proxies['npc_a'] = (level: 'lv1', pos: (100.0, 100.0, 0.0), envTalks: const []);
    data.proxySays['npc_a'] = ['dlg_tm1_5', 'dlg_tm1_6'];
    final mission = {
      'missionId': 'tm1',
      'questDic': {
        'tm1_q#1': step('tm1_q#1', at: (0, 0, 0)),
        'tm1_q#2': step('tm1_q#2', prev: ['tm1_q#1'], at: (100, 0, 0)),
        'tm1_q#3': step('tm1_q#3', prev: ['tm1_q#2'], at: (100, 100, 0), tracks: 'npc_a'),
      },
    };
    final ids = {'radio_tm1_1', 'dlg_tm1_1', 'radio_tm1_2', 'radio_tm1_4', 'dlg_tm1_5', 'dlg_tm1_6'};
    final order = EndfieldStoryOrder(
      data,
      mission: (id) => id == 'tm1' ? mission : null,
      conversationMission: {for (final c in ids) c: 'tm1'},
      stepName: (s) => '${s['questId']}',
    );
    final items = order.build('tm1', ids, const {});
    List<String> layout() => [
          for (final it in items)
            switch (it) {
              StepItem() => '# ${it.text ?? ''}',
              ConversationItem() => it.id,
              NestItem() => '> ${it.mission}',
            },
        ];

    test('each goes to the step whose route passes nearest, in route order', () {
      expect(layout(), [
        '# tm1_q#1',
        '# tm1_q#2',
        'dlg_tm1_1',
        'radio_tm1_1',
        'radio_tm1_4',
        'dlg_tm1_5',
        '# tm1_q#3',
        'radio_tm1_2',
        'dlg_tm1_6',
      ]);
    });

    test('every place says why', () {
      final notes = {for (final it in items.whereType<ConversationItem>()) it.id: it.note};
      expect(notes['radio_tm1_4'], contains('目标处'));
      expect(notes['dlg_tm1_5'], contains('前一个状态'));
      expect(notes['dlg_tm1_6'], contains('点名'));
    });
  });
}
