// 0.12: one retrieval surface over two games' databases; ids name their
// game, so calls about one story go to its database and corpus-wide calls
// ask both.
import 'dart:io';

import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:flutter_test/flutter_test.dart';

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
