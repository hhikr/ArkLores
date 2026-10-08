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

import '../../game.dart' show endfieldId;
import '../text_harvest.dart' show cleanRichText, isMechanical;
import 'endfield_stories.dart' show EndfieldMission;
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

/// Kinds of the collections that hang below an operator besides its
/// missions (`memory`): its Baker topics and its interactions on the
/// Dijiang. They are listed on the operator's page, not as shelves.
const String bakerTopicKind = 'baker';
const String shipInteractionKind = 'ship';

/// The entry type that names the section of the archive a collection is in
/// (`PrtsPage`: 中枢档案, 见闻辑录, 音像存档, and 情报采集); it has no text
/// of its own and groups the archive shelf.
const String archiveSectionType = 'archive_section';

class EndfieldImporter {
  EndfieldImporter(
    this.tables,
    this.writer, {
    this.log,
    this.missions = const {},
  });

  final EndfieldTables tables;
  final EndfieldWriter writer;
  final void Function(String message)? log;

  /// The game's mission definitions (for the region of a text whose id
  /// names its mission).
  final Map<String, EndfieldMission> missions;

  /// Operator entry ids by character id (for bindings).
  final Map<String, String> operators = {};

  Future<void> importTables() async {
    await importOperators();
    await importFactions();
    await importEnemies();
    await importWeapons();
    await importItems();
    await importArchive();
    await importDungeons();
    await importMails();
  }

  /// Dungeons (`DungeonTable`): a stage entry each with its flavour line,
  /// its region, and the enemies it places (`appears_in`, as Arknights'
  /// enemies appear in stages). Mechanics-only descriptions are skipped.
  Future<void> importDungeons() async {
    const name = 'DungeonTable';
    final source = tables.sourcePath(name);
    final regions = {
      for (final MapEntry(:key, :value) in tables.table('DomainDataTable').entries)
        if (value is Map) key: _clean(value['domainName']),
    };
    var count = 0;
    var links = 0;
    for (final MapEntry(key: key, value: row) in tables.table(name).entries) {
      if (row is! Map<String, dynamic>) continue;
      final id = '${row['dungeonId'] ?? key}';
      final title = _clean(row['dungeonName']);
      final desc = _clean(row['dungeonDesc']);
      if (title.isEmpty || desc.isEmpty || isMechanical(desc)) continue;
      final entry = await writer.entry(
        type: 'stage',
        rawId: id,
        name: title,
        group: regions['${row['domainId'] ?? ''}'],
        sourcePath: source,
        category: 'stage',
        texts: [(section: '简介', text: desc)],
      );
      for (final enemy in listOfStrings(row['enemyIds']).toSet()) {
        await writer.link('enemy:${endfieldId(enemy)}', 'appears_in', entry, name);
        links++;
      }
      count++;
    }
    // Links to enemies without an entry (no description) point nowhere.
    await writer.db.rawDelete(
      "DELETE FROM entry_links WHERE relation = 'appears_in' AND src NOT IN "
      '(SELECT id FROM entries)',
    );
    log?.call('dungeons: $count ($links enemy bindings)');
  }

  /// The name of a mail's sender: an operator (`pelica`), or the NPC its id
  /// names (`deliver_thank_002_<npc>_01`).
  String? _senderName(String sender) {
    for (final MapEntry(:key, :value) in tables.table('CharacterTable').entries) {
      if (key.endsWith('_$sender') && value is Map) {
        final name = _clean(value['name']);
        if (name.isNotEmpty) return name;
      }
    }
    final npcs = tables.table('NpcTable');
    for (final part in sender.split('_').reversed) {
      for (final value in npcs.values) {
        if (value is Map && value['npcId'] == part) {
          final name = _clean(value['name']);
          if (name.isNotEmpty) return name;
        }
      }
    }
    return null;
  }

  /// Mails a character sends (thanks, news); system notices are not story.
  Future<void> importMails() async {
    const name = 'MailTemplateTable';
    final source = tables.sourcePath(name);
    var count = 0;
    for (final MapEntry(key: key, value: row) in tables.table(name).entries) {
      if (row is! Map<String, dynamic>) continue;
      final sender = '${row['senderId'] ?? ''}';
      if (sender.isEmpty || sender.startsWith('sys')) continue;
      final title = _clean(row['title']);
      final text = _clean(row['mailContent']);
      if (title.isEmpty || text.isEmpty) continue;
      final from = _senderName(sender);
      await writer.entry(
        type: 'mail',
        rawId: '${row['templateId'] ?? key}',
        name: from == null ? title : '$title · $from',
        sourcePath: source,
        category: 'world',
        texts: [(section: '邮件', text: text)],
      );
      count++;
    }
    log?.call('mails: $count');
  }

  String _clean(Object? field) => endfieldText(tables.text(field));

  /// An interface string of the game by its key ([fallback] when the
  /// tables do not have it).
  String _ui(String key, String fallback) {
    final text = endfieldText(tables.textOfKey(key));
    return text.isEmpty ? fallback : text;
  }

  /// The region (地区, `DomainDataTable`) a level or an id mentioning a map
  /// (`map01…`) is in, by the regions' own level lists.
  String? regionOf(String id) {
    final map = RegExp(r'map\d+').firstMatch(id)?.group(0);
    for (final row in tables.table('DomainDataTable').values) {
      if (row is! Map) continue;
      final levels = listOfStrings(row['levelGroup']);
      final hit = levels.contains(id) ||
          (map != null && levels.any((l) => l.startsWith('${map}_')));
      if (hit) {
        final name = _clean(row['domainName']);
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  /// The mission an id names (`paper_sm1l1m4_2`, `text_c13m3_4`): an
  /// underscore-separated part that is a defined mission, or one once its
  /// sub-mission mark (`d<n>`) is cut. Null when none.
  String? missionIn(String id) {
    for (final part in id.split('_')) {
      if (missions.containsKey(part)) return part;
      final base = part.replaceFirst(RegExp(r'd\d+$'), '');
      if (base != part && missions.containsKey(base)) return base;
    }
    return null;
  }

  /// The region of a text by its ids (its own, its pages', its contents'):
  /// a map named in one of them, else the level of a mission named in one.
  /// Ids only; null when none says.
  String? regionOfIds(Iterable<String> ids) {
    final list = ids.where((i) => i.isNotEmpty).toList();
    for (final id in list) {
      final region = regionOf(id);
      if (region != null) return region;
    }
    for (final id in list) {
      final level = missions[missionIn(id)]?.levelId;
      final region = level == null ? null : regionOf(level);
      if (region != null) return region;
    }
    return null;
  }

  /// The name of a region by its id (`domain_1`).
  String? regionName(String? domainId) {
    final row = tables.table('DomainDataTable')[domainId ?? ''];
    final name = row is Map ? _clean(row['domainName']) : '';
    return name.isEmpty ? null : name;
  }

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
      final tags = _operatorTags(id);
      // The parts of the profile as the game's profile page names them.
      final tagSection = _ui('ui_char_profile_message_title', '干员情报');
      final voiceSection = _ui('ui_char_profile_voice', '语音记录');
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
          if (tags.isNotEmpty) (section: tagSection, text: tags.join('\n')),
          ...records,
          if (voices.isNotEmpty) (section: voiceSection, text: voices.join('\n')),
        ],
      );
      operators[id] = entryId;
      await writer.entityDocument(
        entityId: entity,
        name: title,
        type: 'operator',
        content: [
          if (tags.isNotEmpty) '## $tagSection\n${tags.join('\n')}',
          for (final r in records) '## ${r.section}\n${r.text}',
          if (voices.isNotEmpty) '## $voiceSection\n${voices.join('\n')}',
        ].join('\n\n'),
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

  /// The tag groups of an operator's profile that players see, by the
  /// game's own group names (`TagGroupDataTable`): faction, race, expertise,
  /// hobbies. System-only groups, hidden tags and gift preferences
  /// (gameplay) are left out.
  static const List<(String, String)> _profileTagFields = [
    ('blocTagId', 'tag_group_power'),
    ('raceTagId', 'tag_group_race'),
    ('expertTagIds', 'tag_group_expert'),
    ('hobbyTagIds', 'tag_group_hobby'),
  ];

  /// `阵营：X` lines of [charId]'s profile tags.
  List<String> _operatorTags(String charId) {
    final row = tables.table('CharacterTagTable')[charId];
    if (row is! Map) return const [];
    final data = tables.table('TagDataTable');
    final groups = tables.table('TagGroupDataTable');
    return [
      for (final (field, group) in _profileTagFields)
        if (_tagNames(row[field], data) case final names when names.isNotEmpty)
          if (groups[group] case final Map<String, dynamic> g
              when _clean(g['tagGroupName']).isNotEmpty)
            '${_clean(g['tagGroupName'])}：${names.join('、')}',
    ];
  }

  List<String> _tagNames(Object? raw, Map<String, dynamic> data) => [
        for (final id in raw is List ? raw : [raw])
          if (data['$id'] case final Map<String, dynamic> tag
              when tag['hideTag'] != true)
            if (_clean(tag['tagName']) case final name
                when name.isNotEmpty && name != '？？？')
              name,
      ];

  /// Factions: names only (entities the coverage layer can find); from the
  /// faction table, else from the operators' faction tags.
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
    if (count == 0) {
      final names = <String>{
        for (final row in tables.table('CharacterTagTable').values)
          if (row is Map) ..._tagNames(row['blocTagId'], tables.table('TagDataTable')),
      };
      for (final name in names) {
        await writer.entity(
          rawId: 'power_$name',
          name: name,
          type: 'power',
          sourcePath: tables.sourcePath('CharacterTagTable'),
        );
        count++;
      }
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
      // Where it is found, as the game names the areas.
      final areas = <String>{
        for (final d in listOfStrings(row['distributionIds']))
          if (tables.table('DistributionInfoTable')[d] case final Map<String, dynamic> info)
            _clean(info['areaName']),
      }..remove('');
      await writer.entry(
        type: 'enemy',
        rawId: id,
        name: title,
        group: _groupName('DisplayEnemyTypeTable', row['displayType']),
        sourcePath: source,
        category: 'enemy',
        texts: [
          (section: '介绍', text: text),
          if (areas.isNotEmpty) (section: '分布', text: areas.join('、')),
        ],
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

  /// The PRTS archive (情报档案库), in the game's layout: its pages
  /// (`PrtsPage`: 中枢档案, 见闻辑录, 音像存档) hold categories
  /// (`PrtsCategory`) of archive entries (`PrtsFirstLv`), each with its pages
  /// (`PrtsAllItem`) whose text is a `RichContentTable` row, or the lines of a
  /// `RadioTable` recording (音像存档). Each category is a collection on the
  /// archive shelf, marked with its page ([archiveSectionType]); each archive
  /// entry one document with its pages as text blocks. Investigations
  /// (`PrtsInvestigate`, 情报采集) are collections of their own: the
  /// investigation, the documents it gathers and the report it unlocks.
  Future<void> importArchive() async {
    final categories = tables.table('PrtsCategory');
    final firstLv = tables.table('PrtsFirstLv');
    final pages = tables.table('PrtsAllItem');
    final rich = tables.table('RichContentTable');
    final radio = tables.table('RadioTable');
    final investigateTable = tables.table('PrtsInvestigate');
    const source = 'PrtsFirstLv';
    final sourcePath = tables.sourcePath(source);
    // The pages of the archive by the type of item they show, in the
    // game's order, and the investigations' page.
    final pageNames = <String, String>{
      for (final MapEntry(:key, :value) in tables.table('PrtsPage').entries)
        if (value is Map && _clean(value['name']).isNotEmpty)
          '${value['pageType'] ?? key}': _clean(value['name']),
    };
    final researchPage = _ui('ui_prts_research_title', '情报采集');
    // What an investigation says about the pages it gathers and the report
    // it unlocks: their region, and that the report is part of it.
    final reportOf = <String, String>{}; // report page id -> investigation id
    final investigationRegion = <String, String>{}; // page id -> region
    for (final MapEntry(key: id, value: row) in investigateTable.entries) {
      if (row is! Map<String, dynamic>) continue;
      final region = regionName('${row['domainId'] ?? ''}');
      final report = '${row['unlockPrts'] ?? ''}';
      if (report.isNotEmpty) reportOf[report] = id;
      for (final page in [...listOfStrings(row['collectionIdList']), report]) {
        if (region != null && page.isNotEmpty) investigationRegion[page] = region;
      }
    }
    // A category's page: the page of the type of its items; a category of
    // investigation reports is on the investigations' page.
    final sectionOf = <String, String>{};
    for (final row in firstLv.values) {
      if (row is! Map<String, dynamic>) continue;
      final category = '${row['categoryId'] ?? ''}';
      for (final pageId in listOfStrings(row['itemIds'])) {
        final page = pages[pageId];
        if (page is! Map) continue;
        final section = reportOf.containsKey(pageId)
            ? researchPage
            : pageNames['${page['type'] ?? ''}'];
        if (section != null) sectionOf.putIfAbsent(category, () => section);
      }
    }
    final sectionOrder = [...pageNames.values, researchPage];
    int sectionRank(String? section) {
      final i = section == null ? -1 : sectionOrder.indexOf(section);
      return i < 0 ? sectionOrder.length : i;
    }

    Future<void> markSection(String collection, String section) => writer.entry(
          type: archiveSectionType,
          rawId: 'section_$collection',
          name: section,
          collectionId: collection,
          group: section,
          sourcePath: tables.sourcePath('PrtsPage'),
          category: 'archive',
        );

    for (final MapEntry(key: id, value: row) in categories.entries) {
      if (row is! Map<String, dynamic>) continue;
      final section = sectionOf[id];
      await writer.collection(
        id: 'prts_$id',
        kind: 'archive',
        name: _clean(row['name']).isEmpty ? id : _clean(row['name']),
        sortKey: sectionRank(section) * 1000 + ((row['order'] as num?)?.toInt() ?? 0),
        sourcePath: tables.sourcePath('PrtsCategory'),
      );
      if (section != null) await markSection('prts_$id', section);
    }
    final documentOf = <String, String>{}; // page id -> document entry id
    var count = 0, recordings = 0;
    for (final MapEntry(key: id, value: row) in firstLv.entries) {
      if (row is! Map<String, dynamic>) continue;
      final category = '${row['categoryId'] ?? ''}';
      final title = _clean(row['name']);
      final blocks = <({String section, String text})>[];
      final contentIds = <String>[];
      for (final pageId in listOfStrings(row['itemIds'])) {
        final page = pages[pageId];
        if (page is! Map<String, dynamic>) continue;
        final contentId = '${page['contentId'] ?? ''}';
        contentIds.add(contentId);
        final content = rich[contentId];
        if (content is Map<String, dynamic>) {
          final text = [
            for (final c in listOfMaps(content['contentList'])) _clean(c['content']),
          ].where((t) => t.isNotEmpty).join('\n');
          if (text.isEmpty) continue;
          final pageTitle = _clean(content['title']).isNotEmpty
              ? _clean(content['title'])
              : _clean(page['name']);
          blocks.add((section: pageTitle.isEmpty ? title : pageTitle, text: text));
          continue;
        }
        // A recording (音像存档): the lines of its radio row, with who
        // speaks, under the page's own name and line.
        final recording = radio[contentId];
        if (recording is Map<String, dynamic>) {
          final lines = listOfMaps(recording['radioSingleDataList'])
            ..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
          final text = [
            if (_clean(page['desc']).isNotEmpty) _clean(page['desc']),
            for (final l in lines)
              if (_clean(l['radioText']).isNotEmpty)
                _clean(l['actorName']).replaceAll(RegExp(r'\{[^{}]*\}'), '').trim().isEmpty
                    ? _clean(l['radioText'])
                    : '${_clean(l['actorName']).replaceAll(RegExp(r'\{[^{}]*\}'), '').trim()}：'
                        '${_clean(l['radioText'])}',
          ].join('\n');
          if (lines.isEmpty || text.isEmpty) continue;
          blocks.add((section: _clean(page['name']).isEmpty ? title : _clean(page['name']), text: text));
          recordings++;
        }
      }
      if (blocks.isEmpty || title.isEmpty) continue;
      final itemIds = listOfStrings(row['itemIds']);
      final entryId = await writer.entry(
        type: 'document',
        rawId: id,
        name: title,
        collectionId: category.isEmpty ? null : 'prts_$category',
        group: [
          for (final p in itemIds)
            if (investigationRegion[p] != null) investigationRegion[p]!,
        ].firstOrNull ??
            regionOfIds([id, ...itemIds, ...contentIds]),
        sortKey: (row['order'] as num?)?.toInt(),
        sourcePath: sourcePath,
        category: 'archive',
        texts: blocks,
      );
      for (final pageId in itemIds) {
        documentOf[pageId] = entryId;
      }
      count++;
    }
    var investigations = 0;
    for (final MapEntry(key: id, value: row) in investigateTable.entries) {
      if (row is! Map<String, dynamic>) continue;
      final title = _clean(row['name']);
      if (title.isEmpty) continue;
      final collection = 'investigate_$id';
      await writer.collection(
        id: collection,
        kind: 'archive',
        name: title,
        sortKey: sectionRank(researchPage) * 1000 + 500 + ((row['index'] as num?)?.toInt() ?? 0),
        sourcePath: tables.sourcePath('PrtsInvestigate'),
      );
      await markSection(collection, researchPage);
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
        group: regionName('${row['domainId'] ?? ''}'),
        sortKey: 0,
        sourcePath: tables.sourcePath('PrtsInvestigate'),
        category: 'archive',
        texts: [
          if (desc.isNotEmpty) (section: '简介', text: desc),
          if (notes.isNotEmpty) (section: '线索', text: notes.join('\n')),
        ],
      );
      for (final page in [
        ...listOfStrings(row['collectionIdList']),
        '${row['unlockPrts'] ?? ''}',
      ]) {
        final doc = documentOf[page];
        if (doc != null) {
          await writer.link(doc, 'part_of', intro, 'PrtsInvestigate');
        }
      }
      investigations++;
    }
    log?.call('archive documents: $count ($recordings recordings), '
        'investigations: $investigations');
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
