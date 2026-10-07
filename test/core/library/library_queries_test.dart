import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/library/library_labels.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';

/// A small entry layer: ids and shapes as the importer writes them, names
/// invented.
Future<Database> buildFixture() async {
  final db = await createGameDataDb(inMemoryDatabasePath, catalog: true);

  Future<void> collection(String id, String kind, String name,
      {int? sort, int? start, String? parent,}) =>
      db.insert('collections', {
        'id': id,
        'kind': kind,
        'name': name,
        'sort_key': sort,
        'start_time': start,
        'parent_id': parent,
      });
  Future<void> entry(
    String id,
    String type,
    String name, {
    String? code,
    String? collection,
    String? group,
    int? sort,
    String? raw,
    String? entity,
    String? record,
  }) =>
      db.insert('entries', {
        'id': id,
        'type': type,
        'name': name,
        'code': code,
        'collection_id': collection,
        'group_name': group,
        'sort_key': sort,
        'raw_id': raw ?? id,
        'entity_id': entity,
        'record_id': record,
      });
  Future<void> record(String id, String entryId, String title, String content,
      {String section = '节',}) =>
      insertRecord(
        db,
        id,
        contentType: 'text',
        content: content,
        fields: {
          'title': title,
          'section': section,
          'entry_id': entryId,
          'line_start': 0,
        },
      );

  await collection('main_1', 'main', '第一章', sort: 1);
  await collection('main_2', 'main', '第二章', sort: 2);
  await collection('act_old', 'activity', '旧活动', start: 1000);
  await collection('act_new', 'activity', '新活动', start: 2000);
  await collection('act_empty', 'activity', '空活动', start: 3000);
  await collection('mem_a', 'memory', '密录甲', sort: 5, parent: 'operator:char_x');
  await collection('rogue_1', 'roguelike', '肉鸽一', start: 1500);

  for (var i = 1; i <= 3; i++) {
    await entry(
      'story:main/s$i.txt',
      'story',
      '章节$i',
      code: '1-$i',
      collection: 'main_1',
      group: i.isOdd ? '行动前' : '行动后',
      sort: i,
      raw: 'main/s$i.txt',
    );
  }
  await entry('story:act/n1.txt', 'story', '新篇', collection: 'act_new', sort: 1, raw: 'act/n1.txt');
  await entry('story:act/o1.txt', 'story', '旧篇', collection: 'act_old', sort: 1, raw: 'act/o1.txt');
  await entry('story:mem/a.txt', 'story', '密录故事', collection: 'mem_a', sort: 1, raw: 'mem/a.txt');
  await entry('activity:act_empty', 'activity', '空活动', collection: 'act_empty');
  await entry('stage:st1', 'stage', '突入', code: 'N-1', collection: 'act_new', sort: 1, record: 'r_st1');
  await record('r_st1', 'stage:st1', '突入', '关卡说明文字');
  await entry('enemy:e1', 'enemy', '哨兵', record: 'r_e1');
  await record('r_e1', 'enemy:e1', '哨兵', '一名普通的哨兵。', section: '敌人');
  await entry('enemy:e2', 'enemy', '游荡者', record: 'r_e2');
  await record('r_e2', 'enemy:e2', '游荡者', '四处游荡。');
  await entry('operator:char_x', 'operator', '干员甲', code: 'X1', entity: 'char_x');
  await db.insert('entity_documents', {
    'id': 'd1',
    'game': 'arknights',
    'entity_id': 'char_x',
    'entity_name': '干员甲',
    'entity_type': 'operator',
    'title': '干员甲',
    'content': '## 基础信息\n<@ba.kw>关键词</>说明',
    'document_type': 'operator_profile_bundle',
  });
  await entry('item:i1', 'item', '100%_补给', record: 'r_i1');
  await record('r_i1', 'item:i1', '100%_补给', '一份补给。');
  await entry('roguelike_item:ri1', 'roguelike_item', '怪异的票', collection: 'rogue_1', record: 'r_ri1');
  await record('r_ri1', 'roguelike_item:ri1', '怪异的票', '一张票。');
  await entry('skin:nodoc', 'skin', '无文字皮肤'); // no record: not readable
  await entry('module:m1', 'module', '模组甲', code: 'X-A', record: 'r_m1', sort: 2);
  await record('r_m1', 'module:m1', '模组甲', '一块模组。');
  await entry('skin:s1', 'skin', '皮肤甲', record: 'r_s1', sort: 1);
  await record('r_s1', 'skin:s1', '皮肤甲', '一件皮肤。');
  await entry('operator_stage:p1', 'operator_stage', '模拟场景', code: 'EX', record: 'r_p1');
  await record('r_p1', 'operator_stage:p1', '模拟场景', '一段说明。');
  for (final owned in ['module:m1', 'skin:s1', 'operator_stage:p1']) {
    await db.insert('entry_links', {'src': owned, 'relation': 'belongs_to', 'dst': 'operator:char_x'});
  }

  await entry('medal:m_free', 'medal', '自由奖章', group: '履历奖章', record: 'r_mf');
  await record('r_mf', 'medal:m_free', '自由奖章', '一枚奖章。');
  await entry('medal:m_act', 'medal', '活动奖章', group: '活动奖章', collection: 'act_new', record: 'r_ma');
  await record('r_ma', 'medal:m_act', '活动奖章', '一枚活动奖章。');
  await entry('operator:trap_t1', 'trap', '陷阱甲', record: 'r_t1');
  await record('r_t1', 'operator:trap_t1', '陷阱甲', '一个装置。');
  await entry('operator:token_t1', 'token', '召唤物甲', record: 'r_k1');
  await record('r_k1', 'operator:token_t1', '召唤物甲', '一个召唤物。');
  await db.insert('entry_links', {'src': 'operator:trap_t1', 'relation': 'appears_in', 'dst': 'stage:st1'});
  await db.insert('entry_links', {'src': 'operator:token_t1', 'relation': 'summoned_by', 'dst': 'operator:char_x'});
  await db.insert('entry_links', {'src': 'enemy:e1', 'relation': 'appears_in', 'dst': 'stage:st1'});
  await db.insert('entry_links', {'src': 'stage:st1', 'relation': 'belongs_to', 'dst': 'activity:act_empty'});

  // One person in three versions (the first of the group is the original).
  for (final c in ['a', 'a2', 'a3', 'lone']) {
    await entry('operator:char_$c', 'operator', '干员$c', entity: 'char_$c');
  }
  for (final c in ['a2', 'a3']) {
    await db.insert('entry_links', {'src': 'operator:char_$c', 'relation': 'same_person', 'dst': 'operator:char_a'});
  }

  await db.insert('story_catalog', {
    'story_id': 'main/s1.txt',
    'collection_id': 'main_1',
    'collection_name': '第一章',
    'collection_type': 'MAINLINE',
    'story_sort': 1,
    'synopsis': '官方梗概一。',
  });
  return db;
}

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async => db = await buildFixture());
  tearDown(() => db.close());

  test('shelves count collections and stories, in shelf order', () async {
    final shelves = await shelfSummaries(db);
    expect(shelves.map((s) => s.kind), ['main', 'activity', 'memory', 'roguelike']);
    final main = shelves.first;
    expect((main.collections, main.stories), (2, 3));
    expect(shelves[1].collections, 3);
    expect(await hasEntryLayer(db), isTrue);
  });

  test('the codex lists readable free entries by type, not the operators'
      ' or what belongs to them', () async {
    final types = await codexTypes(db);
    expect({for (final t in types) t.type: t.count}, {
      'enemy': 2,
      'item': 1,
      // A medal of an activity is in the codex too.
      'medal': 2,
      // Summons stay in the codex though they name their operator.
      'token': 1,
      'trap': 1,
    });
  });

  test('an operator page: its record sets and what belongs to it', () async {
    final sets = await collectionsOwnedBy(db, 'operator:char_x');
    expect(sets.map((c) => c.id), ['mem_a']);
    expect(sets.single.stories, 1);
    final owned = await entriesOwnedBy(db, 'operator:char_x');
    // By type, then in order.
    expect(owned.map((e) => e.id), [
      'module:m1',
      'operator_stage:p1',
      'skin:s1',
      // The operator's summons are on its page too.
      'operator:token_t1',    ]);
    expect(await entriesOwnedBy(db, 'operator:nobody'), isEmpty);
    expect(entryTypeName('operator_stage'), '悖论模拟');
  });

  test('the operator shelf counts operators, not their record sets', () async {
    final memory = (await shelfSummaries(db)).firstWhere((s) => s.kind == operatorShelf);
    expect((memory.collections, memory.stories), (1, 1));
  });

  test('collections: release order, empty ones left out, game order otherwise',
      () async {
    final acts = await collectionsOfKind(db, 'activity');
    expect(acts.map((c) => c.id), ['act_new', 'act_old']);
    expect((acts.first.stories, acts.first.others), (1, 2));
    final main = await collectionsOfKind(db, 'main');
    expect(main.map((c) => c.id), ['main_1']); // main_2 has nothing to read
    expect((await collectionById(db, 'main_1'))!.stories, 3);
    expect(await collectionById(db, 'nope'), isNull);
  });

  test('a collection lists readable types and the enemies of its stages',
      () async {
    final types = await collectionTypes(db, 'act_new');
    // A level's traps are listed with its enemies.
    expect({for (final t in types) t.type: t.count}, {'stage': 1, 'enemy': 1, 'trap': 1, 'medal': 1});
    expect(
        (await entriesOfType(db, 'trap', collectionId: 'act_new')).map((e) => e.name),
        ['陷阱甲'],
      );
    final enemies =
        await entriesOfType(db, 'enemy', collectionId: 'act_new');
    expect(enemies.map((e) => e.name), ['哨兵']);
    // Enemies of the codex: all of them.
    expect((await entriesOfType(db, 'enemy')).length, 2);
    expect((await entriesOfType(db, 'medal')).length, 2);
    expect((await entryGroups(db, 'medal')).length, 2);
  });

  test('stories come in reading order with their synopsis', () async {
    final stories = await storiesOf(db, 'main_1');
    expect(stories.map((s) => s.code), ['1-1', '1-2', '1-3']);
    expect(stories.map((s) => s.group), ['行动前', '行动后', '行动前']);
    expect(stories.first.synopsis, '官方梗概一。');
    expect(stories[1].synopsis, isNull);
    expect(stories.first.rawId, 'main/s1.txt');
  });

  test('filters match name or code and escape LIKE characters', () async {
    expect(
      (await entriesOfType(db, 'enemy', query: '游')).map((e) => e.name),
      ['游荡者'],
    );
    expect(
      (await entriesOfType(db, 'operator', query: 'x1')).map((e) => e.name),
      ['干员甲'],
    );
    expect((await entriesOfType(db, 'item', query: '%')).length, 1);
    expect(await entriesOfType(db, 'item', query: '_x'), isEmpty);
  });

  test('entry text: records, or the operator document', () async {
    final enemy = (await entryById(db, 'enemy:e1'))!;
    final texts = await entryTexts(db, enemy);
    expect(texts.single.content, '一名普通的哨兵。');
    expect(texts.single.section, '敌人');
    final op = (await entryById(db, 'operator:char_x'))!;
    final doc = await entryTexts(db, op);
    expect(doc.single.content, contains('基础信息'));
    expect(await entryTexts(db, (await entryById(db, 'skin:nodoc'))!), isEmpty);
  });

  test('bindings are listed from both sides', () async {
    final enemy = await entryBindings(db, 'enemy:e1');
    expect(enemy.single.relation, 'appears_in');
    expect(enemy.single.outgoing, isTrue);
    expect(enemy.single.entry.id, 'stage:st1');
    final stage = await entryBindings(db, 'stage:st1');
    expect(
      {for (final b in stage) '${b.relation}/${b.outgoing}/${b.entry.id}'},
      {
        'appears_in/false/enemy:e1',
        'appears_in/false/operator:trap_t1',
        'belongs_to/true/activity:act_empty',
      },
    );
    expect(bindingName('appears_in', outgoing: false), '出场');
    // A relation of a later build is said plainly, not as its id; a type
    // nobody named reads by its family, else by its id.
    expect(bindingName('unknown', outgoing: true), '相关');
    expect(entryTypeName('roguelike_future'), '集成战略资料');
    expect(entryTypeName('future_kind'), 'future_kind');
  });

  test('versions of one operator list each other, the original first',
      () async {
    List<String> ids(List<LibraryEntry> l) => [for (final e in l) e.id];
    expect(ids(await samePersonOf(db, 'operator:char_a')),
        ['operator:char_a2', 'operator:char_a3'],);
    expect(ids(await samePersonOf(db, 'operator:char_a2')),
        ['operator:char_a', 'operator:char_a3'],);
    expect(await samePersonOf(db, 'operator:char_lone'), isEmpty);
    expect(bindingName('same_person', outgoing: false), '同一人物');
  });

  test('a story knows the chapter before and after it', () async {
    final middle = (await storyPlace(db, 'main/s2.txt'))!;
    expect(middle.previous!.rawId, 'main/s1.txt');
    expect(middle.next!.rawId, 'main/s3.txt');
    final first = (await storyPlace(db, 'main/s1.txt'))!;
    expect(first.previous, isNull);
    expect(first.entry.collectionName, '第一章');
    expect((await storyPlace(db, 'main/s3.txt'))!.next, isNull);
    expect(await storyPlace(db, 'unknown.txt'), isNull);
  });

  test('search finds collections by name and entries by name or code',
      () async {
    final r = await searchLibrary(db, '活动');
    expect(r.collections.map((c) => c.id), ['act_new', 'act_old']);
    final byCode = await searchLibrary(db, '1-2');
    expect(byCode.entries.single.name, '章节2');
    final byName = await searchLibrary(db, '票');
    expect(byName.entries.map((e) => e.id), ['roguelike_item:ri1']);
    expect((await searchLibrary(db, '  ')).entries, isEmpty);
    // Entries without text are not offered.
    expect((await searchLibrary(db, '无文字')).entries, isEmpty);
  });

  test('labels cover the types and read as a headline', () {
    expect(entryTypeName('roguelike_item'), '收藏品');
    expect(entryTypeName('brand_new_type'), 'brand_new_type');
    const stage = LibraryEntry(id: 'x', type: 'stage', name: '突入', code: 'N-1');
    expect(entryHeadline(stage), 'N-1  突入');
    const same = LibraryEntry(id: 'x', type: 'stage', name: 'N-1 突入', code: 'N-1');
    expect(entryHeadline(same), 'N-1 突入');
  });

  test('game codes are named, a code without a name is not shown raw', () {
    expect(groupLabel('roguelike_item', 'copper'), '通宝');
    expect(groupLabel('roguelike_item', 'legacy'), '黄色襁褓生灵');
    expect(groupLabel('roguelike_item', 'start'), '蓝色襁褓生灵');
    // Nobody named these kinds: no heading rather than an invented one.
    expect(groupLabel('roguelike_item', 'copper_buff'), isNull);
    expect(groupLabel('roguelike_buff', 'variationData'), isNull);
    expect(groupLabel('roguelike_item', 'brand_new_code'), isNull);
    expect(groupLabel('item', 'VOUCHER_PICK'), isNull);
    expect(groupLabel('item', 'MATERIAL'), '材料');
    expect(groupLabel('item', 'MATERIAL_ISSUE_VOUCHER'), isNull);
    expect(groupLabel('item', 'EMOTICON_SET'), '表情套组');
    expect(entryTypeName('charm'), '标志物');
    expect(groupLabel('stage', '第九章 · 某章'), '第九章 · 某章');
    expect(groupLabel('skin', 'WWF'), 'WWF');
    expect(groupLabel('item', null), isNull);
    // Characters are numbered, not coded.
    const op = LibraryEntry(id: 'o', type: 'operator', name: '甲', code: 'RCX7');
    expect(codeCaption(op), '编号 RCX7');
    expect(entryHeadline(op), '甲');
    expect(entryTypeName('trap'), '装置');
    expect(entryTypeName('token'), '召唤物');
    expect(typeRank('roguelike_ending'), lessThan(typeRank('roguelike_choice')));
  });

  test('entries are listed by group, and the groups are counted', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute(entriesDdl);
    await db.execute(entryLinksDdl);
    for (final (i, g) in ['a', 'a', 'b', null, ''].indexed) {
      await db.insert('entries', {
        'id': 'e$i',
        'type': 'item',
        'name': '物$i',
        'group_name': g,
        'sort_key': i,
        'record_id': 'r$i',
      });
    }
    final groups = await entryGroups(db, 'item');
    expect(groups.map((g) => (g.group, g.count)), [
      ('a', 2),
      ('b', 1),
      (null, 2),
    ]);
    final onlyA = await entriesOfType(db, 'item', groups: ['a']);
    expect(onlyA.map((e) => e.id), ['e0', 'e1']);
    final none = await entriesOfType(db, 'item', groups: [null]);
    expect(none.map((e) => e.id), ['e3', 'e4']);
    await db.close();
  });

  test('an older database without the entry layer is recognised', () async {
    final old = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    expect(await hasEntryLayer(old), isFalse);
    expect(await storyPlace(old, 'x.txt'), isNull);
    await old.close();
  });
}
