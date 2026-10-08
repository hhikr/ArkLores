part of 'entry_importer.dart';

/// Handbook extras, powers, world view, display meta.
extension _Handbook on EntryImporter {
  Future<void> _handbook(Transaction txn, _Context ctx) async {
    const path = EntryTables.handbook;
    final table = await _table(path);
    for (final entry in _map(table['handbookStageData']).entries) {
      final stage = _map(entry.value);
      final name = _clean(stage['name']);
      final desc = cleanDescription(_s(stage['description']));
      final charId = _s(stage['charId']).isEmpty
          ? entry.key
          : _s(stage['charId']);
      final id = _s(stage['stageId']).isEmpty
          ? entry.key
          : _s(stage['stageId']);
      if (name.isEmpty || !hasChinese(desc)) continue;
      final written = await _emit(
        txn,
        _Draft(
          type: 'operator_stage',
          key: id,
          sourcePath: path,
          name: name,
          // `code` is the stage's file id (`mem_<operator>_1`), not a
          // player-facing code.
          sections: [TextSection('', desc)],
        ),
      );
      if (written) {
        await _link(txn, 'operator_stage:$id', 'belongs_to', 'operator:$charId', path);
      }
    }
    for (final entry in _map(table['npcDict']).entries) {
      final npc = _map(entry.value);
      final name = _clean(npc['name']);
      if (name.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'npc',
          key: entry.key,
          sourcePath: path,
          name: name,
          code: _s(npc['displayNumber']),
          groupName: _s(npc['nationId']),
        ),
      );
    }
  }

  Future<void> _powers(Transaction txn, _Context ctx) async {
    const path = EntryTables.team;
    for (final entry in (await _table(path)).entries) {
      final power = _map(entry.value);
      final name = _clean(power['powerName']);
      if (name.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'power',
          key: _s(power['powerId']).isEmpty ? entry.key : _s(power['powerId']),
          sourcePath: path,
          name: name,
          code: _s(power['powerCode']),
          sortKey: _int(power['orderNum']),
        ),
      );
    }
  }

  Future<void> _worldview(Transaction txn, _Context ctx) async {
    const path = EntryTables.tip;
    final tips = _list((await _table(path))['worldViewTips']);
    for (var i = 0; i < tips.length; i++) {
      final tip = _map(tips[i]);
      final title = _clean(tip['title']);
      final text = _clean(tip['description']);
      if (title.isEmpty || !hasChinese(text)) continue;
      await _emit(
        txn,
        _Draft(
          type: 'worldview',
          key: '$i',
          sourcePath: path,
          name: title,
          sortKey: i,
          sections: [TextSection('', text)],
        ),
      );
    }
  }

  Future<void> _displayMeta(Transaction txn, _Context ctx) async {
    const path = EntryTables.displayMeta;
    final table = await _table(path);
    final mails = _map(_map(table['mailArchiveData'])['mailArchiveInfoDict']);
    for (final entry in mails.entries) {
      final mail = _map(entry.value);
      final text = _clean(mail['content']);
      if (!hasChinese(text)) continue;
      await _emit(
        txn,
        _Draft(
          type: 'mail',
          key: entry.key,
          sourcePath: path,
          name: _clean(mail['title']),
          groupName: _s(mail['senderId']),
          sortKey: _int(mail['sortId']),
          sections: [TextSection('', text)],
        ),
      );
    }
    final home = _map(table['homeBackgroundData']);
    for (final raw in _list(home['homeBgDataList'])) {
      final bg = _map(raw);
      final name = _clean(bg['bgName']);
      final sections = [
        for (final key in const ['bgDes', 'bgUsage'])
          if (hasChinese(_s(bg[key]))) TextSection('', _clean(bg[key])),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'home_theme',
          key: 'bg/${_s(bg['bgId'])}',
          sourcePath: path,
          name: name,
          groupName: '首页场景',
          sections: sections,
        ),
      );
    }
    for (final raw in _list(home['themeList'])) {
      final theme = _map(raw);
      final name = _clean(theme['tmName']);
      final sections = [
        for (final key in const ['tmDes', 'tmUsage'])
          if (hasChinese(_s(theme[key]))) TextSection('', _clean(theme[key])),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'home_theme',
          key: 'theme/${_s(theme['id'])}',
          sourcePath: path,
          name: name,
          groupName: '主题',
          sections: sections,
        ),
      );
    }
  }
}
