part of 'entry_importer.dart';

/// Derived layer: collections and story entries.
extension _Derived on EntryImporter {
  /// [EntryImporter.rebuildDerived].
  Future<void> _rebuildDerived() async {
    final ctx = await _loadContext();
    final memberOf = await _memorySetOwners();
    final namer = await _storyNamer();
    await db.transaction((txn) async {
      await txn.delete('collections');
      await txn.delete('entries', where: "type = 'story'");
      await txn.delete('entry_links', where: "source_path = 'derived'");
      // Re-runs add nothing the original does not have: what the tables
      // attributed to them goes.
      if (ctx.dropped.isNotEmpty) {
        final marks = List.filled(ctx.dropped.length, '?').join(',');
        final ids = 'SELECT id FROM entries WHERE collection_id IN ($marks)';
        final args = ctx.dropped.toList();
        await txn.execute(
          'DELETE FROM normalized_records WHERE entry_id IN ($ids)',
          args,
        );
        await txn.execute(
          'DELETE FROM entry_links WHERE src IN ($ids) OR dst IN ($ids)',
          [...args, ...args],
        );
        final gone = [
          for (final r in await txn.rawQuery(ids, args)) '${r['id']}',
        ];
        await txn.execute(
          'DELETE FROM entries WHERE collection_id IN ($marks)',
          args,
        );
        for (final id in gone) {
          await txn.delete('entity_aliases', where: 'entity_id = ?', whereArgs: [id]);
          await txn.delete('entities', where: 'id = ?', whereArgs: [id]);
        }
      }
      importer.stats.collections = 0;
      final written = <String>{};
      Future<void> putCollection(
        String id,
        String kind,
        String? name,
        int? start,
        int sort, {
        String? parent,
      }) async {
        if (!written.add(id)) return;
        await txn.insert('collections', {
          'id': id,
          'kind': kind,
          'name': name,
          'parent_id': parent,
          'sort_key': sort,
          'start_time': start,
          'source_path': null,
        });
        importer.stats.collections++;
      }

      for (final entry in ctx.collections.entries) {
        final c = entry.value;
        await putCollection(
          entry.key,
          c.kind,
          c.name,
          c.start,
          c.sort,
          parent: memberOf[entry.key],
        );
      }

      // Stories: attribution from the catalog, else from the path.
      final hasCatalog = (await txn.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='story_catalog'",
      ))
          .isNotEmpty;
      // A file with nothing but a title line (a stub, a camera test) is not a
      // story: it gets no entry.
      final titleOnly = {
        for (final r in await txn.rawQuery(
          'SELECT story_id FROM story_lines GROUP BY story_id '
          "HAVING SUM(kind <> 'title') = 0",
        ))
          '${r['story_id']}',
      };
      final rows = [
        for (final r in await txn.rawQuery(
          hasCatalog
              ? 'SELECT s.story_id, s.source_path, c.collection_id, c.story_code, '
                  'c.story_name, c.avg_tag, c.story_sort '
                  'FROM story_scopes s LEFT JOIN story_catalog c '
                  'ON c.story_id = s.story_id ORDER BY s.story_id'
              : 'SELECT story_id, source_path, NULL AS collection_id, '
                  'NULL AS story_code, NULL AS story_name, NULL AS avg_tag, '
                  'NULL AS story_sort FROM story_scopes ORDER BY story_id',
        ))
          if (!titleOnly.contains('${r['story_id']}')) r,
      ];
      final systemNames = {
        'tutorial': '教程',
        'guide': '指引',
        'rune': '符文',
        'legion': '军团',
        'record': '记录',
      };
      var fallbackSort = 100000;
      // Files the catalog does not name get a name from the tables, from
      // the stage they belong to, or from their kind (see story_naming).
      final owners = <String, String?>{};
      final named = <String, StoryNaming>{};
      final unnamed = <String, List<String>>{};
      for (final row in rows) {
        final storyId = '${row['story_id']}';
        final owner = (row['collection_id'] as String?) ??
            _ownerOfStoryPath(ctx, storyId);
        owners[storyId] = owner;
        final catalogName = (row['story_name'] as String?)?.trim() ?? '';
        if (catalogName.isNotEmpty) continue;
        final found = namer.resolve(storyId, collectionId: owner);
        if (found != null) {
          named[storyId] = found;
        } else if (storyId.toLowerCase().contains('/battleavg/')) {
          // A map dialogue no table names is named after who speaks first.
          final first = await txn.rawQuery(
            'SELECT speaker FROM story_lines WHERE story_id = ? '
            "AND speaker IS NOT NULL AND speaker <> '' ORDER BY line_index LIMIT 1",
            [storyId],
          );
          final speaker = first.isEmpty ? '' : '${first.first['speaker']}'.trim();
          if (speaker.isNotEmpty) {
            named[storyId] = StoryNaming(name: speaker, group: npcDialogueGroup);
          } else {
            unnamed.putIfAbsent(owner ?? '', () => []).add(storyId);
          }
        } else {
          unnamed.putIfAbsent(owner ?? '', () => []).add(storyId);
        }
      }
      for (final ids in unnamed.values) {
        named.addAll(numberedKinds(ids));
      }
      final rank = <String, int>{};
      final order = named.keys.toList()..sort(naturalCompare);
      for (var i = 0; i < order.length; i++) {
        rank[order[i]] = i;
      }
      // Several files that carry one name (a merchant's visits, a part's two
      // dialogues) are told apart by a number, in reading order.
      final shownName = <String, String>{};
      final sameName = <String, List<String>>{};
      for (final row in rows) {
        final storyId = '${row['story_id']}';
        final naming = named[storyId];
        if ((row['story_name'] as String?)?.trim().isNotEmpty ?? false) continue;
        if (naming == null) continue;
        sameName
            .putIfAbsent('${owners[storyId]}|${naming.group}|${naming.name}', () => [])
            .add(storyId);
      }
      for (final ids in sameName.values) {
        if (ids.length < 2) continue;
        ids.sort((a, b) {
          final byOrder = ((named[a]!.sort ?? 0) * 10000 + rank[a]!)
              .compareTo((named[b]!.sort ?? 0) * 10000 + rank[b]!);
          return byOrder != 0 ? byOrder : naturalCompare(a, b);
        });
        for (var i = 1; i < ids.length; i++) {
          shownName[ids[i]] = '${named[ids[i]]!.name} · ${i + 1}';
        }
      }
      for (final row in rows) {
        final storyId = '${row['story_id']}';
        final owner = owners[storyId];
        if (owner != null && !written.contains(owner)) {
          final parts = storyId.split('/');
          final system = parts.length >= 2 && parts.first == 'obt'
              ? systemNames[parts[1]]
              : null;
          // A folder no table names (a mode's tutorials and guides, loose
          // files) is a system collection, never shown under its folder id.
          final kind = owner.startsWith('rogue_')
              ? 'roguelike'
              : owner.startsWith('sandbox_')
                  ? 'sandbox'
                  : system != null ||
                          owner.startsWith('system_') ||
                          storyId.startsWith('activities/')
                      ? 'system'
                      : 'activity';
          await putCollection(
            owner,
            kind,
            kind == 'system' ? system ?? '其他' : owner,
            null,
            fallbackSort++,
          );
        }
        final catalogName = (row['story_name'] as String?)?.trim();
        final naming = named[storyId];
        final fromCatalog = catalogName != null && catalogName.isNotEmpty;
        var sort = (row['story_sort'] as num?)?.toInt();
        if (!fromCatalog && naming != null) {
          // Unnamed files follow the catalogued chapters of their collection.
          sort = 1000000 + (naming.sort ?? 0) * 10000 + rank[storyId]!;
        }
        await importer.insertEntry(
          txn,
          id: 'story:$storyId',
          type: 'story',
          name: fromCatalog
              ? catalogName
              : shownName[storyId] ??
                  naming?.name ??
                  p.posix.basenameWithoutExtension(storyId),
          code: row['story_code'] as String?,
          collectionId: owner,
          groupName: fromCatalog
              ? row['avg_tag'] as String?
              : naming?.group ?? row['avg_tag'] as String?,
          sortKey: sort,
          rawId: storyId,
          sourcePath: '${row['source_path']}',
        );
      }
      // Every collection an entry names has a row; bindings need both ends.
      await txn.execute(
        'INSERT OR IGNORE INTO collections (id, kind, name, sort_key) '
        "SELECT DISTINCT collection_id, 'activity', collection_id, 999999 "
        'FROM entries WHERE collection_id IS NOT NULL',
      );
      await txn.execute(
        'UPDATE normalized_records SET collection_id = '
        '(SELECT collection_id FROM entries '
        'WHERE entries.id = normalized_records.entry_id) '
        "WHERE parent_type = 'story_file'",
      );
      await txn.execute(
        'UPDATE lore_chunks SET collection_id = '
        '(SELECT collection_id FROM entries '
        'WHERE entries.id = lore_chunks.entry_id) '
        "WHERE entry_id LIKE 'story:%'",
      );

      // story → stage. The game names a stage's story files after the stage
      // id (`level_<stage id>_beg.txt`); otherwise the same collection and
      // the same code bind them, when that is unique.
      final stageIds = {
        for (final r in await txn.rawQuery(
          "SELECT id FROM entries WHERE type = 'stage'",
        ))
          '${r['id']}',
      };
      final byCode = <String, List<String>>{};
      for (final r in await txn.rawQuery(
        "SELECT id, collection_id, code FROM entries WHERE type = 'stage' "
        "AND collection_id IS NOT NULL AND code IS NOT NULL AND code <> ''",
      )) {
        byCode
            .putIfAbsent('${r['collection_id']}|${r['code']}', () => [])
            .add('${r['id']}');
      }
      final nameStage = RegExp(r'^level_(.+?)(?:_(?:beg|end))?$');
      for (final r in await txn.rawQuery(
        "SELECT id, collection_id, code, raw_id FROM entries WHERE type = 'story'",
      )) {
        final base = p.posix.basenameWithoutExtension('${r['raw_id']}');
        final byName = nameStage.firstMatch(base)?.group(1);
        String? target;
        if (byName != null && stageIds.contains('stage:$byName')) {
          target = 'stage:$byName';
        } else if ('${r['code'] ?? ''}'.isNotEmpty) {
          final match = byCode['${r['collection_id']}|${r['code']}'];
          if (match != null && match.length == 1) target = match.single;
        }
        target ??= named['${r['raw_id']}']?.stageEntryId;
        if (target != null && target.isNotEmpty) {
          await _link(txn, '${r['id']}', 'belongs_to_stage', target, 'derived');
        }
        // A file the tables make part of an entry (an ending's pages, a month
        // squad's short stories) is bound to it; the order is its sort key.
        final parent = named['${r['raw_id']}']?.parent;
        if (parent != null && parent.isNotEmpty) {
          await _link(txn, '${r['id']}', 'part_of', parent, 'derived');
        }
      }
      // A topic without an ending book (older ones) still has the ending's
      // own story: the file named after the ending's number, level_*_ending_<n>,
      // for the ending whose id ends in ending_<n>. The story that opens a
      // topic is level_*_entry in every topic, named or not.
      final bound = {
        for (final r in await txn.rawQuery(
          "SELECT dst FROM entry_links WHERE relation = 'part_of'",
        ))
          '${r['dst']}',
      };
      for (final end in await txn.rawQuery(
        'SELECT id, collection_id, raw_id FROM entries '
        "WHERE type = 'roguelike_ending'",
      )) {
        if (bound.contains('${end['id']}')) continue;
        final n = RegExp(r'ending_(\d+)$').firstMatch('${end['raw_id']}')?.group(1);
        if (n == null) continue;
        for (final story in await txn.rawQuery(
          "SELECT id FROM entries WHERE type = 'story' AND collection_id = ? "
          'AND raw_id GLOB ?',
          ['${end['collection_id']}', '*level_*ending_$n.txt'],
        )) {
          await _link(txn, '${story['id']}', 'part_of', '${end['id']}', 'derived');
          await txn.rawUpdate(
            'UPDATE entries SET group_name = ? WHERE id = ?',
            [endingStoryKind, story['id']],
          );
        }
      }
      await txn.rawUpdate(
        "UPDATE entries SET group_name = ? WHERE type = 'story' "
        "AND raw_id GLOB '*level_*_entry.txt' "
        "AND collection_id IN (SELECT id FROM collections WHERE kind = 'roguelike')",
        [openingStoryKind],
      );

      await _attachLevelStories(txn, hasCatalog);
      // Stages are grouped by the zone they are in: its name, or no group
      // when the zone has none (an id is not a heading).
      await txn.execute(
        'UPDATE entries SET group_name = ('
        "SELECT z.name FROM entries z WHERE z.type = 'zone' "
        'AND z.raw_id = entries.group_name LIMIT 1) '
        "WHERE type = 'stage' AND group_name IS NOT NULL AND EXISTS ("
        "SELECT 1 FROM entries z WHERE z.type = 'zone' "
        'AND z.raw_id = entries.group_name)',
      );
      await txn.execute(
        "UPDATE entries SET group_name = NULL WHERE type = 'stage' "
        "AND group_name NOT GLOB '*[^a-z0-9_]*'",
      );
      // Mail groups are the sender: the character's name when the sender is
      // one, nothing otherwise. The key names of an activity's or a
      // sandbox's text tables are not headings.
      await txn.execute(
        'UPDATE entries SET group_name = ('
        "SELECT o.name FROM entries o WHERE o.id = 'operator:' || "
        'entries.group_name) '
        "WHERE type = 'mail' AND group_name LIKE 'char\\_%' ESCAPE '\\'",
      );
      await txn.execute(
        "UPDATE entries SET group_name = NULL WHERE type = 'mail' "
        "AND group_name NOT GLOB '*[^a-z0-9_]*'",
      );
      await txn.execute(
        'UPDATE entries SET group_name = NULL '
        "WHERE type IN ('activity_text', 'sandbox_text')",
      );
      // Rule stand-ins imported by earlier builds.
      final mechanic = EntryImporter._mechanicItemTypes.map((t) => "'$t'").join(',');
      await txn.execute(
        'DELETE FROM normalized_records WHERE entry_id IN (SELECT id FROM '
        "entries WHERE type = 'roguelike_item' AND group_name IN ($mechanic))",
      );
      await txn.execute(
        "DELETE FROM entries WHERE type = 'roguelike_item' "
        'AND group_name IN ($mechanic)',
      );
      // One collectible is one entry. The game lists the same one several
      // times (a topic's old and new table, one copy per variant or upgrade
      // step, differing only in effect text that is not imported): entries
      // of a topic with the same name and kind are one. The one kept is the
      // newer table's, then the shortest id; bindings of the others move to it.
      await txn.execute(
        'CREATE TEMP TABLE IF NOT EXISTS item_twin (id TEXT PRIMARY KEY, '
        'keep TEXT NOT NULL)',
      );
      await txn.execute('DELETE FROM item_twin');
      // Of the same name: the same kind of item, or the very same words
      // whatever the kind (a coin and its buff, an item and its ticket,
      // the same buff listed per slot).
      await txn.execute(
        'INSERT INTO item_twin (id, keep) '
        'SELECT e.id, (SELECT k.id FROM entries k '
        'LEFT JOIN normalized_records kr ON kr.id = k.record_id '
        "WHERE k.type = e.type AND IFNULL(k.collection_id, '') = "
        "IFNULL(e.collection_id, '') "
        'AND k.name = e.name AND ('
        "(e.type = 'roguelike_item' AND IFNULL(k.group_name, '') = "
        "IFNULL(e.group_name, '')) OR kr.content = er.content) "
        'ORDER BY k.source_path DESC, length(k.raw_id), k.raw_id LIMIT 1) '
        'FROM entries e LEFT JOIN normalized_records er ON er.id = e.record_id '
        "WHERE e.type IN ('roguelike_item', 'roguelike_buff', 'item')",
      );
      await txn.execute('DELETE FROM item_twin WHERE id = keep');
      // A twin whose kept one is itself a twin stays (never lose both).
      await txn.execute(
        'DELETE FROM item_twin WHERE keep IN (SELECT id FROM item_twin)',
      );
      for (final col in const ['src', 'dst']) {
        await txn.execute(
          'UPDATE OR IGNORE entry_links SET $col = '
          '(SELECT keep FROM item_twin WHERE id = entry_links.$col) '
          'WHERE $col IN (SELECT id FROM item_twin)',
        );
      }
      await txn.execute(
        'DELETE FROM entry_links WHERE src IN (SELECT id FROM item_twin) '
        'OR dst IN (SELECT id FROM item_twin)',
      );
      await txn.execute(
        'DELETE FROM normalized_records WHERE entry_id IN '
        '(SELECT id FROM item_twin)',
      );
      for (final table in const ['entity_aliases', 'entities']) {
        await txn.execute(
          'DELETE FROM $table WHERE ${table == 'entities' ? 'id' : 'entity_id'} '
          'IN (SELECT id FROM item_twin)',
        );
      }
      await txn.execute(
        'DELETE FROM entries WHERE id IN (SELECT id FROM item_twin)',
      );
      await txn.execute('DROP TABLE item_twin');
      // Bindings whose ends are not entries (an operator without a profile,
      // a zone without a name) are dropped.
      await txn.execute(
        'DELETE FROM entry_links WHERE src NOT IN (SELECT id FROM entries) '
        'OR dst NOT IN (SELECT id FROM entries)',
      );
    });
  }

  /// Dialogue played inside a battle (tutorial popups, training, in-battle
  /// conversations) is not a story of its own: it is read at the end of the
  /// story of its stage, or on the stage's page when the stage has none.
  ///
  /// A story is in-battle dialogue when a level file plays it (`STORY` action,
  /// `plays_in`: the stage of that level), or when it is a training or
  /// tutorial file the names bind to a stage. The stories of the catalog (the
  /// chapters players read) are never in-battle dialogue. Each such story gets
  /// an `attached_to` link to its host: the first story of its stage in
  /// reading order, else the stage entry. Lists leave attached stories out.
  Future<void> _attachLevelStories(Transaction txn, bool hasCatalog) async {
    final storyIds = {
      for (final r in await txn.rawQuery(
        "SELECT id, raw_id FROM entries WHERE type = 'story'",
      ))
        '${r['raw_id']}'.toLowerCase(): '${r['id']}',
    };
    // Level files name stories in whatever case the game wrote.
    for (final r in await txn.rawQuery(
      "SELECT src, dst, source_path FROM entry_links WHERE relation = 'plays_in'",
    )) {
      final src = '${r['src']}';
      final id =
          storyIds[(src.length > 6 ? src.substring(6) : src).toLowerCase()];
      if (id == src) continue;
      await txn.delete(
        'entry_links',
        where: "src = ? AND relation = 'plays_in' AND dst = ?",
        whereArgs: [src, r['dst']],
      );
      if (id != null) {
        await _link(txn, id, 'plays_in', '${r['dst']}', '${r['source_path']}');
      }
    }
    // Training and tutorial files the names bind to a stage play there too.
    for (final r in await txn.rawQuery(
      'SELECT l.src, l.dst, e.raw_id FROM entry_links l '
      'JOIN entries e ON e.id = l.src '
      "WHERE l.relation = 'belongs_to_stage' AND e.type = 'story'",
    )) {
      if (const {'训练', '训练关卡', '教程'}.contains(storyKindLabel('${r['raw_id']}'))) {
        await _link(txn, '${r['src']}', 'plays_in', '${r['dst']}', 'derived');
      }
    }
    // A map's signs and its stage-bound dialogues are named after the stage
    // they stand in (`dialog_<topic>_level_<n>` → stage `<topic>_<n>`).
    final sandboxStages = {
      for (final r in await txn.rawQuery(
        "SELECT id FROM entries WHERE type = 'sandbox_stage'",
      ))
        '${r['id']}',
    };
    if (sandboxStages.isNotEmpty) {
      final named = RegExp(r'^dialog_(.+?)_level_(\d+)(?:_\d+)?$');
      for (final r in await txn.rawQuery(
        "SELECT id, raw_id FROM entries WHERE type = 'story' "
        "AND raw_id LIKE '%/dialog_%level%'",
      )) {
        final base = p.posix.basenameWithoutExtension('${r['raw_id']}');
        final m = named.firstMatch(base);
        if (m == null) continue;
        final stage = 'sandbox_stage:${m[1]}/${m[1]}_${m[2]}';
        if (sandboxStages.contains(stage)) {
          await _link(txn, '${r['id']}', 'plays_in', stage, 'derived');
        }
      }
    }    // The catalog's chapters are stories, whoever plays them.
    if (hasCatalog) {
      await txn.execute(
        'DELETE FROM entry_links WHERE relation = ? AND src IN '
        '(SELECT e.id FROM entries e JOIN story_catalog c '
        'ON c.story_id = e.raw_id '
        "WHERE e.type = 'story' AND c.story_name IS NOT NULL "
        "AND c.story_name <> '')",
        ['plays_in'],
      );
    }
    final inBattle = {
      for (final r in await txn.rawQuery(
        "SELECT DISTINCT src FROM entry_links WHERE relation = 'plays_in'",
      ))
        '${r['src']}',
    };
    if (inBattle.isEmpty) return;
    // They are bound to their stage by `plays_in`, not `belongs_to_stage`.
    await txn.execute(
      "DELETE FROM entry_links WHERE relation = 'belongs_to_stage' AND src IN "
      "(SELECT DISTINCT src FROM entry_links WHERE relation = 'plays_in')",
    );
    for (final story in inBattle) {
      final stages = [
        for (final r in await txn.rawQuery(
          "SELECT dst FROM entry_links WHERE src = ? AND relation = 'plays_in' "
          'ORDER BY dst',
          [story],
        ))
          '${r['dst']}',
      ];
      String? host;
      for (final stage in stages) {
        final first = await txn.rawQuery(
          'SELECT e.id FROM entry_links l JOIN entries e ON e.id = l.src '
          "WHERE l.dst = ? AND l.relation = 'belongs_to_stage' "
          "AND e.type = 'story' ORDER BY e.sort_key, e.id LIMIT 1",
          [stage],
        );
        if (first.isNotEmpty) {
          host = '${first.first['id']}';
          break;
        }
      }
      host ??= stages.isEmpty ? null : stages.first;
      if (host != null) await _link(txn, story, 'attached_to', host, 'derived');
    }
  }
  /// The lookups that name story files the catalog does not name: names the
  /// tables give them, the stages of the library, stage names by id and by
  /// level file.
  Future<StoryNamer> _storyNamer() async {
    final hints = <String, StoryHint>{};
    final stageNames = <String, String>{};
    final levelNames = <String, String>{};
    hints.addAll(
      roguelikeStoryHints(await _table(EntryTables.roguelikeTopic), _clean),
    );
    final sandbox = sandboxStoryNames(await _table(EntryTables.sandboxPerm), _clean);
    hints.addAll(sandbox.hints);
    levelNames.addAll(sandbox.levelNames);
    collectStageNames(
      _map((await _table(EntryTables.stage))['stages']),
      stageNames,
      levelNames,
      _clean,
    );
    collectStageNames(
      _map((await _table(EntryTables.retro))['stageList']),
      stageNames,
      levelNames,
      _clean,
    );
    final readBy = <String, String>{};
    for (final r in await db.rawQuery(
      'SELECT l.dst AS dst, e.name AS name FROM entry_links l '
      "JOIN entries e ON e.id = l.src WHERE l.relation = 'reads_story'",
    )) {
      final dst = '${r['dst']}';
      final name = '${r['name'] ?? ''}'.trim();
      if (name.isNotEmpty && dst.startsWith('story:')) {
        readBy[storyKey(dst.substring(6))] = name;
      }
    }
    final stages = <StageRef>[];
    final collectionOfStage = <String, String>{};
    for (final r in await db.rawQuery(
      'SELECT id, raw_id, name, code, collection_id FROM entries '
      "WHERE type = 'stage' AND collection_id IS NOT NULL",
    )) {
      final id = '${r['id']}';
      stages.add(StageRef(id, '${r['raw_id']}', '${r['name'] ?? ''}', r['code'] as String?));
      collectionOfStage[id] = '${r['collection_id']}';
    }
    return StoryNamer(
      hints: hints,
      readBy: readBy,
      stages: stages,
      collectionOfStage: collectionOfStage,
      levelNames: levelNames,
      stageNames: stageNames,
    );
  }

  /// Memory story set id → `operator:<charId>` from the handbook's record
  /// lists (`handbookDict.<char>.handbookAvgList[].storySetId`).
  Future<Map<String, String>> _memorySetOwners() async {
    final dict = _map((await _table(EntryTables.handbook))['handbookDict']);
    final owners = <String, String>{};
    for (final entry in dict.entries) {
      for (final set in _list(_map(entry.value)['handbookAvgList'])) {
        final id = _s(_map(set)['storySetId']);
        if (id.isNotEmpty) owners[id] = 'operator:${entry.key}';
      }
    }
    return owners;
  }

  /// Collection of a story file without a catalog row, from its path.
  String? _ownerOfStoryPath(_Context ctx, String storyId) {
    final parts = storyId.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return null;
    if (parts.first == 'activities') {
      final folder = parts[1];
      // A loose file under `activities/` belongs to no activity.
      if (parts.length < 3) return 'system_activities';
      if (ctx.collections.containsKey(folder)) return folder;
      return _activityOfFolder(ctx, folder) ?? folder;
    }
    if (parts.first != 'obt') return null;
    final group = parts[1];
    // A path segment that is a known collection id owns the story.
    for (final segment in parts.skip(2)) {
      if (ctx.collections.containsKey(segment)) return segment;
    }
    final all = parts.join('/');
    final rogue = RegExp(r'rogue_(\d+)|/ro(\d+)/|rogue(\d+)_').firstMatch(all);
    if (rogue != null) {
      final n = rogue.group(1) ?? rogue.group(2) ?? rogue.group(3);
      return 'rogue_$n';
    }
    if (group == 'sandboxperm' && parts.length > 2) return parts[2];
    final file = parts.last;
    // Main story files are named by chapter; operator records by set.
    final chapter = RegExp(r'^level_main_(\d+)-').firstMatch(file);
    if (group == 'main' && chapter != null) {
      return 'main_${int.parse(chapter.group(1)!)}';
    }
    final record = RegExp(r'^(story_.+)_(\d+)_\d+\.txt$').firstMatch(file);
    if (group == 'memory' && record != null) {
      return '${record.group(1)}_set_${record.group(2)}';
    }
    return 'system_$group';
  }

  /// A story folder that is not an activity id (`arkhub`, `bossrush`) belongs
  /// to the activity whose id carries it after the `act<n>` prefix
  /// (`act1arkhub`), or a longer/shorter form of it (`vecbreak` ~ `act1vecb`).
  /// The first such activity in id order wins. Null when none matches.
  String? _activityOfFolder(_Context ctx, String folder) {
    final ids = ctx.collections.keys.toList()..sort(naturalCompare);
    for (final id in ids) {
      if (ctx.collections[id]!.kind != 'activity') continue;
      final tail = RegExp(r'^act\d+(.+)$').firstMatch(id)?.group(1);
      if (tail == null || tail.length < 4) continue;
      if (tail == folder || folder.startsWith(tail) || tail.startsWith(folder)) {
        return id;
      }
    }
    return null;
  }
}
