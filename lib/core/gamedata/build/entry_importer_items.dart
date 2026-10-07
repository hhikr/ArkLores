part of 'entry_importer.dart';

/// Items, skins, medals, modules, charms.
extension _Items on EntryImporter {
  Future<void> _items(Transaction txn, _Context ctx) async {
    const path = EntryTables.item;
    final items = _map((await _table(path))['items']);
    // An activity's items: the id says it (`act12side_token_x`), else the
    // stage it drops in, else the one activity whose tables mention it.
    final owners = <String, String?>{};
    final pending = <String>{};
    for (final entry in items.entries) {
      final item = _map(entry.value);
      final id = _s(item['itemId']).isEmpty ? entry.key : _s(item['itemId']);
      var owner = ctx.collectionForId(id) ?? _chapterOfItem(ctx, id);
      final icon = _s(item['iconId']);
      if (owner == null &&
          (ctx.collections.containsKey(icon) || ctx.alias.containsKey(icon))) {
        owner = ctx.home(icon);
      }
      if (owner == null && _isActivityItem(_s(item['itemType']))) {
        final drops = {
          for (final d in _list(item['stageDropList']))
            ctx.collectionOfStage(_s(_map(d)['stageId'])),
        }..remove(null);
        if (drops.length == 1) {
          owner = drops.single;
        } else {
          pending.add(id);
        }
      }
      owners[id] = owner;
    }
    owners.addAll(await _activityMentions(ctx, pending));
    for (final entry in items.entries) {
      final item = _map(entry.value);
      final id = _s(item['itemId']).isEmpty ? entry.key : _s(item['itemId']);
      final name = _clean(item['name']);
      final desc = cleanDescription(_s(item['description']));
      final usage = _clean(item['usage']);
      final sections = [
        if (hasChinese(desc)) TextSection('', desc),
        if (hasChinese(usage) && !isMechanical(usage)) TextSection('', usage),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'item',
          key: id,
          sourcePath: path,
          name: name,
          collectionId: owners[id],
          groupName: _s(item['itemType']),
          sortKey: _int(item['sortId']),
          sections: sections,
        ),
      );
    }
  }

  /// The item types that belong to an activity (its tokens, coins, stage
  /// tickets, operator folders).
  static bool _isActivityItem(String type) =>
      type.startsWith('ACTIVITY') || type == 'ET_STAGE';

  /// A main chapter's story items (`main16_spitem_1`: the chapter's id is
  /// written without its underscore).
  String? _chapterOfItem(_Context ctx, String id) {
    final n = RegExp(r'^main(\d+)_').firstMatch(id)?.group(1);
    if (n == null) return null;
    final chapter = 'main_${int.parse(n)}';
    return ctx.collections.containsKey(chapter) ? chapter : null;
  }

  /// For each of [ids], the one activity whose tables (the activity table's
  /// sections, by activity id) name it, when there is exactly one.
  Future<Map<String, String>> _activityMentions(
    _Context ctx,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final table = await _table(EntryTables.activity);
    final basic = _map(table['basicInfo']);
    final found = <String, Set<String>>{};
    void scan(String actId, Object? node) {
      final text = jsonEncode(node);
      for (final id in ids) {
        if (text.contains('"$id"')) (found[id] ??= {}).add(ctx.home(actId)!);
      }
    }

    for (final section in const [
      'activity',
      'dynActs',
      'extraData',
      'stageRewardsData',
      'actFunData',
      'missionData',
      'missionGroup',
    ]) {
      final root = _map(table[section]);
      for (final entry in root.entries) {
        if (basic.containsKey(entry.key)) {
          scan(entry.key, entry.value);
        } else {
          for (final inner in _map(entry.value).entries) {
            if (basic.containsKey(inner.key)) scan(inner.key, inner.value);
          }
        }
      }
    }
    return {
      for (final e in found.entries)
        if (e.value.length == 1 && ctx.collections.containsKey(e.value.single))
          e.key: e.value.single,
    };
  }

  /// One section per text, each line (paragraph) only where it first
  /// appears: a line that is, or is part of, one already said is dropped.
  static List<TextSection> _distinctParagraphs(List<String> texts) {
    final said = <String>[];
    final out = <TextSection>[];
    for (final text in texts) {
      final lines = <String>[];
      for (final raw in text.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (said.any((s) => s.contains(line))) continue;
        said.add(line);
        lines.add(line);
      }
      if (lines.isNotEmpty) out.add(TextSection('', lines.join('\n')));
    }
    return out;
  }

  Future<void> _skins(Transaction txn, _Context ctx) async {
    const path = EntryTables.skin;
    final table = await _table(path);
    // A brand (series) lists the groups of skins it released.
    final brandOfGroup = <String, String>{};
    for (final entry in _map(table['brandList']).entries) {
      final brand = _map(entry.value);
      final brandId = _s(brand['brandId']).isEmpty ? entry.key : _s(brand['brandId']);
      for (final group in _list(brand['groupList'])) {
        final groupId = _s(_map(group)['skinGroupId']);
        if (groupId.isNotEmpty) brandOfGroup.putIfAbsent(groupId, () => brandId);
      }
    }
    for (final entry in _map(table['charSkins']).entries) {
      final skin = _map(entry.value);
      final display = _map(skin['displaySkin']);
      final name = _clean(display['skinName']);
      // The fields overlap (the description's paragraphs come again in the
      // content): a paragraph is said once.
      final sections = _distinctParagraphs([
        for (final key in const ['description', 'dialog', 'content'])
          if (hasChinese(_s(display[key])))
            cleanDescription(_s(display[key])),
        if (hasChinese(_s(display['usage'])) &&
            !isMechanical(_s(display['usage'])))
          _clean(display['usage']),
      ]);
      if (name.isEmpty || sections.isEmpty) continue;
      final id = _s(skin['skinId']).isEmpty ? entry.key : _s(skin['skinId']);
      final entryId = 'skin:$id';
      final written = await _emit(
        txn,
        _Draft(
          type: 'skin',
          key: id,
          sourcePath: path,
          name: name,
          groupName: _clean(display['skinGroupName']),
          sections: sections,
        ),
      );
      final charId = _s(skin['charId']);
      if (written && charId.isNotEmpty) {
        await _link(txn, entryId, 'belongs_to', 'operator:$charId', path);
      }
      final brand = brandOfGroup[_s(display['skinGroupId'])];
      if (written && brand != null) {
        await _link(txn, entryId, 'belongs_to', 'skin_brand:$brand', path);
      }
    }
    for (final entry in _map(table['brandList']).entries) {
      final brand = _map(entry.value);
      final name = _clean(brand['brandName']);
      final desc = cleanDescription(_s(brand['description']));
      if (name.isEmpty || !hasChinese(desc)) continue;
      await _emit(
        txn,
        _Draft(
          type: 'skin_brand',
          key: _s(brand['brandId']).isEmpty ? entry.key : _s(brand['brandId']),
          sourcePath: path,
          name: name,
          sortKey: _int(brand['sortId']),
          sections: [TextSection('', desc)],
        ),
      );
    }
  }

  Future<void> _medals(Transaction txn, _Context ctx) async {
    const path = EntryTables.medal;
    final table = await _table(path);
    // The table names its groups (履历奖章, 章节奖章 …).
    final groups = _map(table['medalTypeData']);
    for (final raw in _list(table['medalList'])) {
      final medal = _map(raw);
      final id = _s(medal['medalId']);
      final name = _clean(medal['medalName']);
      final desc = cleanDescription(_s(medal['description']));
      if (id.isEmpty || name.isEmpty || !hasChinese(desc)) continue;
      // What the condition names: stages, activities, a record set, characters.
      final params = [
        for (final p in _list(medal['unlockParam']))
          ...'$p'.split(RegExp(r'[;,]')).map((s) => s.trim()),
      ].where((s) => s.isNotEmpty).toList();
      final written = await _emit(
        txn,
        _Draft(
          type: 'medal',
          key: id,
          sourcePath: path,
          name: name,
          collectionId: _medalOwner(ctx, id, params),
          groupName: _clean(_map(groups[_s(medal['medalType'])])['medalName']),
          sortKey: _int(medal['slotId']),
          sections: [TextSection('', desc)],
        ),
      );
      if (!written) continue;
      for (final token in params) {
        // A character (an operator, or the skin `<char>@<set>#<n>`).
        if (!RegExp(r'^char_[A-Za-z0-9]+_[A-Za-z0-9_]+(@[^#]+#\d+)?$')
            .hasMatch(token)) {
          continue;
        }
        final target = token.contains('@')
            ? 'skin:$token'
            : 'operator:$token';
        await _link(txn, 'medal:$id', 'features', target, path);
      }
    }
  }

  /// The collection a medal is about. Its id says it (`medal_activity_<活动>_n`),
  /// else what its condition names: a record set, an activity, a stage's
  /// chapter (a stage or zone id).
  String? _medalOwner(_Context ctx, String id, List<String> params) {
    // `medal_activity_<活动>_<n>`; the activity id may lack its `act`.
    final stem = RegExp(r'^medal_activity_(.+?)_\d+$').firstMatch(id)?.group(1);
    for (final candidate in [if (stem != null) ...[stem, 'act$stem']]) {
      if (ctx.collections.containsKey(candidate) ||
          ctx.alias.containsKey(candidate)) {
        return ctx.home(candidate);
      }
    }
    final byId = ctx.collectionForId(id);
    if (byId != null) return byId;
    for (final token in params) {
      if (ctx.collections.containsKey(token) || ctx.alias.containsKey(token)) {
        return ctx.home(token);
      }
      final byStage = ctx.collectionOfStage(token);
      if (byStage != null) return byStage;
      if (ctx.zoneType.containsKey(token)) {
        final byZone = ctx.home(ctx.collectionOfZone(token));
        if (byZone != null) return byZone;
      }
    }
    return null;
  }

  Future<void> _modules(Transaction txn, _Context ctx) async {
    const path = EntryTables.uniequip;
    final dict = _map((await _table(path))['equipDict']);
    for (final entry in dict.entries) {
      final module = _map(entry.value);
      final id = _s(module['uniEquipId']).isEmpty
          ? entry.key
          : _s(module['uniEquipId']);
      final name = _clean(module['uniEquipName']);
      final desc = cleanDescription(_s(module['uniEquipDesc']));
      if (name.isEmpty || !hasChinese(desc)) continue;
      final written = await _emit(
        txn,
        _Draft(
          type: 'module',
          key: id,
          sourcePath: path,
          name: name,
          // The module's own type mark (`X`, `Y`; the original badge has
          // none beyond its kind).
          code: _s(module['typeName2']).isNotEmpty
              ? _s(module['typeName2'])
              : _s(module['typeName1']),
          sections: [TextSection('', desc)],
        ),
      );
      final charId = _s(module['charId']);
      if (written && charId.isNotEmpty) {
        await _link(txn, 'module:$id', 'belongs_to', 'operator:$charId', path);
      }
    }
  }

  Future<void> _charms(Transaction txn, _Context ctx) async {
    const path = EntryTables.charm;
    for (final raw in _list((await _table(path))['charmList'])) {
      final charm = _map(raw);
      final id = _s(charm['id']);
      final name = _clean(charm['name']);
      final sections = [
        for (final key in const ['itemUsage', 'itemDesc'])
          if (hasChinese(_s(charm[key])))
            TextSection('', cleanDescription(_s(charm[key]))),
      ];
      if (id.isEmpty || name.isEmpty || sections.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'charm',
          key: id,
          sourcePath: path,
          name: name,
          collectionId: ctx.collectionForId(id),
          sortKey: _int(charm['sort']),
          sections: sections,
        ),
      );
    }
  }
}
