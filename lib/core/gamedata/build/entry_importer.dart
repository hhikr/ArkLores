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

part 'entry_importer_items.dart';
part 'entry_importer_stages.dart';
part 'entry_importer_activities.dart';
part 'entry_importer_handbook.dart';
part 'entry_importer_roguelike.dart';
part 'entry_importer_sandbox.dart';
part 'entry_importer_levels.dart';
part 'entry_importer_derived.dart';

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
  /// zone a stage, item or medal belongs to, which zone a re-run folds into).
  /// When one of them changes, every other entry table is read again too even
  /// if it did not change, or an update would leave their owners and links as
  /// they were (a complete build and an update must end the same).
  static const Set<String> contextTables = {
    storyReview,
    activity,
    retro,
    stage,
    zone,
    sandbox,
  };

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

  /// Level files, enemies and stages, read once per run for the level
  /// bindings (`entry_importer_levels.dart`).
  Map<String, List<String>>? _levelIndexCache;
  Set<String>? _enemyIdCache;
  Set<String>? _stageIdCache;

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

  /// Re-imports the bindings of one changed level file.
  Future<void> importLevelFile(String repoPath) => _importLevelFile(repoPath);

  /// Rebuilds everything that is derived from other tables: the owners
  /// (`collections`), the story entries and their bindings. Run after every
  /// import (full or incremental), once stories and the catalog exist.
  Future<void> rebuildDerived() => _rebuildDerived();

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
    // What an earlier import of the table wrote goes first: a table read again
    // is exactly what its rules make of it now (an update, a rule change and a
    // complete build end the same), not that plus what older rules left.
    await db.transaction((txn) async {
      await _purgeSource(txn, path);
      await run(this, txn, ctx);
    });
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
}
