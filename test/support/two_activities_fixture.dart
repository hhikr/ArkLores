// Two fictional activities with a story catalog: `act_old` (40 chapters,
// 2022-05) and `act_new` (2 chapters, 2024-06), and one speaker, 凯伦, who
// appears in every chapter. For locality questions: hits outside a scope,
// near names, collections named in a question.
import 'package:arklores/core/gamedata/story_catalog.dart';

import 'gamedata_fixture.dart';

const int oldChapters = 40;

Future<void> createTwoActivitiesDb(String path) async {
  final db = await createGameDataDb(path, catalog: true);
  try {
    await insertEntity(db, 'char_fx_karen', '凯伦');
    final stories = <String, (String, List<String>)>{
      for (var i = 1; i <= oldChapters; i++)
        'activities/act_old/level_act_old_${i.toString().padLeft(2, '0')}.txt': (
          'act_old',
          ['凯伦：第 $i 段旧航线。', '海风很大。'],
        ),
      'activities/act_new/level_act_new_01.txt': (
        'act_new',
        ['凯伦：我们出发吧。', '远处有一座灯塔。'],
      ),
      'activities/act_new/level_act_new_02.txt': ('act_new', ['凯伦：灯塔熄灭了。']),
    };
    for (final MapEntry(key: id, value: (collection, lines)) in stories.entries) {
      await insertStory(db, id, lines, scopeId: collection);
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('凯伦：')) continue;
        await db.insert('entity_story_mentions', {
          'entity_id': 'char_fx_karen',
          'story_id': id,
          'scope_id': 'activity:$collection',
          'line_start': i,
          'line_end': i,
          'mention_count': 1,
          'matched_alias': '凯伦',
        });
      }
    }
    await writeStoryCatalog(
      db,
      parseStoryReviewTable(decodeStoryReviewTable(twoActivitiesReviewTable), (_) => null),
    );
  } finally {
    await db.close();
  }
}

/// The `story_review_table.json` of the fixture (plus a fictional main
/// chapter without a release date).
String get twoActivitiesReviewTable {
  final old = [
    for (var i = 1; i <= oldChapters; i++)
      '{"storyCode": "OL-$i", "storyName": "航线第$i段", "avgTag": "行动前", '
          '"storySort": $i, "storyInfo": "", '
          '"storyTxt": "activities/act_old/level_act_old_${i.toString().padLeft(2, '0')}"}',
  ].join(',\n');
  return '''
{
  "act_old": {
    "id": "act_old", "name": "旧日航线", "entryType": "ACTIVITY",
    "startTime": 1651388400,
    "infoUnlockDatas": [$old]
  },
  "act_new": {
    "id": "act_new", "name": "远方之路", "entryType": "ACTIVITY",
    "startTime": 1717560000,
    "infoUnlockDatas": [
      {"storyCode": "FR-1", "storyName": "启程", "avgTag": "行动前", "storySort": 1,
       "storyInfo": "", "storyTxt": "activities/act_new/level_act_new_01"},
      {"storyCode": "FR-2", "storyName": "灯塔熄灭", "avgTag": "行动后", "storySort": 2,
       "storyInfo": "", "storyTxt": "activities/act_new/level_act_new_02"}
    ]
  },
  "main_fx": {
    "id": "main_fx", "name": "虚构主线", "entryType": "MAINLINE", "startTime": -1,
    "infoUnlockDatas": [
      {"storyCode": "0-1", "storyName": "开端", "avgTag": "幕间", "storySort": 1,
       "storyInfo": "", "storyTxt": "obt/main/level_main_fx-01"}
    ]
  }
}
''';
}
