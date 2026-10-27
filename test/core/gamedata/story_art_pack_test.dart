import 'dart:io';

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/sqlite.dart';
import '../../support/story_art_pack_fixture.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;
  setUpAll(useSqfliteFfi);
  setUp(() => dir = Directory.systemTemp.createTempSync('portrait-read'));
  tearDown(() => deleteTempDir(dir));
  test('all layer forms, concurrent queries, close and reopen', () async {
    final file = await createStoryArtPack(dir);
    final pack = StoryArtPack(file.path);
    addTearDown(pack.close);
    expect(await pack.installed, isTrue);
    expect((await pack.manifest())['pack_version'], '2');
    final layers = await Future.wait(
        ['same', 'patch', 'whole', 'blank', 'missing'].map(pack.layers),);
    expect(layers[0]!.patch, isNull);
    expect(layers[1]!.base, layers[0]!.base);
    expect(layers[1]!.patch, isNotEmpty);
    expect(layers[1]!.x, 1);
    expect(layers[1]!.y, 1);
    expect(layers[2]!.base, isNot(layers[0]!.base));
    expect(layers[2]!.patch, isNull);
    expect(layers[3]!.blank, isTrue);
    expect(layers[3]!.base, isEmpty);
    expect(layers[4], isNull);
    await pack.close();
    expect(await pack.layers('whole'), isNotNull);
  });
  test('missing and invalid files are not installed', () async {
    final pack = StoryArtPack('${dir.path}/missing.db');
    addTearDown(pack.close);
    expect(await pack.installed, isFalse);
    expect(await pack.manifest(), isEmpty);
    expect(await pack.layers('same'), isNull);
    await File(pack.path).writeAsString('not a database');
    expect(await pack.installed, isFalse);
  });
  test('version 1 is rejected and categories follow event priority', () async {
    final old = StoryArtPack((await createStoryArtPack(dir, name: 'old.db', version: '1')).path);
    expect(await old.installed, isFalse);
    await old.close();
    final pack = StoryArtPack((await createStoryArtPack(dir, name: 'new.db')).path);
    expect((await pack.artImage('scene', 'background'))?.category, 'background');
    expect((await pack.artImage('scene', 'cg'))?.category, 'illustration');
    expect((await pack.artImage('scene', 'item'))?.category, 'illustration');
    expect((await pack.artTitle('cg'))?.title, 'Title');
    expect(await pack.artImage('unknown', 'cg'), isNull);
    final info = await pack.artInfo([('scene', 'background'), ('scene', 'cg'), ('unknown', 'cg')]);
    expect(info[('scene', 'background')]?.category, 'background');
    expect(info[('scene', 'cg')]?.category, 'illustration');
    expect(info.containsKey(('unknown', 'cg')), isFalse);
    await pack.close();
  });
  test('missing art tables return null', () async {
    final file = await createStoryArtPack(dir);
    final db = await openDatabase(file.path, singleInstance: false);
    await db.execute('DROP TABLE art_images');
    await db.execute('DROP TABLE art_titles');
    await db.close();
    final pack = StoryArtPack(file.path);
    expect(await pack.artImage('x', 'cg'), isNull);
    expect(await pack.artTitle('x'), isNull);
    expect(await pack.artInfo([('x', 'cg')]), isEmpty);
    await pack.close();
  });

}
