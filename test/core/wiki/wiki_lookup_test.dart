import 'dart:io';

import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/wiki/wiki_lookup.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_wiki.dart';
import '../../support/temp_dir.dart';

/// 0.13: fetched page versions are kept, so a citation shows what the
/// agent read even after the page changed, offline, and after a restart.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('arklores_wiki'));
  tearDown(() => deleteTempDir(dir));

  test('reads by ref, title or versioned id; a versioned id is the kept '
      'snapshot', () async {
    final prts = fakePrts();
    final wiki = WikiLookup(
      sources: {WikiSite.prts: prts},
      snapshots: WikiSnapshotStore(directory: () async => dir),
    );
    final first = await wiki.read('wiki:prts:101');
    expect(first!.id, 'wiki:prts:101@7');
    expect((await wiki.read('星灯', game: Game.arknights))!.key, '101');
    // Fetched once: the title read hit the cache of the current version.
    expect(prts.fetches, 2);

    // The page is edited; the cited version stays readable.
    prts.version = '8';
    final kept = await wiki.read('wiki:prts:101@7');
    expect(kept!.version, '7');
    expect((await wiki.snapshot('wiki:prts:101@7'))!.blocks, hasLength(4));

    // After a restart (a new lookup), from disk.
    final again = WikiLookup(
      sources: {WikiSite.prts: prts},
      snapshots: WikiSnapshotStore(directory: () async => dir),
    );
    final restored = await again.snapshot('wiki:prts:101@7');
    expect(restored!.title, '星灯');
    expect(restored.blocks[1].section, '人物关系');
    expect(await again.snapshot('wiki:prts:101@9'), isNull);
  });

  test('a recent current version is not fetched again; an old one is',
      () async {
    var now = DateTime(2026, 10, 9, 12);
    final prts = fakePrts();
    final wiki = WikiLookup(
      sources: {WikiSite.prts: prts},
      cacheTtl: const Duration(minutes: 30),
      now: () => now,
    );
    await wiki.read('wiki:prts:101');
    await wiki.read('wiki:prts:101');
    expect(prts.fetches, 1);
    now = now.add(const Duration(hours: 2));
    await wiki.read('wiki:prts:101');
    expect(prts.fetches, 2);
  });

  test('unknown pages and sites are null; a game without a wiki source '
      'searches nothing', () async {
    final wiki = fakeWikiLookup();
    expect(await wiki.read('wiki:prts:999'), isNull);
    expect(await wiki.read('wiki:nowhere:1'), isNull);
    expect(await wiki.search(Game.endfield, '星灯'), isEmpty);
  });

  test('old snapshots are pruned past the limit', () async {
    final store = WikiSnapshotStore(directory: () async => dir, maxFiles: 2);
    for (var v = 0; v < 4; v++) {
      await store.save(WikiPage(
        site: WikiSite.prts,
        key: '1',
        version: '$v',
        title: 't',
        url: Uri.parse('https://prts.wiki/'),
        fetchedAt: DateTime.now(),
        blocks: const [WikiBlock('', 'x')],
      ),);
    }
    expect(dir.listSync(), hasLength(2));
  });
}
