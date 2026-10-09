// 0.12: one retrieval surface over two games' databases; ids name their
// game, so calls about one story go to its database and corpus-wide calls
// ask both.
import 'dart:io';

import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  useSqfliteFfi();

  test('an id names its game', () {
    expect(gameOfId('obt/main/level_main_01-01_beg.txt'), Game.arknights);
    expect(gameOfId('ef/dlg_x_1'), Game.endfield);
    expect(gameOfId('story:ef/dlg_x_1'), Game.endfield);
    expect(gameOfId('operator:char_x'), Game.arknights);
    expect(gameOfId('ef/main'), Game.endfield);
    expect(endfieldId('dlg_x_1'), 'ef/dlg_x_1');
    expect(endfieldId('ef/dlg_x_1'), 'ef/dlg_x_1');
    expect(Game.parse('endfield'), Game.endfield);
    expect(Game.parse('终末地'), Game.endfield);
    expect(Game.parse('arknights'), Game.arknights);
    expect(Game.parse(null), isNull);
  });

  test('library shelves and scopes name their game', () {
    expect(codexShelfOf(Game.arknights), codexShelf);
    expect(gameOfId(codexShelfOf(Game.endfield)), Game.endfield);
    expect(isCodexShelf(codexShelfOf(Game.endfield)), isTrue);
    expect(isCodexShelf('main'), isFalse);
    expect(gameOfId(operatorShelfOf(Game.endfield)), Game.endfield);
    expect(gameOfScope(listScope(collectionId: 'ef/m1')), Game.endfield);
    expect(gameOfScope(shelfScope('main')), Game.arknights);
    expect(gameOfScope(everywhere), Game.arknights);
  });

  test("an Endfield story's label starts with the game's name", () {
    const entry = StoryCatalogEntry(
      storyId: 'ef/dlg_x_1.txt',
      collectionId: 'ef/m1',
      collectionName: '某个任务',
      collectionType: 'EF_MAIN',
      storySort: 1,
    );
    expect(entry.label, startsWith('终末地·某个任务'));
  });

  group('two games', () {
    late Directory dir;
    late MultiGameRetrieval both;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('arklores_two_games');
      final ak = '${dir.path}/ak.db';
      final ef = '${dir.path}/ef.db';
      final a = await createGameDataDb(ak);
      await insertStory(a, 'activities/act1/level_act1_01_beg.txt', [
        '甲：灯塔还亮着。',
        '乙：走吧。',
      ]);
      await a.close();
      final e = await createGameDataDb(ef);
      await insertStory(
        e,
        'ef/dlg_test_1.txt',
        ['丙：灯塔下面有人。', '丁：去看看。'],
        scopeType: 'mission',
        scopeId: 'ef/mission_1',
      );
      await e.close();
      both = MultiGameRetrieval({
        Game.arknights: GameDataKnowledgeStore(dbPath: ak),
        Game.endfield: GameDataKnowledgeStore(dbPath: ef, game: Game.endfield),
      });
    });

    tearDown(() async {
      for (final s in both.stores.values) {
        await (s as GameDataKnowledgeStore).close();
      }
      await deleteTempDir(dir);
    });

    test('both are installed; a story is read from its own database', () async {
      expect(await both.installedGames(), [Game.arknights, Game.endfield]);
      final ef = await both.readStoryLines(storyId: 'ef/dlg_test_1.txt');
      expect(ef.storyFound, isTrue);
      expect(ef.lines.first.speaker, '丙');
      final ak = await both.readStoryLines(
        storyId: 'activities/act1/level_act1_01_beg.txt',
      );
      expect(ak.lines.first.speaker, '甲');
    });

    test('corpus counts and grep cover both games; one game when asked',
        () async {
      final counts = await both.storyLineHitCounts(['灯塔']);
      expect(
          counts.keys,
          containsAll([
            'ef/dlg_test_1.txt',
            'activities/act1/level_act1_01_beg.txt',
          ]),
        );
      final grep = GrepTool(both, SeenLines());
      final all = await grep.execute({'pattern': '灯塔'});
      expect(all, contains('ef/dlg_test_1.txt'));
      expect(all, contains('level_act1_01_beg.txt'));
      final onlyEf = await grep.execute({'pattern': '灯塔', 'game': 'endfield'});
      expect(onlyEf, contains('ef/dlg_test_1.txt'));
      expect(onlyEf, isNot(contains('level_act1_01_beg.txt')));
    });

    test('sql runs on the game it names', () async {
      final seen = SeenLines();
      final sql = SqlTool(both, seen);
      final ef = await sql.execute({
        'query': 'SELECT story_id, line_index, content FROM story_lines',
        'game': 'endfield',
      });
      expect(ef, contains('ef/dlg_test_1.txt'));
      expect(ef, isNot(contains('level_act1')));
      final ak = await sql.execute({
        'query': 'SELECT story_id, line_index, content FROM story_lines',
      });
      expect(ak, contains('level_act1'));
      // Lines a query showed can be cited, in either game.
      expect(seen.covers('ef/dlg_test_1.txt', 0, 1), isTrue);
      // 0.14: an Endfield id in the query picks Endfield without `game`;
      // zero rows in the default game says how to ask the other.
      final byId = await sql.execute({
        'query': 'SELECT story_id, line_index FROM story_lines '
            "WHERE story_id = 'ef/dlg_test_1.txt'",
      });
      expect(byId, contains('（共 2 行）'));
      final none = await sql.execute({
        'query': "SELECT story_id FROM story_lines WHERE content LIKE '%丙%'",
      });
      expect(none, contains('终末地的内容要加 game=endfield'));
    });

    test('with only Endfield installed, sql without a game reads Endfield', () async {
      final onlyEf = MultiGameRetrieval({
        Game.arknights: GameDataKnowledgeStore(dbPath: '${dir.path}/none.db'),
        Game.endfield: both.stores[Game.endfield]!,
      });
      final result = await onlyEf.readOnlySql('SELECT story_id FROM story_lines LIMIT 1');
      expect(result.error, isNull);
      expect('${result.rows.single.single}', startsWith('ef/'));
    });

    test('tools offer the game choice; an unknown game value searches both', () async {
      final seen = SeenLines();
      for (final tool in [SqlTool(both, seen), GrepTool(both, seen)]) {
        final game = (tool.parameters['properties'] as Map)['game'] as Map;
        expect(game['enum'], ['arknights', 'endfield']);
      }
      final grep = GrepTool(both, seen);
      final all = await grep.execute({'pattern': '灯塔', 'game': 'nonsense'});
      expect(all, contains('ef/dlg_test_1.txt'));
      expect(all, contains('level_act1_01_beg.txt'));
    });

    // 0.14: a game with few hits used to sit at the end of one long list.
    test('grep counts list each game under its own heading with its totals',
        () async {
      final all = await GrepTool(both, SeenLines()).execute({'pattern': '灯塔'});
      expect(all, contains('明日方舟 1 行 / 1 个故事'));
      expect(all, contains('终末地 1 行 / 1 个故事'));
      expect(all.indexOf('## 明日方舟'), lessThan(all.indexOf('## 终末地')));
    });

    test('search looks in both games at once, grouped, and its lines can be '
        'cited', () async {
      final seen = SeenLines();
      final search = SearchTool(both, seen);
      final result = await search.run('灯塔');
      expect(result.mode, SearchMode.keywordOnly);
      expect(result.text, contains('只有关键词检索（没有配置向量服务）'));
      final ak = result.text.indexOf('## 明日方舟剧情');
      final ef = result.text.indexOf('## 终末地剧情');
      expect(ak, greaterThanOrEqualTo(0));
      expect(ef, greaterThan(ak));
      expect(result.text.substring(ak, ef), contains('level_act1_01_beg.txt'));
      expect(result.text.substring(ef), contains('ef/dlg_test_1.txt'));
      expect(seen.covers('ef/dlg_test_1.txt', 0, 0), isTrue);
      expect(seen.covers('activities/act1/level_act1_01_beg.txt', 0, 0), isTrue);
      // One game when asked.
      final only = await search.execute({'query': '灯塔', 'game': 'endfield'});
      expect(only, isNot(contains('## 明日方舟')));
    });

    // 0.14 live: an archive held the answer, but search looked at story
    // text only and the model went to the wiki for it.
    test('search lists matching records (not story text) and they can be '
        'cited', () async {
      final ef = both.stores[Game.endfield]! as GameDataKnowledgeStore;
      final db = await sqflite.openDatabase(ef.dbPath!, singleInstance: false);
      await insertRecord(
        db,
        'ef/rec_lighthouse',
        contentType: 'archive_document',
        category: 'archive',
        subtype: 'document',
        content: '关于灯塔的记录：灯塔在第一次战争后熄灭。',
        fields: {'title': '灯塔档案'},
      );
      await db.close();
      final seen = SeenLines();
      final result = await SearchTool(both, seen).run('灯塔');
      final records = result.text.indexOf('## 终末地资料');
      expect(records, greaterThan(0));
      expect(
        result.text.substring(records),
        contains('record:ef/rec_lighthouse | archive·document | 灯塔档案 | 关于灯塔的记录'),
      );
      expect(seen.hasRecord('ef/rec_lighthouse'), isTrue);
    });

    // 0.14 live: without vectors, a question about a place found only a
    // short speaker name inside the place's name.
    test('without vectors the question\'s own phrases are keywords',
        () async {
      expect(
        SearchTool.phrasesOf('甲地的审判庭是做什么的？'),
        ['甲地', '审判庭'],
      );
      expect(SearchTool.phrasesOf('有人说她是萨卡兹，这个说法对吗？'), ['萨卡兹']);
      final result = await SearchTool(both, SeenLines()).run('灯塔是做什么的？');
      expect(result.mode, SearchMode.keywordOnly);
      expect(result.text, contains('关键词：灯塔'));
      expect(result.text, contains('level_act1_01_beg.txt'));
    });

    // 0.14 live: an operator's race was in their file (entity_documents),
    // which search did not look at; letters that mention the name came
    // instead.
    test('search lists the file of what a term names first, shown around '
        'the other terms', () async {
      final ef = both.stores[Game.endfield]! as GameDataKnowledgeStore;
      final db = await sqflite.openDatabase(ef.dbPath!, singleInstance: false);
      await insertRecord(
        db,
        'ef/rec_letter',
        contentType: 'mail',
        category: 'world',
        subtype: 'mail',
        content: '来自守灯人的信：今天也在擦灯。守灯人',
        fields: {'title': '守灯人的信'},
      );
      await db.insert('entity_documents', {
        // The v0.12.0 asset keeps these ids without ef/.
        'id': 'doc_keeper',
        'game': 'endfield',
        'language': 'zh',
        'entity_id': 'chr_keeper',
        'entity_name': '守灯人',
        'entity_type': 'operator',
        'document_type': 'operator_profile_bundle',
        'title': '守灯人',
        'summary': '守灯人看守灯塔。',
        'content': '## 基础档案\n守灯人看守灯塔。\n【种族】黎博利',
        'source_paths': '[]',
        'source_record_ids': '[]',
      });
      await db.close();
      final seen = SeenLines();
      final result = await SearchTool(both, seen).run('守灯人 种族');
      final records = result.text.indexOf('## 终末地资料');
      expect(records, greaterThan(0));
      final lines = result.text
          .substring(records)
          .split('\n')
          .where((l) => l.contains('record:'))
          .toList();
      expect(lines.first, contains('record:ef/doc_keeper | operator·operator_profile_bundle | 守灯人'));
      expect(lines.first, contains('【种族】黎博利'));
      expect(seen.hasRecord('ef/doc_keeper'), isTrue);
    });

    test('a wrong column comes back with the real columns', () async {
      final result = await SqlTool(both, SeenLines())
          .execute({'query': 'SELECT name FROM story_lines'});
      expect(result, contains('no such column'));
      expect(result, contains('story_lines 的列：'));
      expect(result, contains('content'));
    });

    test('another open of the same file closing does not close the store',
        () async {
      final ak = both.stores[Game.arknights]! as GameDataKnowledgeStore;
      const id = 'activities/act1/level_act1_01_beg.txt';
      expect((await ak.readStoryLines(storyId: id)).storyFound, isTrue);
      // What the knowledge-base page does to read the manifest.
      final other = await sqflite.openDatabase(ak.dbPath!, readOnly: true);
      await other.close();
      expect((await ak.readStoryLines(storyId: id)).storyFound, isTrue);
      // Tools of one turn open the store at the same time.
      final pages = await Future.wait([
        for (var i = 0; i < 4; i++) ak.readStoryLines(storyId: id),
      ]);
      expect(pages.every((p) => p.storyFound), isTrue);
    });

    test('a missing database answers empty; the other still works', () async {
      final only = MultiGameRetrieval({
        Game.arknights: both.stores[Game.arknights]!,
        Game.endfield: GameDataKnowledgeStore(
          dbPath: '${dir.path}/missing.db',
          game: Game.endfield,
        ),
      });
      expect(await only.installedGames(), [Game.arknights]);
      final counts = await only.storyLineHitCounts(['灯塔']);
      expect(counts.keys, ['activities/act1/level_act1_01_beg.txt']);
    });
  });

  test('the two-game section is in the prompt only when Endfield is installed',
      () {
    expect(loreSystemPrompt(), isNot(contains('ef/')));
    final both = loreSystemPrompt(games: [Game.arknights, Game.endfield]);
    expect(both, contains('ef/'));
    expect(both, contains('game'));
    expect(
      loreSystemPrompt(subtask: true, games: [Game.arknights, Game.endfield]),
      contains('ef/'),
    );
  });
}
