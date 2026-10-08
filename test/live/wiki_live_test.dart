// 0.13: the agent's wiki tools against the real sites (opt-in: needs the
// network; free — no model is called).
//
//   $env:ARKLORES_RUN_WIKI_CHECK='true'
//   flutter test test/live/wiki_live_test.dart
//
// Checks shapes only (a search finds pages, a read gives a versioned page
// id and numbered paragraphs under sections), so it holds whatever the
// sites' editors change.
import 'dart:io';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/wiki_tools.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/wiki/wiki_lookup.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:arklores/core/wiki/wiki_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final run = Platform.environment['ARKLORES_RUN_WIKI_CHECK'] == 'true';
  late http.Client client;
  late WikiLookup wiki;

  setUpAll(() {
    client = http.Client();
    wiki = WikiLookup(sources: {
      WikiSite.prts: PrtsWikiSource(client),
      WikiSite.warfarin: WarfarinWikiSource(client),
    },);
  });
  tearDownAll(() => client.close());

  for (final (game, query) in [
    (Game.arknights, '阿米娅'),
    (Game.endfield, '佩丽卡'),
  ]) {
    test('${game.key}: search, then read the first page', () async {
      final hits = await wiki.search(game, query);
      expect(hits, isNotEmpty);
      final seen = SeenLines();
      final page = await wiki.read(hits.first.ref);
      expect(page, isNotNull);
      expect(WikiPageId.parse(page!.id), isNotNull);
      expect(page.blocks.length, greaterThan(5));
      expect(page.blocks.where((b) => b.section.isNotEmpty), isNotEmpty);
      final text = await WikiReadTool(wiki, seen)
          .execute({'page': page.id, 'count': 20});
      expect(text, contains('页面 id：${page.id}'));
      expect(text, contains('P0 '));
      expect(seen.covers(page.id, 0, 0), isTrue);
    }, skip: !run, timeout: const Timeout(Duration(minutes: 2)),);
  }
}
