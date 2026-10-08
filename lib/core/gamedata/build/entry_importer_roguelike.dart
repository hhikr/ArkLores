part of 'entry_importer.dart';

/// Roguelike.
extension _Roguelike on EntryImporter {
  /// Removes what an earlier import of [path] wrote (entries, their records,
  /// chunks and its own bindings), so a re-import is exactly what the table says now:
  /// an entry dropped from the rules (a tip, a duplicate stage) goes away.
  Future<void> _purgeSource(Transaction txn, String path) async {
    const ids = 'SELECT id FROM entries WHERE source_path = ?';
    await txn.rawDelete('DELETE FROM lore_chunks WHERE entry_id IN ($ids)', [path]);
    await txn.rawDelete(
      'DELETE FROM normalized_records WHERE entry_id IN ($ids)',
      [path],
    );
    // Only the bindings this table wrote: others (enemies in a stage, from
    // the level files) stay and meet the re-imported entry by its id.
    await txn.rawDelete('DELETE FROM entry_links WHERE source_path = ?', [path]);
    await txn.rawDelete('DELETE FROM entries WHERE source_path = ?', [path]);
    // The names it put in the name index.
    const entities = 'SELECT id FROM entities WHERE source_path = ?';
    await txn.rawDelete(
      'DELETE FROM entity_aliases WHERE entity_id IN ($entities)',
      [path],
    );
    await txn.rawDelete('DELETE FROM entities WHERE source_path = ?', [path]);
  }

  /// The lines of [text] that are prose: Chinese and not rule text.
  String _prose(String text) => cleanDescription(text)
      .split(RegExp(r'\n|\\n'))
      .map(_clean)
      .where((l) => hasChinese(l) && !isMechanical(l))
      .join('\n');

  Future<void> _roguelikeTopics(Transaction txn, _Context ctx) async {
    const path = EntryTables.roguelikeTopic;
    await _purgeSource(txn, path);
    final table = await _table(path);
    final topics = _map(table['topics']);
    for (final entry in topics.entries) {
      final topic = _map(entry.value);
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_topic',
          key: entry.key,
          sourcePath: path,
          name: _clean(topic['name']),
          collectionId: entry.key,
          sections: [
            if (hasChinese(_s(topic['lineText'])))
              TextSection('', _clean(topic['lineText'])),
          ],
        ),
      );
    }
    for (final entry in _map(table['details']).entries) {
      await _roguelike(txn, ctx, path, entry.key, _map(entry.value));
    }
  }

  Future<void> _roguelikeLegacy(Transaction txn, _Context ctx) async {
    const path = EntryTables.roguelike;
    await _purgeSource(txn, path);
    final table = await _table(path);
    final items = _map(_map(table['itemTable'])['items']);
    await _roguelike(txn, ctx, path, 'rogue_1', {
      'items': items,
      'stages': table['stages'],
      'zones': table['zones'],
      'choices': table['choices'],
      'choiceScenes': table['choiceScenes'],
      'endings': table['endings'],
    });
  }

  /// One roguelike topic's story-relevant structures. Mechanics (difficulty,
  /// tasks, effects, buff descriptions, recruit tickets) are not imported.
  Future<void> _roguelike(
    Transaction txn,
    _Context ctx,
    String path,
    String topic,
    Map<String, dynamic> d,
  ) async {
    String id(String raw) => '$topic/$raw';

    for (final entry in _map(d['items']).entries) {
      final item = _map(entry.value);
      final name = _clean(item['name']);
      final desc = cleanDescription(_s(item['description']));
      if (name.isEmpty || !hasChinese(desc) || isMechanical(desc)) continue;
      // `feature` items are stand-ins the game's rules use (potion drop
      // control, resource refunds), and the counters and tickets are the
      // rules' own resources: mechanics, not story.
      if (EntryImporter._mechanicItemTypes.contains(_s(item['type']).toLowerCase())) continue;
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_item',
          key: id(entry.key),
          sourcePath: path,
          name: name,
          collectionId: topic,
          // `<topic>_start_<n>`: what a run starts with.
          groupName: RegExp(r'_start_\d+$').hasMatch(entry.key)
              ? 'start'
              : _s(item['type']).toLowerCase(),
          sortKey: _int(item['sortId']),
          sections: [TextSection('', desc)],
        ),
      );
    }
    // Events. A scene and its follow-up scenes share an id stem
    // (`scene_<topic>_<stem>_enter`, `scene_<topic>_<stem>_2`), and the choices
    // offered carry the same stem (`choice_<topic>_<stem>_1`): one entry per
    // stem. A choice names the scene it leads to (`nextSceneId`); a scene no
    // choice leads to is what the event says when it starts. So the entry has
    // three parts: the event's own text, the options offered, and what is said
    // after choosing each option.
    String stemOf(String raw, String lead) {
      final s = raw.startsWith(lead) ? raw.substring(lead.length) : raw;
      return s.replaceAll(RegExp(r'(_enter|_\d+)+$'), '');
    }

    final sceneTable = _map(d['choiceScenes']);
    final scenesOf = <String, List<String>>{};
    for (final key in sceneTable.keys) {
      (scenesOf[stemOf(key, 'scene_')] ??= []).add(key);
    }
    final choicesOf = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final e in _map(d['choices']).entries) {
      (choicesOf[stemOf(e.key, 'choice_')] ??= [])
          .add(MapEntry(e.key, _map(e.value)));
    }
    String sceneProse(String key) =>
        _prose(_s(_map(sceneTable[key])['description']));
    final seenEvents = <String>{};
    final eventNames = <String, int>{};
    var eventRank = 0;
    for (final stem in scenesOf.keys) {
      final keys = scenesOf[stem]!
        ..sort((a, b) {
          final ea = a.endsWith('_enter'), eb = b.endsWith('_enter');
          if (ea != eb) return ea ? -1 : 1;
          return naturalCompare(a, b);
        });
      var name = [
        for (final k in keys)
          if (_clean(_map(sceneTable[k])['title']).isNotEmpty)
            _clean(_map(sceneTable[k])['title']),
      ].firstOrNull;
      if (name == null) continue;
      final picks = [...?choicesOf[stem]]..sort((a, b) {
          final byOrder = (_int(a.value['sortId']) ?? 0)
              .compareTo(_int(b.value['sortId']) ?? 0);
          return byOrder != 0 ? byOrder : naturalCompare(a.key, b.key);
        });
      final led = {
        for (final pick in picks) _s(pick.value['nextSceneId']),
      }..remove('');
      // A scene numbered like a choice (`choice_<stem>_3` / `scene_<stem>_3`)
      // that no choice leads to is what is said when that choice is made.
      String ownOf(MapEntry<String, Map<String, dynamic>> pick) {
        final k = 'scene_${pick.key.startsWith('choice_') ? pick.key.substring(7) : pick.key}';
        return sceneTable.containsKey(k) && !led.contains(k) ? k : '';
      }

      final owned = {for (final pick in picks) ownOf(pick)}..remove('');
      // What the event says when it starts: the scenes no choice leads to
      // and none is the result of (the first scene when there are none).
      var opening = [
        for (final k in keys)
          if (!led.contains(k) && !owned.contains(k)) k,
      ];
      if (opening.isEmpty) opening = [keys.first];
      final start = [
        for (final k in opening)
          if (sceneProse(k).isNotEmpty) sceneProse(k),
      ].join('\n\n');
      // The options, each with the text after choosing it, layer by layer
      // (see [eventOutline]); their own text only when it is prose (most is
      // effect text and is left out).
      final outline = eventOutline(
        [
          for (final pick in picks)
            (
              title: _clean(pick.value['title']),
              text: _prose(_s(pick.value['description'])),
              next: _s(pick.value['nextSceneId']),
              own: ownOf(pick),
            ),
        ],
        sceneProse,
      );
      final blocks = <String>[
        if (start.isNotEmpty) '## 事件\n$start',
        if (outline.isNotEmpty) '## 选项\n$outline',
      ];
      if (blocks.isEmpty) continue;
      final text = blocks.join('\n\n');
      // The same event listed under several stems (one per layer slot) is
      // one; what still shares a name is numbered.
      if (!seenEvents.add('$name|$text')) continue;
      final nth = eventNames[name] = (eventNames[name] ?? 0) + 1;
      if (nth > 1) name = '$name · $nth';
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_scene',
          key: id(stem),
          sourcePath: path,
          name: name,
          collectionId: topic,
          sortKey: eventRank++,
          sections: [TextSection('', text)],
        ),
      );
    }    for (final entry in _map(d['endings']).entries) {
      final ending = _map(entry.value);
      final name = _clean(ending['name']);
      final sections = [
        for (final key in const ['desc', 'changeEndingDesc'])
          if (hasChinese(_s(ending[key]))) TextSection('', _clean(ending[key])),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_ending',
          key: id(entry.key),
          sourcePath: path,
          name: name,
          collectionId: topic,
          sections: sections,
        ),
      );
    }
    // Zones. The game lists the same zone once per layer slot (identical
    // text, other id); those are one zone. A stage belongs to the zone its
    // level number says (`level_<topic>_<zone>-<n>` → `zone_<zone>`).
    final zoneTable = _map(d['zones']);
    final zoneBySignature = <String, String>{};
    final zoneKeyOf = <String, String>{};
    var zoneRank = 0;
    final zoneNames = <String, int>{};
    for (final entry in zoneTable.entries) {
      final zone = _map(entry.value);
      var name = _clean(zone['name']);
      // The prose only: a zone's description may end with the rule line of
      // the variant (this zone raises attack …), which is gameplay.
      final sections = [
        for (final key in const ['description', 'endingDescription'])
          if (_prose(_s(zone[key])).isNotEmpty) TextSection('', _prose(_s(zone[key]))),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      final signature = '$name|${sections.map((s) => s.content).join('|')}';
      final first = zoneBySignature.putIfAbsent(signature, () => entry.key);
      zoneKeyOf[entry.key] = first;
      if (first != entry.key) continue;
      final nth = zoneNames[name] = (zoneNames[name] ?? 0) + 1;
      if (nth > 1) name = '$name · $nth';
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_zone',
          key: id(entry.key),
          sourcePath: path,
          name: name,
          collectionId: topic,
          sortKey: zoneRank++,
          sections: sections,
        ),
      );
    }
    // A stage has a normal and a raid (`isElite`) form that share name, level
    // and text; the raid one names its normal one in `linkedStageId`. Both
    // carry the form in their name; a stage listed twice for one level is
    // one, and what still shares a name (other levels) is numbered.
    final stageTable = _map(d['stages']);
    final raidOf = {
      for (final s in stageTable.values)
        if (_s(_map(s)['linkedStageId']).isNotEmpty)
          _s(_map(s)['linkedStageId']),
    };
    final seenStages = <String>{};
    final nameCount = <String, int>{};
    for (final entry in stageTable.entries) {
      final stage = _map(entry.value);
      var name = _clean(stage['name']);
      if (name.isEmpty) continue;
      final desc = cleanDescription(_s(stage['description']));
      final raid = _int(stage['isElite']) == 1;
      if (!seenStages.add('$name|${_s(stage['levelId']).toLowerCase()}|$raid')) {
        continue;
      }
      if (raid) {
        name = '$name · 突袭';
      } else if (raidOf.contains(entry.key)) {
        name = '$name · 普通';
      }
      final nth = nameCount[name] = (nameCount[name] ?? 0) + 1;
      if (nth > 1) name = '$name · $nth';
      final written = await _emit(
        txn,
        _Draft(
          type: 'roguelike_stage',
          key: id(entry.key),
          sourcePath: path,
          name: name,
          code: _s(stage['code']),
          collectionId: topic,
          sections: [if (hasChinese(desc)) TextSection('', desc)],
        ),
      );
      final level = _s(stage['levelId']).split('/').last.toLowerCase();
      final zoneNumber = RegExp(r'_(\d+)-\d+$').firstMatch(level)?.group(1);
      final zone = zoneNumber == null ? null : zoneKeyOf['zone_$zoneNumber'];
      if (written && zone != null) {
        await _link(
          txn,
          'roguelike_stage:${id(entry.key)}',
          'belongs_to',
          'roguelike_zone:${id(zone)}',
          path,
        );
      }
    }    for (final entry in _map(d['monthSquad']).entries) {
      final squad = _map(entry.value);
      final name = _clean(squad['teamName']);
      // Only the Chinese one-liner: the subtitle (`teamFlavorDesc`,
      // `teamSubName`) is written in English or in an invented language and
      // is not the squad's name.
      final sections = [
        if (hasChinese(_s(squad['teamDes'])))
          TextSection('', _clean(squad['teamDes'])),
      ];
      if (name.isEmpty || sections.isEmpty) continue;
      final key = id(entry.key);
      final year = _int(squad['teamYear']);
      final month = _int(squad['teamMonth']);
      final written = await _emit(
        txn,
        _Draft(
          type: 'roguelike_squad',
          key: key,
          sourcePath: path,
          name: name,
          collectionId: topic,
          groupName: year != null && month != null ? '$year年$month月' : null,
          sortKey: _int(squad['teamIndex']),
          sections: sections,
        ),
      );
      if (written) {
        for (final member in _list(squad['teamChars'])) {
          final charId = _s(_map(member)['teamCharId']);
          if (charId.isEmpty) continue;
          await _link(
            txn,
            'roguelike_squad:$key',
            'features',
            'operator:$charId',
            path,
          );
        }
      }
    }
    final prizes = _list(d['grandPrizes']);
    for (var i = 0; i < prizes.length; i++) {
      final prize = _map(prizes[i]);
      final name = _clean(prize['displayName']);
      final text = cleanDescription(_s(prize['displayDiscription']));
      if (name.isEmpty || !hasChinese(text)) continue;
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_prize',
          key: '$topic/${_s(prize['grandPrizeDisplayId']).isEmpty ? '$i' : _s(prize['grandPrizeDisplayId'])}',
          sourcePath: path,
          name: name,
          collectionId: topic,
          sections: [TextSection('', text)],
        ),
      );
    }
    final tips = _list(d['battleLoadingTips']);
    for (var i = 0; i < tips.length; i++) {
      final text = _clean(_map(tips[i])['tip']);
      // Loading tips are mostly play advice; the ones that explain a term of
      // the setting are written `词——解释` and are the only ones kept, under
      // the term.
      final term = RegExp(r'^([^—\n]{1,24})——').firstMatch(text)?.group(1);
      if (!hasChinese(text) || term == null || isMechanical(text)) continue;
      await _emit(
        txn,
        _Draft(
          type: 'roguelike_tip',
          key: '$topic/$i',
          sourcePath: path,
          name: term.trim(),
          collectionId: topic,
          sortKey: i,
          sections: [TextSection('', text)],
        ),
      );
    }
    for (final group in const ['variationData', 'charBuffData', 'squadBuffData']) {
      final kind = _buffKind(topic, group, _map(d[group]));
      for (final entry in _map(d[group]).entries) {
        final buff = _map(entry.value);
        final name = _clean(buff['outerName']).isEmpty
            ? _clean(buff['innerName'])
            : _clean(buff['outerName']);
        final text = _clean(buff['desc']);
        if (name.isEmpty || !hasChinese(text) || isMechanical(text)) continue;
        await _emit(
          txn,
          _Draft(
            type: 'roguelike_buff',
            key: id(entry.key),
            sourcePath: path,
            name: name,
            collectionId: topic,
            groupName: kind,
            sections: [TextSection('', text)],
          ),
        );
      }
    }
  }
}
