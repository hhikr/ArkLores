import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/gamedata/build/portrait_index.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/core/library/portrait_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  setUpAll(useSqfliteFfi);
  test('knowledge base status invalidation refreshes cached portrait queries', () async {
    final dir = Directory.systemTemp.createTempSync('portrait-provider');
    final db = await createGameDataDb('${dir.path}/kb.db');
    final store = GameDataKnowledgeStore(dbPath: db.path);
    final container = ProviderContainer(overrides: [
      sharedGameDataStoreProvider.overrideWithValue(store),
      gameDataInstallStatusProvider.overrideWith((ref) async => GameDataInstallStatus(
        installed: true, dbPath: db.path, bytes: 1, manifest: const {},
      ),),
    ],);
    try {
      expect(await container.read(hasPortraitIndexProvider.future), isFalse);
      expect(await container.read(spriteOfLineProvider((storyId: 'story', lineIndex: 1)).future), isNull);
      await db.execute(portraitGroupsDdl);
      await db.execute(storyLinePortraitsDdl);
      await db.insert('story_line_portraits', {'story_id': 'story', 'line_index': 1, 'sprite': 'sprite'});
      container.invalidate(gameDataInstallStatusProvider);
      expect(await container.read(hasPortraitIndexProvider.future), isTrue);
      expect(await container.read(spriteOfLineProvider((storyId: 'story', lineIndex: 1)).future), 'sprite');
    } finally {
      container.dispose();
      await store.close();
      await db.close();
      await deleteTempDir(dir);
    }
  });
}
