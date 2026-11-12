// The library's queries run again when another knowledge base is put in
// place (2026-11-13: the library tab, kept alive, kept the old database's
// answers until it was pulled to refresh).
import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  setUpAll(useSqfliteFfi);

  test('a replaced knowledge base refreshes the word counts', () async {
    final dir = Directory.systemTemp.createTempSync('library-provider');
    final db = await createGameDataDb('${dir.path}/kb.db');
    final store = GameDataKnowledgeStore(dbPath: db.path);
    final container = ProviderContainer(overrides: [
      sharedGameDataStoreProvider.overrideWithValue(store),
      gameDataInstalledProvider.overrideWith(
        (ref) async => GameDataInstallStatus(
          installed: true,
          dbPath: db.path,
          bytes: 1,
          manifest: const {},
        ),
      ),
    ],);
    try {
      final counts = collectionWordCountsProvider(Game.arknights);
      expect(await container.read(counts.future), isEmpty);
      await insertStory(db, 'act/level_a.txt', ['甲：一二三']);
      await db.insert('entries', {
        'id': 'story:act/level_a.txt',
        'type': 'story',
        'collection_id': 'act',
        'raw_id': 'act/level_a.txt',
      });
      // Kept once read: the same database gives the same counts.
      expect(await container.read(counts.future), isEmpty);
      container.invalidate(gameDataInstalledProvider);
      expect(await container.read(counts.future), {'act': 3});
    } finally {
      container.dispose();
      await store.close();
      await db.close();
      await deleteTempDir(dir);
    }
  });
}
