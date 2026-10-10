import 'dart:io';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/temp_dir.dart';

/// 0.14 phone: two sessions spent a dozen `sql` calls each on reading one
/// operator's file (the wrong table, the id with its `record:` prefix, 400
/// characters a call), were told a name they asked for "is not in the
/// library", and took a voice line for another operator's. Fixture names
/// are fictional.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late GameDataKnowledgeStore store;
  final long = [
    '## 基础档案',
    '守灯人的档案。${'很长的一段。' * 2000}',
    '## 档案资料一',
    '结尾的一句。',
  ].join('\n');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('arklores_read_record');
    final path = p.join(dir.path, 'kb.db');
    final db = await createGameDataDb(path);
    await insertEntity(db, 'char_fx_keeper', '守灯人');
    await insertStory(db, 'obt/main/level_main_fx-01.txt', [
      '夜色很深。',
      '守灯人：钟楼的灯由我来点亮。',
    ]);
    // A voice line carries the id of its operator, not the name.
    await insertRecord(
      db,
      'rec_fx_voice',
      contentType: 'operator_voice',
      category: 'operator',
      subtype: 'voice',
      content: '上次有人邀我去舞会，我没有答应。',
      fields: {'entity_id': 'char_fx_keeper', 'title': '交谈1'},
    );
    await insertRecord(
      db,
      'rec_fx_item',
      contentType: 'item_description',
      category: 'world_item',
      subtype: 'item',
      content: '一盏旧灯。',
      fields: {'entity_name': '旧灯', 'title': '旧灯'},
    );
    await db.insert('entity_documents', {
      'id': 'doc_fx_keeper',
      'game': 'arknights',
      'language': 'zh',
      'entity_id': 'char_fx_keeper',
      'entity_name': '守灯人',
      'entity_type': 'operator',
      'document_type': 'operator_profile_bundle',
      'title': '守灯人',
      'summary': '',
      'content': long,
      'source_paths': '[]',
      'source_record_ids': '[]',
    });
    await db.close();
    store = GameDataKnowledgeStore(dbPath: path);
  });

  tearDown(() async {
    await store.close();
    await deleteTempDir(dir);
  });

  test('read_record reads either table by id and says whose record it is',
      () async {
    final seen = SeenLines();
    final tool = ReadRecordTool(store, seen);

    // With the prefix the search result shows it under.
    final voice = await tool.execute({'id': 'record:rec_fx_voice'});
    expect(voice, startsWith('record:rec_fx_voice | operator·voice | 交谈1'));
    expect(voice, contains('所属：守灯人'));
    expect(voice, contains('舞会'));
    expect(seen.hasRecord('rec_fx_voice'), isTrue);
    expect(seen.recordIsPartial('rec_fx_voice'), isFalse);

    // An operator's file is in the other table; a long one comes in pages.
    final first = await tool.execute({'id': 'doc_fx_keeper'});
    expect(first, startsWith('record:doc_fx_keeper | operator·'));
    expect(first, contains('## 基础档案'));
    expect(first, isNot(contains('结尾的一句')));
    expect(seen.recordIsPartial('doc_fx_keeper'), isTrue);
    final next = RegExp(r'继续读用 start=(\d+)').firstMatch(first)!.group(1)!;
    expect(first, contains('全文 ${long.length} 个字'));
    final rest = await tool.execute({
      'id': 'doc_fx_keeper',
      'start': int.parse(next),
    });
    expect(rest, contains('结尾的一句'));

    final none = await tool.execute({'id': 'no_such'});
    expect(none, startsWith('没有 id 为 no_such 的资料'));
    expect(await tool.execute({}), startsWith('缺少参数'));
    expect(loreTools(store, SeenLines()).map((t) => t.name),
        contains('read_record'),);
  });

  test('sql counts a record as shown whatever its text column is called',
      () async {
    final seen = SeenLines();
    final tool = SqlTool(store, seen);
    await tool.execute({
      'query': 'SELECT id, section, substr(content, 1, 500) t '
          "FROM normalized_records WHERE category = 'operator'",
    });
    expect(seen.hasRecord('rec_fx_voice'), isTrue);
    expect(seen.recordIsPartial('rec_fx_voice'), isTrue);

    // Read by its id, without the id column.
    await tool.execute({
      'query': 'SELECT substr(content, 1, 2200) c FROM normalized_records '
          "WHERE id = 'rec_fx_item'",
    });
    expect(seen.hasRecord('rec_fx_item'), isTrue);

    // A length or a count shows no text.
    final bare = SeenLines();
    await SqlTool(store, bare).execute({
      'query': 'SELECT id, length(content) FROM normalized_records',
    });
    await SqlTool(store, bare).execute({
      'query': 'SELECT id, count(*) FROM normalized_records GROUP BY id',
    });
    expect(bare.isEmpty, isTrue);
  });

  test('one row is shown whole; several are cut', () async {
    final tool = SqlTool(store, SeenLines());
    final one = await tool.execute({
      'query': "SELECT content FROM entity_documents WHERE id = 'doc_fx_keeper'",
    });
    expect(one.length, greaterThan(5000));
    final many = await tool.execute({
      'query': 'SELECT id, content FROM entity_documents '
          'UNION ALL SELECT id, content FROM normalized_records',
    });
    expect(many.length, lessThan(1500));
  });

  test('a record looked up in the table that does not hold it is pointed at',
      () async {
    final tool = SqlTool(store, SeenLines());
    final out = await tool.execute({
      'query': 'SELECT id, content FROM normalized_records '
          "WHERE id = 'record:doc_fx_keeper'",
    });
    expect(out, startsWith('0 行'));
    expect(out, contains('read_record'));
    expect(out, contains('doc_fx_keeper'));
  });

  test('a name the library has is never called missing', () async {
    final tool = SqlTool(store, SeenLines());
    // No row for another reason: the name itself exists.
    final out = await tool.execute({
      'query': 'SELECT id FROM normalized_records '
          "WHERE content LIKE '%守灯人%' AND category LIKE '%bundle%'",
    });
    expect(out, startsWith('0 行'));
    expect(out, isNot(contains('没有“守灯人”')));
    // A category is not a name.
    expect(out, isNot(contains('bundle')));
    // A misspelled name still gets its near names.
    final typo = await tool.execute({
      'query': "SELECT * FROM story_lines WHERE speaker LIKE '%守登人%'",
    });
    expect(typo, contains('库里的名字中没有“守登人”这个写法'));
    expect(typo, contains('守灯人'));
    expect(await store.hasName('守灯人'), isTrue);
    expect(await store.hasName('守登人'), isFalse);
  });

  test('search lists whose record it is and points at read_record', () async {
    final seen = SeenLines();
    final out = (await SearchTool(store, seen).run('舞会')).text;
    expect(out, contains('record:rec_fx_voice | operator·voice | 交谈1（守灯人）'));
    expect(out, contains('全文用 read_record 按 id 读'));
    expect(out, isNot(contains('normalized_records')));
  });
}
