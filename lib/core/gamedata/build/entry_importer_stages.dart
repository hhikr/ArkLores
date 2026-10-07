part of 'entry_importer.dart';

/// Stage types that are story-relevant; the rest (daily, weekly, climb
/// tower, campaign, guide) are gameplay.
const Set<String> _storyZoneTypes = {
  'MAINLINE',
  'MAINLINE_ACTIVITY',
  'MAINLINE_RETRO',
  'ACTIVITY',
  'SIDESTORY',
  'BRANCHLINE',
};

/// Enemies, stages, zones.
extension _Stages on EntryImporter {
  Future<void> _enemies(Transaction txn, _Context ctx) async {
    const path = EntryTables.enemy;
    final table = await _table(path);
    final races = {
      for (final e in _map(table['raceData']).entries)
        e.key: _clean(_map(e.value)['raceName']),
    };
    const levels = {'NORMAL': '普通', 'ELITE': '精英', 'BOSS': '首领'};
    for (final entry in _map(table['enemyData']).entries) {
      final enemy = _map(entry.value);
      final id = _s(enemy['enemyId']).isEmpty ? entry.key : _s(enemy['enemyId']);
      final name = _clean(enemy['name']);
      final desc = cleanDescription(_s(enemy['description']));
      if (name.isEmpty || !hasChinese(desc)) continue;
      // Ability descriptions (`abilityList`, `ability`) are gameplay text and
      // are not imported.
      final race = races[_s(enemy['enemyRace'])];
      final level = levels[_s(enemy['enemyLevel'])];
      await _emit(
        txn,
        _Draft(
          type: 'enemy',
          key: id,
          sourcePath: path,
          name: name,
          code: _s(enemy['enemyIndex']),
          groupName: level,
          sortKey: _int(enemy['sortId']),
          sections: [
            TextSection('', desc),
            if (level != null && level != '普通') TextSection('类别', level),
            if (race != null && race.isNotEmpty) TextSection('种族', race),
          ],
        ),
      );
    }
  }

  Future<void> _zones(Transaction txn, _Context ctx) async {
    const path = EntryTables.zone;
    final zones = _map((await _table(path))['zones']);
    for (final entry in zones.entries) {
      final zone = _map(entry.value);
      final type = _s(zone['type']);
      if (!_storyZoneTypes.contains(type)) continue;
      final id = _s(zone['zoneID']).isEmpty ? entry.key : _s(zone['zoneID']);
      final name = [
        for (final key in const ['zoneNameFirst', 'zoneNameSecond'])
          if (hasChinese(_s(zone[key]))) _clean(zone[key]),
      ].join(' · ');
      if (name.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'zone',
          key: id,
          sourcePath: path,
          name: name,
          collectionId: ctx.collectionOfZone(id),
          groupName: type,
          sortKey: _int(zone['zoneIndex']),
          sections: [TextSection('', name)],
        ),
      );
    }
  }

  Future<void> _stages(Transaction txn, _Context ctx) async {
    const path = EntryTables.stage;
    final stages = _map((await _table(path))['stages']);
    const stageTypes = {'MAIN', 'ACTIVITY', 'SUB', 'SPECIAL_STORY'};
    for (final entry in stages.entries) {
      final stage = _map(entry.value);
      if (!stageTypes.contains(_s(stage['stageType']))) continue;
      final zoneId = _s(stage['zoneId']);
      if (!_storyZoneTypes.contains((ctx.zoneType[zoneId] ?? ''))) continue;
      await _stageEntry(txn, ctx, path, entry.key, stage);
    }
  }


  Future<void> _stageEntry(
    Transaction txn,
    _Context ctx,
    String path,
    String fallbackId,
    Map<String, dynamic> stage,
  ) async {
    // A patch stage is a variant of another stage (same name and text).
    if (stage['isStagePatch'] == true) return;
    final id = _s(stage['stageId']).isEmpty ? fallbackId : _s(stage['stageId']);
    final name = _clean(stage['name']);
    if (name.isEmpty) return;
    final desc = cleanDescription(_s(stage['description']));
    final written = await _emit(
      txn,
      _Draft(
        type: 'stage',
        key: id,
        sourcePath: path,
        name: name,
        code: _s(stage['code']),
        collectionId: ctx.collectionOfZone(_s(stage['zoneId'])),
        groupName: _s(stage['zoneId']),
        sections: [if (hasChinese(desc)) TextSection('', desc)],
      ),
    );
    final zoneId = _s(stage['zoneId']);
    if (written && zoneId.isNotEmpty) {
      await _link(txn, 'stage:$id', 'belongs_to', 'zone:$zoneId', path);
    }
  }
}
