import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/build/arknights_importer.dart';
import 'package:arklores/core/gamedata/build/entry_importer.dart'
    show EntryTables;
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/build/story_catalog_importer.dart';
import 'package:arklores/core/gamedata/build/text_harvest.dart';
import 'package:arklores/core/gamedata/story_catalog.dart'
    show queryCatalogEntries;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

/// 0.11 entry layer: entries owned by collections, deterministic bindings
/// and the rule that gameplay text is not imported. Fixture names are
/// fictional; assertions check generic behaviour only.
void main() {
  sqfliteFfiInit();

  group('text harvest', () {
    test('keeps narrative under narrative keys and drops gameplay text', () {
      final texts = harvestNarrative({
        'newsInfoList': {
          'n1': {
            'newsText': '今天的新闻正文写得很长，用来说明一件发生过的事情。',
            'newsFormat': 'F1',
          },
        },
        'taskData': {
          't1': {'desc': '完成指定关卡并获得奖励的任务说明，不属于故事文本。'},
        },
        'misc': {
          'tip': '在场干员的攻击力提升20%，持续10秒。',
          'note': '这是一段没有任何关键词的长文字，它写成了完整的句子，有逗号，也有句号，而且比较长，足以被当作叙事文字。',
        },
      });
      expect(texts.map((t) => t.text), [
        '今天的新闻正文写得很长，用来说明一件发生过的事情。',
        '这是一段没有任何关键词的长文字，它写成了完整的句子，有逗号，也有句号，而且比较长，足以被当作叙事文字。',
      ]);
    });

    test('a gameplay structure is dropped by the name it is stored under', () {
      final texts = harvestNarrative(
        {'x': '一段写得足够长的文字，有逗号，也有句号，但它在任务结构里面。'},
        rootKey: 'taskDataMap',
      );
      expect(texts, isEmpty);
    });

    test('mechanical text is recognised from content', () {
      expect(isMechanical('每秒回复3点生命'), isTrue);
      expect(isMechanical('【某某】战斗开始时获得护盾'), isTrue);
      expect(isMechanical('一个能装很多东西的罐子'), isFalse);
    });

    test('gameplay hint lines are removed from descriptions', () {
      expect(
        cleanDescription('关卡的背景描述。\\n<@lv.item>机制提示</>'),
        '关卡的背景描述。',
      );
    });

    test('splitText keeps lines whole', () {
      final pieces = splitText('${'甲' * 10}\n${'乙' * 10}', max: 12);
      expect(pieces, ['甲' * 10, '乙' * 10]);
    });
  });

  group('entry layer in a database', () {
    late Directory dir;
    late Database db;
    late BuildStats stats;
    late ArknightsImporter importer;

    Future<void> writeJson(String rel, Object? value) async {
      final f = File(p.join(dir.path, 'src', 'zh_CN', 'gamedata', rel));
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(value));
    }

    Future<void> writeText(String rel, String text) async {
      final f = File(p.join(dir.path, 'src', 'zh_CN', 'gamedata', rel));
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_entry_test');
      await writeJson('excel/character_table.json', {
        'char_fx_1': {
          'name': '虚构干员',
          'description': '一名虚构的干员。',
          'displayNumber': 'FX01',
          'profession': 'PIONEER',
        },
        'token_fx_1': {
          'name': '虚构召唤物',
          'description': '一个召唤物的设定描述。',
          'profession': 'TOKEN',
        },
        'trap_fx_1': {
          'name': '虚构装置',
          'description': '一个装置的设定描述。',
          'profession': 'TRAP',
        },
      });
      await writeJson('excel/handbook_info_table.json', {
        'handbookDict': {
          'char_fx_1': {
            'storyTextAudio': [
              {
                'storyTitle': '档案资料一',
                'stories': [
                  {'storyText': '虚构干员的档案正文。'},
                ],
              },
            ],
          },
        },
        'handbookStageData': {
          'mem_fx_1': {
            'charId': 'char_fx_1',
            'stageId': 'mem_fx_1',
            'code': 'mem_fx_1',
            'name': '密录关',
            'description': '密录关的描述。\\n<@lv.item>只是提示</>',
          },
        },
      });
      await writeJson('excel/charword_table.json', {
        'charWords': {
          'w1': {
            'charWordId': 'w1',
            'charId': 'char_fx_1',
            'voiceTitle': '问候',
            'voiceText': '你好。',
          },
        },
      });
      await writeJson('excel/zone_table.json', {
        'zones': {
          'main_0': {
            'zoneID': 'main_0',
            'type': 'MAINLINE',
            'zoneIndex': 0,
            'zoneNameFirst': '序章',
            'zoneNameSecond': '虚构之始',
          },
          'act_fx_zone1': {
            'zoneID': 'act_fx_zone1',
            'type': 'ACTIVITY',
            'zoneNameFirst': '虚构区',
          },
          'weekly_1': {
            'zoneID': 'weekly_1',
            'type': 'WEEKLY',
            'zoneNameFirst': '每周',
          },
        },
      });
      await writeJson('excel/activity_table.json', {
        'basicInfo': {
          'act_fx': {
            'id': 'act_fx',
            'name': '虚构活动',
            'startTime': 1600000000,
            'type': 'TYPE_FX',
          },
          'act1fxhub': {
            'id': 'act1fxhub',
            'name': '虚构展',
            'startTime': 1600000001,
            'type': 'TYPE_FX',
          },
        },
        'zoneToActivity': {'act_fx_zone1': 'act_fx'},
        'activity': {
          'TYPE_FX': {
            'act_fx': {
              'newsInfoList': {
                'news_1': {
                  'newsText': '虚构活动期间发布的新闻，用来测试叙事文字的收集，写得足够长。',
                },
              },
              'taskData': {
                't1': {'desc': '通关关卡并获得奖励的任务说明，写得也很长，但属于玩法。'},
              },
            },
          },
        },
      });
      await writeJson('excel/stage_table.json', {
        'stages': {
          'main_00-01': {
            'stageId': 'main_00-01',
            'stageType': 'MAIN',
            'zoneId': 'main_0',
            'code': '0-1',
            'name': '虚构一关',
            'description': '主线关卡的描述。',
            'levelId': 'Obt/Main/level_main_00-01',
          },
          'fx_01': {
            'stageId': 'fx_01',
            'stageType': 'ACTIVITY',
            'zoneId': 'act_fx_zone1',
            'code': 'FX-1',
            'name': '虚构活动关',
            'description': '活动关卡的描述。',
            'levelId': 'Activities/act_fx/level_fx_01',
          },
          'weekly_stage': {
            'stageId': 'weekly_stage',
            'stageType': 'DAILY',
            'zoneId': 'weekly_1',
            'code': 'W-1',
            'name': '每周关',
            'description': '玩法关卡。',
            'levelId': 'Obt/Weekly/level_weekly',
          },
        },
      });
      await writeJson('excel/enemy_handbook_table.json', {
        'raceData': <String, Object?>{},
        'enemyData': {
          'enemy_fx_a': {
            'enemyId': 'enemy_fx_a',
            'enemyIndex': 'A1',
            'name': '虚构敌人甲',
            'enemyLevel': 'BOSS',
            'description': '甲的设定描述。',
            'abilityList': [
              {'text': '攻击时造成额外伤害', 'textFormat': 'NORMAL'},
            ],
          },
          'enemy_fx_b': {
            'enemyId': 'enemy_fx_b',
            'enemyIndex': 'A2',
            'name': '虚构敌人乙',
            'enemyLevel': 'NORMAL',
            'description': '乙的设定描述。',
          },
        },
      });
      await writeJson('levels/obt/main/level_main_00-01.json', {
        'enemyDbRefs': [
          {'id': 'enemy_fx_a'},
        ],
        'waves': <Object?>[],
      });
      await writeJson('levels/activities/act_fx/level_fx_01.json', {
        'enemyDbRefs': <Object?>[],
        'waves': [
          {
            'fragments': [
              {
                'actions': [
                  {'actionType': 'SPAWN', 'key': 'enemy_fx_a'},
                  {'actionType': 'SPAWN', 'key': 'enemy_fx_b'},
                  {'actionType': 'WAIT', 'key': 'enemy_not_a_spawn'},
                ],
              },
            ],
          },
        ],
      });
      await writeJson('levels/obt/r/level_fx_1-2.json', {
        'enemyDbRefs': [
          {'id': 'enemy_fx_b'},
        ],
        'waves': <Object?>[],
      });
      await writeJson('excel/roguelike_topic_table.json', {
        'topics': {
          'rogue_fx': {
            'id': 'rogue_fx',
            'name': '虚构肉鸽',
            'startTime': 1,
            'lineText': '这是虚构肉鸽的一小段介绍。',
          },
        },
        'details': {
          'rogue_fx': {
            'endings': {
              'end_a': {'id': 'end_a', 'name': '某结局', 'desc': '结局的一句话。'},
            },
            'monthSquad': {
              'sq1': {
                'id': 'sq1',
                'teamName': '小队甲',
                'teamFlavorDesc': 'Hello There',
                'teamDes': '小队的一句话。',
                'teamYear': '2026',
                'teamMonth': '07',
                'teamIndex': '1',
                'teamChars': [
                  {'teamCharId': 'char_fx_1'},
                ],
                'chatId': 'chat_1',
              },
            },
            'archiveComp': {
              'endbook': {
                'endbook': {
                  'eb': {
                    'endingId': 'end_a',
                    'title': '某结局',
                    'sortId': 1,
                    'avgId': 'Obt/Rogue/rogue_fx/ending',
                    'clientEndbookItemDatas': [
                      {
                        'textId': 'Obt/Rogue/rogue_fx/Endbook/e1',
                        'endbookName': '篇一',
                        'sortId': 1,
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
                        'floor': 1,
                        'chatDesc': '第一段',
                        'chatStoryId': 'Obt/Rogue/rogue_fx/MonthRecord/m1',
                      },
                    ],
                  },
                },
              },
            },
            'zones': {
              'zone_1': {
                'id': 'zone_1',
                'name': '区甲',
                'description': '区甲的描述。',
              },
              'zone_portal_1': {
                'id': 'zone_portal_1',
                'name': '区甲',
                'description': '区甲的描述。',
              },
            },
            'battleLoadingTips': [
              {'tip': '词语——这是对一个词语的设定解释，写得足够长。'},
              {'tip': '请规划好路线，否则将会触发追猎。'},
            ],
            'stages': {
              'st_n': {
                'name': '某关',
                'code': 'ISW-NO',
                'levelId': 'Obt/R/level_a',
                'description': '关卡描述。',
                'isElite': 0,
              },
              'st_e': {
                'name': '某关',
                'code': 'ISW-NO',
                'levelId': 'Obt/R/level_a',
                'description': '关卡描述。',
                'isElite': 1,
                'linkedStageId': 'st_n',
              },
              'st_copy': {
                'name': '某关',
                'code': 'ISW-NO',
                'levelId': 'Obt/R/level_a',
                'description': '关卡描述。',
                'isElite': 0,
              },
              'st_solo': {
                'name': '独关',
                'code': 'ISW-NO',
                'levelId': 'Obt/R/level_fx_1-2',
                'description': '另一个关卡描述。',
                'isElite': 0,
              },
            },
            'items': {
              'rogue_fx_relic_1': {
                'name': '虚构藏品',
                'description': '一件藏品的设定描述。',
                'usage': '每秒回复3点生命',
                'type': 'RELIC',
              },
              // The same collectible listed again (a variant copy).
              'rogue_fx_relic_1_b': {
                'name': '虚构藏品',
                'description': '一件藏品的设定描述。',
                'usage': '每秒回复3点生命\n变体效果',
                'type': 'RELIC',
              },
              'rogue_fx_feature_1': {
                'name': '规则替身',
                'description': '规则替身的一段中文描述文字。',
                'type': 'FEATURE',
              },
            },
            'choiceScenes': {
              'scene_1_enter': {
                'id': 'scene_1_enter',
                'title': '路口',
                'description': '一个岔路口。',
              },
              'scene_1_2': {
                'id': 'scene_1_2',
                'title': '路口',
                'description': '你向左走去。',
              },
            },
            'choices': {
              'choice_1_1': {
                'id': 'choice_1_1',
                'title': '向左走',
                'description': '获得3点生命',
                'nextSceneId': 'scene_1_2',
              },
              'choice_1_2': {
                'id': 'choice_1_2',
                'title': '向左走',
                'description': '获得3点生命',
                'nextSceneId': 'scene_1_2',
              },
              'choice_1_3': {
                'id': 'choice_1_3',
                'title': '离开',
                'nextSceneId': null,
              },
            },
          },
        },
      });
      await writeJson('excel/story_review_table.json', <String, Object?>{
        'main_0': {
          'id': 'main_0',
          'name': '虚构主线',
          'entryType': 'MAINLINE',
          'infoUnlockDatas': [
            {
              'storyCode': '0-1',
              'storyName': '开端',
              'avgTag': '行动前',
              'storySort': 1,
              'storyInfo': 'info/obt/main/level_main_00-01_beg',
              'storyTxt': 'obt/main/level_main_00-01_beg',
            },
          ],
        },
      });
      await writeText(
        'story/obt/main/level_main_00-01_beg.txt',
        '[Subtitle(text="夜幕降临。", x=1)]\n[name="甲"]你好。\n',
      );
      await writeText(
        'story/obt/rogue/rogue_fx/endbook/e1.txt',
        '[name="乙"]肉鸽里的故事。\n',
      );
      await writeText(
        'story/obt/rogue/rogue_fx/ending.txt',
        '[name="乙"]结局的故事。\n',
      );
      await writeText(
        'story/obt/rogue/rogue_fx/monthrecord/m1.txt',
        '[name="乙"]月度小故事。\n',
      );
      await writeText(
        'story/activities/fxhub/guide_fx_entry.txt',
        '[name="丙"]欢迎来到这里。\n',
      );
      await writeText(
        'story/obt/tutorial/t1.txt',
        '[PopupDialog(dialogHead="x")] 点击这里。\n',
      );

      db = await databaseFactoryFfi.openDatabase(
        p.join(dir.path, 'entry.db'),
      );
      await createGamedataSchema(db);
      stats = BuildStats();
      final source = Directory(p.join(dir.path, 'src'));
      importer = ArknightsImporter(
        sourceDir: source,
        db: db,
        stats: stats,
        storyLimit: 0,
      );
      await importer.importAll();
      await importStoryCatalog(db, source);
      await importer.entryImporter.rebuildDerived();
    });

    tearDown(() async {
      await db.close();
      await deleteTempDir(dir);
    });

    Future<List<Map<String, Object?>>> q(String sql, [List<Object?>? a]) =>
        db.rawQuery(sql, a);

    test('stories get kinds, entries and an owner', () async {
      final lines = await q(
        'SELECT kind, content FROM story_lines '
        "WHERE story_id = 'obt/main/level_main_00-01_beg.txt' "
        'ORDER BY line_index',
      );
      expect(lines.map((l) => l['kind']), ['subtitle', 'dialogue']);
      final entry = (await q(
        "SELECT * FROM entries WHERE id = 'story:obt/main/level_main_00-01_beg.txt'",
      ))
          .single;
      expect(entry['collection_id'], 'main_0');
      expect(entry['code'], '0-1');
      // Without a catalog row the owner comes from the path.
      final rogue = (await q(
        "SELECT collection_id FROM entries WHERE id = 'story:obt/rogue/rogue_fx/endbook/e1.txt'",
      ))
          .single;
      expect(rogue['collection_id'], 'rogue_fx');
      final tutorial = (await q(
        'SELECT c.kind FROM entries e JOIN collections c ON c.id = e.collection_id '
        "WHERE e.id = 'story:obt/tutorial/t1.txt'",
      ))
          .single;
      expect(tutorial['kind'], 'system');
      // Tutorial text is kept as lines but is not retrieval text.
      final tutorialRecords = await q(
        "SELECT 1 FROM normalized_records WHERE parent_id = 'obt/tutorial/t1.txt'",
      );
      expect(tutorialRecords, isEmpty);
    });

    test('a story outside the review table is labelled from the entry layer',
        () async {
      final labels = await queryCatalogEntries(db, [
        'obt/rogue/rogue_fx/endbook/e1.txt',
        'obt/main/level_main_00-01_beg.txt',
      ]);
      final rogue = labels['obt/rogue/rogue_fx/endbook/e1.txt']!;
      expect(rogue.label, startsWith('虚构肉鸽 '));
      expect(rogue.label, isNot(contains('e1')));
      // A catalogued story keeps its catalogue label.
      expect(labels['obt/main/level_main_00-01_beg.txt']!.label,
          contains('开端'),);
    });

    test('endings and month squads hold their stories, in order', () async {
      Future<List<String>> partsOf(String parent) async => [
            for (final r in await q(
              'SELECT e.name FROM entry_links l JOIN entries e ON e.id = l.src '
              "WHERE l.dst = ? AND l.relation = 'part_of' "
              'ORDER BY e.sort_key, e.id',
              [parent],
            ))
              '${r['name']}',
          ];
      // The ending's sentence is its text; the pages of its book come
      // first, the ending's own story (named like it) last.
      expect(
        await partsOf('roguelike_ending:rogue_fx/end_a'),
        ['篇一', '某结局'],
      );
      // A squad: its short stories by floor, the protagonist an operator.
      expect(await partsOf('roguelike_squad:rogue_fx/sq1'), ['第一段']);
      final protagonist = await q(
        "SELECT dst FROM entry_links WHERE src = 'roguelike_squad:rogue_fx/sq1' "
        "AND relation = 'features'",
      );
      expect(protagonist.single['dst'], 'operator:char_fx_1');
      final squad = (await q(
        "SELECT group_name FROM entries WHERE id = 'roguelike_squad:rogue_fx/sq1'",
      ))
          .single;
      expect(squad['group_name'], '2026年7月');
      // The subtitle (English or invented) is not imported, only the
      // Chinese one-liner.
      final text = await q(
        "SELECT content FROM normalized_records WHERE entry_id = 'roguelike_squad:rogue_fx/sq1'",
      );
      final joined = text.map((r) => '${r['content']}').join('\n');
      expect(joined, contains('小队的一句话'));
      expect(joined, isNot(contains('Hello There')));
      // The topic's introduction is its text.
      final intro = await q(
        "SELECT content FROM normalized_records WHERE entry_id = 'roguelike_topic:rogue_fx'",
      );
      expect(intro.single['content'], '这是虚构肉鸽的一小段介绍。');
    });

    test('tips keep only the terms, stages say normal or raid once', () async {
      final tips = await q(
        "SELECT name FROM entries WHERE type = 'roguelike_tip'",
      );
      expect(tips.map((t) => t['name']), ['词语']);
      expect(
        await q("SELECT 1 FROM entries WHERE type = 'roguelike_scene' AND name LIKE '% · 2'"),
        isEmpty,
      );
      final stages = await q(
        "SELECT name FROM entries WHERE type = 'roguelike_stage' ORDER BY name",
      );
      expect(
        stages.map((s) => s['name']).toSet(),
        {'独关', '某关 · 突袭', '某关 · 普通'},
      );
      expect(stages, hasLength(3));
    });

    test('summons and devices are told from operators by the table', () async {
      final types = await q(
        "SELECT id, type, code FROM entries WHERE id LIKE 'operator:%' ORDER BY id",
      );
      expect(types.map((r) => (r['id'], r['type'], r['code'])), [
        ('operator:char_fx_1', 'operator', 'FX01'),
        ('operator:token_fx_1', 'token', null),
        ('operator:trap_fx_1', 'trap', null),
      ]);
    });

    test('names are shown, not ids: stage zones, rule stand-ins, folders',
        () async {
      // A stage is grouped by the name of its zone.
      final group = (await q(
        "SELECT group_name FROM entries WHERE id = 'stage:main_00-01'",
      ))
          .single['group_name'];
      expect(group, '序章 · 虚构之始');
      // The id of a zone no table names is no group.
      final act = (await q(
        "SELECT group_name FROM entries WHERE id = 'stage:fx_01'",
      ))
          .single['group_name'];
      expect(act, isNot('act_fx_zone1'));
      // Feature items are rule stand-ins, not story.
      expect(
        await q("SELECT 1 FROM entries WHERE name = '规则替身'"),
        isEmpty,
      );
      expect(
        await q("SELECT 1 FROM entries WHERE name = '虚构藏品'"),
        isNotEmpty,
      );
      // A story folder that is an activity's id without the `act<n>` prefix
      // belongs to that activity; the activity's own `type` is not a code.
      final guide = (await q(
        "SELECT collection_id FROM entries WHERE raw_id = 'activities/fxhub/guide_fx_entry.txt'",
      ))
          .single['collection_id'];
      expect(guide, 'act1fxhub');
      final collection = (await q(
        "SELECT kind, name FROM collections WHERE id = 'act1fxhub'",
      ))
          .single;
      expect(collection['name'], '虚构展');
      final activity = await q(
        "SELECT code FROM entries WHERE type = 'activity' AND collection_id = 'act_fx'",
      );
      expect(activity.single['code'], isNull);
    });

    test('stages are attributed through zones; gameplay stages are skipped',
        () async {
      final stages = await q(
        "SELECT id, collection_id, code FROM entries WHERE type = 'stage' ORDER BY id",
      );
      expect(stages.map((s) => (s['id'], s['collection_id'], s['code'])), [
        ('stage:fx_01', 'act_fx', 'FX-1'),
        ('stage:main_00-01', 'main_0', '0-1'),
      ]);
      final link = await q(
        "SELECT dst FROM entry_links WHERE src = 'story:obt/main/level_main_00-01_beg.txt' "
        "AND relation = 'belongs_to_stage'",
      );
      expect(link.single['dst'], 'stage:main_00-01');
    });

    test('enemies are bound to the stages they spawn in, both ways', () async {
      final links = await q(
        "SELECT src, dst FROM entry_links WHERE relation = 'appears_in' "
        'ORDER BY src, dst',
      );
      expect(links.map((l) => (l['src'], l['dst'])), [
        ('enemy:enemy_fx_a', 'stage:fx_01'),
        ('enemy:enemy_fx_a', 'stage:main_00-01'),
        ('enemy:enemy_fx_b', 'roguelike_stage:rogue_fx/st_solo'),
        ('enemy:enemy_fx_b', 'stage:fx_01'),
      ]);
      final inActivity = await q(
        "SELECT enemy_id FROM collection_enemies WHERE collection_id = 'act_fx' "
        'ORDER BY enemy_id',
      );
      expect(inActivity.map((r) => r['enemy_id']), [
        'enemy:enemy_fx_a',
        'enemy:enemy_fx_b',
      ]);
    });

    test('enemy ability text is not imported', () async {
      final texts = await q(
        "SELECT content FROM normalized_records WHERE entry_id LIKE 'enemy:%'",
      );
      expect(texts.map((r) => r['content']).join(), isNot(contains('额外伤害')));
      expect(texts.map((r) => r['content']).join(), contains('设定描述'));
    });

    test('activity narrative is kept, tasks are not', () async {
      final text = await q(
        "SELECT content FROM normalized_records WHERE entry_id LIKE 'activity_text:%'",
      );
      final all = text.map((r) => r['content']).join();
      expect(all, contains('虚构活动期间发布的新闻'));
      expect(all, isNot(contains('任务说明')));
      final owner = await q(
        "SELECT collection_id FROM entries WHERE type = 'activity_text'",
      );
      expect(owner.single['collection_id'], 'act_fx');
    });

    test('roguelike items keep flavor text and drop effects', () async {
      final item = (await q(
        'SELECT r.content, e.collection_id FROM entries e JOIN normalized_records r '
        "ON r.id = e.record_id WHERE e.type = 'roguelike_item'",
      ))
          .single;
      expect(item['content'], '一件藏品的设定描述。');
      expect(item['collection_id'], 'rogue_fx');
      // Listed twice by the game, one entry: the shorter id is kept.
      expect(
        (await q("SELECT raw_id FROM entries WHERE type = 'roguelike_item'"))
            .single['raw_id'],
        'rogue_fx/rogue_fx_relic_1',
      );
      // Options are not entries of their own: they are part of the event
      // that offers them (same id stem), the effect text left out.
      expect(
        await q("SELECT 1 FROM entries WHERE type = 'roguelike_choice'"),
        isEmpty,
      );
      final event = (await q(
        'SELECT e.name, r.content FROM entries e JOIN normalized_records r '
        "ON r.id = e.record_id WHERE e.type = 'roguelike_scene'",
      ))
          .single;
      expect(event['name'], '路口');
      // The event's own text, then the options, each followed by what is
      // said after choosing it.
      expect(
        event['content'],
        '## 事件\n一个岔路口。\n\n'
        '## 选项\n- **向左走**\n你向左走去。\n- **离开**',
      );
    });

    test('a roguelike stage has its enemies, also after its table is read again',
        () async {
      Future<List<Object?>> enemies() async => [
            for (final r in await q(
              "SELECT src FROM entry_links WHERE relation = 'appears_in' "
              "AND dst = 'roguelike_stage:rogue_fx/st_solo'",
            ))
              r['src'],
          ];
      expect(await enemies(), ['enemy:enemy_fx_b']);
      await importer.entryImporter.importTable(EntryTables.roguelikeTopic);
      await importer.entryImporter.rebuildDerived();
      expect(await enemies(), ['enemy:enemy_fx_b']);
    });

    test('a zone listed once per slot is one zone, with its stages', () async {
      final zones = await q(
        "SELECT id FROM entries WHERE type = 'roguelike_zone'",
      );
      expect(zones.map((z) => z['id']), ['roguelike_zone:rogue_fx/zone_1']);
      final stages = await q(
        "SELECT src FROM entry_links WHERE relation = 'belongs_to' "
        "AND dst = 'roguelike_zone:rogue_fx/zone_1'",
      );
      expect(stages.map((s) => s['src']), ['roguelike_stage:rogue_fx/st_solo']);
    });

    test('operators, records and handbook stages are bound', () async {
      final voice = (await q(
        "SELECT entry_id FROM normalized_records WHERE content_type = 'operator_voice'",
      ))
          .single;
      expect(voice['entry_id'], 'operator:char_fx_1');
      final stage = await q(
        "SELECT dst FROM entry_links WHERE src = 'operator_stage:mem_fx_1'",
      );
      expect(stage.single['dst'], 'operator:char_fx_1');
      final text = (await q(
        "SELECT content FROM normalized_records WHERE entry_id = 'operator_stage:mem_fx_1'",
      ))
          .single;
      expect(text['content'], '密录关的描述。');
    });

    test('every link and every owner refers to a row', () async {
      final dangling = await q(
        'SELECT COUNT(*) AS n FROM entry_links l WHERE '
        'NOT EXISTS (SELECT 1 FROM entries e WHERE e.id = l.src) '
        'OR NOT EXISTS (SELECT 1 FROM entries e WHERE e.id = l.dst)',
      );
      expect(dangling.single['n'], 0);
      final orphans = await q(
        'SELECT COUNT(*) AS n FROM entries e WHERE e.collection_id IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM collections c WHERE c.id = e.collection_id)',
      );
      expect(orphans.single['n'], 0);
    });

    test('re-importing one table does not duplicate its entries', () async {
      importer = ArknightsImporter(
        sourceDir: Directory(p.join(dir.path, 'src')),
        db: db,
        stats: stats,
        storyLimit: 0,
      );
      await db.delete(
        'entries',
        where: 'source_path = ?',
        whereArgs: ['zh_CN/gamedata/excel/enemy_handbook_table.json'],
      );
      await db.delete(
        'normalized_records',
        where: 'source_path = ?',
        whereArgs: ['zh_CN/gamedata/excel/enemy_handbook_table.json'],
      );
      await importer.entryImporter
          .importTable('zh_CN/gamedata/excel/enemy_handbook_table.json');
      final n = await q("SELECT COUNT(*) AS n FROM entries WHERE type = 'enemy'");
      expect(n.single['n'], 2);
    });
  });
}
