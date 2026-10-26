import 'dart:io';

import 'package:arklores/core/gamedata/portrait_pack.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/portrait_pack_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;
  setUpAll(useSqfliteFfi);
  setUp(() => dir = Directory.systemTemp.createTempSync('portrait-read'));
  tearDown(() => deleteTempDir(dir));
  test('all layer forms, concurrent queries, close and reopen', () async {
    final file = await createPortraitPack(dir);
    final pack = PortraitPack(file.path);
    addTearDown(pack.close);
    expect(await pack.installed, isTrue);
    expect((await pack.manifest())['pack_version'], '1');
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
    final pack = PortraitPack('${dir.path}/missing.db');
    addTearDown(pack.close);
    expect(await pack.installed, isFalse);
    expect(await pack.manifest(), isEmpty);
    expect(await pack.layers('same'), isNull);
    await File(pack.path).writeAsString('not a database');
    expect(await pack.installed, isFalse);
  });
}
