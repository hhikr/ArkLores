import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/endfield/endfield_level_data.dart';
import 'package:arklores/core/gamedata/build/endfield/endfield_stories.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/temp_dir.dart';

Map<String, Object?> _c(Object? v) => {'constValue': v, 'm_variableBind': false};

/// A level the way the decoded JSON has it, with made-up ids. Enums are
/// names in one place and numbers in another: both sources occur.
void _writeLevel(Directory root) {
  void write(String path, Object json) {
    final f = File('${root.path}/$path');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(json));
  }

  write('GameplayConfig/WorldEntityRegistry.json', {
    'npcProxyBriefInfos': {
      '700': {'proxyId': 'npc_a', 'segmentIdGlobal': 700},
    },
    'worldEntityBriefInfos': {'800': <String, Object>{}},
  });
  write('GameplayConfig/NpcProxyTable.json', {
    'dataTable': {
      'npc_a': {'levelId': 'lv1', 'position': {'x': 1, 'y': 0, 'z': 1}, 'envTalkIds': <String>[]},
    },
  });
  write('GameplayConfig/NpcProxyExDataTable.json', {'data': <String, Object>{}});
  write('GameplayConfig/AtmosphericNpcClusterDataTable.json', {'dataTable': <String, Object>{}});
  write('GameplayConfig/MissionAreaTable.json', {'m_areas': <String, Object>{}});
  write('LevelScriptData/lv1/100.json', {
    'scriptId': 100,
    'actionMap': {
      'dataMap': {
        'headerList': [
          {
            r'$type': 'Beyond.Gameplay.Actions.ScriptEvent.OnLeaderEnterTriggerVolume, Gameplay.Beyond',
            '_ID': 1,
            '_nextID': 2,
            '_triggerSlotIdFilter': _c(80001),
          },
          {
            r'$type': 'Beyond.Gameplay.Actions.LevelEvent.OnDialogExit, Gameplay.Beyond',
            '_ID': 10,
            '_nextID': 11,
            '_filteredDialogId': _c('dlg_m1_1'),
          },
          {r'$type': 'Beyond.Gameplay.Actions.ScriptEvent.OnScriptActive, Gameplay.Beyond', '_ID': 30, '_nextID': 4},
        ],
        'actionList': [
          {r'$type': 'Beyond.Gameplay.Actions.SetEnablePlayerMove, Gameplay.Beyond', '_ID': 2, '_nextID': 3},
          {r'$type': 'Beyond.Gameplay.Actions.StartDialogAction, Gameplay.Beyond', '_ID': 3, '_nextID': 4, '_dialogId': _c('dlg_m1_1')},
          {
            r'$type': 'Beyond.Gameplay.Actions.IfElseAction, Gameplay.Beyond',
            '_ID': 4,
            '_condition': {'idRef': 20, 'constValue': false},
            '_onTrueID': 5,
            '_onFalseID': 6,
          },
          {r'$type': 'Beyond.Gameplay.Actions.PlayRadio, Gameplay.Beyond', '_ID': 5, '_radioId': _c('radio_m1_2')},
          {
            r'$type': 'Beyond.Gameplay.Actions.ShowSceneDecorationNew, Gameplay.Beyond',
            '_ID': 6,
            '_visible': _c(true),
            '_targetDynamicEntity': _c(1200000001),
          },
          {
            r'$type': 'Beyond.Gameplay.Actions.CheckBoolIfTrue, Gameplay.Beyond',
            '_ID': 11,
            '_nextID': 12,
            '_value': {'idRef': 21, 'constValue': false},
          },
          {r'$type': 'Beyond.Gameplay.Actions.WaitForNpcProxyReady, Gameplay.Beyond', '_ID': 12, '_nextID': 13, '_npcProxyId': _c('npc_a')},
          {r'$type': 'Beyond.Gameplay.Actions.StartDialogAction, Gameplay.Beyond', '_ID': 13, '_dialogId': _c('dlg_m1_3')},
        ],
        'getterList': [
          {
            r'$type': 'Beyond.Gameplay.Actions.CheckMissionOrQuestIsComplete, Gameplay.Beyond',
            '_ID': 20,
            '_missionId': _c('m1_q#1'),
          },
          {
            r'$type': 'Beyond.Gameplay.Actions.StringEqual, Gameplay.Beyond',
            '_ID': 21,
            '_valueB': _c('dlg_m1_9'),
          },
        ],
      },
    },
    'triggerVolumes': {
      '80001': {
        'slotId': 80001,
        'shapeList': [
          {'position': {'x': 10.004, 'y': 2, 'z': 3}, 'shapeType': 2, 'radius': 12.0, 'size': {'x': 3, 'y': 3, 'z': 3}},
        ],
      },
    },
    'interactives': {
      '40001': {
        'position': {'x': 5, 'y': 0, 'z': 5},
        'componentProperties': {
          'NarrativeComponent': [
            {'key': 'dlg_finish_id', 'value': {'valueArray': [{'valueString': 'dlg_m1_4'}]}},
          ],
        },
      },
    },
  });
  write('LevelData/lv1/lv1_lv_data_sub_m1.json', {
    'interactives': [
      {
        'levelLogicId': 800,
        'position': {'x': 7, 'y': 0, 'z': 7},
        'progressLockCondition': {
          r'$type': 'Beyond.Gameplay.SimpleConditionCheckQuestState, Gameplay.Beyond',
          'questId': 'm1_q#2',
          'compareOperator': 'Equal',
          'compareTarget': 'Processing',
        },
        'componentProperties': {
          'NarrativeComponent': [
            {'key': 'dlg', 'value': {'valueArray': [{'valueString': 'dlg_m1_5'}]}},
          ],
        },
      },
    ],
    'npcs': [
      {
        'levelLogicId': 700,
        'progressLockCondition': {
          r'$type': 'Beyond.Gameplay.SimpleConditionCheckMissionState, Gameplay.Beyond',
          'missionId': 'm1',
          'compareOperator': 0,
          'compareTarget': 3,
        },
      },
    ],
    'airWalls': [
      {
        'pushBackRadioId': 'radio_m1_6',
        'checkData': {
          'missionData': {
            'riseReason': [
              {'id': 'm1_q#2', 'isQuest': true, 'detailState': 2},
            ],
          },
        },
      },
    ],
  });
}

void main() {
  late Directory root;
  late EndfieldLevelData data;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('ef_level_json');
    _writeLevel(root);
    data = EndfieldLevelData.read(root, questIds: {'m1_q#1', 'm1_q#2'}, missionIds: {'m1'});
  });
  tearDownAll(() => deleteTempDir(root));

  test('a chain plays its conversations in order from its header, with its trigger area', () {
    final script = data.scripts['lv1/100.json']!;
    final entered = script.chains.firstWhere((c) => c.items.contains('dlg_m1_1'));
    expect(entered.items, ['dlg_m1_1', 'radio_m1_2']);
    expect(entered.trigger, (10.0, 2.0, 3.0));
    expect(entered.sphere, 12.0);
    expect(script.chainInfo[2]!.header, 'ScriptEvent_OnLeaderEnterTriggerVolume');
    expect(script.chainInfo[2]!.staged, isTrue);
  });

  test('what a chain waits for comes from its header and its conditions, not what it plays', () {
    final script = data.scripts['lv1/100.json']!;
    final after = script.chains.firstWhere((c) => c.items.contains('dlg_m1_3'));
    expect(after.items, ['dlg_m1_3']);
    expect(after.after, containsAll(['dlg_m1_1', 'dlg_m1_9']));
    expect(script.chainInfo[11]!.npcs, ['npc_a']);
  });

  test('a property name is not a conversation', () {
    expect(data.scripts['lv1/100.json']!.entities.keys, ['dlg_m1_4']);
  });

  test('a segment switch keeps the branch of the step condition it sits in', () {
    final s = data.segments['1200000001']!.single;
    expect(s.when, 'active');
    expect(s.on, isTrue);
    expect(s.cond, ('CheckMissionOrQuestIsComplete', 'm1_q#1', 'else'));
  });

  test('sub-data: an object with its condition, an air wall radio zone with its step', () {
    final object = data.subData['dlg_m1_5']!.single;
    expect(object.pos, (7.0, 0.0, 7.0));
    expect(object.questsBefore, ['m1_q#2']);
    final zone = data.subData['radio_m1_6']!.single;
    expect(zone.zone, isTrue);
    expect(zone.zoneStep, 'm1_q#2');
  });

  test('a mission type written as a name means the number the tables are keyed by', () {
    expect(EndfieldStoryImporter.missionTypeNumber('Side'), 10);
    expect(EndfieldStoryImporter.missionTypeNumber(10), 10);
    expect(EndfieldStoryImporter.missionTypeNumber('NoSuchType'), -1);
    expect(EndfieldStoryImporter.missionTypeNumber(null), -1);
  });

  test('entity groups from the entities’ conditions, known entities only', () {
    expect(data.groups['700']!.single, (owner: 'm1', mission: true, op: 0, state: 3, file: 'lv1/lv1_lv_data_sub_m1.json'));
    expect(data.groups['800']!.single.owner, 'm1_q#2');
    expect(data.strings, contains('dlg_m1_9'));
  });
}
