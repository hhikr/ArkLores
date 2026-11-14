/// The Endfield level data as decoded JSON (AKEDatabase's `Json` set,
/// https://data.akedata.wiki): the same level scripts, mission sub-data and
/// entity groups [endfield_level_data.dart] reads from the client's binary
/// files, read from their fields instead of byte patterns. The output has
/// the same shape, so the story order does not know which it got
/// (docs/ENDFIELD_STORY_ORDER.md §2.3).
///
/// A script is `{actionMap: {dataMap: {headerList, actionList, getterList}},
/// triggerVolumes, interactives, npcs, enemies}`; each record has a `$type`
/// (`Beyond.Gameplay.Actions.<Name>`, headers `….ScriptEvent.<Name>` or
/// `….LevelEvent.<Name>`), an `_ID`, the ids it goes on to (`_nextID`,
/// `_onTrueID`/`_onFalseID`, `m_extraThreadIDList`, `_idList`, …) and its
/// parameters as `{constValue: …}` or a reference `{idRef: <getter>}`.
library;

import 'dart:convert';
import 'dart:io';

import 'endfield_level_data.dart';

/// The record type as the binary reader names it: headers keep their event
/// family (`ScriptEvent_OnScriptActive`), the rest the class name.
String levelRecordName(Object? type) {
  final parts = '${type ?? ''}'.split(',').first.split('.');
  final last = parts.last;
  final family = parts.length > 1 ? parts[parts.length - 2] : '';
  return family == 'ScriptEvent' || family == 'LevelEvent' ? '${family}_$last' : last;
}

class _Rec {
  _Rec(this.id, this.name, this.json, {required this.header, required this.getter});
  final int id;
  final String name;
  final Map<String, dynamic> json;
  final bool header;
  final bool getter;
  final List<int> next = [];
  int? cond, then, otherwise;
  final List<String> strings = [];
  final List<int> ids = [];

  /// The getters its parameters read (`{idRef: <getter>}`).
  final List<int> refs = [];

  /// Header: the action it starts.
  int? get entry => header ? next.firstOrNull : null;
}

// `key` names a property (`{key: "dlg_finish_id", value: …}`), not a value.
const _skipKeys = {r'$type', 'path', '_uid', 'paramSource', 'm_variableBind', 'key'};

void _leaves(Object? o, void Function(String key, Object value) f, [String key = '']) {
  if (o is Map) {
    for (final MapEntry(:key, :value) in o.entries) {
      if (_skipKeys.contains(key)) continue;
      _leaves(value, f, '$key');
    }
  } else if (o is List) {
    for (final v in o) {
      _leaves(v, f, key);
    }
  } else if (o != null) {
    f(key, o);
  }
}

List<int> _nextOf(Map<String, dynamic> r) {
  int? one(String k) => r[k] is num && (r[k] as num) > 0 ? (r[k] as num).toInt() : null;
  List<int> many(String k) => [for (final x in (r[k] as List? ?? const [])) if (x is num && x > 0) x.toInt()];
  return [
    ...[one('_onTrueID'), one('_onFalseID')].whereType<int>(),
    ...many('_caseIDList'),
    ...[one('_defaultID'), one('_doID')].whereType<int>(),
    ...many('_idList'),
    ...many('m_extraThreadIDList'),
    ...[one('_nextID'), one('m_nextID'), one('_onBreakID')].whereType<int>(),
  ];
}

Map<int, _Rec> _records(Map<String, dynamic> script) {
  final dm = ((script['actionMap'] as Map?)?['dataMap'] as Map?) ?? const {};
  final out = <int, _Rec>{};
  for (final (part, header, getter) in const [('headerList', true, false), ('actionList', false, false), ('getterList', false, true)]) {
    for (final r in (dm[part] as List? ?? const <Object?>[]).whereType<Map<String, dynamic>>()) {
      final id = (r['_ID'] as num?)?.toInt();
      if (id == null) continue;
      final rec = _Rec(id, levelRecordName(r[r'$type']), r, header: header, getter: getter);
      if (!getter) rec.next.addAll({..._nextOf(r)});
      if (rec.name == 'IfElseAction') {
        rec.cond = ((r['_condition'] as Map?)?['idRef'] as num?)?.toInt();
        rec.then = (r['_onTrueID'] as num?)?.toInt() ?? 0;
        rec.otherwise = (r['_onFalseID'] as num?)?.toInt() ?? 0;
      }
      _leaves(r, (key, v) {
        if (key == 'idRef' && v is num) {
          rec.refs.add(v.toInt());
          return;
        }
        if (v is String && v.isNotEmpty) rec.strings.add(v);
        if (v is num && v == v.roundToDouble() && v > 1000000000 && v < 100000000000) rec.ids.add(v.toInt());
      });
      out[id] = rec;
    }
  }
  return out;
}

List<_Rec> _chainFrom(Map<int, _Rec> recs, int root) {
  final seen = <int>{};
  final out = <_Rec>[];
  void visit(int a) {
    if (seen.contains(a) || !recs.containsKey(a)) return;
    seen.add(a);
    out.add(recs[a]!);
    for (final n in recs[a]!.next) {
      visit(n);
    }
  }

  visit(root);
  return out;
}

Vec3? _pos(Object? p) {
  final v = vecOf(p);
  return v == null ? null : ((v.$1 * 100).round() / 100, (v.$2 * 100).round() / 100, (v.$3 * 100).round() / 100);
}

/// The entities a script or level file places (`interactives`, `npcs`,
/// `enemies`, as maps by slot or as lists).
Iterable<Map<String, dynamic>> _entities(Map<String, dynamic> json) sync* {
  for (final part in const ['interactives', 'npcs', 'enemies']) {
    final v = json[part];
    final items = v is Map ? v.values : (v is List ? v : const <Object?>[]);
    yield* items.whereType<Map<String, dynamic>>();
  }
}

/// Reads one level script ([key] `<level>/<id>.json`); [segmentSwitches]
/// receives its `ShowSceneDecorationNew` switches.
LevelScript readLevelScriptJson(
  String key,
  Map<String, dynamic> json,
  LevelStrings ls,
  Map<int, String> proxyOfSegment,
  Map<String, List<SegmentSwitch>> segmentSwitches,
) {
  final script = LevelScript(key);
  final recs = _records(json);
  final proxies = proxyOfSegment.values.toSet();
  final quests = ls.questIds;
  bool owner(String s) => ls.ownerIds.contains(s);

  // Trigger areas.
  for (final v in ((json['triggerVolumes'] as Map?) ?? const {}).values) {
    if (v is! Map) continue;
    final slot = (v['slotId'] as num?)?.toInt();
    final shape = ((v['shapeList'] as List?) ?? const []).whereType<Map<dynamic, dynamic>>().firstOrNull;
    final pos = _pos(shape?['position']);
    if (slot == null || shape == null || pos == null) continue;
    final size = vecOf(shape['size']);
    final extent = size == null ? 0.0 : [size.$1, size.$2, size.$3].reduce((a, b) => a > b ? a : b);
    script.slots[slot] = (
      pos: pos,
      size: (extent * 10).round() / 10,
      shape: shape['shapeType'] == 'Sphere' ? 2 : 1,
      radius: (((shape['radius'] as num?)?.toDouble() ?? 0) * 10).round() / 10,
    );
  }
  final bySlot = <int, Vec3?>{};
  if (json['interactives'] case final Map<dynamic, dynamic> m) {
    for (final MapEntry(:key, :value) in m.entries) {
      if (int.tryParse('$key') case final s? when value is Map<dynamic, dynamic>) bySlot[s] = _pos(value['position']);
    }
  }

  // Conversations on the script's own entities.
  for (final e in _entities(json)) {
    final pos = _pos(e['position']);
    _leaves(e, (_, v) {
      if (v is String && storyIdPattern.hasMatch(v)) script.entities.putIfAbsent(v, () => pos);
    });
  }

  final headers = [for (final r in recs.values) if (r.header && r.entry != null && recs.containsKey(r.entry)) r];
  final actions = {for (final r in recs.values) if (!r.header && !r.getter) r.id: r};
  final plays = {
    for (final r in actions.values) r.id: {for (final s in r.strings) if (storyIdPattern.hasMatch(s)) s}.toList(),
  };
  final slotOf = <int, int>{};
  final placeOf = <int, Vec3>{};
  final cond = <int, ({List<String> after, List<String> quest})>{};
  for (final h in headers) {
    final slot = ((h.json['_triggerSlotIdFilter'] as Map?)?['constValue'] as num?)?.toInt();
    if (slot != null && slot != 0 && script.slots.containsKey(slot)) slotOf[h.entry!] = slot;
    final target = (h.json['_targetEntity'] as Map?)?['constValue'];
    if (target is Map && target['useSlotId'] == true) {
      if (bySlot[(target['slotId'] as num?)?.toInt()] case final p?) placeOf[h.entry!] = p;
    }
    // What the chain waits for: the conversations and steps its header and
    // the conditions along it name (a conversation a condition compares
    // with is waited for, not played).
    final read = <String>[...h.strings];
    final getters = <int>{};
    void getter(int id) {
      final g = recs[id];
      if (g == null || !g.getter || !getters.add(id)) return;
      read.addAll(g.strings);
      g.refs.forEach(getter);
    }

    h.refs.forEach(getter);
    for (final r in _chainFrom(recs, h.entry!)) {
      r.refs.forEach(getter);
    }
    final after = {for (final s in read) if (storyIdPattern.hasMatch(s)) s}.toList();
    final quest = {for (final s in read) if (quests.contains(s)) s}.toList();
    if (after.isNotEmpty || quest.isNotEmpty) {
      final c = cond.putIfAbsent(h.entry!, () => (after: [], quest: []));
      c.after.addAll(after);
      c.quest.addAll(quest);
    }
  }

  // Chains: from each header (or each action no header reaches).
  final referenced = {for (final a in actions.values) ...a.next};
  final roots = <int>[...{for (final h in headers) h.entry!}];
  if (roots.isEmpty) roots.addAll([for (final a in actions.keys) if (!referenced.contains(a)) a]..sort());
  final seen = <int>{};
  for (final r in [...roots, ...(actions.keys.toList()..sort())]) {
    final out = <String>[];
    final depth = <String, int>{};
    void visit(int a, int n) {
      if (seen.contains(a) || !actions.containsKey(a)) return;
      seen.add(a);
      for (final c in plays[a] ?? const <String>[]) {
        if (!out.contains(c)) {
          out.add(c);
          depth[c] = n;
        }
      }
      for (final x in actions[a]!.next) {
        visit(x, n + 1);
      }
    }

    visit(r, 0);
    if (out.isEmpty) continue;
    final slot = script.slots[slotOf[r]];
    final c = cond[r];
    script.chains.add(ScriptChain(
      root: r,
      items: out,
      depth: depth,
      trigger: slot?.pos ?? placeOf[r],
      size: slot?.size ?? 0,
      sphere: slot != null && slot.shape == 2 ? slot.radius : 0,
      after: c?.after ?? const [],
      quest: c?.quest ?? const [],
    ),);
  }

  // NPCs it drives: by proxy name or by logic id (not its own id).
  final sid = int.tryParse(script.id);
  final npcs = <String>{};
  _leaves(json, (_, v) {
    if (v is String && proxies.contains(v)) npcs.add(v);
    if (v is num && v == v.roundToDouble() && v.toInt() != sid) {
      if (proxyOfSegment[v.toInt()] case final p?) npcs.add(p);
    }
  });
  script.npcs.addAll(npcs.toList()..sort());
  for (final MapEntry(:key, :value) in cond.entries) {
    script.waits[key] = value;
  }

  script.moves.addAll(({
    for (final r in recs.values)
      if (r.name == 'NpcProxyPatrolStart' || r.name == 'NpcPatrolStart')
        for (final x in r.strings)
          if (proxies.contains(x)) x,
  }).toList()
    ..sort(),);
  List<String> strs(_Rec r) => [for (final s in r.strings) if ((owner(s) || storyIdPattern.hasMatch(s)) && s.length > 3) s];
  for (final h in headers) {
    final chain = _chainFrom(recs, h.entry!);
    script.chainInfo[h.entry!] = (
      header: h.name,
      staged: chain.any((r) => stagedEntryActions.contains(r.name)),
      gait: chain.any((r) => r.name == 'SetCharacterGait')
          ? 'set'
          : chain.any((r) => r.name == 'RestoreCharacterGait')
              ? 'restore'
              : null,
      npcs: ({
        for (final r in chain)
          if (const {'WaitForNpcProxyReady', 'Play3DRadio', 'Play3DRadioAndWait'}.contains(r.name))
            for (final x in r.strings)
              if (proxies.contains(x)) x,
      }).toList()
        ..sort(),
    );
    if (h.name == 'ScriptEvent_OnScriptStageChanged') {
      script.stages.addAll([for (final x in strs(h)) if (!storyIdPattern.hasMatch(x)) x]);
    }
  }

  // Segment switches the headers reach.
  for (final h in headers) {
    final when = switchWhen[h.name];
    if (when == null) continue;
    final arg = strs(h).firstOrNull;
    void walk(int a, (String, String?, String)? c, Set<int> seen) {
      if (seen.contains(a) || !recs.containsKey(a)) return;
      seen = {...seen, a};
      final r = recs[a]!;
      if (r.name == 'ShowSceneDecorationNew' && r.ids.isNotEmpty) {
        final visible = (r.json['_visible'] as Map?)?['constValue'];
        if (visible is bool) {
          segmentSwitches.putIfAbsent('${r.ids.first}', () => []).add(
                (when: when, arg: arg, cond: c, on: visible, by: script.key),
              );
        }
      }
      if (r.name == 'IfElseAction' && recs.containsKey(r.cond)) {
        final g = recs[r.cond]!;
        final step = strs(g).where((x) => !storyIdPattern.hasMatch(x)).firstOrNull;
        if (r.then! > 0) walk(r.then!, (g.name, step, 'then'), seen);
        if (r.otherwise! > 0) walk(r.otherwise!, (g.name, step, 'else'), seen);
        return;
      }
      for (final n in r.next) {
        walk(n, c, seen);
      }
    }

    walk(h.entry!, null, const {});
  }
  return script;
}

const _states = ['None', 'Available', 'Processing', 'Completed', 'Failed', 'Disabled'];

/// The quest that must be in progress for an object of the sub-data to act:
/// a condition on a quest's state `Processing` inside it.
String? _processingQuest(Object? o, LevelStrings ls) {
  String? found;
  void walk(Object? x) {
    if (found != null) return;
    if (x is Map) {
      final q = '${x['questId'] ?? x['id'] ?? ''}';
      // A condition names the state (`compareTarget: Processing`); an air
      // wall's reasons number it (`detailState: 2`).
      final state = '${x['compareTarget'] ?? x['state'] ?? x['questState'] ?? x['detailState'] ?? ''}';
      if (ls.questIds.contains(q) && (state == 'Processing' || state == '2')) {
        found = q;
        return;
      }
      x.values.forEach(walk);
    } else if (x is List) {
      x.forEach(walk);
    }
  }

  walk(o);
  return found;
}

/// The objects and radio zones of the levels' mission sub-data that carry a
/// conversation, by conversation id.
Map<String, List<SubDataEntry>> readSubDataJson(Directory levelData, LevelStrings ls) {
  final out = <String, List<SubDataEntry>>{};
  for (final (file, json) in _levelFiles(levelData, subOnly: true)) {
    void add(String id, Vec3? pos, {bool zone = false, String? step, List<String> quests = const []}) =>
        out.putIfAbsent(id, () => []).add(
              (file: file, pos: pos, questsBefore: quests, zone: zone, zoneStep: step),
            );
    for (final e in (json['interactives'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      // The steps the object's existence is conditioned on (the binary
      // reader's "quests before it in the file").
      final quests = <String>[];
      _leaves(e['progressLockCondition'], (_, v) {
        if (v is String && ls.ownerIds.contains(v) && !quests.contains(v)) quests.add(v);
      });
      final pos = _pos(e['position']);
      final ids = <String>{};
      for (final part in [e['componentProperties'], e['properties']]) {
        _leaves(part, (key, v) {
          if (key == 'valueString' && v is String && storyIdPattern.hasMatch(v)) ids.add(v);
        });
      }
      for (final id in ids) {
        add(id, pos, quests: quests);
      }
    }
    for (final b in ((json['levelScriptBriefDataDict'] as Map?) ?? const {}).values) {
      final ids = <String>{};
      _leaves((b as Map?)?['properties'], (key, v) {
        if (key == 'valueString' && v is String && storyIdPattern.hasMatch(v)) ids.add(v);
      });
      for (final id in ids) {
        add(id, null);
      }
    }
    for (final patrol in (json['npcPatrol'] as List? ?? const []).whereType<Map<dynamic, dynamic>>()) {
      for (final point in (patrol['points'] as List? ?? const []).whereType<Map<dynamic, dynamic>>()) {
        for (final a in (point['actions'] as List? ?? const []).whereType<Map<dynamic, dynamic>>()) {
          if (a['radioId'] case final String id when storyIdPattern.hasMatch(id)) {
            add(id, _pos(point['position']), zone: true, step: _processingQuest(a, ls));
          }
        }
      }
    }
    for (final w in (json['airWalls'] as List? ?? const []).whereType<Map<dynamic, dynamic>>()) {
      if (w['pushBackRadioId'] case final String id when storyIdPattern.hasMatch(id)) {
        add(id, _pos(w['position']), zone: true, step: _processingQuest(w['checkData'], ls));
      }
    }
    final area = json['functionArea'];
    if (area is Map) {
      for (final s in (area['specificDatas'] as List? ?? const []).whereType<Map<dynamic, dynamic>>()) {
        if (s['radioId'] case final String id when storyIdPattern.hasMatch(id)) {
          add(id, _pos(s['position']), zone: true, step: _processingQuest(area['functionAreaConditions'], ls));
        }
      }
    }
  }
  return out;
}

/// Entities that exist only while a mission (or a step) is in a state: an
/// entity's `progressLockCondition` on a mission's or a quest's state.
Map<String, List<EntityGroup>> readEntityGroupsJson(Directory levelData, LevelStrings ls, Set<int> knownEntities) {
  final out = <String, List<EntityGroup>>{};
  for (final (file, json) in _levelFiles(levelData)) {
    for (final e in _entities(json)) {
      final id = (e['levelLogicId'] as num?)?.toInt();
      if (id == null || !knownEntities.contains(id)) continue;
      void walk(Object? c) {
        if (c is! Map) return;
        final type = '${c[r'$type'] ?? ''}';
        final mission = type.contains('MissionState');
        final quest = type.contains('QuestState');
        if (mission || quest) {
          final owner = '${(mission ? c['missionId'] : c['questId']) ?? ''}';
          final state = _states.indexOf('${c['compareTarget'] ?? ''}');
          if (ls.ownerIds.contains(owner) && state >= 0) {
            out.putIfAbsent('$id', () => []).add((
              owner: owner,
              mission: mission,
              op: c['compareOperator'] == 'NotEqual' ? 1 : 0,
              state: state,
              file: file,
            ),);
          }
        }
        for (final s in (c['subConditions'] as List? ?? const [])) {
          walk(s);
        }
      }

      walk(e['progressLockCondition']);
    }
  }
  return out;
}

Iterable<(String, Map<String, dynamic>)> _levelFiles(Directory levelData, {bool subOnly = false}) sync* {
  if (!levelData.existsSync()) return;
  final dirs = levelData.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final lv in dirs) {
    final files = lv.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json') || (subOnly && !name.contains('_lv_data_sub_'))) continue;
      final Object? json;
      try {
        json = jsonDecode(f.readAsStringSync());
      } catch (_) {
        continue;
      }
      if (json is Map<String, dynamic>) yield ('${lv.uri.pathSegments.where((x) => x.isNotEmpty).last}/$name', json);
    }
  }
}

/// Every string the JSON level data holds (the binary data's string pool):
/// a conversation no level data names is not placed anywhere.
List<String> jsonLevelStrings(Directory jsonData) {
  final out = <String>{};
  for (final sub in const ['LevelScriptData', 'LevelData', 'GameplayConfig']) {
    final d = Directory('${jsonData.path}/$sub');
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        _leaves(jsonDecode(f.readAsStringSync()), (_, v) {
          if (v is String && v.isNotEmpty) out.add(v);
        });
      } catch (_) {}
    }
  }
  return out.toList();
}
