import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../shared/providers/settings_provider.dart'
    show settingsServiceProvider, skipOperatorNamesProvider;
import '../agent/agent_provider.dart' show gameStoreProvider;
import '../gamedata/game.dart';
import '../gamedata/gamedata_provider.dart';
import 'portrait_queries.dart';

Future<R?> _query<R>(
  Ref ref,
  Future<R> Function(DatabaseExecutor) action,
) async {
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
    ref,
    (db) => spriteOfLine(db, key.storyId, key.lineIndex),
  ),
);
final speakerPortraitsProvider =
    FutureProvider.family<SpeakerPortraits?, String>(
  (ref, name) =>
      _query<SpeakerPortraits?>(ref, (db) => speakerPortraits(db, name)),
);
final portraitGroupProvider = FutureProvider.family<PortraitGroup?, String>(
  (ref, id) => _query<PortraitGroup?>(ref, (db) => portraitGroup(db, id)),
);
final portraitSpritesProvider = FutureProvider.family<List<String>, String>(
  (ref, id) async =>
      await _query(ref, (db) => portraitSprites(db, id)) ?? const [],
);
final portraitStoriesProvider = FutureProvider.family<List<PortraitStory>,
    ({String speaker, String groupId})>(
  (ref, key) async =>
      await _query(
        ref,
        (db) => portraitStories(db, key.speaker, key.groupId),
      ) ??
      const [],
);

/// The names the knowledge base marks for answers (worked out once, when
/// the portrait index is built).
final indexedNamesProvider = FutureProvider<List<String>>((ref) async {
  final skip = ref.watch(skipOperatorNamesProvider);
  return await _query(ref, (db) => highlightNames(db, skipOperators: skip)) ??
      const [];
});

/// The reader's say over underlined names: on or off, and the names never
/// to underline.
class NameLinks {
  const NameLinks({this.on = true, this.blocked = const []});
  final bool on;

  /// In the order added.
  final List<String> blocked;
}

class NameLinksNotifier extends AsyncNotifier<NameLinks> {
  @override
  Future<NameLinks> build() async {
    final service = ref.read(settingsServiceProvider);
    try {
      return NameLinks(
        on: await service.loadNameLinks(),
        blocked: await service.loadBlockedNames(),
      );
    } catch (_) {
      return const NameLinks();
    }
  }

  NameLinks get _now => state.valueOrNull ?? const NameLinks();

  Future<void> setOn(bool on) async {
    state = AsyncData(NameLinks(on: on, blocked: _now.blocked));
    await ref.read(settingsServiceProvider).saveNameLinks(on);
  }

  /// Adds [name] (trimmed); false when it is empty or already there.
  Future<bool> block(String name) async {
    final value = name.trim();
    if (value.isEmpty || _now.blocked.contains(value)) return false;
    final blocked = [..._now.blocked, value];
    state = AsyncData(NameLinks(on: _now.on, blocked: blocked));
    await ref.read(settingsServiceProvider).saveBlockedNames(blocked);
    return true;
  }

  Future<void> unblock(String name) async {
    final blocked = [
      for (final n in _now.blocked)
        if (n != name) n,
    ];
    state = AsyncData(NameLinks(on: _now.on, blocked: blocked));
    await ref.read(settingsServiceProvider).saveBlockedNames(blocked);
  }
}

final nameLinksProvider =
    AsyncNotifierProvider<NameLinksNotifier, NameLinks>(NameLinksNotifier.new);

/// The names an answer underlines: the knowledge base's, unless the reader
/// turned them off, without the blocked ones. Matching them in an answer is
/// done as it is shown, so a change here shows at once.
final highlightNamesProvider = FutureProvider<List<String>>((ref) async {
  final links = await ref.watch(nameLinksProvider.future);
  if (!links.on) return const [];
  final names = await ref.watch(indexedNamesProvider.future);
  if (links.blocked.isEmpty) return names;
  final blocked = links.blocked.toSet();
  return [
    for (final name in names)
      if (!blocked.contains(name)) name,
  ];
});
