import 'package:arklores/core/gamedata/build/story_naming.dart';
import 'package:flutter_test/flutter_test.dart';

String _clean(Object? v) => v == null ? '' : '$v'.trim();

StoryNamer _namer({
  Map<String, StoryHint> hints = const {},
  Map<String, String> readBy = const {},
  Map<String, String> levelNames = const {},
  Map<String, String> stageNames = const {},
}) {
  const stages = [
    StageRef('stage:actx_01', 'actx_01', '第一关', 'X-1'),
    StageRef('stage:actx_02', 'actx_02', '第二关', 'X-2'),
    StageRef('stage:actx_tr01', 'actx_tr01', '练习之一', 'X-TR-1'),
    StageRef('stage:acty_01', 'acty_01', '另一活动的关', 'Y-1'),
  ];
  return StoryNamer(
    hints: hints,
    readBy: readBy,
    stages: stages,
    collectionOfStage: {
      'stage:actx_01': 'actx',
      'stage:actx_02': 'actx',
      'stage:actx_tr01': 'actx',
      'stage:acty_01': 'acty',
    },
    levelNames: levelNames,
    stageNames: stageNames,
  );
}

void main() {
  group('a story file is named after the stage it belongs to', () {
    test('a training file belongs to the training stage, not the chapter stage',
        () {
      final n = _namer().resolve(
        'activities/actx/training/training_actx_01_a.txt',
        collectionId: 'actx',
      )!;
      expect(n.name, '练习之一 · 训练 1');
      expect(n.stageEntryId, 'stage:actx_tr01');
      expect(n.fromTables, isTrue);
    });

    test('a training file without a training stage stays unbound', () {
      final n = _namer().resolve(
        'activities/acty/training/training_acty_01_a.txt',
        collectionId: 'acty',
      );
      expect(n, isNull);
    });

    test('a level file keeps its place: stage, then 行动前/行动后', () {
      final n = _namer().resolve(
        'activities/actx/level_actx_02_end.txt',
        collectionId: 'actx',
      )!;
      expect(n.name, '第二关 · 行动后');
      expect(n.stageEntryId, 'stage:actx_02');
    });

    test('digits meet digits however they are padded', () {
      final n = _namer().resolve(
        'activities/actx/level/actx_1_a.txt',
        collectionId: 'actx',
      )!;
      expect(n.stageEntryId, 'stage:actx_01');
      expect(n.name, '第一关 · 1');
    });

    test('a stage of another collection is not taken', () {
      final n = _namer().resolve(
        'activities/acty/level_acty_02_beg.txt',
        collectionId: 'acty',
      );
      expect(n, isNull);
    });

    test('stage names by id and by level file need no entry', () {
      final byId = _namer(stageNames: {'guide_01': '开始之前'}).resolve(
        'obt/tutorial/level/guide_01_a.txt',
      )!;
      expect(byId.name, '开始之前 · 教程 1');
      expect(byId.stageEntryId, isNull);
      final byLevel = _namer(levelNames: {'level_box_tr03': '工具训练'}).resolve(
        'obt/box/traininglevel/level_box_tr03_2.txt',
      )!;
      expect(byLevel.name, startsWith('工具训练'));
    });
  });

  group('names the tables give', () {
    test('a hint beats the stage; a reading entry names its story', () {
      final n = _namer(
        hints: {'obt/x/endbook/p1': const StoryHint('逃避', group: '某结局')},
        readBy: {'obt/x/book/b1': '书名'},
      );
      expect(n.resolve('obt/x/endbook/p1.txt')!.name, '逃避');
      expect(n.resolve('obt/x/endbook/p1.txt')!.group, '某结局');
      expect(n.resolve('Obt/X/Book/B1.txt')!.name, '书名');
    });

    test('roguelike ending books and month chats', () {
      final hints = roguelikeStoryHints({
        'details': {
          'topic_a': {
            'monthSquad': {
              'sq1': {'chatId': 'chat_1', 'teamName': '联谊会'},
            },
            'archiveComp': {
              'endbook': {
                'endbook': {
                  'end_1': {
                    'endingId': 'ee1',
                    'title': '结局一',
                    'sortId': 1,
                    'avgId': 'Obt/Roguelike/RO/ending_1',
                    'clientEndbookItemDatas': [
                      {
                        'sortId': 2,
                        'endbookName': '篇名',
                        'textId': 'Obt/Rogue/a/Endbook/eb_1_2',
                      },
                    ],
                  },
                },
              },
              'chat': {
                'chat': {
                  'chat_1': {
                    'sortId': 1,
                    'chatItemList': [
                      {
                        'floor': 3,
                        'chatDesc': null,
                        'chatStoryId': 'Obt/Rogue/chat_1/c_3',
                      },
                      {
                        'floor': 5,
                        'chatDesc': '这一层',
                        'chatStoryId': 'Obt/Rogue/chat_1/c_5',
                      },
                    ],
                  },
                },
              },
            },
          },
        },
      }, _clean,);
      expect(hints['obt/roguelike/ro/ending_1']!.name, '结局一');
      expect(hints['obt/rogue/a/endbook/eb_1_2']!.name, '篇名');
      expect(hints['obt/rogue/a/endbook/eb_1_2']!.group, '结局一');
      expect(hints['obt/rogue/chat_1/c_3']!.name, '第3层');
      expect(hints['obt/rogue/chat_1/c_3']!.group, '联谊会');
      expect(hints['obt/rogue/chat_1/c_5']!.name, '这一层');
      // Each file names the entry it is part of; the ending's own story
      // sorts after the pages of its book.
      expect(
        hints['obt/rogue/a/endbook/eb_1_2']!.parent,
        'roguelike_ending:topic_a/ee1',
      );
      expect(
        hints['obt/roguelike/ro/ending_1']!.parent,
        'roguelike_ending:topic_a/ee1',
      );
      expect(
        hints['obt/roguelike/ro/ending_1']!.sort!,
        greaterThan(hints['obt/rogue/a/endbook/eb_1_2']!.sort!),
      );
      expect(
        hints['obt/rogue/chat_1/c_3']!.parent,
        'roguelike_squad:topic_a/sq1',
      );
    });

    test('sandbox dialogs take the name of the NPC, levels their stage name',
        () {
      final r = sandboxStoryNames({
        'detail': {
          'npcs': {
            'npc1': {
              'picName': '旅人',
              'dialogIds': {'REACT': 'dlg_1'},
            },
          },
          'dialogs': {
            'dlg_1': {'dialogId': 'dlg_1', 'avgId': 'Obt/Box/Avg/dlg_1'},
          },
          'stages': {
            's1': {'stageId': 's1', 'levelId': 'Obt/Box/level_box_tr01', 'name': '采掘训练'},
          },
        },
      }, _clean,);
      expect(r.hints['obt/box/avg/dlg_1']!.name, '旅人');
      expect(r.levelNames['level_box_tr01'], '采掘训练');
    });
  });

  group('files that only have a kind', () {
    test('are numbered in natural order, per kind', () {
      final out = numberedKinds([
        'obt/guide/box/g_10.txt',
        'obt/guide/box/g_2.txt',
        'obt/tutorial/t_1.txt',
      ]);
      expect(out['obt/guide/box/g_2.txt']!.name, '指引 1');
      expect(out['obt/guide/box/g_10.txt']!.name, '指引 2');
      expect(out['obt/tutorial/t_1.txt']!.name, '教程');
    });

    test('the kind comes from words in the path', () {
      expect(storyKindLabel('activities/a/training/training_a_01_a'), '训练');
      expect(storyKindLabel('obt/rogue/r/endbook/e_1'), '结局文集');
      expect(storyKindLabel('obt/x/y/z'), '剧情');
      expect(storyKindLabel('obt/roguelike/r1/level_rogue1_entry'), '开局剧情');
      expect(storyKindLabel('activities/a/guide_a_entry'), '指引');
    });
  });
}
