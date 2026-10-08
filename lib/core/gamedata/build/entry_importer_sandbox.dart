part of 'entry_importer.dart';

/// Sandbox, ark events.
extension _Sandbox on EntryImporter {
  /// Item type names the sandbox table gives (`itemTypeData`), by type code.
  Future<Map<String, String>> _sandboxTypeNames() async {
    final names = <String, String>{};
    final detail = _map((await _table(EntryTables.sandboxPerm))['detail']);
    for (final template in detail.values) {
      for (final topic in _map(template).values) {
        for (final t in _map(_map(topic)['itemTypeData']).values) {
          final code = _s(_map(t)['itemType']);
          final name = _clean(_map(t)['itemTypeName']);
          if (code.isNotEmpty && name.isNotEmpty) names.putIfAbsent(code, () => name);
        }
      }
    }
    return names;
  }

  Future<void> _sandboxPerm(Transaction txn, _Context ctx) async {
    const path = EntryTables.sandboxPerm;
    await _purgeSource(txn, path);
    final table = await _table(path);
    await _sandboxItems(
      txn,
      ctx,
      path,
      _map(table['itemData']),
      await _sandboxTypeNames(),
    );
    // The mode's own blurb, and its plot: acts (main and side), each with the
    // summary the game gives it; the stories are part of their act.
    final blurbs = _map(table['basicInfo']);
    final acts = sandboxActs(table, _clean);
    for (final template in _map(table['detail']).values) {
      for (final topic in _map(template).entries) {
        final d = _map(topic.value);
        final info = _map(blurbs[topic.key]);
        final blurb = cleanDescription(_s(info['description']));
        if (hasChinese(blurb)) {
          await _emit(
            txn,
            _Draft(
              type: 'sandbox_topic',
              key: topic.key,
              sourcePath: path,
              name: _clean(info['topicName']),
              collectionId: topic.key,
              sections: [TextSection('', blurb)],
            ),
          );
        }
        for (final act in acts[topic.key] ?? const <SandboxAct>[]) {
          await _emit(
            txn,
            _Draft(
              type: 'sandbox_act',
              key: act.key,
              sourcePath: path,
              name: act.title,
              collectionId: topic.key,
              groupName: act.kind.isEmpty ? null : act.kind,
              sortKey: act.order,
              sections: [if (hasChinese(act.summary)) TextSection('', act.summary)],
            ),
          );
        }
        await _sandboxStages(txn, path, topic.key, _map(d['stageData']));
        // The events a quest line starts carry the game's name for them.
        final kindOf = <String, String>{
          for (final e in _map(d['eventData']).values)
            if (_s(_map(e)['type']) == 'QUEST_EVENT' &&
                _clean(_map(e)['iconName']).isNotEmpty)
              _s(_map(e)['enterSceneId']): _clean(_map(e)['iconName']),
        };
        await _sandboxEvents(
          txn,
          path,
          topic.key,
          _map(d['eventSceneData']),
          _map(d['eventChoiceData']),
          kindOf,
        );
      }
    }
  }

  Future<void> _sandboxLegacy(Transaction txn, _Context ctx) async {
    const path = EntryTables.sandbox;
    await _purgeSource(txn, path);
    final table = await _table(path);
    // The items of this table are the items of the one mode it describes.
    final acts = _map(table['sandboxActTables']);
    await _sandboxItems(
      txn,
      ctx,
      path,
      _map(table['itemDatas']),
      await _sandboxTypeNames(),
      owner: acts.length == 1 ? acts.keys.first : null,
    );
    for (final act in acts.entries) {
      final d = _map(act.value);
      await _sandboxStages(txn, path, act.key, _map(d['stageDatas']));
      await _sandboxEvents(
        txn,
        path,
        act.key,
        _map(d['eventSceneDatas']),
        _map(d['eventChoiceDatas']),
        const {},
      );
    }
  }

  Future<void> _sandboxItems(
    Transaction txn,
    _Context ctx,
    String path,
    Map<String, dynamic> items,
    Map<String, String> typeNames, {
    String? owner,
  }) async {
    for (final entry in items.entries) {
      final item = _map(entry.value);
      final name = _clean(item['itemName']);
      final sections = [
        for (final key in const ['itemDesc', 'itemUsage'])
          if (hasChinese(_s(item[key])) && !isMechanical(_s(item[key])))
            TextSection('', cleanDescription(_s(item[key]))),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'sandbox_item',
          key: _s(item['itemId']).isEmpty ? entry.key : _s(item['itemId']),
          sourcePath: path,
          name: name,
          collectionId: ctx.collectionForId(entry.key) ?? owner,
          // The table's own name for the kind of item; a kind it does not
          // name has no heading.
          groupName: typeNames[_s(item['itemType'])],
          sections: sections,
        ),
      );
    }
  }

  /// The prose of a sandbox text: what the tables mark as an effect (a
  /// `<color>` span, a line in 【】) is not text of the story.
  String _sandboxProse(String raw) => _prose(
        raw
            .replaceAll(
              RegExp(r'<color=[^>]*>.*?</color>', dotAll: true),
              '',
            )
            .split(RegExp(r'\n|\\n'))
            .where((l) => !RegExp(r'^\s*【.*】\s*$').hasMatch(l))
            .join('\n'),
      );

  /// The stages of a sandbox topic: name, the prose of the description, and
  /// the place the description opens with (a line the game marks `<@lv.…>`
  /// that says where, not how).
  Future<void> _sandboxStages(
    Transaction txn,
    String path,
    String topic,
    Map<String, dynamic> stages,
  ) async {
    final codes = <String, int>{};
    for (final s in stages.values) {
      final code = _s(_map(s)['code']);
      if (code.isNotEmpty) codes[code] = (codes[code] ?? 0) + 1;
    }
    final nameCount = <String, int>{};
    var rank = 0;
    for (final entry in stages.entries) {
      final s = _map(entry.value);
      final id = _s(s['stageId']).isEmpty ? entry.key : _s(s['stageId']);
      var name = _clean(s['name']);
      if (name.isEmpty) continue;
      String? place;
      final prose = <String>[];
      for (final line in _s(s['description']).split(RegExp(r'\n|\\n'))) {
        final marked =
            RegExp(r'^\s*<@lv\.[^>]*>(.*?)</>\s*$').firstMatch(line);
        if (marked == null) {
          prose.add(line);
          continue;
        }
        final inner = _clean(marked[1]);
        if (place == null && hasChinese(inner) && !RegExp(r'[\d%]').hasMatch(inner)) {
          place = inner;
        }
      }
      final text = _prose(prose.join('\n'));
      // A code every stage shares says nothing.
      final code = _s(s['code']);
      final nth = nameCount[name] = (nameCount[name] ?? 0) + 1;
      if (nth > 1) name = '$name · $nth';
      await _emit(
        txn,
        _Draft(
          type: 'sandbox_stage',
          key: '$topic/$id',
          sourcePath: path,
          name: name,
          code: (codes[code] ?? 0) <= 3 ? code : null,
          collectionId: topic,
          groupName: place,
          sortKey: rank++,
          sections: [if (text.isNotEmpty) TextSection('', text)],
        ),
      );
    }
  }

  /// The events of a sandbox topic. An event starts at a scene whose id ends
  /// in `_enter`; every scene lists the options it offers, and the scene shown
  /// after an option is the one numbered like it (`choice_x_1` →
  /// `scene_x_1`). The event is its opening text and its options layer by
  /// layer; effects are left out.
  Future<void> _sandboxEvents(
    Transaction txn,
    String path,
    String topic,
    Map<String, dynamic> sceneTable,
    Map<String, dynamic> choiceTable,
    Map<String, String> groupOf,
  ) async {
    final scenes = <String, ({String title, String text, List<String> choices})>{};
    for (final entry in sceneTable.entries) {
      final s = _map(entry.value);
      final id = [
        for (final k in const ['eventSceneId', 'sceneId', 'choiceSceneId'])
          if (_s(s[k]).isNotEmpty) _s(s[k]),
      ].firstOrNull;
      if (id == null) continue;
      scenes[id] = (
        title: _clean(s['title']),
        text: _sandboxProse(_s(s['desc'] ?? s['description'])),
        choices: [
          for (final c in _list(s['choiceIds'] ?? s['choiceIdList'] ?? s['choices']))
            _s(c),
        ],
      );
    }
    final choices = <String, ({String title, String text})>{
      for (final e in choiceTable.entries)
        (_s(_map(e.value)['choiceId']).isEmpty
            ? e.key
            : _s(_map(e.value)['choiceId'])): (
          title: _clean(_map(e.value)['title']),
          text: _sandboxProse(
            _s(_map(e.value)['desc'] ?? _map(e.value)['description']),
          ),
        ),
    };
    SandboxOption option(String id) {
      final c = choices[id];
      final result = 'scene_${id.startsWith('choice_') ? id.substring(7) : id}';
      final scene = scenes[result];
      return (
        title: c?.title ?? '',
        text: c?.text ?? '',
        after: scene?.text ?? '',
        then: scene?.choices ?? const <String>[],
      );
    }

    final nameCount = <String, int>{};
    var rank = 0;
    for (final root in scenes.keys.where((k) => k.endsWith('_enter'))) {
      final scene = scenes[root]!;
      var name = scene.title;
      if (name.isEmpty) continue;
      final blocks = <String>[
        if (scene.text.isNotEmpty) '## 事件\n${scene.text}',
        () {
          final outline = sandboxEventOutline(scene.choices, option);
          return outline.isEmpty ? '' : '## 选项\n$outline';
        }(),
      ].where((b) => b.isNotEmpty).toList();
      if (blocks.isEmpty) continue;
      final nth = nameCount[name] = (nameCount[name] ?? 0) + 1;
      if (nth > 1) name = '$name · $nth';
      await _emit(
        txn,
        _Draft(
          type: 'sandbox_event',
          key: '$topic/$root',
          sourcePath: path,
          name: name,
          collectionId: topic,
          groupName: groupOf[root],
          sortKey: rank++,
          sections: [TextSection('', blocks.join('\n\n'))],
        ),
      );
    }
  }
  Future<void> _arkvent(Transaction txn, _Context ctx, String path) async {
    final table = await _table(path);
    for (final root in table.values) {
      await _harvestGroups(txn, ctx, _map(root), path);
    }
  }
}
