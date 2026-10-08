// One operator with a profile, a voice line, an entity document and a story
// line: the database the local-lore search, the roleplay agent and the
// installer are tested on.
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'gamedata_fixture.dart';

const amiyaId = 'char_002_amiya';

/// Writes the fixture database to [path] (production schema, valid
/// manifest). [extra] adds rows before the search indexes are rebuilt.
Future<void> createAmiyaDb(
  String path, {
  Future<void> Function(Database db)? extra,
}) async {
  final db = await createGameDataDb(path);
  try {
    await insertStory(
      db,
      'activities/act_test/level_test_01.txt',
      ['阿米娅：测试剧情行内容'],
      scopeId: 'act_test',
    );
    await insertEntity(db, amiyaId, '阿米娅',
        sourceType: 'operator_handbook_profile', aliases: {'Amiya': 0.8},);
    await insertRecord(
      db,
      'record_profile_amiya',
      contentType: 'operator_handbook_profile',
      category: 'operator',
      subtype: 'handbook_profile',
      content: '阿米娅是罗德岛的公开领袖，也是剧情中的核心角色。',
      sourcePath: 'zh_CN/gamedata/excel/handbook_info_table.json',
      fields: {
        'entity_id': amiyaId,
        'entity_name': '阿米娅',
        'title': '阿米娅',
        'section': '档案资料',
        'raw_id': amiyaId,
      },
    );
    await insertRecord(
      db,
      'record_voice_amiya',
      contentType: 'operator_voice',
      category: 'operator',
      subtype: 'voice',
      content: '博士，我们继续前进吧。',
      sourcePath: 'zh_CN/gamedata/excel/charword_table.json',
      fields: {
        'entity_id': amiyaId,
        'entity_name': '阿米娅',
        'title': '交谈1',
        'section': '交谈1',
        'raw_id': 'char_002_amiya_CN_001',
      },
    );
    await db.insert('entity_documents', {
      'id': 'doc_operator_amiya',
      'game': 'arknights',
      'language': 'zh',
      'entity_id': amiyaId,
      'entity_name': '阿米娅',
      'entity_type': 'operator',
      'document_type': 'operator_profile_bundle',
      'title': '阿米娅',
      'summary': '阿米娅是罗德岛的公开领袖。',
      'content': '## 基础信息\n阿米娅是罗德岛的公开领袖。\n\n'
          '## 档案资料\n她也是剧情中的核心角色。',
      'source_paths': '["zh_CN/gamedata/excel/character_table.json",'
          '"zh_CN/gamedata/excel/handbook_info_table.json"]',
      'source_record_ids': '["$amiyaId"]',
    });
    await extra?.call(db);
    await rebuildGamedataFts(db);
  } finally {
    await db.close();
  }
}

/// An item sharing the alias `Amiya`: exact-alias lookups become ambiguous.
Future<void> addAmbiguousAmiya(Database db) => insertEntity(
      db,
      'token_amiya_memory',
      '阿米娅的记忆',
      type: 'item',
      sourceType: 'item_description',
      aliases: {'Amiya': 0.7},
      sourcePath: 'zh_CN/gamedata/excel/item_table.json',
    );

/// A main-story chunk about Amiya, optionally bound to her entity.
Future<void> addAmiyaStoryChunk(Database db, {bool withEntityId = false}) =>
    db.insert('lore_chunks', {
      'id': 'chunk_story_amiya_chernobog',
      'game': 'arknights',
      'source_type': 'game_data',
      'content_category': 'story',
      'content_subtype': 'main',
      'content_type': 'story_dialogue',
      'entity_id': withEntityId ? amiyaId : null,
      'story_id': 'main_00_01',
      'page_title': '切尔诺伯格行动',
      'section': '行动前',
      'content': '切尔诺伯格行动中，阿米娅与博士会合。',
      'source_path': 'zh_CN/gamedata/story/[uc]obt/main_00_01.txt',
      'language': 'zh',
      'raw_id': 'main_00_01',
    });
