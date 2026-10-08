part of 'entry_importer.dart';

/// Activities, retro, archives.
extension _Activities on EntryImporter {
  /// Writes the narrative text of every sub-structure of [byActivity]
  /// (activity id → structure) as `activity_text` entries.
  Future<void> _harvestGroups(
    Transaction txn,
    _Context ctx,
    Map<String, dynamic> byActivity,
    String path, {
    String type = 'activity_text',
  }) async {
    for (final entry in byActivity.entries) {
      final actId = entry.key;
      // ct4FunData belongs to the story directory ct4fun.
      final owner = ctx.collections.containsKey(actId)
          ? actId
          : actId.endsWith('FunData')
              ? '${actId.substring(0, actId.length - 7)}fun'.toLowerCase()
              : ctx.collectionForId(actId);
      final base = ctx.collections[owner]?.name ??
          ctx.activityName[actId] ??
          actId;
      final node = entry.value;
      if (node is! Map) continue;
      for (final sub in node.entries) {
        final texts = harvestNarrative(sub.value, rootKey: '${sub.key}');
        if (texts.isEmpty) continue;
        await _emit(
          txn,
          _Draft(
            type: type,
            key: '$actId/${sub.key}',
            sourcePath: path,
            name: '$base · ${_labelFor('${sub.key}')}',
            collectionId: owner,
            groupName: '${sub.key}',
            sections: [for (final t in texts) TextSection('', t.text)],
            sectionLabel: _labelFor('${sub.key}'),
          ),
        );
      }
    }
  }

  Future<void> _activities(Transaction txn, _Context ctx) async {
    const path = EntryTables.activity;
    final table = await _table(path);
    for (final entry in _map(table['basicInfo']).entries) {
      final name = _clean(_map(entry.value)['name']);
      if (name.isEmpty) continue;
      await _emit(
        txn,
        _Draft(
          type: 'activity',
          key: entry.key,
          sourcePath: path,
          name: name,
          // `type` is the game's activity kind (an enum), not a code.
          collectionId: entry.key,
        ),
      );
    }
    for (final byType in _map(table['activity']).values) {
      await _harvestGroups(txn, ctx, _map(byType), path);
    }
    await _harvestGroups(txn, ctx, _map(table['dynActs']), path);
    await _harvestGroups(txn, ctx, _map(table['actFunData']), path);
  }

  Future<void> _retro(Transaction txn, _Context ctx) async {
    const path = EntryTables.retro;
    final table = await _table(path);
    for (final raw in _map(table['stageList']).entries) {
      final stage = _map(raw.value);
      final zoneId = _s(stage['zoneId']);
      if (zoneId.isNotEmpty &&
          !_storyZoneTypes.contains(ctx.zoneType[zoneId] ?? '')) {
        continue;
      }
      await _stageEntry(txn, ctx, path, raw.key, stage);
    }
    for (final byType in _map(table['customData']).values) {
      await _harvestGroups(txn, ctx, _map(byType), path);
    }
  }

  /// Name of the entry prefix (`act13side_file_1` → `act13side`) taken from
  /// the known collection ids.
  String? _ownerOf(_Context ctx, String id) => ctx.collectionForId(id);

  Future<void> _archives(Transaction txn, _Context ctx) async {
    const path = EntryTables.storyReviewMeta;
    final data = _map((await _table(path))['actArchiveResData']);
    String base(String? owner, String id) =>
        owner == null ? id : (ctx.collections[owner]?.name ?? owner);

    for (final entry in _map(data['stories']).entries) {
      final file = _map(entry.value);
      final text = _clean(file['text']);
      if (!hasChinese(text)) continue;
      final owner = _ownerOf(ctx, entry.key);
      await _emit(
        txn,
        _Draft(
          type: 'archive_file',
          key: entry.key,
          sourcePath: path,
          name: _clean(file['desc']).isEmpty
              ? base(owner, entry.key)
              : _clean(file['desc']),
          collectionId: owner,
          groupName: _s(file['date']),
          sections: [
            if (_s(file['date']).isNotEmpty) TextSection('日期', _s(file['date'])),
            TextSection('', text),
          ],
        ),
      );
    }
    for (final entry in _map(data['news']).entries) {
      final news = _map(entry.value);
      final text = _clean(news['newsText']);
      if (!hasChinese(text)) continue;
      final owner = _ownerOf(ctx, entry.key);
      await _emit(
        txn,
        _Draft(
          type: 'archive_news',
          key: entry.key,
          sourcePath: path,
          name: _clean(news['desc']).isEmpty
              ? base(owner, entry.key)
              : _clean(news['desc']),
          collectionId: owner,
          groupName: _s(news['newsAuthor']),
          sections: [
            if (_s(news['newsAuthor']).isNotEmpty)
              TextSection('来源', _s(news['newsAuthor'])),
            TextSection('', text),
          ],
        ),
      );
    }
    for (final entry in _map(data['landmarks']).entries) {
      final mark = _map(entry.value);
      final text = _clean(mark['landmarkDesc']);
      if (!hasChinese(text)) continue;
      await _emit(
        txn,
        _Draft(
          type: 'archive_landmark',
          key: entry.key,
          sourcePath: path,
          name: _clean(mark['landmarkName']),
          collectionId: _ownerOf(ctx, entry.key),
          sections: [TextSection('', text)],
        ),
      );
    }
    for (final entry in _map(data['logs']).entries) {
      final text = _clean(_map(entry.value)['logDesc']);
      if (!hasChinese(text)) continue;
      final owner = _ownerOf(ctx, entry.key);
      await _emit(
        txn,
        _Draft(
          type: 'archive_log',
          key: entry.key,
          sourcePath: path,
          name: '${base(owner, entry.key)} · 行动日志',
          collectionId: owner,
          sections: [TextSection('', text)],
        ),
      );
    }
    for (final entry in _map(data['challengeBooks']).entries) {
      final book = _map(entry.value);
      final name = _clean(book['titleName']);
      if (name.isEmpty) continue;
      final written = await _emit(
        txn,
        _Draft(
          type: 'archive_book',
          key: entry.key,
          sourcePath: path,
          name: name,
          collectionId: _ownerOf(ctx, entry.key),
        ),
      );
      final target = _storyIdOfPath(_s(book['textId']));
      if (written && target != null) {
        await _link(
          txn,
          'archive_book:${entry.key}',
          'reads_story',
          'story:$target',
          path,
        );
      }
    }
    for (final entry in _map(data['avgs']).entries) {
      final avg = _map(entry.value);
      final name = _clean(avg['desc']);
      if (name.isEmpty) continue;
      final written = await _emit(
        txn,
        _Draft(
          type: 'archive_avg',
          key: entry.key,
          sourcePath: path,
          name: name,
          collectionId: _ownerOf(ctx, entry.key),
        ),
      );
      final target = _storyIdOfPath(_s(avg['contentPath']));
      if (written && target != null) {
        await _link(
          txn,
          'archive_avg:${entry.key}',
          'reads_story',
          'story:$target',
          path,
        );
      }
    }
  }

  /// `Activities/act29side/mark/mark1` → `activities/act29side/mark/mark1.txt`
  String? _storyIdOfPath(String textId) {
    final clean = textId.trim();
    if (clean.isEmpty) return null;
    final lower = clean.toLowerCase();
    return lower.endsWith('.txt') ? lower : '$lower.txt';
  }
}
