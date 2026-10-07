// FIND (`search_story_lines`) beyond its scope: hits elsewhere, near names
// for a misspelt one, and scope ids written as paths.
import 'dart:io';

import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/search_story_lines.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/sqlite.dart';
import '../../../support/temp_dir.dart';
import '../../../support/two_activities_fixture.dart';

void main() {
  late Directory dir;
  late SearchStoryLinesTool tool;

  setUpAll(useSqfliteFfi);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('search_story_lines');
    final path = '${dir.path}/kb.db';
    await createTwoActivitiesDb(path);
    final store = GameDataKnowledgeStore(dbPath: path);
    addTearDown(store.close);
    tool = SearchStoryLinesTool(gameDataStore: store);
  });
  tearDown(() => deleteTempDir(dir));

  Future<String> find(Map<String, dynamic> args) async =>
      ((await tool.execute(args)) as ToolExecutionResult).observation;

  test('a scope without hits reports where the term does occur', () async {
    final scoped = await find({'query': '灯塔', 'scope_id': 'activity:act_old'});
    expect(scoped, contains('范围外命中：“灯塔”在 activity:act_old 内 0 行'));
    expect(scoped, contains('activities/act_new/'));
    expect(scoped, isNot(contains('资料未覆盖')));
  });

  test('a misspelt name gets near names', () async {
    expect(await find({'query': '凯仑'}), contains('相近的名字：凯伦'));
  });

  test('a story-path scope names its activity; a chapter file is not a scope',
      () async {
    expect(normalizeScopeId('activities/act_new'), 'activity:act_new');
    expect(normalizeScopeId('@activities/act_new/'), 'activity:act_new');
    for (final file in [
      '@activities/act_new/level_act_new_01.txt',
      'obt/memory/story_x_1_1',
    ]) {
      final text = await find({'query': '灯塔', 'scope_id': file});
      expect(text, contains('是单个章节文件，不是检索范围'), reason: file);
      expect(text, contains('READ '), reason: file);
    }
  });
}
