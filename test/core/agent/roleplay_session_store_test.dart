import 'dart:io';

import 'package:arklores/core/agent/roleplay_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/temp_dir.dart';

void main() {
  test('empty, save, load, a corrupt file, clear', () async {
    final dir = Directory.systemTemp.createTempSync('roleplay_store');
    addTearDown(() => deleteTempDir(dir));
    final path = '${dir.path}/roleplay.json';
    final store = RoleplaySessionStore(filePath: path);
    expect(await store.load(), isNull);

    await store.save({'version': 1, 'scene': '甲板'});
    expect((await store.load())?['scene'], '甲板');

    await File(path).writeAsString('{broken');
    expect(await store.load(), isNull);
    await store.clear();
    expect(File(path).existsSync(), isFalse);
  });
}
