part of 'entry_importer.dart';

/// Levels: enemy ↔ stage bindings.
extension _Levels on EntryImporter {
  /// Stage entry id for each level id (lower-cased), from every table that
  /// has stages with a `levelId`.
  Future<Map<String, List<String>>> _levelIndex(_Context ctx) async {
    final index = <String, List<String>>{};
    void add(String levelId, String entryId) {
      if (levelId.isEmpty) return;
      index.putIfAbsent(levelId.toLowerCase(), () => []).add(entryId);
    }

    final stages = _map((await _table(EntryTables.stage))['stages']);
    for (final entry in stages.entries) {
      final stage = _map(entry.value);
      add(
        _s(stage['levelId']),
        'stage:${_s(stage['stageId']).isEmpty ? entry.key : _s(stage['stageId'])}',
      );
    }
    final retro = _map((await _table(EntryTables.retro))['stageList']);
    for (final entry in retro.entries) {
      final stage = _map(entry.value);
      add(
        _s(stage['levelId']),
        'stage:${_s(stage['stageId']).isEmpty ? entry.key : _s(stage['stageId'])}',
      );
    }
    final details = _map((await _table(EntryTables.roguelikeTopic))['details']);
    for (final topic in details.entries) {
      for (final entry in _map(_map(topic.value)['stages']).entries) {
        add(
          _s(_map(entry.value)['levelId']),
          'roguelike_stage:${topic.key}/${entry.key}',
        );
      }
    }
    // Sandbox stages: the permanent topics and the first one (an activity).
    final perm = _map((await _table(EntryTables.sandboxPerm))['detail']);
    for (final template in perm.values) {
      for (final topic in _map(template).entries) {
        for (final entry in _map(_map(topic.value)['stageData']).entries) {
          final stage = _map(entry.value);
          add(
            _s(stage['levelId']),
            'sandbox_stage:${topic.key}/${_s(stage['stageId']).isEmpty ? entry.key : _s(stage['stageId'])}',
          );
        }
      }
    }
    final legacy = _map(
      _map(await _table(EntryTables.sandbox))['sandboxActTables'],
    );
    for (final act in legacy.entries) {
      for (final entry in _map(_map(act.value)['stageDatas']).entries) {
        final stage = _map(entry.value);
        add(
          _s(stage['levelId']),
          'sandbox_stage:${act.key}/${_s(stage['stageId']).isEmpty ? entry.key : _s(stage['stageId'])}',
        );
      }
    }
    return index;
  }

  /// Binds enemies to the stages they appear in, from the level files
  /// (`enemyDbRefs` and the `SPAWN` actions of the waves). Skipped when the
  /// source tree has no `levels/` directory (in-app builds).
  Future<void> _importLevels(_Context ctx) async {
    final root = Directory(p.join(sourceDir.path, _levels));
    if (!await root.exists()) return;
    final index = await _levelIndex(ctx);
    final enemies = {
      for (final r in await db.rawQuery(
        "SELECT id FROM entries WHERE type IN ('enemy', 'trap', 'token')",
      ))
        '${r['id']}',
    };
    final stages = {
      for (final r in await db.rawQuery(
        "SELECT id FROM entries WHERE type IN ('stage', 'roguelike_stage', 'sandbox_stage')",
      ))
        '${r['id']}',
    };
    for (final entry in index.entries) {
      final repoPath = '$_levels/${entry.key}.json';
      await _levelBindings(repoPath, entry.value, enemies, stages);
    }
  }

  /// [EntryImporter.importLevelFile].
  Future<void> _importLevelFile(String repoPath) async {
    // An update can change hundreds of level files: the stage index (it
    // parses several large tables) and the entry id sets are built once and
    // dropped when a table is re-imported.
    final index =
        _levelIndexCache ??= await _levelIndex(await _loadContext());
    final key = repoPath.substring('$_levels/'.length).replaceAll('.json', '');
    final stagesOfLevel = index[key.toLowerCase()];
    if (stagesOfLevel == null) return;
    final enemies = _enemyIdCache ??= {
      for (final r in await db.rawQuery(
        "SELECT id FROM entries WHERE type IN ('enemy', 'trap', 'token')",
      ))
        '${r['id']}',
    };
    final stages = _stageIdCache ??= {
      for (final r in await db.rawQuery(
        "SELECT id FROM entries WHERE type IN ('stage', 'roguelike_stage', 'sandbox_stage')",
      ))
        '${r['id']}',
    };
    await _levelBindings(repoPath, stagesOfLevel, enemies, stages);
  }

  Future<void> _levelBindings(
    String repoPath,
    List<String> stageIds,
    Set<String> enemies,
    Set<String> stages,
  ) async {
    final file = File(p.join(sourceDir.path, repoPath));
    if (!await file.exists()) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      return;
    }
    final level = _map(decoded);
    final ids = <String>{};
    for (final ref in _list(level['enemyDbRefs'])) {
      final id = _s(_map(ref)['id']);
      if (id.isNotEmpty) ids.add(id);
    }
    for (final wave in _list(level['waves'])) {
      for (final fragment in _list(_map(wave)['fragments'])) {
        for (final action in _list(_map(fragment)['actions'])) {
          final a = _map(action);
          if (_s(a['actionType']) == 'SPAWN' && _s(a['key']).isNotEmpty) {
            ids.add(_s(a['key']));
          }
        }
      }
    }
    // Traps and summons the level places (`predefines`, and the harder
    // variant's own list): character-table entries under `operator:`.
    for (final key in const ['predefines', 'hardPredefines']) {
      final defs = _map(level[key]);
      for (final list in const ['characterInsts', 'tokenInsts']) {
        for (final inst in _list(defs[list])) {
          final character = _s(_map(_map(inst)['inst'])['characterKey']);
          if (character.isNotEmpty) ids.add('operator:$character');
        }
      }
    }
    final targets = [for (final s in stageIds) if (stages.contains(s)) s];
    if (targets.isEmpty) return;
    final played = <String>{};
    _storyKeysOf(level, played);
    await db.transaction((txn) async {
      for (final id in ids) {
        final entry = id.startsWith('operator:') ? id : 'enemy:$id';
        if (!enemies.contains(entry)) continue;
        for (final stage in targets) {
          await _link(txn, entry, 'appears_in', stage, repoPath);
        }
      }
      // The stories the battle itself plays (`STORY` actions: tutorials,
      // training and in-battle dialogue). The story entries do not exist yet
      // on a full build; the ids are matched to them in [rebuildDerived].
      for (final key in played) {
        for (final stage in targets) {
          await _link(txn, 'story:$key', 'plays_in', stage, repoPath);
        }
      }
    });
  }

  /// The story files named by `STORY` actions anywhere in a level file, as
  /// `<path>.txt` in lower case with forward slashes (the key of a story).
  static void _storyKeysOf(Object? node, Set<String> out) {
    if (node is List) {
      for (final v in node) {
        _storyKeysOf(v, out);
      }
    } else if (node is Map) {
      if (node['actionType'] == 'STORY') {
        final key = _s(node['key']).toLowerCase().replaceAll('\\', '/');
        if (key.isNotEmpty) out.add(key.endsWith('.txt') ? key : '$key.txt');
      }
      for (final v in node.values) {
        _storyKeysOf(v, out);
      }
    }
  }
}
