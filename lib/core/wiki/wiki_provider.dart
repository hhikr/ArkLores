import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'wiki_lookup.dart';
import 'wiki_page.dart';
import 'wiki_sources.dart';

/// 0.13: the games' wikis for the Ask agent and the answer view. Fetched
/// page versions are kept in `wiki_snapshots/` under the app's documents,
/// so cited paragraphs stay readable offline and after the page changes.
final wikiLookupProvider = Provider<WikiLookup>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return WikiLookup(
    sources: {
      WikiSite.prts: PrtsWikiSource(client),
      WikiSite.warfarin: WarfarinWikiSource(client),
    },
    snapshots: WikiSnapshotStore(
      directory: () async => Directory(
        '${(await getApplicationDocumentsDirectory()).path}/wiki_snapshots',
      ),
    ),
  );
});

/// The kept version of a cited wiki page (`wiki:<site>:<key>@<version>`),
/// for the answer's evidence; null when it is not kept on this device.
final citedWikiPageProvider =
    FutureProvider.family<WikiPage?, String>((ref, pageId) async {
  try {
    return await ref.watch(wikiLookupProvider).snapshot(pageId);
  } catch (_) {
    return null;
  }
});
