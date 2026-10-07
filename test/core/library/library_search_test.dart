import 'package:arklores/core/library/library_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';

/// A small entry layer with text; names invented.
Future<Database> _fixture() async {
  final db = await createGameDataDb(inMemoryDatabasePath, catalog: true);
  Future<void> collection(String id, String kind, String name,
          {String? parent,}) =>
      db.insert('collections',
          {'id': id, 'kind': kind, 'name': name, 'parent_id': parent},);
  Future<void> entry(String id, String type, String name,
          {String? code, String? collection, String? raw, String? entity,}) =>
      db.insert('entries', {
        'id': id,
        'type': type,
        'name': name,
        'code': code,
        'collection_id': collection,
        'raw_id': raw ?? id,
        'entity_id': entity,
        'record_id': type == 'story' || type == 'operator' ? null : 'r_$id',
      });
  Future<void> record(String entryId, String content) => insertRecord(
        db,
        'r_$entryId',
        contentType: 'text',
        content: content,
        fields: {'title': entryId, 'entry_id': entryId, 'line_start': 0},
      );

  await collection('main_1', 'main', '星灯之城');
  await collection('act_a', 'activity', '雾港来信');
  await collection('mem_x', 'memory', '密录甲', parent: 'operator:char_x');

  await entry('story:m/1.txt', 'story', '钟楼之夜',
      code: '1-1', collection: 'main_1', raw: 'm/1.txt',);
  await insertStory(db, 'm/1.txt', ['甲：灯塔还亮着。', '乙：源石的光很冷。', '源石又响了。']);
  await entry('story:m/2.txt', 'story', '离城',
      code: '1-2', collection: 'main_1', raw: 'm/2.txt',);
  await insertStory(db, 'm/2.txt', ['一切归于平静。']);
  await entry('story:a/1.txt', 'story', '雾中信使',
      collection: 'act_a', raw: 'a/1.txt',);
  await insertStory(db, 'a/1.txt', ['信使提到了源石。']);
  await entry('story:x/1.txt', 'story', '旧日回响',
      collection: 'mem_x', raw: 'x/1.txt',);
  await insertStory(db, 'x/1.txt', ['那天的事。']);

  await entry('enemy:e1', 'enemy', '特蕾西娅的影子');
  await record('enemy:e1', '一个徘徊在城墙边的影子。');
  await entry('item:i1', 'item', '罗德岛制药徽章', collection: 'act_a');
  await record('item:i1', '一枚徽章。');
  await entry('operator:char_x', 'operator', '干员甲', entity: 'char_x');
  await db.insert('entity_documents', {
    'id': 'd1',
    'game': 'arknights',
    'entity_id': 'char_x',
    'entity_name': '干员甲',
    'entity_type': 'operator',
    'title': '档案',
    'content': '## 档案\n曾在灯塔下工作。',
    'document_type': 'operator_profile_bundle',
  });
  await entry('skin:s1', 'skin', '甲的礼服');
  await record('skin:s1', '一件礼服。');
  await db.insert('entry_links',
      {'src': 'skin:s1', 'relation': 'belongs_to', 'dst': 'operator:char_x'},);
  return db;
}

void main() {
  sqfliteFfiInit();
  late Database db;
  setUp(() async => db = await _fixture());
  tearDown(() async => db.close());

  test('every word must be in the name, code or collection name', () async {
    final both = await searchLibraryIn(db, '星灯之城 离城');
    expect(both.entries.map((e) => e.id), ['story:m/2.txt']);
    // A word that only names the collection does not list all its entries.
    final collectionOnly = await searchLibraryIn(db, '星灯之城');
    expect(collectionOnly.collections.map((c) => c.id), ['main_1']);
    expect(collectionOnly.entries, isEmpty);
    expect((await searchLibraryIn(db, '1-2')).entries.single.name, '离城');
    // Names matched: no fallback, and the texts only on request.
    expect(collectionOnly.searchedText, isFalse);
    expect(collectionOnly.similar, isEmpty);
  });

  test('a scope limits names and collections to what the page shows',
      () async {
    final inMain = await searchLibraryIn(db, '城',
        scope: listScope(collectionId: 'main_1'),);
    expect(inMain.collections, isEmpty);
    expect(inMain.entries.map((e) => e.id), ['story:m/2.txt']);
    final shelf =
        await searchLibraryIn(db, '雾', scope: shelfScope('activity'));
    expect(shelf.collections.map((c) => c.id), ['act_a']);
    expect(shelf.entries.map((e) => e.id), ['story:a/1.txt']);
    final owner =
        await searchLibraryIn(db, '甲', scope: ownerScope('operator:char_x'));
    expect(owner.collections.map((c) => c.id), ['mem_x']);
    expect(owner.entries.map((e) => e.id), ['skin:s1']);
    final codex = await searchLibraryIn(db, '徽章', scope: shelfScope(codexShelf));
    // The badge belongs to an activity: not a free entry.
    expect(codex.entries, isEmpty);
  });

  test('without a name match: close names (homophones, words left out)',
      () async {
    final typo = await searchLibraryIn(db, '特雷西娅的影子');
    expect(typo.hasNameHits, isFalse);
    expect(typo.similar.map((e) => e.id), contains('enemy:e1'));
    final abbreviated = await searchLibraryIn(db, '罗德徽章');
    expect(abbreviated.similar.map((e) => e.id), ['item:i1']);
    final collection = await searchLibraryIn(db, '雾港信');
    expect(collection.similarCollections.map((c) => c.id), ['act_a']);
  });

  test('without a name match: the texts that contain the words', () async {
    final r = await searchLibraryIn(db, '源石');
    expect(r.searchedText, isTrue);
    final byId = {for (final h in r.mentions) h.entry.id: h};
    expect(byId.keys, containsAll(['story:m/1.txt', 'story:a/1.txt']));
    final main = byId['story:m/1.txt']!;
    expect(main.count, 2);
    expect(main.line, 1);
    expect(main.snippet, contains('源石'));
    expect(r.mentions.first.entry.id, 'story:m/1.txt'); // most matches first
    // Records and profile documents too.
    expect((await searchLibraryIn(db, '城墙')).mentions.single.entry.id,
        'enemy:e1',);
    expect((await searchLibraryIn(db, '灯塔下')).mentions.single.entry.id,
        'operator:char_x',);
    // Limited to the page's scope.
    final scoped = await searchLibraryIn(db, '源石',
        scope: listScope(collectionId: 'act_a'),);
    expect(scoped.mentions.map((h) => h.entry.id), ['story:a/1.txt']);
    // Asked for although names matched.
    final asked = await searchLibraryIn(db, '离城', text: true);
    expect(asked.entries, isNotEmpty);
    expect(asked.searchedText, isTrue);
  });

  test('a passage is cut around the first word', () {
    final long = '${'前' * 80}关键${'后' * 80}';
    final s = snippetAround(long, ['关键'], width: 20);
    expect(s, startsWith('…'));
    expect(s, endsWith('…'));
    expect(s, contains('关键'));
    expect(snippetAround('短 句\n子', ['x']), '短 句 子');
  });

  test('semantic hits become one story entry each, within the scope',
      () async {
    final hits = await storyChunkEntries(db, [
      (storyId: 'm/1.txt', lineStart: 1, lineEnd: 2),
      (storyId: 'a/1.txt', lineStart: 0, lineEnd: 0),
      (storyId: 'm/1.txt', lineStart: 0, lineEnd: 0),
      (storyId: 'gone.txt', lineStart: 0, lineEnd: 0),
    ]);
    expect(hits.map((h) => h.entry.id), ['story:m/1.txt', 'story:a/1.txt']);
    expect(hits.first.line, 1);
    expect(hits.first.lineEnd, 2);
    expect(hits.first.snippet, '源石的光很冷。');
    final scoped = await storyChunkEntries(
      db,
      [(storyId: 'm/1.txt', lineStart: 1, lineEnd: 2),
        (storyId: 'a/1.txt', lineStart: 0, lineEnd: 0),],
      scope: shelfScope('activity'),
    );
    expect(scoped.map((h) => h.entry.id), ['story:a/1.txt']);
  });
}
