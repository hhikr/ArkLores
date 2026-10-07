/// 0.12: builds the Endfield knowledge base from the game's tables (and, when
/// given, the conversations the research kit reconstructed).
///
/// Same rules as the Arknights build (docs/KNOWLEDGE_BASE_LESSONS.md): only
/// text with story value — operator archives and voice lines, the PRTS
/// archive (documents, papers, records, media, investigations), enemy, weapon
/// and item flavour text, faction and region names, the conversations. No
/// skills, talents, potentials, numbers, rewards or how to obtain things.
/// Owners and bindings come from the tables' ids only.
library;

import '../text_harvest.dart' show cleanRichText, isMechanical;
import 'endfield_tables.dart';
import 'endfield_writer.dart';

/// Collection kinds of the Endfield library (without the `ef/` namespace),
/// in shelf order. `memory` is the operator shelf, as in Arknights.
const List<String> endfieldShelfKinds = [
  'main',
  'discovery',
  'side',
  'activity',
  'other',
  // Conversations outside missions (a level's interactions, an enemy's
  // encounter): unnamed in the game, shown as 其他.
  'world',
  'archive',
  'memory',
];

class EndfieldImporter {
  EndfieldImporter(this.tables, this.writer, {this.log});

  final EndfieldTables tables;
  final EndfieldWriter writer;
  final void Function(String message)? log;

  /// Operator entry ids by character id (for bindings).
  final Map<String, String> operators = {};

  Future<void> importTables() async {
    await importOperators();
    await importFactions();
    await importEnemies();
    await importWeapons();
    await importItems();
    await importArchive();
  }

  String _clean(Object? field) => endfieldText(tables.text(field));

  /// The localized `name` of row [key] of a kind table (null when none).
  String? _groupName(String table, Object? key) {
    final row = tables.table(table)['${key ?? ''}'];
    final name = row is Map ? _clean(row['name']) : '';
    return name.isEmpty ? null : name;
  }

  /// Operators: the archive records (档案) and the voice lines, one entry
  /// each, an entity for the coverage layer, and a `memory` collection that
  /// carries the operator shelf (like Arknights' record sets).
  Future<void> importOperators() async {
    const name = 'CharacterTable';
    final source = tables.sourcePath(name);
    var count = 0;
    for (final row in tables.table(name).values) {
      if (row is! Map<String, dynamic>) continue;
      final id = '${row['charId'] ?? ''}';
      final title = _clean(row['name']);
      if (id.isEmpty || title.isEmpty) continue;
      final records = [
        for (final r in listOfMaps(row['profileRecord']))
          (
            section: _clean(r['recordTitle']).isEmpty
                ? '档案'
                : _clean(r['recordTitle']),
            text: _clean(r['recordDesc']),
          ),
      ].where((r) => r.text.isNotEmpty).toList();
      final voices = [
        for (final v in listOfMaps(row['profileVoice']))
          if (_clean(v['voiceDesc']).isNotEmpty)
            '${_clean(v['voiceTitle'])}：${_clean(v['voiceDesc'])}',
      ];
      // A character with nothing to read (a stand-in row) is not listed.
      if (records.isEmpty && voices.isEmpty) continue;
      final english = '${row['engName'] ?? ''}'.trim();
      final entity = await writer.entity(
        rawId: id,
        name: title,
        type: 'operator',
        sourcePath: source,
        aliases: [if (english.isNotEmpty) english],
      );
      final entryId = await writer.entry(
        type: 'operator',
        rawId: id,
        name: title,
        group: '${row['department'] ?? ''}'.trim().isEmpty
            ? null
            : '${row['department']}'.trim(),
        entityId: entity,
        sourcePath: source,
        category: 'operator',
        contentType: 'endfield_operator_profile',
        texts: [
          ...records,
          if (voices.isNotEmpty) (section: '语音', text: voices.join('\n')),
        ],
      );
      operators[id] = entryId;
      await writer.entityDocument(
        entityId: entity,
        name: title,
        type: 'operator',
        content: records.map((r) => '【${r.section}】\n${r.text}').join('\n\n'),
        sourcePath: source,
      );
      await writer.collection(
        id: 'operator_$id',
        kind: 'memory',
        name: title,
        parentId: entryId,
        sourcePath: source,
      );
      count++;
    }
    log?.call('operators: $count');
  }

  /// Factions: names only (entities the coverage layer can find).
  Future<void> importFactions() async {
    const name = 'BlocDataTable';
    final source = tables.sourcePath(name);
    var count = 0;
    for (final row in tables.table(name).values) {
      if (row is! Map<String, dynamic>) continue;
      final id = '${row['blocId'] ?? ''}';
      final title = _clean(row['blocName']);
      if (id.isEmpty || title.isEmpty) continue;
      final english = '${row['engName'] ?? ''}'.trim();
      await writer.entity(
        rawId: id,
        name: title,
        type: 'power',
        sourcePath: source,
        aliases: [if (english.isNotEmpty) english],
      );
      count++;
    }
    log?.call('factions: $count');
  }

  /// Enemies: the description of each enemy template (not its abilities).
  Future<void> importEnemies() async {
    const name = 'EnemyTemplateDisplayInfoTable';
    final source = tables.sourcePath(name);
    var count = 0;
    for (final MapEntry(key: key, value: row) in tables.table(name).entries) {
      if (row is! Map<String, dynamic>) continue;
      final id = '${row['templateId'] ?? key}';
      final title = _clean(row['name']);
      final text = _clean(row['description']);
      if (title.isEmpty || text.isEmpty) continue;
      await writer.entry(
        type: 'enemy',
        rawId: id,
        name: title,
        group: _groupName('DisplayEnemyTypeTable', row['displayType']),
        sourcePath: source,
        category: 'enemy',
        texts: [(section: '介绍', text: text)],
      );
      count++;
    }
    log?.call('enemies: $count');
  }

  /// Weapons: their flavour text (a short story each), not their stats.
  Future<void> importWeapons() async {
    const name = 'WeaponBasicTable';
    final source = tables.sourcePath(name);
    final items = tables.table('ItemTable');
    var count = 0;
    for (final MapEntry(key: key, value: row) in tables.table(name).entries) {
      if (row is! Map<String, dynamic>) continue;
      final id = '${row['weaponId'] ?? key}';
      final text = _clean(row['weaponDesc']);
      final item = items[id];
      final title = item is Map ? _clean(item['name']) : '';
      if (text.isEmpty) continue;
      await writer.entry(
        type: 'weapon',
        rawId: id,
        name: title.isEmpty ? '${row['engName'] ?? id}' : title,
        code: '${row['engName'] ?? ''}'.trim().isEmpty ? null : '${row['engName']}',
        sourcePath: source,
        category: 'world_item',
        texts: [(section: '描述', text: text)],
      );
      count++;
    }
    log?.call('weapons: $count');
  }

  /// Items: only the flavour line (`decoDesc`), which tells what a thing is;
  /// the usage line (`desc`) is gameplay. Weapons are already listed.
  Future<void> importItems() async {
    const name = 'ItemTable';
    final source = tables.sourcePath(name);
    final weapons = tables.table('WeaponBasicTable');
    final rows = tables.table(name);
    // A line many items share once their own name is taken out is a
    // template ("the blueprint of X"), not a description of the thing.
    final shapes = <String, int>{};
    String shape(Map<String, dynamic> row) =>
        _clean(row['decoDesc']).replaceAll(_clean(row['name']), '\u0000');
    for (final row in rows.values) {
      if (row is Map<String, dynamic>) {
        shapes.update(shape(row), (n) => n + 1, ifAbsent: () => 1);
      }
    }
    var count = 0;
    for (final MapEntry(key: key, value: row) in rows.entries) {
      if (row is! Map<String, dynamic>) continue;
      final id = '${row['id'] ?? key}';
      if (weapons.containsKey(id)) continue;
      final title = _clean(row['name']);
      final text = _clean(row['decoDesc']);
      if (title.isEmpty || text.isEmpty || text == title) continue;
      if ((shapes[shape(row)] ?? 0) >= 3 || isMechanical(text)) continue;
      await writer.entry(
        type: 'item',
        rawId: id,
        name: title,
        // The game's own name of the item kind (ItemTypeTable).
        group: _groupName('ItemTypeTable', row['type']),
        sourcePath: source,
        category: 'world_item',
        texts: [(section: '描述', text: text)],
      );
      count++;
    }
    log?.call('items: $count');
  }

  /// The PRTS archive: categories → archive entries (`PrtsFirstLv`) → pages
  /// (`PrtsAllItem`) whose text is a `RichContentTable` row. Each category
  /// is a collection on the archive shelf; each archive entry one document
  /// with its pages as text blocks. Investigations (`PrtsInvestigate`) are
  /// collections of their own, listing the documents they gather.
  Future<void> importArchive() async {
    final categories = tables.table('PrtsCategory');
    final firstLv = tables.table('PrtsFirstLv');
    final pages = tables.table('PrtsAllItem');
    final rich = tables.table('RichContentTable');
    const source = 'PrtsFirstLv';
    final sourcePath = tables.sourcePath(source);
    for (final MapEntry(key: id, value: row) in categories.entries) {
      if (row is! Map<String, dynamic>) continue;
      await writer.collection(
        id: 'prts_$id',
        kind: 'archive',
        name: _clean(row['name']).isEmpty ? id : _clean(row['name']),
        sortKey: (row['order'] as num?)?.toInt(),
        sourcePath: tables.sourcePath('PrtsCategory'),
      );
    }
    final documentOf = <String, String>{}; // page id -> document entry id
    var count = 0;
    for (final MapEntry(key: id, value: row) in firstLv.entries) {
      if (row is! Map<String, dynamic>) continue;
      final category = '${row['categoryId'] ?? ''}';
      final title = _clean(row['name']);
      final blocks = <({String section, String text})>[];
      for (final pageId in listOfStrings(row['itemIds'])) {
        final page = pages[pageId];
        if (page is! Map<String, dynamic>) continue;
        final content = rich['${page['contentId'] ?? ''}'];
        if (content is! Map<String, dynamic>) continue;
        final text = [
          for (final c in listOfMaps(content['contentList'])) _clean(c['content']),
        ].where((t) => t.isNotEmpty).join('\n');
        if (text.isEmpty) continue;
        final pageTitle = _clean(content['title']).isNotEmpty
            ? _clean(content['title'])
            : _clean(page['name']);
        blocks.add((section: pageTitle.isEmpty ? title : pageTitle, text: text));
      }
      if (blocks.isEmpty || title.isEmpty) continue;
      final entryId = await writer.entry(
        type: 'document',
        rawId: id,
        name: title,
        collectionId: category.isEmpty ? null : 'prts_$category',
        sortKey: (row['order'] as num?)?.toInt(),
        sourcePath: sourcePath,
        category: 'archive',
        texts: blocks,
      );
      for (final pageId in listOfStrings(row['itemIds'])) {
        documentOf[pageId] = entryId;
      }
      count++;
    }
    var investigations = 0;
    for (final MapEntry(key: id, value: row)
        in tables.table('PrtsInvestigate').entries) {
      if (row is! Map<String, dynamic>) continue;
      final title = _clean(row['name']);
      if (title.isEmpty) continue;
      final collection = 'investigate_$id';
      await writer.collection(
        id: collection,
        kind: 'archive',
        name: title,
        sortKey: 1000 + ((row['index'] as num?)?.toInt() ?? 0),
        sourcePath: tables.sourcePath('PrtsInvestigate'),
      );
      final desc = _clean(row['desc']);
      final notes = [
        for (final cat in listOfMaps(row['categoryDataList']))
          for (final noteId in listOfStrings(cat['noteIdList']))
            _clean((tables.table('PrtsNote')[noteId] as Map?)?['desc']),
      ].where((t) => t.isNotEmpty);
      final intro = await writer.entry(
        type: 'investigation',
        rawId: id,
        name: title,
        collectionId: collection,
        sortKey: 0,
        sourcePath: tables.sourcePath('PrtsInvestigate'),
        category: 'archive',
        texts: [
          if (desc.isNotEmpty) (section: '简介', text: desc),
          if (notes.isNotEmpty) (section: '线索', text: notes.join('\n')),
        ],
      );
      for (final page in listOfStrings(row['collectionIdList'])) {
        final doc = documentOf[page];
        if (doc != null) {
          await writer.link(doc, 'part_of', intro, 'PrtsInvestigate');
        }
      }
      investigations++;
    }
    log?.call('archive documents: $count, investigations: $investigations');
  }
}

/// [text] without references to image or asset files the game shows beside
/// it (`Reading/x_photo`): ASCII path tokens are not part of the prose.
String stripAssetRefs(String text) => text
    .replaceAll(RegExp(r'[A-Za-z][A-Za-z0-9_]*(?:/[A-Za-z0-9_.\-]+)+'), '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n');

/// An Endfield text as the knowledge base stores it: markup and asset
/// references removed, the player character's lines in one form. The game
/// writes a line for either gender of the Endministrator as `{F}…{M}…`; the
/// female form is kept (the research kit's default too). `{player}` is the
/// player's name, written as the title every character uses for them.
String endfieldText(String raw) {
  var text = raw;
  if (text.contains('{F}') && text.contains('{M}')) {
    text = text.replaceAllMapped(
      RegExp(r'\{F\}([\s\S]*?)\s*\{M\}[\s\S]*?(?=\{F\}|$)'),
      (m) => m.group(1)!,
    );
  }
  text = text.replaceAll(RegExp(r'@?\{player\}'), '管理员');
  return stripAssetRefs(cleanRichText(text)).trim();
}
