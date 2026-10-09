import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/amiya_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  setUpAll(useSqfliteFfi);

  test('a cited record opens from its table, an operator file from its own',
      () async {
    final dir = Directory.systemTemp.createTempSync('cited_record_');
    final path = p.join(dir.path, 'kb.db');
    await createAmiyaDb(path);
    final store = GameDataKnowledgeStore(dbPath: path);
    final container = ProviderContainer(
      overrides: [sharedGameDataStoreProvider.overrideWithValue(store)],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
      await deleteTempDir(dir);
    });

    final record =
        await container.read(citedRecordProvider('record_voice_amiya').future);
    expect(record!.content, '博士，我们继续前进吧。');
    // 0.14: search also lists operator files (entity_documents).
    final file =
        await container.read(citedRecordProvider('doc_operator_amiya').future);
    expect(file!.title, '阿米娅');
    expect(file.content, contains('## 档案资料'));
    expect(
      await container.read(citedRecordProvider('no_such_record').future),
      isNull,
    );
  });
}
