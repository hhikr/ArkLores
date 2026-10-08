/// 0.12: the Endfield conversations.
///
/// The conversations of the dialog tables (`DialogTextTable`, `RadioTable`,
/// `RemoteCommonTable`, `EnvTalkTable`, `SNSDialogTable`) are read as one
/// story per mission (or per place, enemy, message topic): all of its
/// conversations in the game's numbering, each opened by a `section` line
/// that names its kind. A mission is one collection (named and shelved by
/// the game's mission definitions when given) holding that story, the
/// mission's description and the texts read in it.
library;

import 'dart:convert';
import 'dart:io';

import '../../story_catalog.dart' show endfieldCollectionTypePrefix;
import '../../story_vectors.dart' show sectionLineKind;
import 'endfield_dialog_tree.dart';
import 'endfield_importer.dart';
import 'endfield_tables.dart';
import 'endfield_writer.dart';

/// The mission a conversation id belongs to: the id without its kind
/// prefix (`dlg_`, `radio_`, `sns_`) and its trailing conversation number
/// (`dlg_a1m2_1` → `a1m2`).
String missionOfConversation(String id) {
  final bare = id.replaceFirst(RegExp(r'^(dlg|radio|sns|remotecomm|envTalk)_'), '');
  final cut = bare.lastIndexOf('_');
  return cut > 0 ? bare.substring(0, cut) : bare;
}

/// The kind of a conversation as its section line names it, from the id
/// prefix (the table it comes from): dialogue, radio, a remote call, talk
/// around the player, messages.
String conversationKind(String id) => switch (RegExp(r'^[a-zA-Z]+').firstMatch(id)?.group(0)) {
      'radio' => '通讯',
      'remotecomm' => '远程通话',
      'envTalk' => '闲话',
      'sns' => '短信',
      _ => '对话',
    };

/// The place of a conversation among those of its kind in a mission: its
/// number (`0d5` is half way between 0 and 1: `d` marks a decimal point in
/// the game's ids). Null when the id has no number.
///
/// Each table numbers its conversations on its own (radio 3 is not between
/// dialogue 2 and 3), and the client says in what order the kinds play only
/// for some of them (the level scripts that start them, the cutscene
/// timelines); so a mission reads kind by kind ([conversationKindRank]),
/// each kind in its own numbering.
int? conversationOrder(String id) {
  final m = RegExp(r'_(\d+)(?:d(\d+))?$').firstMatch(id);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final part = m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0').substring(0, 2));
  return whole * 100 + part;
}

/// The kinds of a mission in reading order: the dialogue that carries the
/// story, then what is said over the radio and in remote calls on the way,
/// then talk around the player, then messages.
int conversationKindRank(String id) => switch (RegExp(r'^[a-zA-Z]+').firstMatch(id)?.group(0)) {
      'dlg' => 0,
      'radio' => 1,
      'remotecomm' => 2,
      'envTalk' => 3,
      'sns' => 4,
      _ => 5,
    };

/// A mission's place on its shelf: the numbers of its id in order, each
/// given three digits (`e1m2d5` → 001 002 005), so `e1m2` comes before
/// `e10m1`. Null when the id has no number.
int? missionOrder(String id) {
  final numbers = [
    for (final m in RegExp(r'\d+').allMatches(id)) int.parse(m.group(0)!).clamp(0, 999),
  ];
  if (numbers.isEmpty) return null;
  var key = 0;
  for (var i = 0; i < 3; i++) {
    key = key * 1000 + (i < numbers.length ? numbers[i] : 0);
  }
  return key;
}

/// The operator entry a character mission belongs to: `c<n>m…` is the
/// story of the operator numbered `n` (`chr_00<n>_…`), when there is one.
String? operatorOfMission(String mission, Map<String, String> operators) {
  final n = RegExp(r'^c(\d+)m').firstMatch(mission)?.group(1);
  if (n == null) return null;
  final prefix = 'chr_${n.padLeft(4, '0')}_';
  for (final MapEntry(:key, :value) in operators.entries) {
    if (key.startsWith(prefix)) return value;
  }
  return null;
}

/// The shelf of a mission without a definition, from its id's letter prefix
/// (`e<n>m<n>` main story, `c…` an operator's story, the rest side stories).
String shelfOfMission(String mission) {
  final letters = RegExp(r'^[a-z]+').firstMatch(mission)?.group(0) ?? '';
  return switch (letters) {
    'e' => 'main',
    'c' => 'memory',
    _ => 'side',
  };
}

/// One mission as the game defines it (`MissionRuntimeAsset/<id>.json`).
typedef EndfieldMission = ({
  String name,
  String? description,
  int type,
  String? charId,
  int sortId,
  String? levelId,
});

/// One chapter of the game's mission panel (`Beyond.Gameplay.ChapterInfo`,
/// listed by the `ChapterTable` asset): the main story's chapters and
/// processes (`main_e<n>`) and each operator's chapters (`chr_…_e<n>`), with
/// the text keys of their headings and their missions in order.
typedef EndfieldChapter = ({
  String id,
  int type,
  List<String> headingKeys,
  List<String> missions,
});

/// One conversation waiting to be placed in its mission's story.
typedef _Part = ({
  String id,
  int order,
  String kind,
  List<EndfieldLine> lines,
  String source,
  String? summary,
});

/// The mission tabs of the game's mission panel (`GEnums.MissionViewType`,
/// in declaration order), as shelf kinds. A mission's tab is
/// `MissionTypeInfoTable[missionType].missionViewType`.
const List<String> missionViewShelves = [
  'main',
  'discovery',
  'side',
  'activity',
  'other',
];

class EndfieldStoryImporter {
  EndfieldStoryImporter(
    this.tables,
    this.writer,
    this.importer, {
    this.log,
    this.missions = const {},
    this.dialogTrees = const {},
    this.timelineLines = const {},
    this.chapters = const [],
  }) {
    // Each chapter's missions: under the chapter's heading, in its order.
    for (final (c, chapter) in chapters.indexed) {
      final heading = [
        for (final key in chapter.headingKeys)
          if (_keyText(key) case final text?) text,
      ].join(' · ');
      for (final (i, mission) in chapter.missions.indexed) {
        _chapterOf.putIfAbsent(
          mission,
          () => (heading: heading.isEmpty ? null : heading, order: (c + 1) * 1000 + i),
        );
      }
    }
  }

  /// The game's chapters, main story first ([loadChapters]).
  final List<EndfieldChapter> chapters;

  /// The heading and place of each mission listed in a chapter.
  final Map<String, ({String? heading, int order})> _chapterOf = {};

  /// Reads the chapters from an AnimeStudio MonoBehaviour export (JSON) of
  /// the `main_e<n>` and `chr_…_e<n>` objects; later directories replace
  /// earlier ones (list the hot-update layer last). The main story comes
  /// first, then the operators' chapters, each in its number order.
  static List<EndfieldChapter> loadChapters(Iterable<Directory> dirs) {
    final byId = <String, EndfieldChapter>{};
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final Object? json;
        try {
          json = jsonDecode(file.readAsStringSync());
        } catch (_) {
          continue;
        }
        if (json is! Map<String, dynamic>) continue;
        final id = '${json['m_Name'] ?? ''}';
        final missions = listOfStrings(json['missionIdList']);
        if (id.isEmpty || missions.isEmpty) continue;
        String key(Object? field) => field is Map ? '${field['key'] ?? ''}' : '';
        byId[id] = (
          id: id,
          type: (json['type'] as num?)?.toInt() ?? 0,
          headingKeys: [
            for (final f in [json['chapterNum'], json['episodeNum'], json['episodeName']])
              // An operator's chapter is headed by its number and name; the
              // series title (`狼卫纪事`) is the operator's page itself.
              if (key(f).isNotEmpty && !key(f).endsWith('_title')) key(f),
          ],
          missions: missions,
        );
      }
    }
    return byId.values.toList()
      ..sort((a, b) {
        if (a.type != b.type) return a.type.compareTo(b.type);
        return _naturalCompare(a.id, b.id);
      });
  }

  final EndfieldTables tables;
  final EndfieldWriter writer;
  final EndfieldImporter importer;
  final void Function(String message)? log;

  /// The game's mission definitions by id (empty: the id rules decide).
  final Map<String, EndfieldMission> missions;

  /// The conversations' dialog trees by conversation id (empty: the lines
  /// keep the table's numbering).
  final Map<String, Map<String, dynamic>> dialogTrees;

  /// The lines cutscene timelines show, by conversation id, in the order
  /// they start ([loadTimelineLines]).
  final Map<String, List<TimelineLine>> timelineLines;

  /// Reads the dialog trees from an AnimeStudio TextAsset export: files
  /// `<conversation>_p<path id>.txt` (or `<conversation>.json`), the
  /// `_extra_config` ones left out. Later files of the same conversation
  /// replace earlier ones (list the hot-update layer last).
  static Map<String, Map<String, dynamic>> loadDialogTrees(Iterable<Directory> dirs) {
    final out = <String, Map<String, dynamic>>{};
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      final files = dir.listSync(recursive: true).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final m = RegExp(r'^(dlg_.+?)(?:_p[0-9A-Fa-f]{16})?(?: \(\d+\))?\.(?:txt|json)$').firstMatch(name);
        if (m == null || m.group(1)!.endsWith('_extra_config')) continue;
        final Object? json;
        try {
          json = jsonDecode(file.readAsStringSync());
        } catch (_) {
          continue;
        }
        if (json is Map<String, dynamic> && json['type'] == 'Beyond.Gameplay.DialogTree') {
          out[m.group(1)!] = json;
        }
      }
    }
    return out;
  }

  /// Reads the mission definitions from a JsonData dump's
  /// `MissionRuntimeAsset` folder; names and descriptions are text keys of
  /// `TextTable`.
  static Map<String, EndfieldMission> loadMissions(
    Directory dir,
    EndfieldTables tables,
  ) {
    final out = <String, EndfieldMission>{};
    if (!dir.existsSync()) return out;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.json') || file.path.endsWith('_meta.json')) {
        continue;
      }
      final Object? json;
      try {
        json = jsonDecode(file.readAsStringSync());
      } catch (_) {
        continue;
      }
      if (json is! Map<String, dynamic>) continue;
      final id = '${json['missionId'] ?? ''}';
      if (id.isEmpty) continue;
      String keyText(Object? field) => field is Map && field['key'] != null
          ? endfieldText(tables.text(tables.table('TextTable')['${field['key']}']))
          : '';
      final description = keyText(json['missionDescription']);
      final charId = '${json['charId'] ?? ''}';
      final levelId = '${json['levelId'] ?? ''}';
      out[id] = (
        name: keyText(json['missionName']),
        description: description.isEmpty ? null : description,
        type: (json['missionType'] as num?)?.toInt() ?? -1,
        charId: charId.isEmpty ? null : charId,
        sortId: (json['sortId'] as num?)?.toInt() ?? 0,
        levelId: levelId.isEmpty ? null : levelId,
      );
    }
    return out;
  }

  /// The shelf of a defined mission: its operator's (`memory`) when it is
  /// an operator's story, else the game's mission tab.
  String _shelfOf(String id, EndfieldMission m) {
    if (m.charId != null) return 'memory';
    final info = tables.table('MissionTypeInfoTable')['${m.type}'];
    final view = info is Map ? (info['missionViewType'] as num?)?.toInt() : null;
    return view != null && view >= 0 && view < missionViewShelves.length
        ? missionViewShelves[view]
        : shelfOfMission(id);
  }

  final Map<String, ({String name, String kind, int sort})> _missions = {};

  String _clean(Object? field) => endfieldText(tables.text(field));

  /// Text the game keeps by key (`<mission>_name`, `<mission>_desc_001`):
  /// the name and description of a mission whose definition the client
  /// does not ship any more, or ships without them.
  String? _keyText(String key) {
    final text = endfieldText(tables.textOfKey(key));
    return text.isEmpty ? null : text;
  }

  /// Whether the mission panel lists missions of [type]
  /// (`MissionTypeInfoTable.isVisible`).
  bool _visible(int type) {
    final info = tables.table('MissionTypeInfoTable')['$type'];
    return info is! Map || info['isVisible'] != false;
  }

  /// A mission's name: its definition's, else the one the text table keeps.
  String? _nameOf(String id) {
    final defined = missions[id]?.name ?? '';
    return defined.isNotEmpty ? defined : _keyText('${id}_name');
  }

  /// The mission whose story a mission's conversations are part of. A
  /// sub-mission (`<base>d<n>`) is read in its base mission when it is a
  /// step of it: it has its base's name, or no name, or no definition at all
  /// while its base has one. A step with a name of its own (a hidden
  /// `准备工作`) is a mission of its own, on its base's shelf.
  String canonicalMission(String id) {
    final m = _subMission.firstMatch(id);
    if (m == null) return id;
    final base = m.group(1)!;
    if (!missions.containsKey(base)) return id;
    final defined = missions[id];
    if (defined == null || defined.name.isEmpty || defined.name == _nameOf(base)) {
      return canonicalMission(base);
    }
    return id;
  }

  static final RegExp _subMission = RegExp(r'^(.+?\d)d\d+$');

  /// The shelf of a mission. A defined mission the mission panel shows is
  /// on its tab (an operator's own on the operator shelf); a hidden one on
  /// its base mission's shelf, else by its id's letters. A mission without a
  /// definition is not in the game the client runs (its conversations are
  /// left in the tables: an older version of a story, a cut mission; the
  /// wikis have no page for any of them): it is on [unusedMissionShelf].
  String _shelfFor(String id) {
    final defined = missions[id];
    if (defined == null) return unusedMissionShelf;
    if (_visible(defined.type)) {
      // An operator's mission the panel lists as main story stays there
      // (it is still on its operator's page); the others are the
      // operator's own.
      final tab = _shelfOf(
        id,
        (
          name: defined.name,
          description: defined.description,
          type: defined.type,
          charId: null,
          sortId: defined.sortId,
          levelId: defined.levelId,
        ),
      );
      return defined.charId != null && tab != 'main' ? 'memory' : tab;
    }
    final base = _subMission.firstMatch(id)?.group(1);
    if (base != null && missions.containsKey(base)) return _shelfFor(base);
    final byId = shelfOfMission(id);
    return byId == 'memory' && operatorOfMission(id, importer.operators) == null ? 'side' : byId;
  }

  /// The defined sub-missions of [id] (`<id>d<n>`), in number order.
  List<String> _subMissions(String id) => [
        for (final key in missions.keys)
          if (RegExp('^${RegExp.escape(id)}d\\d+\$').hasMatch(key)) key,
      ]..sort(_naturalCompare);

  /// The name the sub-missions of [id] share (`据点建设·难民暂居处·其一`,
  /// `…·其二` → `据点建设·难民暂居处`): their common beginning up to a
  /// separator. Null when they share none.
  String? _sharedName(String id) {
    final names = [
      for (final s in _subMissions(id))
        if (missions[s]!.name.isNotEmpty) missions[s]!.name,
    ];
    if (names.isEmpty) return null;
    if (names.length == 1) return names.first;
    var common = names.first;
    for (final n in names.skip(1)) {
      var i = 0;
      while (i < common.length && i < n.length && common[i] == n[i]) {
        i++;
      }
      common = common.substring(0, i);
    }
    // Cut back to a whole part: up to the last separator, or a numeral
    // that tells the parts apart (`像差探索计划Ⅰ`, `…Ⅱ`).
    final whole = names.every((n) => n == common);
    if (!whole) {
      final cut = common.lastIndexOf('·');
      if (cut > 0) {
        common = common.substring(0, cut);
      } else {
        common = common.replaceFirst(RegExp(r'[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ0-9一二三四五六七八九十其]+$'), '');
      }
    }
    common = common.replaceFirst(RegExp(r'[·\s]+$'), '');
    return common.runes.length >= 2 ? common : null;
  }

  /// The id of the operator an operator mission belongs to (`chr_0006_…`).
  String? _charIdOf(String? ownerEntry) {
    if (ownerEntry == null) return null;
    for (final MapEntry(:key, :value) in importer.operators.entries) {
      if (value == ownerEntry) return key;
    }
    return null;
  }

  /// The heading of an operator's mission series as the game writes it:
  /// its chapter number and name (`chr_ep_num1` · `chr_0006_ep1_name`:
  /// 篇章Ⅰ · 离群之狼).
  String? _seriesOf(String? charId) {
    final n = charId == null ? null : RegExp(r'^chr_\d+').firstMatch(charId)?.group(0);
    final name = n == null ? null : _keyText('${n}_ep1_name');
    if (name == null) return null;
    final number = _keyText('chr_ep_num1');
    return number == null ? name : '$number · $name';
  }

  /// The official one-paragraph summary of a conversation, if any.
  String? _summary(String conversation) {
    final key = tables.table('DialogSummaryMapTable')[conversation];
    if (key == null) return null;
    final text = _clean(tables.table('DialogSummaryTable')['$key']);
    return text.isEmpty ? null : text;
  }

  /// The conversations of each mission (or place, enemy, topic) so far, in
  /// the order they were read; [_writeStories] writes them as one story.
  final Map<String, List<_Part>> _parts = {};

  /// Stories written into another key's collection (a place's Baker topics
  /// into the place's): story key → host key.
  final Map<String, String> _hostOf = {};

  Future<void> _ensureMission(
    String id, {
    String? name,
    String? kind,
    String? owner,
  }) async {
    if (_missions.containsKey(id)) return;
    final defined = missions[id];
    final shelf = kind ?? _shelfFor(id);
    // An operator's mission hangs below it; a mission the game does not
    // have (see [_shelfFor]) belongs to nobody.
    if (shelf == unusedMissionShelf) {
      owner = null;
    } else {
      owner ??=
          defined?.charId != null ? importer.operators[defined!.charId] : operatorOfMission(id, importer.operators);
    }
    final title = name ?? _nameOf(id) ?? _sharedName(id);
    // A mission the game names nowhere (no definition, no name text, no
    // named sub-mission) is said to be one, with its id: no name is made up,
    // and the label stays the same from build to build.
    final entry = (name: title ?? '无名任务（$id）', kind: shelf, sort: _missions.length);
    if (title == null) log?.call('mission without a name: $id ($shelf)');
    _missions[id] = entry;
    await writer.collection(
      id: 'mission_$id',
      kind: shelf,
      name: entry.name,
      // A character mission hangs below its operator (the operator page
      // lists it, like an Arknights record set).
      parentId: owner,
      // Missions read in their chapter's order (the game's), the others in
      // the order of their ids' numbers (e1m2 before e10m1).
      sortKey: _chapterOf[id]?.order ?? missionOrder(id) ?? entry.sort,
      sourcePath: 'mission:$id',
    );
    // The mission's own description, and where it is listed: a mission of a
    // chapter under the chapter's heading (第一章 · 进程Ⅰ · 碎裂大地;
    // 篇章Ⅰ · 离群之狼), any other operator mission under its series' name,
    // the rest under the region it is played in (the game's region of its
    // level). The shelf lists a mission with both.
    if (kind != null) return;
    final description = defined?.description ?? _keyText('${id}_desc_001');
    final level = defined?.levelId;
    final group = _chapterOf[id]?.heading ??
        (owner != null
            ? _seriesOf(defined?.charId ?? _charIdOf(owner))
            : level == null
                ? importer.regionOfIds([id])
                : importer.regionOf(level));
    if (description == null && group == null) return;
    await writer.entry(
      type: 'mission_intro',
      rawId: 'mission_$id',
      name: entry.name,
      collectionId: 'mission_$id',
      group: group,
      sourcePath: defined != null ? 'MissionRuntimeAsset/$id.json' : 'TextTable/${id}_desc_001',
      category: 'story',
      texts: [
        if (description != null) (section: '任务简介', text: description),
      ],
    );
  }

  /// A speaker as players see it: the game appends an internal note in
  /// braces (`工作人员{c13-…}`, a hidden identity) that is not shown.
  String _speaker(Object? field) => _clean(field).replaceAll(RegExp(r'\{[^{}]*\}'), '').trim();

  /// Where a conversation goes: a mission, an operator's topic, a level's
  /// interactions, an enemy's encounter; null for filler the game plays
  /// between lines, factory tutorials and tests (not story).
  Future<String?> _home(String id) async {
    final bare = id.replaceFirst(RegExp(r'^(dlg|radio|sns|remotecomm|envTalk)_'), '');
    if (RegExp(r'^(continue|blackbox|timeline_blackbox|sr|test)').hasMatch(bare)) {
      return null;
    }
    // A topic of an operator's messages (SNSDialogTopicTable).
    final topic = _topicOf(id);
    if (topic != null) {
      // A place's topic (`topic_map01_lv001_1`: a contact or group chat of
      // that place) is read with the place, a story of its own there.
      final place = topic.owner != null
          ? null
          : RegExp(r'^topic_((?:map|indie|base)\w*?_(?:lv|dg)\d+)_').firstMatch(topic.key)?.group(1);
      final host = place == null ? null : await _levelHome(place);
      if (host != null) {
        _hostOf[topic.key] = host;
        _missions.putIfAbsent(topic.key, () => (name: topic.name, kind: 'world', sort: _missions.length));
        return topic.key;
      }
      // An operator's topic is on its page (Baker); a topic of nobody's is
      // a story of its own on the side shelf.
      await _ensureMission(
        topic.key,
        name: topic.name,
        kind: topic.owner == null ? 'side' : bakerTopicKind,
        owner: topic.owner,
      );
      return topic.key;
    }
    // What an operator says on the Dijiang when the player talks to it,
    // gives it a gift, sends it to rest or to work (`sim_<what>_<operator>`):
    // one story per operator, on its page.
    final ship = RegExp(r'^sim_(?:talk|gift|rest|work)_([a-z]+)').firstMatch(bare)?.group(1);
    if (ship != null) {
      final owner = _operatorBySuffix(ship);
      if (owner == null) return null;
      final key = 'ship_$ship';
      await _ensureMission(
        key,
        name: _ui('guide_text_spaceship_interaction_title_1', '与干员互动'),
        kind: shipInteractionKind,
        owner: owner,
      );
      return key;
    }
    final levelMatch = RegExp(r'^((?:map|indie|base)\w*?_(?:lv|dg)\d+|map\d+(?:lv|dg)\d+)').firstMatch(bare)?.group(1);
    // `map01lv005_…` names the level `map01_lv005`.
    final level = levelMatch == null || levelMatch.contains('_')
        ? levelMatch
        : levelMatch.replaceFirstMapped(RegExp(r'(lv|dg)'), (m) => '_${m[1]}');
    if (level != null) return _levelHome(level);
    final enemy = RegExp(r'^(eny_\d+)').firstMatch(bare)?.group(1);
    if (enemy != null) {
      final name = _enemyName(enemy);
      if (name == null) return null;
      await _ensureMission(enemy, name: name, kind: 'world');
      return enemy;
    }
    final mission = canonicalMission(missionOfConversation(id));
    // Ambient talk outside a known mission or place (a named passer-by's
    // lines) has no home worth a shelf.
    if (id.startsWith('envTalk_') && !missions.containsKey(mission) && !_missions.containsKey(mission)) {
      return null;
    }
    return _missionHome(mission);
  }

  /// The collection key of [mission] (made when first met). A hidden
  /// mission the game names nowhere, that is no step of another (the game
  /// plays it as something that happens at a place), is read with the
  /// interactions of its level.
  Future<String?> _missionHome(String mission) async {
    final defined = missions[mission];
    if (defined != null &&
        !_visible(defined.type) &&
        _nameOf(mission) == null &&
        defined.levelId != null &&
        _levelName(defined.levelId!) != null) {
      return _levelHome(defined.levelId!);
    }
    await _ensureMission(mission);
    return mission;
  }

  /// The collection of the interactions at [level] (a place on the map).
  Future<String?> _levelHome(String level) async {
    final place = _levelName(level);
    if (place == null) return null;
    final region = importer.regionOf(level);
    final name = region == null || region == place ? place : '$region·$place';
    await _ensureMission('level_$level', name: name, kind: 'world');
    return 'level_$level';
  }

  ({String key, String name, String? owner})? _topicOf(String id) {
    for (final MapEntry(:key, :value) in tables.table('SNSDialogTopicTable').entries) {
      if (value is! Map) continue;
      if (!listOfStrings(value['includeDialogIds']).contains(id)) continue;
      // The topic names its operator by number (`chr_0033_…`); the name part
      // after it is not always the character table's (`kamiu`, `camille`).
      final number = RegExp(r'chr_\d+').firstMatch(key)?.group(0);
      final char = number == null
          ? null
          : importer.operators.keys.where((k) => k.startsWith('${number}_')).firstOrNull;
      final name = endfieldText(tables.text(value['topicName']));
      return (
        key: key,
        name: name.isEmpty ? key : name,
        owner: char == null ? null : importer.operators[char],
      );
    }
    return null;
  }

  String? _operatorBySuffix(String suffix) {
    for (final MapEntry(:key, :value) in importer.operators.entries) {
      if (key.endsWith('_$suffix')) return value;
    }
    return null;
  }

  /// An interface string of the game by its key ([fallback] when absent).
  String _ui(String key, String fallback) => _keyText(key) ?? fallback;

  String? _levelName(String level) {
    final row = tables.table('LevelDescTable')[level];
    final name = row is Map ? endfieldText(tables.text(row['showName'])) : '';
    return name.isEmpty ? null : name;
  }

  String? _enemyName(String enemy) {
    for (final MapEntry(:key, :value) in tables.table('EnemyTemplateDisplayInfoTable').entries) {
      if (!key.startsWith('${enemy}_') || value is! Map) continue;
      final name = endfieldText(tables.text(value['name']));
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  Future<void> _story({
    required String id,
    required List<EndfieldLine> lines,
    required String source,
    String? name,
    int? sort,
  }) async {
    final mission = await _home(id);
    if (mission == null) return;
    if (!lines.any((l) => l.content.trim().isNotEmpty)) return;
    final ship = _shipPlace(id);
    _parts.putIfAbsent(mission, () => []).add(
      (
        id: id,
        // Within a mission the kinds share the game's numbering.
        order: ship?.order ?? conversationOrder(id) ?? sort ?? 0,
        kind: name ?? ship?.kind ?? conversationKind(id),
        lines: lines,
        source: source,
        summary: _summary(id),
      ),
    );
  }

  /// The place of a Dijiang conversation in its operator's story: the talks
  /// by the trust level they open at (`lv01` … `max`), then the gift (given,
  /// taken, thanks, goodbye), then rest and work; gifts under the game's name
  /// for giving one. Null for other conversations.
  ({int order, String kind})? _shipPlace(String id) {
    final m = RegExp(r'^sim_(talk|gift|rest|work)_[a-z]+(?:_(\w+))?$').firstMatch(id);
    if (m == null) return null;
    final part = m.group(2) ?? '';
    return switch (m.group(1)) {
      'talk' => (
          order: part.startsWith('lv') ? int.tryParse(part.substring(2)) ?? 40 : 50,
          kind: '对话',
        ),
      'gift' => (
          order: 100 + const ['give', 'recv', 'recvsuccess', 'recvbye', 'givebye'].indexOf(part).clamp(0, 9),
          kind: _ui('LUA_GIFT_SEND_TITLE', '赠送礼物'),
        ),
      'rest' => (order: 200, kind: '对话'),
      _ => (order: 201, kind: '对话'),
    };
  }

  /// Each mission's conversations as one story, kind by kind, each kind in
  /// the game's numbering (ties by id; see [conversationOrder]): a `section`
  /// line naming the kind before each conversation. The catalog synopsis is
  /// the official summaries of its conversations, in the same order (a
  /// locating hint, not evidence).
  Future<void> _writeStories() async {
    var count = 0;
    for (final MapEntry(key: mission, value: parts) in _parts.entries) {
      final m = _missions[mission]!;
      parts.sort((a, b) {
        final byKind = conversationKindRank(a.id).compareTo(conversationKindRank(b.id));
        if (byKind != 0) return byKind;
        return a.order != b.order ? a.order.compareTo(b.order) : _naturalCompare(a.id, b.id);
      });
      final summaries = [
        for (final p in parts)
          if (p.summary != null) p.summary!,
      ];
      // A story kept in another's collection (a place's Baker topic) comes
      // after that collection's own story.
      final host = _hostOf[mission];
      final written = await writer.story(
        rawId: mission,
        name: m.name,
        lines: [
          for (final p in parts) ...[
            EndfieldLine(p.kind, kind: sectionLineKind),
            ...p.lines,
          ],
        ],
        collectionId: 'mission_${host ?? mission}',
        collectionName: host == null ? m.name : _missions[host]!.name,
        collectionType: '$endfieldCollectionTypePrefix${m.kind.toUpperCase()}',
        synopsis: summaries.isEmpty ? null : summaries.join('\n'),
        sortKey: host == null ? 0 : 1 + m.sort,
        sourcePath: {for (final p in parts) p.source}.join(';'),
      );
      if (written != null) count++;
    }
    _parts.clear();
    log?.call('stories (one per mission, place, enemy, topic): $count');
  }

  /// Conversations from the dialog tables, ordered by row id.
  Future<void> importDialogTables() async {
    var count = 0;
    final dialog = tables.table('DialogTextTable');
    final byConversation = <String, List<(int, Map<String, dynamic>)>>{};
    for (final MapEntry(:key, :value) in dialog.entries) {
      if (value is! Map<String, dynamic>) continue;
      final m = RegExp(r'^(.*)_(\d+)$').firstMatch(key);
      if (m == null) continue;
      byConversation.putIfAbsent(m.group(1)!, () => []).add((int.parse(m.group(2)!), value));
    }
    // Player choices: `option_<conversation>_<group>_<n>`.
    final choices = <String, Map<int, List<String>>>{};
    final optionGroup = <String, int>{};
    final optionText = <String, String>{};
    for (final MapEntry(:key, :value) in tables.table('DialogOptionTable').entries) {
      final m = RegExp(r'^option_(.+)_(\d+)_(\d+)$').firstMatch(key);
      if (m == null || value is! Map) continue;
      final text = _clean(value['optionText']);
      if (text.isEmpty) continue;
      optionText[key] = text;
      optionGroup[key] = int.parse(m.group(2)!);
      choices.putIfAbsent(m.group(1)!, () => {}).putIfAbsent(int.parse(m.group(2)!), () => []).add(text);
    }
    final ids = byConversation.keys.toList()..sort(_naturalCompare);
    final source = tables.sourcePath('DialogTextTable');
    var byTree = 0, placedRows = 0, allRows = 0;
    for (final (i, id) in ids.indexed) {
      final rows = byConversation[id]!..sort((a, b) => a.$1.compareTo(b.$1));
      EndfieldLine lineOf(Map<String, dynamic> r) => EndfieldLine(
            _clean(r['dialogText']),
            speaker: _speaker(r['actorName']),
            kind: _speaker(r['actorName']).isEmpty ? 'narration' : 'dialogue',
          );
      // The order the game plays: the conversation's dialog tree, and the
      // start times of the lines its cutscene timelines show.
      final steps = dialogTrees[id] == null ? const <DialogStep>[] : readDialogTree(dialogTrees[id]!);
      final timeline = timelineLines[id] ?? const <TimelineLine>[];
      final ordered = <EndfieldLine>[];
      final usedRows = <int>{};
      final usedGroups = <int>{};
      void addChoice(List<String> options) {
        final texts = [
          for (final o in options)
            if (optionText[o] != null) optionText[o]!,
        ];
        if (texts.isEmpty) return;
        ordered.add(EndfieldLine(texts.join('／'), kind: 'choice'));
        for (final o in options) {
          if (optionGroup[o] != null) usedGroups.add(optionGroup[o]!);
        }
      }

      void addRow(String rowId) {
        final n = int.tryParse(rowId.substring(rowId.lastIndexOf('_') + 1));
        final row = n == null || !rowId.startsWith('${id}_') ? null : rows.where((r) => r.$1 == n).firstOrNull;
        if (row == null || !usedRows.add(n!)) return;
        ordered.add(lineOf(row.$2));
      }

      var timelinePlayed = false;
      void playTimeline() {
        if (timelinePlayed) return;
        timelinePlayed = true;
        for (final l in timeline) {
          addRow(l.rowId);
          if (l.options.isNotEmpty) addChoice(l.options);
        }
      }

      if (steps.isNotEmpty || timeline.isNotEmpty) byTree++;
      for (final step in steps) {
        if (step.isCutscene) {
          // Every cutscene line goes where the first cutscene plays (the
          // clips do not say which of several timelines they are in).
          playTimeline();
        } else if (step.isChoice) {
          addChoice(step.options);
        } else {
          addRow(step.rowId!);
        }
      }
      playTimeline();
      // Lines and choices the tree does not reach (a conversation played by
      // a cutscene timeline has no tree of lines) keep the table's numbering:
      // a choice group fills the line number its lines skip.
      final groups = choices[id] ?? const <int, List<String>>{};
      final rest = <(int, int, EndfieldLine)>[
        for (final (n, r) in rows)
          if (!usedRows.contains(n)) (n, 0, lineOf(r)),
        for (final MapEntry(key: n, value: texts) in groups.entries)
          if (!usedGroups.contains(n)) (n, 1, EndfieldLine(texts.join('／'), kind: 'choice')),
      ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      placedRows += usedRows.length;
      allRows += rows.length;
      await _story(
        id: id,
        source: source,
        sort: i,
        lines: [...ordered, for (final p in rest) p.$3],
      );
      count++;
    }
    log?.call('dialogs: $count ($byTree with a tree or timeline; lines placed by them '
        '$placedRows of $allRows, the rest by number)');
    count = 0;
    final radio = tables.table('RadioTable');
    final radioSource = tables.sourcePath('RadioTable');
    final radioIds = radio.keys.toList()..sort(_naturalCompare);
    for (final (i, id) in radioIds.indexed) {
      final row = radio[id];
      if (row is! Map<String, dynamic>) continue;
      final lines = listOfMaps(row['radioSingleDataList'])
        ..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
      await _story(
        id: id,
        source: radioSource,
        sort: 100000 + i,
        lines: [
          for (final l in lines) EndfieldLine(_clean(l['radioText']), speaker: _speaker(l['actorName'])),
        ],
      );
      count++;
    }
    log?.call('radio: $count');
    await _importRemoteCalls();
    await _importEnvTalk();
    await _importSns();
    await _writeStories();
    await _importReadings();
    await _numberRepeatedNames();
  }

  /// Missions of one shelf that share a name (the game reuses a name for
  /// the steps of a daily commission, for two preparations) are told apart
  /// as the wiki does: `准备工作·一阶段`, `准备工作·二阶段`, in game order.
  Future<void> _numberRepeatedNames() async {
    final db = writer.db;
    final rows = await db.rawQuery(
      "SELECT id, kind, name FROM collections WHERE id LIKE 'ef/mission_%' "
      "AND kind NOT IN ('ef/world', 'ef/$bakerTopicKind', 'ef/$shipInteractionKind') "
      "AND EXISTS (SELECT 1 FROM entries e WHERE e.collection_id = collections.id AND e.type <> 'mission_intro') "
      'ORDER BY kind, name, sort_key, id',
    );
    final groups = <String, List<String>>{};
    for (final r in rows) {
      (groups['${r['kind']}\u0000${r['name']}'] ??= []).add('${r['id']}');
    }
    var renamed = 0;
    for (final MapEntry(key: key, value: ids) in groups.entries) {
      if (ids.length < 2) continue;
      final name = key.split('\u0000').last;
      for (final (i, id) in ids.indexed) {
        final numbered = '$name·${chineseNumber(i + 1)}阶段';
        await db.update('collections', {'name': numbered}, where: 'id = ?', whereArgs: [id]);
        await db.update(
          'entries',
          {'name': numbered},
          where: "collection_id = ? AND type IN ('story', 'mission_intro')",
          whereArgs: [id],
        );
        await db.update(
          'story_catalog',
          {'collection_name': numbered, 'story_name': numbered},
          where: 'collection_id = ?',
          whereArgs: [id],
        );
        renamed++;
      }
    }
    log?.call('missions told apart by stage: $renamed');
  }

  /// Remote calls during missions (`RemoteCommonTable`).
  Future<void> _importRemoteCalls() async {
    final table = tables.table('RemoteCommonTable');
    final source = tables.sourcePath('RemoteCommonTable');
    var count = 0;
    final ids = table.keys.toList()..sort(_naturalCompare);
    for (final (i, id) in ids.indexed) {
      final row = table[id];
      if (row is! Map<String, dynamic>) continue;
      final lines = listOfMaps(row['remoteCommSingleDataList'])
        ..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
      await _story(
        id: id,
        source: source,
        sort: 150000 + i,
        lines: [
          for (final l in lines) EndfieldLine(_clean(l['remoteCommText']), speaker: _speaker(l['actorName'])),
        ],
      );
      count++;
    }
    log?.call('remote calls: $count');
  }

  /// What characters say around the player in a mission or a place
  /// (`EnvTalkTable`); speakers by their character or NPC id.
  Future<void> _importEnvTalk() async {
    final table = tables.table('EnvTalkTable');
    final source = tables.sourcePath('EnvTalkTable');
    final names = <String, String>{
      for (final MapEntry(:key, :value) in tables.table('CharacterTable').entries)
        if (value is Map) key: _clean(value['name']),
      for (final value in tables.table('NpcTable').values)
        if (value is Map) '${value['npcId']}': _clean(value['name']),
    };
    var count = 0;
    final ids = table.keys.where((k) => k.startsWith('envTalk_')).toList()..sort(_naturalCompare);
    for (final (i, id) in ids.indexed) {
      final row = table[id];
      if (row is! Map<String, dynamic>) continue;
      final lines = listOfMaps(row['envTalkDataList'])
        ..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
      await _story(
        id: id,
        source: source,
        sort: 300000 + i,
        lines: [
          for (final l in lines)
            EndfieldLine(
              _clean(l['text']),
              speaker: (names['${l['actorId'] ?? ''}'] ?? '').isEmpty ? null : names['${l['actorId']}'],
            ),
        ],
      );
      count++;
    }
    log?.call('ambient talk: $count');
  }

  /// Texts the player reads in the world or in a mission (`RichContentTable`
  /// rows the archive does not list: notes, messages, signs). Each is a
  /// document in its mission (by id), at its level, or in the codex.
  Future<void> _importReadings() async {
    final rich = tables.table('RichContentTable');
    final inArchive = <String>{
      for (final page in tables.table('PrtsAllItem').values)
        if (page is Map) '${page['contentId']}',
      for (final reading in tables.table('PrtsReading').values)
        if (reading is Map)
          for (final item in listOfMaps(reading['list'])) '${item['contentId']}',
    };
    final popupTitle = <String, String>{
      for (final p in tables.table('ReadingPopUpTable').values)
        if (p is Map) '${p['contentId']}': endfieldText(tables.text(p['title'])),
    };
    final source = tables.sourcePath('RichContentTable');
    var count = 0;
    final ids = rich.keys.where((k) => !inArchive.contains(k)).toList()..sort(_naturalCompare);
    for (final id in ids) {
      final row = rich[id];
      if (row is! Map<String, dynamic>) continue;
      final text = [
        for (final c in listOfMaps(row['contentList'])) _clean(c['content']),
      ].where((t) => t.isNotEmpty).join('\n');
      if (text.isEmpty) continue;
      final title = _clean(row['title']).isNotEmpty ? _clean(row['title']) : (popupTitle[id] ?? '');
      if (title.isEmpty) continue;
      final bare = id.replaceFirst(RegExp(r'^text_'), '');
      final cut = bare.lastIndexOf('_');
      final mission = canonicalMission(cut > 0 ? bare.substring(0, cut) : bare);
      final level = RegExp(r'^(map\d+_lv\d+)').firstMatch(bare)?.group(1);
      String? collection;
      if (missions.containsKey(mission) || _missions.containsKey(mission)) {
        collection = 'mission_${await _missionHome(mission) ?? mission}';
      } else if (level != null && _levelName(level) != null) {
        // The same collection as the level's interactions (see [_home]).
        final key = 'level_$level';
        final place = _levelName(level)!;
        final region = importer.regionOf(level);
        await _ensureMission(
          key,
          name: region == null || region == place ? place : '$region·$place',
          kind: 'world',
        );
        collection = 'mission_$key';
      }
      await writer.entry(
        type: 'document',
        rawId: id,
        name: title,
        collectionId: collection,
        group: importer.regionOfIds([bare]),
        sourcePath: source,
        category: 'archive',
        texts: [(section: title, text: text)],
      );
      count++;
    }
    log?.call('readings: $count');
  }

  /// Messages (SNS): each thread in content order, options as choice lines.
  Future<void> _importSns() async {
    final sns = tables.table('SNSDialogTable');
    final chats = tables.table('SNSChatTable');
    final options = tables.table('SNSDialogOptionTable');
    final source = tables.sourcePath('SNSDialogTable');
    var count = 0;
    final ids = sns.keys.toList()..sort(_naturalCompare);
    for (final (i, id) in ids.indexed) {
      final row = sns[id];
      if (row is! Map<String, dynamic>) continue;
      final content = row['dialogContentData'];
      if (content is! Map) continue;
      final keys = content.keys.map((k) => int.tryParse('$k') ?? -1).where((k) => k > 0).toList()..sort();
      String who(String speaker) {
        if (speaker.isEmpty) return '';
        if (speaker.startsWith('endmin')) return '管理员';
        final chat = chats[speaker];
        return chat is Map ? _clean(chat['name']) : speaker;
      }

      final lines = <EndfieldLine>[];
      for (final k in keys) {
        final c = content['$k'];
        if (c is! Map) continue;
        final text = _clean(c['content']);
        if (text.isNotEmpty) {
          lines.add(EndfieldLine(text, speaker: who('${c['speaker'] ?? ''}')));
        }
        final choices = [
          for (final o in listOfStrings(c['dialogOptionIds']))
            _clean((options[o] as Map?)?['optionText'] ?? (options[o] as Map?)?['optionDesc']),
        ].where((t) => t.isNotEmpty).toList();
        if (choices.isNotEmpty) {
          lines.add(EndfieldLine(choices.join('／'), kind: 'choice'));
        }
      }
      final chat = chats['${row['chatId'] ?? ''}'];
      await _story(
        id: id,
        source: source,
        sort: 200000 + i,
        name: chat is Map && _clean(chat['name']).isNotEmpty ? '短信 · ${_clean(chat['name'])}' : null,
        lines: lines,
      );
      count++;
    }
    log?.call('sns: $count');
  }
}

/// [n] (1–99) in Chinese numerals: 一, 十, 十二, 二十一.
String chineseNumber(int n) {
  const digits = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (n < 10) return digits[n];
  final tens = n ~/ 10, ones = n % 10;
  return '${tens == 1 ? '' : digits[tens]}十${digits[ones]}';
}

/// Natural order of ids (`a1m2_10` after `a1m2_9`).
int _naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]), nb = int.tryParse(pb[i]);
    final c = na != null && nb != null ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
