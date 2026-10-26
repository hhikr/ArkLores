import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../shared/providers/settings_provider.dart'
    show skipOperatorNamesProvider;
import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../gamedata/gamedata_provider.dart';
import 'portrait_queries.dart';

Future<R?> _query<R>(
    Ref ref, Future<R> Function(DatabaseExecutor) action,) async {
  // The store survives replacement; the status dependency refreshes query results.
  try {
    await ref.watch(gameDataInstallStatusProvider.future);
    return await ref
        .watch(gameStoreProvider(Game.arknights))
        .withDatabase(action);
  } catch (_) {
    return null;
  }
}

final hasPortraitIndexProvider = FutureProvider<bool>(
  (ref) async => await _query(ref, hasPortraitIndex) ?? false,
);
final spriteOfLineProvider =
    FutureProvider.family<String?, ({String storyId, int lineIndex})>(
  (ref, key) => _query<String?>(
      ref, (db) => spriteOfLine(db, key.storyId, key.lineIndex),),
);
final speakerPortraitsProvider =
    FutureProvider.family<SpeakerPortraits?, String>(
  (ref, name) =>
      _query<SpeakerPortraits?>(ref, (db) => speakerPortraits(db, name)),
);
final portraitGroupProvider = FutureProvider.family<PortraitGroup?, String>(
  (ref, id) => _query<PortraitGroup?>(ref, (db) => portraitGroup(db, id)),
);
final highlightNamesProvider = FutureProvider<List<String>>((ref) async {
  final skip = ref.watch(skipOperatorNamesProvider);
  return await _query(ref, (db) => highlightNames(db, skipOperators: skip)) ??
      const [];
});
