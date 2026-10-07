/// Entry layer importer (schema 5, 0.11): every official item that is not an
/// operator, a voice line or a story file becomes an `entries` row owned by
/// a `collections` row, with its text as one or more citable
/// `normalized_records` and its bindings in `entry_links`.
///
/// What is imported follows one rule: *story-relevant text*. Names, flavor
/// text, briefings, news, letters, event narration, archive documents.
/// Gameplay text — skills, mechanics, rules, effects, how to obtain, enemy
/// ability descriptions — is not imported (an ability text outnumbers the
/// story lines that mention the same word several times over and answers
/// questions the story agent must not answer from, see `docs`).
///
/// Everything is deterministic and derived from ids in the source tables:
/// - attribution (`collection_id`) comes from the zone/activity maps of the
///   tables, or from the id prefix matching a known collection id — never
///   from a name list of stories, activities or characters;
/// - bindings (enemy ↔ stage …) come from fields (`levelId`, `zoneId`,
///   `charId`) or from the level files' spawn tables.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import 'arknights_importer.dart';
import 'event_outline.dart';
import 'story_naming.dart';
import 'text_harvest.dart';

const String _excel = 'zh_CN/gamedata/excel';
const String _levels = 'zh_CN/gamedata/levels';

/// The excel tables the entry layer reads (besides the character tables).
class EntryTables {
  EntryTables._();

  static const String storyReview = '$_excel/story_review_table.json';
  static const String storyReviewMeta = '$_excel/story_review_meta_table.json';
  static const String item = '$_excel/item_table.json';
  static const String skin = '$_excel/skin_table.json';
  static const String medal = '$_excel/medal_table.json';
  static const String uniequip = '$_excel/uniequip_table.json';
  static const String enemy = '$_excel/enemy_handbook_table.json';
  static const String stage = '$_excel/stage_table.json';
  static const String zone = '$_excel/zone_table.json';
  static const String activity = '$_excel/activity_table.json';
  static const String retro = '$_excel/retro_table.json';
  static const String roguelikeTopic = '$_excel/roguelike_topic_table.json';
  static const String roguelike = '$_excel/roguelike_table.json';
  static const String sandboxPerm = '$_excel/sandbox_perm_table.json';
  static const String sandbox = '$_excel/sandbox_table.json';
  static const String handbook = '$_excel/handbook_info_table.json';
  static const String team = '$_excel/handbook_team_table.json';
  static const String tip = '$_excel/tip_table.json';
  static const String charm = '$_excel/charm_table.json';
  static const String displayMeta = '$_excel/display_meta_table.json';
  static const String arkvent = '$_excel/arkvent_table.json';
  static const String arkOdc = '$_excel/ark_odc_table.json';

  /// Every excel table of the entry layer (the in-app updater downloads
  /// these; the character tables are listed with the operator stage).
  static const List<String> all = [
    storyReview,
    storyReviewMeta,
    item,
    skin,
    medal,
    uniequip,
    enemy,
    stage,
    zone,
    activity,
    retro,
    roguelikeTopic,
    roguelike,
    sandboxPerm,
    sandbox,
    handbook,
    team,
    tip,
    charm,
    displayMeta,
    arkvent,
    arkOdc,
  ];

  /// Tables the owner of an entry is read from (which activity, chapter or
  /// zone a stage, item or medal belongs to). When one of them changes, the
  /// tables in [ownerDependents] are read again even if they did not change,
  /// or an update would leave their owners as they were.
  static const Set<String> contextTables = {
    storyReview,
    activity,
    retro,
    stage,
    zone,
    sandbox,
  };

  /// Entry tables whose owners come from [contextTables].
  static const List<String> ownerDependents = [zone, stage, item, medal, charm];

  /// Whether [path] is a level file (`levels/**.json`): the source of the
  /// enemy ↔ stage bindings.
  static bool isLevelFile(String path) =>
      path.startsWith('$_levels/') &&
      path.endsWith('.json') &&
      !path.contains('/enemydata/') &&
      !path.endsWith('/levels_meta.json');
}

/// How one entry type is stored as records.
class _TypeSpec {
  const _TypeSpec(
    this.category,
    this.subtype,
    this.contentType, {
    this.entity = false,
  });

  final String category;
  final String subtype;
  final String contentType;

  /// Whether the entry's name goes into `entities` (name index, aliases and
  /// the story coverage layer). Only types people ask about by name.
  final bool entity;
}

const Map<String, _TypeSpec> _typeSpecs = {
  'item': _TypeSpec('world_item', 'item', 'item_description', entity: true),
  'skin': _TypeSpec('world_item', 'skin', 'skin_description', entity: true),
  'skin_brand': _TypeSpec('world_item', 'skin', 'skin_description'),
  'medal': _TypeSpec('world_item', 'medal', 'medal_description', entity: true),
  'charm': _TypeSpec('world_item', 'charm', 'charm_description'),
  'module': _TypeSpec('operator', 'module', 'operator_module', entity: true),
  'operator_stage': _TypeSpec('operator', 'stage', 'operator_stage'),
  'enemy': _TypeSpec('enemy', 'profile', 'enemy_profile', entity: true),
  'stage': _TypeSpec('stage', 'stage', 'stage_description', entity: true),
  'zone': _TypeSpec('stage', 'zone', 'zone_description', entity: true),
  'activity':
      _TypeSpec('activity', 'basic_info', 'activity_basic_info', entity: true),
  'activity_text': _TypeSpec('activity', 'text', 'activity_text'),
  'archive_file': _TypeSpec('activity', 'archive', 'activity_archive'),
  'archive_news': _TypeSpec('activity', 'archive', 'activity_archive'),
  'archive_landmark': _TypeSpec('activity', 'archive', 'activity_archive'),
  'archive_log': _TypeSpec('activity', 'archive', 'activity_archive'),
  'archive_book': _TypeSpec('activity', 'archive', 'activity_archive'),
  'archive_avg': _TypeSpec('activity', 'archive', 'activity_archive'),
  'power': _TypeSpec('world', 'power', 'power_profile', entity: true),
  'npc': _TypeSpec('world', 'npc', 'npc_profile', entity: true),
  'worldview': _TypeSpec('world', 'worldview', 'worldview'),
  'mail': _TypeSpec('world', 'mail', 'mail_archive'),
  'home_theme': _TypeSpec('world_item', 'theme', 'home_theme'),
  'roguelike_topic': _TypeSpec(
    'roguelike',
    'topic',
    'roguelike_topic',
    entity: true,
  ),
  'roguelike_item': _TypeSpec('roguelike', 'item', 'roguelike_item'),
  'roguelike_scene': _TypeSpec('roguelike', 'scene', 'roguelike_scene'),
  'roguelike_choice': _TypeSpec('roguelike', 'choice', 'roguelike_choice'),
  'roguelike_ending': _TypeSpec('roguelike', 'ending', 'roguelike_ending'),
  'roguelike_stage': _TypeSpec('roguelike', 'stage', 'roguelike_stage'),
  'roguelike_zone': _TypeSpec('roguelike', 'zone', 'roguelike_zone'),
  'roguelike_squad': _TypeSpec('roguelike', 'squad', 'roguelike_squad'),
  'roguelike_prize': _TypeSpec('roguelike', 'prize', 'roguelike_prize'),
  'roguelike_tip': _TypeSpec('roguelike', 'tip', 'roguelike_tip'),
  'roguelike_buff': _TypeSpec('roguelike', 'buff', 'roguelike_buff'),
  'sandbox_item': _TypeSpec('sandbox', 'item', 'sandbox_item'),
  'sandbox_text': _TypeSpec('sandbox', 'text', 'sandbox_text'),
  'sandbox_stage': _TypeSpec('sandbox', 'stage', 'sandbox_stage'),
  'sandbox_event': _TypeSpec('sandbox', 'event', 'sandbox_event'),
  'sandbox_topic': _TypeSpec('sandbox', 'topic', 'sandbox_topic'),
  'sandbox_act': _TypeSpec('sandbox', 'act', 'sandbox_act'),
};

_TypeSpec _specOf(String type) =>
    _typeSpecs[type] ?? _TypeSpec('misc', type, type);

/// Chinese name of each entry type: the `section` of its records, so that a
/// search for the words players use ("收藏品", "关卡", "敌人") finds them.
/// The labels are the game's own terms (the roguelike mode is 集成战略).
const Map<String, String> _typeLabels = {
  'item': '物品',
  'skin': '皮肤',
  'skin_brand': '皮肤系列',
  'medal': '奖章',
  'charm': '标志物',
  'module': '干员模组',
  'operator_stage': '悖论模拟关卡',
  'enemy': '敌人',
  'stage': '关卡',
  'zone': '章节',
  'activity': '活动',
  'activity_text': '活动文本',
  'archive_file': '活动档案',
  'archive_news': '活动档案',
  'archive_landmark': '活动档案',
  'archive_log': '活动档案',
  'archive_book': '活动档案',
  'archive_avg': '活动档案',
  'power': '势力',
  'npc': '角色',
  'worldview': '世界观',
  'mail': '邮件',
  'home_theme': '界面主题',
  'roguelike_topic': '集成战略',
  'roguelike_item': '集成战略收藏品',
  'roguelike_scene': '集成战略事件',
  'roguelike_choice': '集成战略选项',
  'roguelike_ending': '集成战略结局',
  'roguelike_stage': '集成战略关卡',
  'roguelike_zone': '集成战略区域',
  'roguelike_squad': '月度小队',
  'roguelike_prize': '集成战略奖励',
  'roguelike_tip': '注释',
  'roguelike_buff': '集成战略加成',
  'sandbox_item': '生息演算物品',
  'sandbox_text': '生息演算文本',
  'sandbox_stage': '生息演算关卡',
  'sandbox_event': '生息演算事件',
  'sandbox_topic': '生息演算',
  'sandbox_act': '生息演算篇章',
};

/// One entry before it is written.
class _Draft {
  _Draft({
    required this.type,
    required this.key,
    required this.sourcePath,
    this.name,
    this.code,
    this.collectionId,
    this.groupName,
    this.sortKey,
    this.sections = const [],
    this.sectionLabel,
  });

  final String type;

  /// Unique within [type]; the entry id is `<type>:<key>`.
  final String key;
  final String sourcePath;
  final String? name;
  final String? code;
  final String? collectionId;
  final String? groupName;
  final int? sortKey;

  /// Text pieces; `label` is shown as `label：text` when not empty.
  final List<TextSection> sections;

  /// `normalized_records.section` (defaults to the type).
  final String? sectionLabel;

  String get id => '$type:$key';
}

/// Read-only lookup tables used for attribution (which collection owns
/// what), loaded from the source tree once per run.
class _Context {
  final Map<String, String> activityName = {};
  final Map<String, int?> activityStart = {};
  final Map<String, String> zoneToActivity = {};
  final Map<String, String> zoneToRetro = {};
  final Map<String, String> zoneType = {};

  /// Re-runs: they carry what the original carries, so they are not entries
  /// of the library (their rows are removed in [EntryImporter.rebuildDerived]).
  final Set<String> dropped = {};

  /// A re-run's id → the id of the activity it re-runs. What the re-run's
  /// tables say (texts, drops, medals) is said of that activity.
  final Map<String, String> alias = {};

  /// Stage id → the zone it is in (stages of every table that has them).
  final Map<String, String> stageZone = {};

  /// Every known collection: id → (kind, name, start, sort).
  final Map<String, ({String kind, String name, int? start, int sort})>
      collections = {};

  List<String>? _byLength;

  void add(String id, String kind, String name, int? start, int sort) {
    collections.putIfAbsent(
      id,
      () => (kind: kind, name: name, start: start, sort: sort),
    );
    _byLength = null;
  }

  /// [id], or the activity it is a re-run of.
  String? home(String? id) => id == null ? null : (alias[id] ?? id);

  /// The collection whose id is a prefix of [rawId] (followed by `_`), after
  /// dropping leading tokens (`item_sandbox_1_x` → `sandbox_1_x`). A re-run's
  /// id stands for the activity it re-runs.
  String? collectionForId(String rawId) {
    _byLength ??= ({...collections.keys, ...alias.keys}.toList()
      ..sort((a, b) => b.length.compareTo(a.length)));
    var id = rawId.toLowerCase();
    while (true) {
      for (final known in _byLength!) {
        final k = known.toLowerCase();
        if (id == k || id.startsWith('${k}_')) return alias[known] ?? known;
      }
      final cut = id.indexOf('_');
      if (cut < 0) return null;
      id = id.substring(cut + 1);
    }
  }

  String? collectionOfZone(String zoneId) =>
      zoneToActivity[zoneId] ??
      zoneToRetro[zoneId] ??
      (collections.containsKey(zoneId) ? zoneId : collectionForId(zoneId));

  /// The collection a stage belongs to, a re-run's stage counted with the
  /// activity it re-runs.
  String? collectionOfStage(String stageId) {
    final zone = stageZone[stageId];
    return zone == null ? null : home(collectionOfZone(zone));
  }
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const <dynamic>[];
String _s(Object? v) => v == null ? '' : '$v'.trim();
String _clean(Object? v) => cleanRichText(_s(v));
int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

/// Subkey → label used in the name of harvested activity text entries.
String _labelFor(String subkey) {
  final k = subkey.toLowerCase();
  const labels = <String, String>{
    'news': '新闻',
    'event': '事件',
    'principal': '人物介绍',
    'festival': '节日祝福',
    'blessing': '节日祝福',
    'perform': '演出',
    'dialog': '对话',
    'plot': '剧情',
    'archive': '档案',
    'landmark': '地标',
    'photo': '照片',
    'bark': '台词',
    'treasure': '宝箱',
    'choice': '选项',
    'story': '故事',
    'comment': '评论',
    'cmt': '评论',
    'mail': '邮件',
  };
  for (final entry in labels.entries) {
    if (k.contains(entry.key)) return entry.value;
  }
  return '活动文本';
}

/// Imports the entry layer into the importer's database.
class EntryImporter {
  EntryImporter(this.importer);

  final ArknightsImporter importer;

  Database get db => importer.db;
  Directory get sourceDir => importer.sourceDir;

  /// Entry ids written in this run (the first writer wins).
  final Set<String> _seen = {};

  /// Harvested groups: an activity and its re-run carry identical text, and
  /// the first copy stays. Looked up in the database (not in memory), so a
  /// single re-imported table makes the same choice a complete build does.
  static const Set<String> _dedupedTypes = {'activity_text', 'sandbox_text'};

  /// What a topic calls one of its buff tables (the wiki pages of the modes):
  /// the tables only name them by key. A table whose entries all read
  /// 回响：… is named by that prefix; kinds nobody named stay unnamed.
  static const Map<String, String> _buffKinds = {
    'rogue_1/variationData': '幻觉',
    'rogue_2/charBuffData': '排异反应',
    'rogue_6/variationData': '乌托邦',
  };

  String? _buffKind(String topic, String group, Map<String, dynamic> table) {
    final prefixes = {
      for (final v in table.values)
        if (_clean(_map(v)['innerName']).contains('：'))
          _clean(_map(v)['innerName']).split('：').first
        else
          '',
    };
    if (prefixes.length == 1 && prefixes.first.isNotEmpty) return prefixes.first;
    return _buffKinds['$topic/$group'];
  }

  /// Roguelike item types that are the rules' own stand-ins and resources.
  static const Set<String> _mechanicItemTypes = {
    'feature',
    'copper_draw_num',
    'divination_kit',
    'stash_recruit_limit',
    'custom_ticket',
    // The buff twin of a coin (same name and words, or a revised line).
    'copper_buff',
  };

  /// The shelf of an activity: the game's own displayType first (the
  /// activity table), else what the story review lists it as. A big
  /// SideStory, a mini story collection (故事集), an interlude, and the rest
  /// (check-ins, battle modes, minor events) that carry little story.
  static String _activityKind(String displayType, String reviewType) {
    switch (displayType) {
      case 'SIDESTORY':
        return 'sidestory';
      case 'MINISTORY':
        return 'ministory';
      case 'BRANCHLINE':
        return 'branchline';
    }
    return switch (reviewType) {
      'ACTIVITY' => 'sidestory',
      'MINI_ACTIVITY' => 'ministory',
      _ => 'activity',
    };
  }

  Future<Object?> _json(String repoPath) async {
    final file = File(p.join(sourceDir.path, repoPath));
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<Map<String, dynamic>> _table(String repoPath) async =>
      _map(await _json(repoPath));

  // ─── Context ────────────────────────────────────────────────────

  Future<_Context> _loadContext() async {
    final ctx = _Context();
    final activity = await _table(EntryTables.activity);
    final basic = _map(activity['basicInfo']);
    final review = await _table(EntryTables.storyReview);
    // The first sandbox mode is an activity: the sandbox table lists it, so it
    // sits on the sandbox shelf with the others.
    final legacySandbox = _map(
      _map(await _table(EntryTables.sandbox))['sandboxActTables'],
    ).keys.toSet();
    var sort = 0;
    for (final entry in review.entries) {
      final c = _map(entry.value);
      final type = _s(c['entryType']);
      final id = _s(c['id']).isEmpty ? entry.key : _s(c['id']);
      final kind = legacySandbox.contains(id)
          ? 'sandbox'
          : type == 'MAINLINE'
          ? 'main'
          : type == 'NONE'
              ? 'memory'
              : _activityKind(
                  _s(_map(basic[id])['displayType']),
                  type,
                );
      final start = _int(c['startTime']);
      ctx.add(
        _s(c['id']).isEmpty ? entry.key : _s(c['id']),
        kind,
        _clean(c['name']),
        start == null || start < 0 ? null : start,
        sort++,
      );
    }
    for (final entry in basic.entries) {
      final info = _map(entry.value);
      final name = _clean(info['name']);
      final start = _int(info['startTime']);
      ctx.activityName[entry.key] = name;
      ctx.activityStart[entry.key] = start;
      if (info['isReplicate'] == true || name.contains('复刻')) {
        ctx.dropped.add(entry.key);
        continue;
      }
      ctx.add(
        entry.key,
        legacySandbox.contains(entry.key)
            ? 'sandbox'
            : _activityKind(_s(info['displayType']), ''),
        name,
        start == null || start < 0 ? null : start,
        sort++,
      );
    }
    for (final entry in _map(activity['zoneToActivity']).entries) {
      ctx.zoneToActivity[entry.key] = '${entry.value}';
    }
    final retro = await _table(EntryTables.retro);
    // A re-run is the same content as the activity it re-runs: its zones and
    // stages belong to that activity, not to a shelf of re-runs of their
    // own. Only a re-run that links no known activity stays a collection.
    final retroHome = <String, String>{};
    for (final entry in _map(retro['retroActList']).entries) {
      final info = _map(entry.value);
      final home = [
        for (final id in _list(info['linkedActId']))
          if (ctx.collections.containsKey(_s(id))) _s(id),
      ];
      if (home.isNotEmpty) {
        retroHome[entry.key] = home.first;
        continue;
      }
      ctx.dropped.add(entry.key);
    }
    for (final entry in _map(retro['zoneToRetro']).entries) {
      final id = '${entry.value}';
      ctx.zoneToRetro[entry.key] = retroHome[id] ?? id;
    }
    ctx.alias.addAll(retroHome);
    // A re-run the retro table does not link is the activity of the same
    // name (the game writes “<名>·复刻”).
    final named = <String, List<String>>{};
    for (final e in ctx.collections.entries) {
      (named[e.value.name] ??= []).add(e.key);
    }
    for (final entry in basic.entries) {
      final info = _map(entry.value);
      final name = _clean(info['name']);
      if (!ctx.dropped.contains(entry.key) || ctx.alias.containsKey(entry.key)) {
        continue;
      }
      final base = name.replaceFirst(RegExp(r'[·・\s]*复刻$'), '').trim();
      final same = [
        for (final id in named[base] ?? const <String>[])
          if (id != entry.key) id,
      ];
      if (base == name || same.isEmpty) continue;
      // Of several (a name two activities share) the one of the same kind.
      final kind = _s(info['type']);
      ctx.alias[entry.key] = same.firstWhere(
        (id) => _s(_map(basic[id])['type']) == kind,
        orElse: () => same.first,
      );
    }
    for (final source in [
      _map((await _table(EntryTables.stage))['stages']),
      _map(retro['stageList']),
    ]) {
      for (final entry in source.entries) {
        final stage = _map(entry.value);
        final zone = _s(stage['zoneId']);
        if (zone.isEmpty) continue;
        final id = _s(stage['stageId']).isEmpty ? entry.key : _s(stage['stageId']);
        ctx.stageZone.putIfAbsent(id, () => zone);
      }
    }
    final topics = _map((await _table(EntryTables.roguelikeTopic))['topics']);
    for (final entry in topics.entries) {
      final info = _map(entry.value);
      final start = _int(info['startTime']);
      ctx.add(
        entry.key,
        'roguelike',
        _clean(info['name']),
        start == null || start < 0 ? null : start,
        sort++,
      );
    }
    final sandbox = await _table(EntryTables.sandboxPerm);
    for (final entry in _map(sandbox['basicInfo']).entries) {
      final info = _map(entry.value);
      final start = _int(info['topicStartTime']);
      ctx.add(
        entry.key,
        'sandbox',
        _clean(info['topicName']),
        start == null || start < 0 ? null : start,
        sort++,
      );
    }
    final zones = _map((await _table(EntryTables.zone))['zones']);
    for (final entry in zones.entries) {
      ctx.zoneType[entry.key] = _s(_map(entry.value)['type']);
    }
    return ctx;
  }

  // ─── Writing ────────────────────────────────────────────────────

  /// Owner lookup of the run in progress (names of the collections).
  _Context? _ctx;

  /// Display title of a record: `<owner name> · <entry name>`, so a hit
  /// shows which activity, topic or chapter the entry belongs to.
  String? _titleOf(_Draft d) {
    final owner = d.collectionId == null
        ? null
        : _ctx?.collections[d.collectionId]?.name;
    final name = d.name;
    if (name == null || name.isEmpty) return owner;
    if (owner == null || owner.isEmpty || name.startsWith(owner)) return name;
    return '$owner · $name';
  }

  /// Writes [d] (entry, entity and records) unless the id was written
  /// already in this run. Returns whether it was written.
  Future<bool> _emit(Transaction txn, _Draft d) async {
    if (!_seen.add(d.id)) return false;
    final spec = _specOf(d.type);
    final content = d.sections
        .where((s) => s.content.trim().isNotEmpty)
        .map((s) => s.section.isEmpty ? s.content : '${s.section}：${s.content}')
        .join('\n')
        .trim();
    if (content.isNotEmpty && _dedupedTypes.contains(d.type)) {
      final first = splitText(content).first;
      final same = await txn.rawQuery(
        'SELECT 1 FROM normalized_records WHERE content_type = ? '
        "AND content = ? AND raw_id NOT LIKE '%#%' "
        'AND (entry_id IS NULL OR entry_id <> ?) LIMIT 1',
        [spec.contentType, first, d.id],
      );
      if (same.isNotEmpty) {
        _seen.remove(d.id);
        return false;
      }
    }
    // Texts of an earlier run of this entry (a table read again after a rule
    // changed) are replaced, not added to.
    await txn.delete(
      'normalized_records',
      where: 'entry_id = ?',
      whereArgs: [d.id],
    );
    String? firstRecord;
    if (content.isNotEmpty) {
      final pieces = splitText(content);
      for (var i = 0; i < pieces.length; i++) {
        final record = NormalizedRecord(
          category: spec.category,
          subtype: spec.subtype,
          contentType: spec.contentType,
          entityId: spec.entity ? d.id : null,
          entityName: d.name,
          parentId: d.collectionId,
          parentType: d.collectionId == null ? null : 'collection',
          title: _titleOf(d),
          section: d.sectionLabel ?? _typeLabels[d.type] ?? d.type,
          content: pieces[i],
          sourcePath: d.sourcePath,
          rawId: i == 0 ? d.key : '${d.key}#$i',
          entryId: d.id,
          collectionId: d.collectionId,
        );
        firstRecord ??= record.id;
        await importer.insertRecord(txn, record);
      }
    }
    if (spec.entity && (d.name ?? '').isNotEmpty) {
      await importer.upsertEntity(
        txn,
        id: d.id,
        name: d.name!,
        entityType: d.type,
        sourceType: spec.contentType,
        sourcePath: d.sourcePath,
      );
    }
    await importer.insertEntry(
      txn,
      id: d.id,
      type: d.type,
      name: d.name,
      code: d.code,
      collectionId: d.collectionId,
      groupName: d.groupName,
      sortKey: d.sortKey,
      entityId: spec.entity ? d.id : null,
      rawId: d.key,
      recordId: firstRecord,
      sourcePath: d.sourcePath,
    );
    return true;
  }

  Future<void> _link(
    Transaction txn,
    String src,
    String relation,
    String dst,
    String sourcePath,
  ) =>
      importer.insertLink(
        txn,
        src: src,
        relation: relation,
        dst: dst,
        sourcePath: sourcePath,
      );

  // ─── Entry points ───────────────────────────────────────────────

  /// Imports every table of the entry layer, then the level bindings when
  /// the source tree has `levels/`.
  Future<void> importAllTables() async {
    _seen.clear();
    final ctx = await _loadContext();
    _ctx = ctx;
    for (final path in _importers.keys) {
      await _importTableWith(path, ctx);
    }
    await _importLevels(ctx);
  }

  /// Re-imports one table (incremental updates). The owner lookup is
  /// reloaded from the tables as they are on disk now.
  Future<void> importTable(String path) async {
    if (!_importers.containsKey(path)) return;
    _seen.clear();
    await _importTableWith(path, await _loadContext());
  }

  /// Binds the enemies to their stages from the level files again (after the
  /// stage entries were imported anew); a no-op without a `levels/` tree.
  Future<void> importLevels() async {
    _levelIndexCache = null;
    await _importLevels(await _loadContext());
  }

  /// Whether [path] is imported by this class.
  bool handles(String path) =>
      _importers.containsKey(path) || EntryTables.isLevelFile(path);

  Future<void> _importTableWith(String path, _Context ctx) async {
    final run = _importers[path];
    if (run == null) return;
    _ctx = ctx;
    _levelIndexCache = null;
    _enemyIdCache = null;
    _stageIdCache = null;
    await db.transaction((txn) => run(this, txn, ctx));
  }

  static final Map<String,
      Future<void> Function(EntryImporter, Transaction, _Context)> _importers = {
    EntryTables.item: (s, t, c) => s._items(t, c),
    EntryTables.skin: (s, t, c) => s._skins(t, c),
    EntryTables.medal: (s, t, c) => s._medals(t, c),
    EntryTables.uniequip: (s, t, c) => s._modules(t, c),
    EntryTables.enemy: (s, t, c) => s._enemies(t, c),
    EntryTables.zone: (s, t, c) => s._zones(t, c),
    EntryTables.stage: (s, t, c) => s._stages(t, c),
    EntryTables.activity: (s, t, c) => s._activities(t, c),
    EntryTables.retro: (s, t, c) => s._retro(t, c),
    EntryTables.storyReviewMeta: (s, t, c) => s._archives(t, c),
    EntryTables.handbook: (s, t, c) => s._handbook(t, c),
    EntryTables.team: (s, t, c) => s._powers(t, c),
    EntryTables.tip: (s, t, c) => s._worldview(t, c),
    EntryTables.charm: (s, t, c) => s._charms(t, c),
    EntryTables.displayMeta: (s, t, c) => s._displayMeta(t, c),
    EntryTables.roguelikeTopic: (s, t, c) => s._roguelikeTopics(t, c),
    EntryTables.roguelike: (s, t, c) => s._roguelikeLegacy(t, c),
    EntryTables.sandboxPerm: (s, t, c) => s._sandboxPerm(t, c),
    EntryTables.sandbox: (s, t, c) => s._sandboxLegacy(t, c),
    EntryTables.arkvent: (s, t, c) => s._arkvent(t, c, EntryTables.arkvent),
    EntryTables.arkOdc: (s, t, c) => s._arkvent(t, c, EntryTables.arkOdc),
  };

  // ─── Items, skins, medals, modules, charms ──────────────────────

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

  // ─── Enemies, stages, zones ─────────────────────────────────────

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

  /// Stage types that are story-relevant; the rest (daily, weekly, climb
  /// tower, campaign, guide) are gameplay.
  static const Set<String> _storyZoneTypes = {
    'MAINLINE',
    'MAINLINE_ACTIVITY',
    'MAINLINE_RETRO',
    'ACTIVITY',
    'SIDESTORY',
    'BRANCHLINE',
  };

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

  // ─── Activities, retro, archives ────────────────────────────────

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

  // ─── Handbook extras, powers, world view, display meta ──────────

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

  // ─── Roguelike ──────────────────────────────────────────────────

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
      if (_mechanicItemTypes.contains(_s(item['type']).toLowerCase())) continue;
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

  // ─── Sandbox, ark events ────────────────────────────────────────

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

  // ─── Levels: enemy ↔ stage bindings ─────────────────────────────

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

  /// Re-imports the bindings of one changed level file.
  Future<void> importLevelFile(String repoPath) async {
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

  Map<String, List<String>>? _levelIndexCache;
  Set<String>? _enemyIdCache;
  Set<String>? _stageIdCache;

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

  // ─── Derived layer: collections and story entries ───────────────

  /// Rebuilds everything that is derived from other tables: the owners
  /// (`collections`), the story entries and their bindings. Run after every
  /// import (full or incremental), once stories and the catalog exist.
  Future<void> rebuildDerived() async {
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
      final mechanic = _mechanicItemTypes.map((t) => "'$t'").join(',');
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
