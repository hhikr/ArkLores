/// 0.12: the Endfield conversations.
///
/// One story per conversation of the dialog tables (`DialogTextTable`,
/// `RadioTable`, `SNSDialogTable`), ordered by their row ids, grouped into a
/// collection per mission (named and shelved by the game's mission
/// definitions when given).
library;

import 'dart:convert';
import 'dart:io';

import '../../story_catalog.dart' show endfieldCollectionTypePrefix;
import 'endfield_importer.dart';
import 'endfield_tables.dart';
import 'endfield_writer.dart';

/// The mission a conversation id belongs to: the id without its kind
/// prefix (`dlg_`, `radio_`, `sns_`) and its trailing conversation number
/// (`dlg_a1m2_1` → `a1m2`).
String missionOfConversation(String id) {
  final bare = id.replaceFirst(RegExp(r'^(dlg|radio|sns)_'), '');
  final cut = bare.lastIndexOf('_');
  return cut > 0 ? bare.substring(0, cut) : bare;
}

/// A readable name of a conversation without a name of its own: its kind
/// (from the id prefix) and its number in the mission (`dlg_a1m2_3` →
/// `对话 3`). Nothing is invented beyond what the id says.
String conversationLabel(String id) {
  final kind = switch (RegExp(r'^[a-z]+').firstMatch(id)?.group(0)) {
    'dlg' => '对话',
    'radio' => '通讯',
    'sns' => '短信',
    _ => '对话',
  };
  final number = RegExp(r'_([0-9a-z]+)$').firstMatch(id)?.group(1);
  return number == null ? kind : '$kind $number';
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

/// The game's names of its mission tabs (`ui_mis_panel_tab_*`), for
/// numbering a mission without a name.
const Map<String, String> missionTabNames = {
  'main': '主线任务',
  'discovery': '探索任务',
  'side': '支线任务',
  'activity': '活动任务',
  'other': '委派任务',
  // The game lists an operator's missions under its side-mission tab.
  'memory': '支线任务',
};

class EndfieldStoryImporter {
  EndfieldStoryImporter(
    this.tables,
    this.writer,
    this.importer, {
    this.log,
    this.missions = const {},
  });

  final EndfieldTables tables;
  final EndfieldWriter writer;
  final EndfieldImporter importer;
  final void Function(String message)? log;

  /// The game's mission definitions by id (empty: the id rules decide).
  final Map<String, EndfieldMission> missions;

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
      out[id] = (
        name: keyText(json['missionName']),
        description: description.isEmpty ? null : description,
        type: (json['missionType'] as num?)?.toInt() ?? -1,
        charId: charId.isEmpty ? null : charId,
        sortId: (json['sortId'] as num?)?.toInt() ?? 0,
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

  /// The official one-paragraph summary of a conversation, if any.
  String? _summary(String conversation) {
    final key = tables.table('DialogSummaryMapTable')[conversation];
    if (key == null) return null;
    final text = _clean(tables.table('DialogSummaryTable')['$key']);
    return text.isEmpty ? null : text;
  }

  /// Missions without a name of their own, numbered per shelf (as Arknights'
  /// unnamed training stories are: `训练 3`).
  final Map<String, int> _unnamed = {};

  /// Conversations numbered so far per mission and kind.
  final Map<String, int> _ordinal = {};

  Future<void> _ensureMission(
    String id, {
    String? name,
    String? kind,
    String? owner,
  }) async {
    if (_missions.containsKey(id)) return;
    final defined = missions[id];
    final shelf = kind ?? (defined == null ? shelfOfMission(id) : _shelfOf(id, defined));
    owner ??= defined?.charId != null
        ? importer.operators[defined!.charId]
        : operatorOfMission(id, importer.operators);
    final title = defined == null || defined.name.isEmpty ? null : defined.name;
    String numbered() {
      final label = missionTabNames[shelf] ?? '任务';
      final n = _unnamed.update(label, (v) => v + 1, ifAbsent: () => 1);
      return '$label $n';
    }

    final entry = (name: name ?? title ?? numbered(), kind: shelf, sort: _missions.length);
    _missions[id] = entry;
    await writer.collection(
      id: 'mission_$id',
      kind: shelf,
      name: entry.name,
      // A character mission hangs below its operator (the operator page
      // lists it, like an Arknights record set).
      parentId: owner,
      sortKey: defined?.sortId ?? entry.sort,
      sourcePath: 'mission:$id',
    );
    final description = defined?.description;
    if (description != null) {
      await writer.entry(
        type: 'mission_intro',
        rawId: 'mission_$id',
        name: entry.name,
        collectionId: 'mission_$id',
        sourcePath: 'MissionRuntimeAsset/$id.json',
        category: 'story',
        texts: [(section: '任务简介', text: description)],
      );
    }
  }

  /// A speaker as players see it: the game appends an internal note in
  /// braces (`工作人员{c13-…}`, a hidden identity) that is not shown.
  String _speaker(Object? field) =>
      _clean(field).replaceAll(RegExp(r'\{[^{}]*\}'), '').trim();

  /// Where a conversation goes: a mission, an operator's topic, a level's
  /// interactions, an enemy's encounter; null for filler the game plays
  /// between lines, factory tutorials and tests (not story).
  Future<String?> _home(String id) async {
    final bare = id.replaceFirst(RegExp(r'^(dlg|radio|sns)_'), '');
    if (RegExp(r'^(continue|blackbox|timeline_blackbox|sr|test)').hasMatch(bare)) {
      return null;
    }
    // A topic of an operator's messages (SNSDialogTopicTable).
    final topic = _topicOf(id);
    if (topic != null) {
      await _ensureMission(
        topic.key,
        name: topic.name,
        kind: 'memory',
        owner: topic.owner,
      );
      return topic.key;
    }
    final gift = RegExp(r'^sim_gift_([a-z]+)').firstMatch(bare)?.group(1);
    if (gift != null) {
      final owner = _operatorBySuffix(gift);
      if (owner == null) return null;
      final key = 'gift_$gift';
      await _ensureMission(key, name: _itemTypeName(33) ?? key, kind: 'memory', owner: owner);
      return key;
    }
    final level = RegExp(r'^((?:map|indie|base)\w*?_(?:lv|dg)\d+)').firstMatch(bare)?.group(1);
    if (level != null) {
      final name = _levelName(level);
      if (name == null) return null;
      await _ensureMission('level_$level', name: name, kind: 'world');
      return 'level_$level';
    }
    final enemy = RegExp(r'^(eny_\d+)').firstMatch(bare)?.group(1);
    if (enemy != null) {
      final name = _enemyName(enemy);
      if (name == null) return null;
      await _ensureMission(enemy, name: name, kind: 'world');
      return enemy;
    }
    final mission = missionOfConversation(id);
    await _ensureMission(mission);
    return mission;
  }

  ({String key, String name, String? owner})? _topicOf(String id) {
    for (final MapEntry(:key, :value) in tables.table('SNSDialogTopicTable').entries) {
      if (value is! Map) continue;
      if (!listOfStrings(value['includeDialogIds']).contains(id)) continue;
      final char = RegExp(r'chr_\d+_[a-z]+').firstMatch(key)?.group(0);
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

  String? _itemTypeName(int type) {
    final row = tables.table('ItemTypeTable')['$type'];
    final name = row is Map ? endfieldText(tables.text(row['name'])) : '';
    return name.isEmpty ? null : name;
  }

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
    final m = _missions[mission]!;
    // Unnamed conversations are numbered in their mission, per kind
    // (`对话 3`, `通讯 2`), in the order of their ids.
    final kind = conversationLabel(id).split(' ').first;
    final n = _ordinal.update('$mission/$kind', (v) => v + 1, ifAbsent: () => 1);
    await writer.story(
      rawId: id,
      name: name ?? '$kind $n',
      lines: lines,
      collectionId: 'mission_$mission',
      collectionName: m.name,
      collectionType: '$endfieldCollectionTypePrefix${m.kind.toUpperCase()}',
      synopsis: _summary(id),
      sortKey: sort,
      sourcePath: source,
    );
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
      byConversation
          .putIfAbsent(m.group(1)!, () => [])
          .add((int.parse(m.group(2)!), value));
    }
    // Player choices: `option_<conversation>_<group>_<n>`; a group takes the
    // place of the line number it fills in the conversation (its lines skip
    // that number).
    final choices = <String, Map<int, List<String>>>{};
    for (final MapEntry(:key, :value) in tables.table('DialogOptionTable').entries) {
      final m = RegExp(r'^option_(.+)_(\d+)_(\d+)$').firstMatch(key);
      if (m == null || value is! Map) continue;
      final text = _clean(value['optionText']);
      if (text.isEmpty) continue;
      choices
          .putIfAbsent(m.group(1)!, () => {})
          .putIfAbsent(int.parse(m.group(2)!), () => [])
          .add(text);
    }
    final ids = byConversation.keys.toList()..sort(_naturalCompare);
    final source = tables.sourcePath('DialogTextTable');
    for (final (i, id) in ids.indexed) {
      final rows = byConversation[id]!..sort((a, b) => a.$1.compareTo(b.$1));
      final groups = choices[id] ?? const <int, List<String>>{};
      final placed = <(int, int, EndfieldLine)>[
        for (final (n, r) in rows)
          (
            n,
            0,
            EndfieldLine(
              _clean(r['dialogText']),
              speaker: _speaker(r['actorName']),
              kind: _speaker(r['actorName']).isEmpty ? 'narration' : 'dialogue',
            ),
          ),
        for (final MapEntry(key: n, value: texts) in groups.entries)
          (n, 1, EndfieldLine(texts.join('／'), kind: 'choice')),
      ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      await _story(
        id: id,
        source: source,
        sort: i,
        lines: [for (final p in placed) p.$3],
      );
      count++;
    }
    log?.call('dialogs: $count');
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
          for (final l in lines)
            EndfieldLine(_clean(l['radioText']), speaker: _speaker(l['actorName'])),
        ],
      );
      count++;
    }
    log?.call('radio: $count');
    await _importSns();
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
      final keys = content.keys.map((k) => int.tryParse('$k') ?? -1).where((k) => k > 0).toList()
        ..sort();
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
        name: chat is Map && _clean(chat['name']).isNotEmpty
            ? '短信 · ${_clean(chat['name'])}'
            : null,
        lines: lines,
      );
      count++;
    }
    log?.call('sns: $count');
  }
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
