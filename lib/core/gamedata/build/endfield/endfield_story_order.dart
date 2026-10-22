/// The order of a mission's conversations along its steps, from the level
/// data ([EndfieldLevelData]): which step each conversation belongs to and
/// where in that step it plays, with the basis for each place.
///
/// Where a conversation goes, strongest basis first:
///  1. the step names it: its completion condition (or `clientActionMap`)
///     names the dialogue, it tracks the message, or it tracks an NPC that
///     carries it;
///  2. the step's condition names a level script that plays it (or waits for
///     it, or drives the NPC that says it); a radio zone whose state list wants
///     the step in progress;
///  3. it is on one action chain with a placed one; an object whose group in
///     the level sub-data waits on the step;
///  5. by position: its own place (the trigger area that starts its chain,
///     the object it is on, the NPC or crowd that says it) nearest the step's
///     route (from the previous target in that level to the step's targets),
///     within the steps its segment and its NPCs are about at;
///  4. nothing: next to its kind by number; a cutscene with nothing closes
///     the story.
/// Within a step, conversations go by how far along the route they sit, then
/// messages, talk around, radio, calls, cutscenes, dialogue (developer
/// 2026-10-21). A step that waits for another mission's step holds that
/// mission (nested; not one with a story of its own). What no step can hold
/// goes in tail groups (after the mission, talk any time, heard only in
/// passing), the last of them the conversations nothing places (said by
/// nothing, or not in the game's data), folded in the reader.
///
/// Only generic rules: nothing here names a mission, a character or a
/// scene. See docs/ENDFIELD_STORY_ORDER.md for the data, the rules and how
/// each was found.
library;

import 'dart:math' as math;

import 'endfield_level_data.dart';

/// One item of a mission's order.
sealed class OrderItem {
  const OrderItem();
}

/// A step's goal (null when the step has no goal text; `quest` null for a
/// tail group's heading; `unplaced` for the group whose place the data
/// cannot give, folded in the reader).
class StepItem extends OrderItem {
  const StepItem(this.text, {this.quest, this.tail = false, this.unplaced = false});
  final String? text;
  final String? quest;
  final bool tail;
  final bool unplaced;
}

/// A conversation with the basis of its place (level as above).
class ConversationItem extends OrderItem {
  const ConversationItem(this.id, {required this.level, required this.note});
  final String id;
  final int level;
  final String note;
}

/// A mission played inside a step of this one.
class NestItem extends OrderItem {
  const NestItem(this.mission, this.items);
  final String mission;
  final List<OrderItem> items;
}

/// An area this wide says where the chain can start, not how far along the
/// route: its conversations count as at the step's end.
const double wideArea = 30;

/// Farther than this from every route, a position says nothing.
const double nearRoute = 50;

const Map<int, String> _certain = {
  1: '这一步点名这段（完成条件、追踪的短信或 NPC）',
  2: '这一步的完成条件点名的脚本播放它',
};

/// Within one place of a step: a message, talk around the player, radio, a
/// remote call, a cutscene, then the dialogue (developer 2026-10-21).
const Map<String, int> _stepRank = {
  'sns': 0,
  'envTalk': 1,
  'radio': 2,
  'remotecomm': 3,
  'cutscene': 4,
  'cs': 4,
  'dlg': 5,
};

String _prefix(String c) => RegExp(r'^[a-zA-Z]+').firstMatch(c)?.group(0) ?? '';

/// A conversation's number among its kind (`0d5` is half way between 0 and
/// 1); trailing letters (`…_3pre`) are left out.
int _number(String c) {
  final p = _prefix(c);
  final m = p == 'cutscene' || p == 'cs'
      ? RegExp(r'^(?:cutscene|cs_video)_[^_]+_(\d+)(?:d(\d+))?').firstMatch(c)
      : RegExp(r'_(\d+)(?:d(\d+))?[a-zA-Z]*$').firstMatch(c);
  if (m == null) return 0;
  final part = m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0').substring(0, 2));
  return int.parse(m.group(1)!) * 100 + part;
}

int _compareStepKey(String a, String b) {
  final n = _number(a).compareTo(_number(b));
  if (n != 0) return n;
  final r = (_stepRank[_prefix(a)] ?? 6).compareTo(_stepRank[_prefix(b)] ?? 6);
  return r != 0 ? r : a.compareTo(b);
}

/// Python's `round` (half to even), as the order was first worked out with.
int _roundEven(double x) {
  final f = x.floorToDouble();
  final d = x - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

double _round2(double x) => (x * 100).round() / 100;

String _g(double x) {
  if (x == x.roundToDouble()) return '${x.toInt()}';
  var s = x.toStringAsPrecision(6);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Distance from p to the segment a–b and how far along it (0..1); with no
/// start, the distance to b at the end.
(double, double) _segDist(Vec3 p, Vec3? a, Vec3 b) {
  if (a == null) return (distance(p, b), 1.0);
  final ab = (b.$1 - a.$1, b.$2 - a.$2, b.$3 - a.$3);
  final ap = (p.$1 - a.$1, p.$2 - a.$2, p.$3 - a.$3);
  final l = ab.$1 * ab.$1 + ab.$2 * ab.$2 + ab.$3 * ab.$3;
  final t = l == 0 ? 0.0 : ((ab.$1 * ap.$1 + ab.$2 * ap.$2 + ab.$3 * ap.$3) / l).clamp(0.0, 1.0);
  return (distance(p, (a.$1 + t * ab.$1, a.$2 + t * ab.$2, a.$3 + t * ab.$3)), t);
}

/// A place a conversation is said: level, position, basis, area size.
typedef Place = ({String? level, Vec3 pos, String basis, double size});

/// One leg of a step's route: from (null when unknown) to.
typedef _Leg = ({String level, Vec3? from, Vec3 to});

class _Anchor {
  _Anchor(this.step, this.level, this.note, this.t, {this.npc});
  final String step;
  final int level;
  final String note;
  final double t;

  /// For an NPC's earlier row: the NPC, its t found once all else is placed.
  final NpcProxy? npc;
}

/// A candidate step for a conversation placed by position.
typedef _Cand = ({double d, int i, String q, double t, String basis, double size});

int _compareCand(_Cand a, _Cand b) {
  if (a.d != b.d) return a.d.compareTo(b.d);
  if (a.i != b.i) return a.i.compareTo(b.i);
  final q = a.q.compareTo(b.q);
  if (q != 0) return q;
  if (a.t != b.t) return a.t.compareTo(b.t);
  final s = a.basis.compareTo(b.basis);
  return s != 0 ? s : a.size.compareTo(b.size);
}

_Cand _minCand(Iterable<_Cand> xs) => xs.reduce((a, b) => _compareCand(a, b) <= 0 ? a : b);

typedef _Facts = ({List<String> named, List<String> scripts, List<String> nest, List<(String, Vec3)> targets});

/// Builds the order of missions' conversations. [mission] gives a mission's
/// definition (`MissionRuntimeAsset` JSON) by id; [conversationMission] the
/// story each conversation is in (all conversations of the build).
class EndfieldStoryOrder {
  EndfieldStoryOrder(this.data, {required this.mission, required this.conversationMission, required this.stepName}) {
    _index();
  }

  final EndfieldLevelData data;
  final Map<String, dynamic>? Function(String id) mission;
  final Map<String, String> conversationMission;

  /// A step's goal text by step id.
  final String? Function(Map<String, dynamic> step) stepName;

  // ─── Whole-game indexes ───────────────────────────────────────────

  /// Scripts by the stories whose conversations they play (one: a script
  /// of that story; more: a manager, left out).
  final Map<String, Set<String>> _scriptStories = {};
  final Map<String, List<Place>> _places = {};
  final Map<(String, Vec3), double> _sphere = {};
  final Map<(String, Vec3, double), Set<String>> _sameTrigger = {};
  final Map<(String, Vec3), Map<String, int>> _sameArea = {};
  final List<(String, List<String>)> _chains = [];
  late final Set<String> _pool = data.strings.toSet();

  void _index() {
    for (final MapEntry(key: sc, value: v) in data.scripts.entries) {
      final set = <String>{};
      for (final c in [...v.order, ...v.entities.keys]) {
        final m = conversationMission[c];
        if (m != null) set.add(m);
      }
      _scriptStories[sc] = set;
    }
    for (final MapEntry(key: sc, value: v) in data.scripts.entries) {
      if (_scriptStories[sc]!.length != 1) continue;
      for (final ch in v.chains) {
        final trig = ch.trigger;
        if (trig == null) continue;
        // a chain that takes the camera or the player's control is a staged
        // entry: it runs on entering, however wide the area
        final staged = v.chainInfo[ch.root]?.staged ?? false;
        final size = staged ? 0.0 : ch.size;
        if (ch.sphere != 0) _sphere[(v.level, trig)] = ch.sphere;
        _sameTrigger.putIfAbsent((v.level, trig, ch.size), () => {}).add(sc);
        final basis = staged && ch.size >= wideArea ? '进入时演出的触发区域' : '触发它的区域';
        for (final c in ch.items) {
          if (conversationMission.containsKey(c)) {
            _places.putIfAbsent(c, () => []).add((level: v.level, pos: trig, basis: basis, size: size));
          }
        }
      }
      for (final MapEntry(key: c, value: p) in v.entities.entries) {
        if (conversationMission.containsKey(c) && p != null) {
          _places.putIfAbsent(c, () => []).add((level: v.level, pos: p, basis: '它所在的物件', size: 0));
        }
      }
    }
    for (final MapEntry(key: c, value: rows) in data.subData.entries) {
      if (!conversationMission.containsKey(c)) continue;
      for (final r in rows) {
        if (r.pos != null) {
          _places.putIfAbsent(c, () => []).add((level: r.file.split('/').first, pos: r.pos!, basis: '它所在的物件', size: 0));
        }
      }
    }
    for (final MapEntry(key: k, value: says) in data.proxySays.entries) {
      final p = data.proxies[k];
      if (p == null || p.pos == null) continue;
      for (final c in says) {
        if (conversationMission.containsKey(c)) {
          _places.putIfAbsent(c, () => []).add((level: p.level, pos: p.pos!, basis: '说它的 NPC', size: 0));
        }
      }
    }
    for (final crowd in data.crowds) {
      if (crowd.pos == null) continue;
      for (final c in crowd.says) {
        if (conversationMission.containsKey(c)) {
          _places.putIfAbsent(c, () => []).add((level: crowd.level, pos: crowd.pos!, basis: '说它的路人', size: 0));
        }
      }
    }
    for (final MapEntry(key: sc, value: v) in data.scripts.entries) {
      for (final ch in v.chains) {
        if (ch.trigger == null) continue;
        final area = _sameArea.putIfAbsent((sc, ch.trigger!), () => {});
        for (final c in ch.items) {
          area.putIfAbsent(c, () => ch.depth[c] ?? 0);
        }
      }
      if (_scriptStories[sc]!.length != 1) continue;
      for (final ch in v.chains) {
        if (ch.items.length > 1) _chains.add((sc, ch.items));
      }
    }
  }

  /// What a script puts on: conversations its actions play, those on its
  /// objects, and those said by the NPCs it drives.
  List<String> _members(LevelScript v) => {
        ...v.order,
        ...v.entities.keys,
        for (final n in v.npcs) ...?data.proxySays[n],
      }.toList();

  /// The levels a conversation is played or said in.
  Set<String> levelsOf(String c) => {
        for (final MapEntry(key: sc, value: v) in data.scripts.entries)
          if (v.order.contains(c) || v.entities.containsKey(c)) sc.split('/').first,
        for (final p in _places[c] ?? const <Place>[])
          if (p.level != null) p.level!,
      };

  // ─── One mission ──────────────────────────────────────────────────

  static List<String> orderedSteps(Map<String, dynamic> m) {
    final qd = (m['questDic'] as Map?)?.cast<String, dynamic>() ?? const {};
    (int, int) key(String q) {
      final mm = RegExp(r'#(\d+)(?:d(\d+))?').firstMatch(q);
      if (mm == null) return (0, 0);
      return (int.parse(mm.group(1)!), int.parse((mm.group(2) ?? '0').padRight(3, '0')));
    }

    final pending = qd.keys.toList()
      ..sort((a, b) {
        final x = key(a), y = key(b);
        return x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2);
      });
    final order = <String>[];
    final done = <String>{};
    while (pending.isNotEmpty) {
      String? next;
      for (final q in pending) {
        final prev = ((qd[q] as Map)['prevQuestIdList'] as List?) ?? const [];
        if (prev.every((p) => done.contains(p) || !qd.containsKey(p))) {
          next = q;
          break;
        }
      }
      if (next == null) {
        order.addAll(pending);
        break;
      }
      order.add(next);
      done.add(next);
      pending.remove(next);
    }
    return order;
  }

  /// The missions a mission's steps wait for (played inside it).
  List<String> nestedMissions(String mid) {
    final m = mission(mid);
    if (m == null) return const [];
    final f = _stepFacts(m, mid);
    return {for (final x in f.values) ...x.nest}.toList();
  }

  Map<String, _Facts> _stepFacts(Map<String, dynamic> m, String mid) {
    final out = <String, _Facts>{};
    final qd = (m['questDic'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final MapEntry(key: q, value: v) in qd.entries) {
      final named = <String>[], scripts = <String>[], nest = <String>[], targets = <(String, Vec3)>[];
      void walk(Object? o) {
        if (o is Map) {
          final t = '${o[r'$type'] ?? ''}'.split(',').first.split('.').last;
          for (final MapEntry(key: k, value: val) in o.entries) {
            if (k == 'constValue' && val is String && conversationMission.containsKey(val)) named.add(val);
            if (k == 'constValue' && val is Map && val.containsKey('scriptId')) scripts.add('${val['scriptId']}');
            if (k == '_questId' && val is Map && val['constValue'] is String) {
              final other = (val['constValue'] as String).split('_q#').first;
              if (other != mid) nest.add(other);
            }
          }
          if (t == 'ReachDestination') {
            final a = (o['_areaId'] as Map?)?['constValue'];
            final lv = (o['_mapId'] as Map?)?['constValue'];
            final pos = data.areas['$a']?['$lv'];
            if (pos != null) targets.add(('$lv', pos));
          }
          o.values.forEach(walk);
        } else if (o is List) {
          o.forEach(walk);
        }
      }

      for (final obj in ((v as Map)['objectiveList'] as List?) ?? const []) {
        // the player first goes where the step points (tracking), then to
        // the area its condition asks for
        final before = targets.length;
        walk((obj as Map)['condition']);
        final reach = targets.sublist(before);
        targets.removeRange(before, targets.length);
        for (final t in (obj['trackingInfoList'] as List?) ?? const []) {
          final tt = t as Map;
          final tp = vecOf(tt['trackingPos']);
          if (tp != null) targets.add(('${tt['sceneId']}', tp));
          if (conversationMission.containsKey(tt['snsDialogId'])) named.add('${tt['snsDialogId']}');
          final pid = tt['npcProxyId'] as String?;
          if (pid != null && pid.isNotEmpty) {
            final p = data.proxies[pid];
            if (p != null && p.pos != null) targets.add((p.level ?? '${tt['sceneId']}', p.pos!));
            named.addAll([for (final c in data.proxySays[pid] ?? const <String>[]) if (conversationMission.containsKey(c)) c]);
          }
        }
        for (final x in reach) {
          if (!targets.contains(x)) targets.add(x);
        }
      }
      out[q] = (named: named, scripts: scripts, nest: nest, targets: targets);
    }
    final acts = {
      for (final a in ((((m['actionMapRaw'] as Map?)?['dataMap'] as Map?)?['actionList'] as List?) ?? const []))
        (a as Map)['_ID']: a,
    };
    final keys = (m['clientActionMapKey'] as List?) ?? const [];
    final values = (m['clientActionMapValue'] as List?) ?? const [];
    for (var k = 0; k < math.min(keys.length, values.length); k++) {
      final q = (keys[k] as Map)['questId'];
      for (final val in (acts[values[k]] ?? const {}).values) {
        if (val is Map && conversationMission.containsKey(val['constValue']) && out.containsKey(q)) {
          out[q]!.named.add('${val['constValue']}');
        }
      }
    }
    return out;
  }

  /// The order of [ids] (the conversations of [mid]'s story played in [mid]
  /// itself) along [mid]'s steps; [stageIds] holds the conversations of the
  /// missions it nests.
  List<OrderItem> build(String mid, Set<String> ids, Map<String, Set<String>> stageIds) {
    final m = mission(mid)!;
    final qd = (m['questDic'] as Map).cast<String, dynamic>();
    final steps = orderedSteps(m);
    final rank = {for (final (i, q) in steps.indexed) q: i};
    final facts = _stepFacts(m, mid);
    final anchor = <String, _Anchor>{};
    final anchorFar = <String, int>{};
    void put(String c, String q, int level, String note, [double t = 1.0]) {
      if (!rank.containsKey(q) || !ids.contains(c)) return;
      final a = anchor[c];
      if (a == null || level < a.level || level == a.level && rank[q]! < rank[a.step]!) {
        anchor[c] = _Anchor(q, level, note, t);
      }
    }

    for (final q in steps) {
      final f = facts[q]!;
      for (final c in f.named) {
        put(c, q, 1, _certain[1]!);
      }
      for (final sid in f.scripts) {
        for (final MapEntry(key: sc, value: v) in data.scripts.entries) {
          if (!sc.endsWith('/$sid.json')) continue;
          for (final c in [...v.order, ...v.entities.keys]) {
            put(c, q, 2, _certain[2]!);
          }
          for (final c in _members(v)) {
            put(c, q, 2, '这一步的完成条件点名的脚本控制说它的 NPC');
          }
          for (final w in v.waits.values) {
            for (final c in w.after) {
              put(c, q, 2, '这一步的完成条件点名的脚本等这段结束');
            }
          }
        }
      }
    }
    // A step that tracks an NPC wants the last of its dialogue rows (the rows
    // are its states in order); the earlier rows are what it says before
    // that, while the step before is under way (unless that step tracks it).
    for (final (k, q) in steps.indexed) {
      if (k == 0) continue;
      for (final o in ((qd[q] as Map)['objectiveList'] as List?) ?? const []) {
        for (final t in ((o as Map)['trackingInfoList'] as List?) ?? const []) {
          final pid = '${(t as Map)['npcProxyId'] ?? ''}';
          final rows = [for (final c in data.proxySays[pid] ?? const <String>[]) if (ids.contains(c)) c];
          if (rows.length < 2) continue;
          final prev = steps[k - 1];
          if (rows.any(facts[prev]!.named.contains)) continue;
          final p = data.proxies[pid];
          for (final c in rows.sublist(0, rows.length - 1)) {
            if (anchor[c]?.step == q) {
              anchor[c] = _Anchor(prev, 1,
                  '追踪的 NPC 的前一个状态说的（它的最后一个状态 ${rows.last} 才是这一步要的），在上一步进行时', 1.0,
                  npc: p,);
            }
          }
        }
      }
    }
    final pendingNpc = [for (final MapEntry(:key, :value) in anchor.entries) if (value.npc != null) key];
    // an object in the level sub-data whose group waits on one of this
    // mission's steps is there at that step; a radio zone plays while the
    // step its state list wants is in progress
    for (final c in ids) {
      for (final r in data.subData[c] ?? const <SubDataEntry>[]) {
        final qs = [for (final x in r.questsBefore) if (rank.containsKey(x)) x];
        if (qs.isNotEmpty) put(c, qs.last, 3, '它所在的物件组以这一步为条件');
        if (r.zone && r.zoneStep != null && rank.containsKey(r.zoneStep)) {
          put(c, r.zoneStep!, 2, '它所在的区域只在这一步进行中起作用');
        }
      }
    }
    // same chain as a placed one
    var changed = true;
    while (changed) {
      changed = false;
      for (final c in ids) {
        if (anchor.containsKey(c)) continue;
        final mates = [
          for (final x in ids)
            if (x != c && anchor.containsKey(x) && _chains.any((ch) => ch.$2.contains(c) && ch.$2.contains(x))) x,
        ];
        if (mates.isEmpty) continue;
        mates.sort((a, b) {
          final r = rank[anchor[a]!.step]!.compareTo(rank[anchor[b]!.step]!);
          return r != 0 ? r : _compareStepKey(a, b);
        });
        final x = mates.first;
        anchor[c] = _Anchor(anchor[x]!.step, 3, '和 $x 在同一条动作链上', anchor[x]!.t);
        changed = true;
      }
    }
    // Routes. A step's route runs from the previous target in that level to
    // its own targets; where it names a conversation, that conversation's
    // own place (when away from the targets) ends the route too. A step with
    // no target is on the way to the next one's (it does not move the start
    // of the next step).
    final route = <String, List<_Leg>>{};
    var last = <String, Vec3>{};
    for (final (k, q) in steps.indexed) {
      var tg = [...facts[q]!.targets];
      final borrowed = tg.isEmpty;
      if (borrowed) {
        tg = [
          ...steps.skip(k + 1).map((x) => facts[x]!.targets).firstWhere((t) => t.isNotEmpty, orElse: () => const []),
        ];
      }
      final own = [...tg];
      for (final c in facts[q]!.named) {
        for (final p in _places[c] ?? const <Place>[]) {
          if (p.level == null) continue;
          if (!own.any((o) => o.$1 == p.level && distance(p.pos, o.$2) <= math.max(5, p.size / 2))) {
            tg.add((p.level!, p.pos));
          }
        }
      }
      final legs = <_Leg>[];
      final here = {...last};
      for (final (lv, p) in tg) {
        legs.add((level: lv, from: here[lv], to: p));
        here[lv] = p;
      }
      route[q] = legs;
      if (!borrowed) last = here;
    }

    bool consistent(String c, int i) {
      for (final MapEntry(key: x, value: a) in anchor.entries) {
        if (_prefix(x) != _prefix(c) || x == c) continue;
        final j = rank[a.step]!;
        if (_number(x) < _number(c) && j > i || _number(x) > _number(c) && j < i) return false;
      }
      return true;
    }

    // Segment windows: a script, or an NPC (its logic id is its segment), is
    // switched on and off by ShowSceneDecorationNew. On activation a script
    // restores the state for the progress so far: an IfElse on "step Q is
    // complete" gives the state before Q ends (else) and after (then); a
    // step-state header sets it at Q. Dialogue-time toggles are left out
    // (they hide things during a conversation and put them back). A number
    // that is an NPC's logic id switches the NPC, not the script.
    final sidOf = <String, Set<String>>{};
    for (final v in data.scripts.values) {
      if (data.proxyOfLogic.containsKey(v.id)) continue;
      for (final c in [...v.order, ...v.entities.keys]) {
        if (ids.contains(c)) sidOf.putIfAbsent(c, () => {}).add(v.id);
      }
    }
    for (final MapEntry(key: lid, value: pid) in data.proxyOfLogic.entries) {
      for (final c in data.proxySays[pid] ?? const <String>[]) {
        if (ids.contains(c)) sidOf.putIfAbsent(c, () => {}).add(lid);
      }
    }
    final trackedBy = <String, Set<int>>{};
    for (final MapEntry(key: q, value: v) in qd.entries) {
      for (final o in ((v as Map)['objectiveList'] as List?) ?? const []) {
        for (final t in ((o as Map)['trackingInfoList'] as List?) ?? const []) {
          final pid = (t as Map)['npcProxyId'] as String?;
          if (pid != null && pid.isNotEmpty && rank.containsKey(q)) trackedBy.putIfAbsent(pid, () => {}).add(rank[q]!);
        }
      }
    }
    // An NPC is about at the steps that track it and the steps a script that
    // sets it walking stages itself on.
    Set<int>? presence(String npc) {
      final idx = {...?trackedBy[npc]};
      for (final v in data.scripts.values) {
        if (v.moves.contains(npc)) idx.addAll([for (final s in v.stages) if (rank.containsKey(s)) rank[s]!]);
      }
      if (idx.isEmpty) return null;
      return {for (var i = idx.reduce(math.min); i <= idx.reduce(math.max); i++) i};
    }

    final chainNpcs = <String, Set<String>>{};
    for (final v in data.scripts.values) {
      for (final ch in v.chains) {
        for (final n in v.chainInfo[ch.root]?.npcs ?? const <String>[]) {
          for (final c in ch.items) {
            if (ids.contains(c)) chainNpcs.putIfAbsent(c, () => {}).add(n);
          }
        }
      }
    }
    Set<int>? window(String c) {
      var allowed = {for (var i = 0; i < steps.length; i++) i};
      var said = false;
      for (final n in chainNpcs[c] ?? const <String>{}) {
        final pr = presence(n);
        if (pr != null) {
          allowed = allowed.intersection(pr);
          said = true;
        }
      }
      for (final sid in sidOf[c] ?? const <String>{}) {
        final state = List<bool?>.filled(steps.length, null);
        final events = data.segments[sid] ?? const <SegmentSwitch>[];
        for (final e in events) {
          final cond = e.cond;
          if (e.when == 'active' && cond != null && rank.containsKey(cond.$2)) {
            final r = rank[cond.$2]!;
            final Iterable<int> rng = switch (cond.$1) {
              'CheckMissionOrQuestIsComplete' =>
                cond.$3 == 'then' ? [for (var i = r + 1; i < steps.length; i++) i] : [for (var i = 0; i <= r; i++) i],
              'CheckMissionOrQuestIsProcessing' => cond.$3 == 'then' ? [r] : const [],
              _ => const [],
            };
            for (final i in rng) {
              state[i] ??= e.on;
            }
          }
        }
        for (final e in events) {
          if (e.when == 'quest' && rank.containsKey(e.arg) && e.cond == null) state[rank[e.arg]!] = e.on;
        }
        if (state.any((s) => s != null)) {
          said = true;
          allowed = allowed.intersection({for (final (i, s) in state.indexed) if (s != false) i});
        }
      }
      return said ? allowed : null;
    }

    final scriptOf = <String, Set<String>>{};
    for (final MapEntry(key: sc, value: v) in data.scripts.entries) {
      if (_scriptStories[sc]!.length != 1) continue;
      for (final c in _members(v)) {
        if (ids.contains(c)) scriptOf.putIfAbsent(c, () => {}).add(sc);
      }
    }
    // Steps a conversation's script points at: the step of a placed
    // conversation it waits to end, or a step that tracks an NPC the script
    // sets walking (the player goes after that NPC there).
    Set<int> waitedSteps(String c) {
      final out = <int>{};
      for (final sc in scriptOf[c] ?? const <String>{}) {
        for (final n in data.scripts[sc]!.moves) {
          out.addAll(trackedBy[n] ?? const {});
        }
        for (final w in data.scripts[sc]!.waits.values) {
          for (final d in w.after) {
            final a = anchor[d];
            if (a != null && a.level <= 2) out.add(rank[a.step]!);
          }
        }
      }
      return out;
    }

    // Placed on a firmer basis, a conversation keeps its step but still
    // takes its place along that step's path where it fires.
    for (final c in anchor.keys.toList()) {
      final a = anchor[c]!;
      if (a.level > 3 || a.npc != null || !_places.containsKey(c)) continue;
      (double, double)? best;
      for (final p in _places[c]!) {
        if (!(p.basis.startsWith('触发它的区域') || p.basis.startsWith('它所在的物件') || p.basis.startsWith('进入时演出'))) continue;
        final legs = route[a.step]!;
        final n = math.max(1, legs.length);
        for (final (k, leg) in legs.indexed) {
          if (leg.level != p.level) continue;
          final (d, t) = _segDist(p.pos, leg.from, leg.to);
          final tt = p.size >= wideArea ? 1.0 : (k + t) / n;
          if (best == null || d < best.$1) best = (d, tt);
        }
      }
      if (best != null && best.$1 <= nearRoute) anchor[c] = _Anchor(a.step, a.level, a.note, best.$2);
    }

    // The step whose route passes nearest. Steps about as near (within half
    // the area, or 3 m) are told apart by: the author's numbering (one that
    // keeps it in order with the placed ones of its kind), the step its
    // script points at, the step of a placed conversation of the same script,
    // and an object right at the earlier step's own target.
    ({_Cand best, bool windowed, bool waited, bool onTheWay, bool byMate, bool atTarget})? nearest(String c) {
      final cands = <_Cand>[];
      final win = window(c);
      for (final p in _places[c] ?? const <Place>[]) {
        for (final (i, q) in steps.indexed) {
          if (win != null && !win.contains(i)) continue;
          final legs = route[q]!;
          final n = math.max(1, legs.length);
          // Its chain waits for an NPC (or has one speak) and where this
          // step starts is already inside its sphere: it fires as soon as the
          // NPC is about, at the start of the step.
          final r0 = _sphere[(p.level ?? '', p.pos)] ?? 0;
          final start = legs.isNotEmpty && legs.first.level == p.level ? legs.first.from : null;
          if ((chainNpcs[c]?.isNotEmpty ?? false) && win != null && r0 != 0 && start != null && distance(p.pos, start) <= r0) {
            cands.add((d: 0.0, i: i, q: q, t: 0.0, basis: '${p.basis}（半径 ${_g(r0)} 米；它等的 NPC 出现时玩家已在区域内）', size: 0));
            continue;
          }
          for (final (k, leg) in legs.indexed) {
            if (leg.level != p.level) continue;
            final (d, t0) = _segDist(p.pos, leg.from, leg.to);
            final t = p.size >= wideArea ? 1.0 : (k + t0) / n;
            cands.add((d: d, i: i, q: q, t: t, basis: p.basis, size: p.size));
          }
        }
      }
      if (cands.isEmpty) return null;
      final d0 = _minCand(cands);
      final reach = math.max(3.0, d0.size / 2);
      final near = [for (final x in cands) if (x.d <= d0.d + reach) x];
      final consistentOnes = [for (final x in near) if (consistent(c, x.i)) x];
      final ok = consistentOnes.isEmpty ? near : consistentOnes;
      final waitedIdx = waitedSteps(c);
      var pref = [for (final x in ok) if (waitedIdx.contains(x.i) && !x.basis.startsWith('进入时演出')) x];
      var waited = pref.isNotEmpty;
      var byMate = false;
      if (pref.isEmpty) {
        final mates = [
          for (final sc in scriptOf[c] ?? const <String>{})
            for (final x in data.scripts[sc]!.order)
              if (x != c && anchor.containsKey(x) && anchor[x]!.level <= 2) rank[anchor[x]!.step]!,
        ];
        final tied = [for (final x in ok) if (x.d <= d0.d + 1) x];
        if (mates.isNotEmpty && {for (final x in tied) x.i}.length > 1) {
          int gap(_Cand x) => mates.map((j) => (x.i - j).abs()).reduce(math.min);
          final g0 = tied.map(gap).reduce(math.min);
          pref = [for (final x in tied) if (gap(x) == g0) x];
          byMate = _compareCand(_minCand(pref), _minCand(ok)) != 0;
        }
      }
      var best = _minCand(pref.isEmpty ? ok : pref);
      // Where one step ends and the next begins: an object right at the
      // earlier step's own target (a few metres) is what that step goes to
      // (an NPC or a crowd standing there is not).
      var atTarget = false;
      if (best.t <= 0.1 && best.i > 0 && best.basis.startsWith('它所在的物件')) {
        final prev = steps[best.i - 1];
        final end = facts[prev]!.targets.isNotEmpty && route[prev]!.isNotEmpty ? route[prev]!.last : null;
        if (end != null &&
            (_places[c] ?? const <Place>[])
                .any((p) => p.level == end.level && p.basis.startsWith('它所在的物件') && distance(p.pos, end.to) <= 5)) {
          for (final x in near) {
            if (x.i == best.i - 1 && x.t >= 0.9) {
              best = x;
              atTarget = true;
              waited = false;
              byMate = false;
              break;
            }
          }
        }
      }
      // Off every known route, and its segment is on from the level's first
      // step: it is on the way to that step, whose approach is not known.
      if (win != null && best.d > wideArea) {
        final level = (_places[c] ?? const <Place>[]).firstOrNull?.level;
        final first = steps.indexed.where((e) => route[e.$2]!.any((l) => l.level == level)).firstOrNull?.$1;
        if (first != null && win.contains(first)) {
          return (
            best: (d: best.d, i: first, q: steps[first], t: 0.0, basis: best.basis, size: best.size),
            windowed: true,
            waited: false,
            onTheWay: true,
            byMate: false,
            atTarget: false,
          );
        }
      }
      return (best: best, windowed: win != null, waited: waited, onTheWay: false, byMate: byMate, atTarget: atTarget);
    }

    // Nearest first: each placed one then keeps the numbering of the next
    // ones in check.
    final guess = {for (final c in ids) if (!anchor.containsKey(c)) c: nearest(c)};
    final order = [for (final c in ids) if (!anchor.containsKey(c) && guess[c] != null) c]
      ..sort((a, b) {
        final r = _roundEven(guess[a]!.best.d).compareTo(_roundEven(guess[b]!.best.d));
        return r != 0 ? r : _compareStepKey(a, b);
      });
    for (final c in order) {
      final n = nearest(c)!;
      final best = n.best;
      if (best.d > nearRoute && !n.windowed) {
        // Too far from every route. If its script has a placed conversation,
        // it comes at the end of the first such step.
        final mates = [
          for (final sc in scriptOf[c] ?? const <String>{})
            for (final x in ids)
              if (x != c && (scriptOf[x]?.contains(sc) ?? false) && anchor.containsKey(x)) rank[anchor[x]!.step]!,
        ];
        if (mates.isNotEmpty) {
          anchor[c] = _Anchor(steps[mates.reduce(math.min)], 5,
              '离路线 ${_roundEven(best.d)} 米，太远；同一脚本里有已定位的一段，排在那一步末尾', 1.01,);
        } else {
          anchorFar[c] = _roundEven(best.d);
        }
        continue;
      }
      var note = '${best.basis}离这一步的路线最近（${_roundEven(best.d)} 米）';
      if (n.onTheWay) note = '${best.basis}离所有已知路线都远（${_roundEven(best.d)} 米），所在分段从这一步起打开：在去这一步的路上';
      if (best.size >= wideArea) note += '；区域宽 ${_g(best.size)} 米，按这一步的终点算';
      if (n.windowed) note += '；它所在的分段只在这几步打开';
      if (n.waited) note += '；它的脚本等这一步的对话结束，或让这一步追踪的 NPC 走过来';
      if (n.byMate) note += '；前后两步离它一样近，取离同一脚本里已定位的对话较近的一步';
      if (n.atTarget) note += '；它就在这一步追踪的目标处（5 米内），是这一步要去找的东西';
      anchor[c] = _Anchor(best.q, 5, note, best.t);
    }
    // An NPC's earlier row: at the point of that step's path nearest where
    // the NPC stands, after what plays around there (talking to it is the
    // player's choice).
    for (final c in pendingNpc) {
      final a = anchor[c]!;
      final p = a.npc!;
      var best = (double.infinity, 1.0);
      final legs = route[a.step]!;
      final n = math.max(1, legs.length);
      if (p.pos != null) {
        for (final (k, leg) in legs.indexed) {
          if (leg.level != p.level) continue;
          final (d, t) = _segDist(p.pos!, leg.from, leg.to);
          if (d < best.$1 || d == best.$1 && (k + t) / n < best.$2) best = (d, (k + t) / n);
        }
      }
      final hereT = [
        for (final MapEntry(key: x, value: o) in anchor.entries)
          if (x != c && o.step == a.step && o.npc == null && p.pos != null &&
              (_places[x] ?? const <Place>[]).any((pl) => pl.level == p.level && distance(pl.pos, p.pos!) <= 10))
            o.t,
      ];
      anchor[c] = _Anchor(a.step, a.level, a.note, [best.$2, ...hereT].reduce(math.max) + 0.01);
    }
    // A script that slows the player's walk on entering (a staged walk-in)
    // and gives it back in the chain of conversation D: the walk leads to D,
    // and the objects of that script are looked at after it.
    for (final v in data.scripts.values) {
      final gaits = {for (final ch in v.chains) ch.root: v.chainInfo[ch.root]?.gait};
      if (!gaits.values.contains('set')) continue;
      final ds = [
        for (final ch in v.chains)
          if (gaits[ch.root] == 'restore')
            for (final c in ch.items)
              if (anchor.containsKey(c)) c,
      ];
      if (ds.isEmpty) continue;
      final d = ds.first;
      for (final c in v.entities.keys) {
        final a = anchor[c];
        if (a != null && c != d && a.level >= 4) {
          anchor[c] = _Anchor(anchor[d]!.step, 5, '它所在的物件属于进门演出的脚本：演出放慢脚步，到 $d 才恢复，所以在那之后才能查看',
              anchor[d]!.t + 0.001,);
        }
      }
    }

    final seq = <OrderItem>[];
    for (final q in steps) {
      seq.add(StepItem(stepName((qd[q] as Map).cast<String, dynamic>()), quest: q));
      final here = [for (final c in ids) if (anchor[c]?.step == q) c]
        ..sort((a, b) {
          final t = _round2(anchor[a]!.t).compareTo(_round2(anchor[b]!.t));
          if (t != 0) return t;
          final r = (_stepRank[_prefix(a)] ?? 6).compareTo(_stepRank[_prefix(b)] ?? 6);
          if (r != 0) return r;
          final n = _number(a).compareTo(_number(b));
          return n != 0 ? n : a.compareTo(b);
        });
      void reorder(bool Function(String) member, int Function(String, String) compare) {
        final at = [for (final (i, c) in here.indexed) if (member(c)) i];
        if (at.length < 2) return;
        final sorted = [for (final i in at) here[i]]..sort(compare);
        for (final (k, i) in at.indexed) {
          here[i] = sorted[k];
        }
      }

      // The very same trigger volume in two scripts fires them at once: the
      // dialogue takes the screen, the radio plays when it ends.
      for (final MapEntry(key: key, value: scs) in _sameTrigger.entries) {
        if (scs.length < 2) continue;
        reorder(
          (c) =>
              scs.any((sc) => data.scripts[sc]!.order.contains(c)) &&
              (_places[c] ?? const <Place>[]).any((p) => p.pos == key.$2),
          (a, b) {
            final x = (_prefix(a) != 'dlg' ? 1 : 0).compareTo(_prefix(b) != 'dlg' ? 1 : 0);
            return x != 0 ? x : _compareStepKey(a, b);
          },
        );
      }
      // conversations on one chain keep the chain's order among their places
      for (final (_, ch) in _chains) {
        reorder(ch.contains, (a, b) => ch.indexOf(a).compareTo(ch.indexOf(b)));
      }
      // an NPC's dialogue rows follow its states in order
      for (final rows in data.proxySays.values) {
        reorder(rows.contains, (a, b) => rows.indexOf(a).compareTo(rows.indexOf(b)));
      }
      // chains started by the same area at the same point of the step: the
      // one that runs more actions before playing it comes later
      for (final deep in _sameArea.values) {
        var at = [for (final (i, c) in here.indexed) if (deep.containsKey(c)) i];
        if (at.isEmpty) continue;
        final t0 = _round2(anchor[here[at.first]]!.t);
        at = [for (final i in at) if (_round2(anchor[here[i]]!.t) == t0) i];
        if (at.length < 2) continue;
        // (stable: equal depths keep their order)
        final sorted = [for (final (k, i) in at.indexed) (k, here[i])]
          ..sort((a, b) {
            final d = deep[a.$2]!.compareTo(deep[b.$2]!);
            return d != 0 ? d : a.$1.compareTo(b.$1);
          });
        for (final (k, i) in at.indexed) {
          here[i] = sorted[k].$2;
        }
      }
      for (final c in here) {
        seq.add(ConversationItem(c, level: anchor[c]!.level, note: anchor[c]!.note));
      }
      for (final other in facts[q]!.nest) {
        if (stageIds.containsKey(other)) seq.add(NestItem(other, build(other, stageIds[other]!, stageIds)));
      }
    }
    // A background NPC: nothing in the data controls it (no step tracks it,
    // no script moves, switches or waits for it, no sub-data group). Talking
    // to it is optional and not part of the step: after the step's flow, or,
    // off every route, in the story's tail.
    bool controlled(String pid) {
      final lid = data.logicOfProxy[pid] ?? '';
      return (trackedBy[pid]?.isNotEmpty ?? false) ||
          (data.segments[lid]?.isNotEmpty ?? false) ||
          (data.groups[lid]?.isNotEmpty ?? false) ||
          data.scripts.values.any((v) => v.moves.contains(pid) || v.chainInfo.values.any((i) => i.npcs.contains(pid)));
    }

    final background = <String>{};
    for (final c in ids) {
      final sayers = [for (final MapEntry(:key, :value) in data.proxySays.entries) if (value.contains(c)) key];
      if (sayers.isNotEmpty &&
          sayers.every((p) => !controlled(p)) &&
          (_prefix(c) == 'dlg' || _prefix(c) == 'envTalk') &&
          !data.scripts.values.any((v) => v.order.contains(c)) &&
          (anchor[c]?.level ?? 5) >= 4) {
        background.add(c);
      }
    }
    for (final c in background) {
      final a = anchor[c];
      if (a != null) anchor[c] = _Anchor(a.step, a.level, '说它的 NPC 没有任何数据控制（可选闲聊），排在这一步之后', 1.02);
    }
    var out = <OrderItem>[];
    final block = <ConversationItem>[];
    void flush() {
      // (stable: the background ones go to the end of their step's run)
      final indexed = block.indexed.toList()
        ..sort((x, y) {
          double key(ConversationItem it) => background.contains(it.id) ? anchor[it.id]!.t : -1;
          final k = key(x.$2).compareTo(key(y.$2));
          return k != 0 ? k : x.$1.compareTo(y.$1);
        });
      out.addAll(indexed.map((e) => e.$2));
      block.clear();
    }

    for (final it in seq) {
      if (it is ConversationItem) {
        if (background.contains(it.id) && !anchor.containsKey(it.id)) continue;
        block.add(background.contains(it.id) ? ConversationItem(it.id, level: it.level, note: anchor[it.id]!.note) : it);
      } else {
        flush();
        out.add(it);
      }
    }
    flush();
    // An NPC whose sub-data group exists only once this mission is Completed:
    // what it says comes after the story.
    final afterDone = <String>{
      for (final c in ids)
        for (final lid in sidOf[c] ?? const <String>{})
          for (final g in data.groups[lid] ?? const <EntityGroup>[])
            if (g.mission && g.owner == mid && g.op == 0 && g.state == 3) c,
    }.toList()
      ..sort(_compareStepKey);
    for (final c in afterDone) {
      anchor.remove(c);
    }
    out = [for (final it in out) if (!(it is ConversationItem && afterDone.contains(it.id))) it];
    final anytime = [for (final c in background) if (!anchor.containsKey(c)) c]..sort(_compareStepKey);
    final placed = {for (final it in out) if (it is ConversationItem) it.id};
    var unplaced = [
      for (final c in ids)
        if (!anchor.containsKey(c) && !placed.contains(c) && !afterDone.contains(c) && !anytime.contains(c)) c,
    ];
    // Not in the string pool and nowhere in the tables: nothing in the game
    // plays it.
    final unused = [for (final c in unplaced) if (!_pool.contains(c) && !_places.containsKey(c)) c]..sort(_compareStepKey);
    // In the pool, but nothing carries it (no script, NPC, crowd, object or
    // zone): where it would come cannot be told.
    bool carried(String c) =>
        _places.containsKey(c) ||
        data.scripts.values.any((v) => _members(v).contains(c) || v.waits.values.any((w) => w.after.contains(c))) ||
        data.subData.containsKey(c) ||
        data.proxySays.values.any((s) => s.contains(c));
    final uncarried = [for (final c in unplaced) if (!unused.contains(c) && !carried(c)) c]..sort(_compareStepKey);
    // Off every route, said by an NPC whose segment is switched off when a
    // conversation of this story starts: heard only by passing by, before.
    final optional = <String, String>{};
    for (final c in unplaced) {
      if (!anchorFar.containsKey(c)) continue;
      for (final n in chainNpcs[c] ?? const <String>{}) {
        final offs = [
          for (final e in data.segments[data.logicOfProxy[n] ?? ''] ?? const <SegmentSwitch>[])
            if (e.when == 'dialog_enter' && !e.on && e.arg != null && ids.contains(e.arg) && anchor.containsKey(e.arg))
              e.arg!,
        ];
        if (offs.isEmpty) continue;
        offs.sort((a, b) {
          final r = rank[anchor[a]!.step]!.compareTo(rank[anchor[b]!.step]!);
          return r != 0 ? r : _compareStepKey(a, b);
        });
        optional[c] = offs.first;
      }
    }
    unplaced = [
      for (final c in unplaced)
        if (!unused.contains(c) && !uncarried.contains(c) && !optional.containsKey(c)) c,
    ];
    final closing = [for (final c in unplaced) if (_prefix(c) == 'cutscene' || _prefix(c) == 'cs') c]..sort(_compareStepKey);
    for (final c in [for (final c in unplaced) if (!closing.contains(c)) c]..sort(_compareStepKey)) {
      // Next to the number before or after it of its kind, whichever is
      // placed on the stronger basis (the one after it when equal); right
      // after a conversation on the same chain.
      final kin = [
        for (final (i, it) in out.indexed)
          if (it is ConversationItem && _prefix(it.id) == _prefix(c)) (i, it),
      ];
      (int, ConversationItem)? prev, next;
      for (final k in kin) {
        if (_number(k.$2.id) < _number(c) && (prev == null || _number(k.$2.id) > _number(prev.$2.id))) prev = k;
        if (_number(k.$2.id) > _number(c) && (next == null || _number(k.$2.id) < _number(next.$2.id))) next = k;
      }
      int pos;
      if (prev != null && (next == null || prev.$2.level < next.$2.level)) {
        pos = prev.$1 + 1;
      } else if (next != null) {
        pos = next.$1;
      } else {
        pos = out.length;
      }
      final mates = [
        for (final (i, it) in out.indexed)
          if (it is ConversationItem && _chains.any((ch) => ch.$2.contains(c) && ch.$2.contains(it.id))) i,
      ];
      if (mates.isNotEmpty) pos = mates.last + 1;
      final note = anchorFar.containsKey(c)
          ? '离最近的路线 ${anchorFar[c]} 米，太远不作依据；按编号推定位置'
          : '没有锚点，按编号推定位置';
      out.insert(pos, ConversationItem(c, level: 4, note: note));
    }
    out.addAll([for (final c in closing) ConversationItem(c, level: 4, note: '没有锚点的过场，放在本篇末尾')]);
    if (anytime.isNotEmpty) {
      out.add(const StepItem('可以随时找 NPC 说的话', tail: true));
      out.addAll([
        for (final c in anytime) ConversationItem(c, level: 4, note: '说它的 NPC 没有任何数据控制，也不在任务路线附近（可选闲聊）'),
      ]);
    }
    if (afterDone.isNotEmpty) {
      out.add(const StepItem('任务完成后', tail: true));
      out.addAll([for (final c in afterDone) ConversationItem(c, level: 2, note: '说它的 NPC 所在的实体组以“本任务已完成”为条件')]);
    }
    if (optional.isNotEmpty) {
      out.add(const StepItem('可选：路过时才会听到', tail: true));
      out.addAll([
        for (final c in optional.keys.toList()..sort(_compareStepKey))
          ConversationItem(c,
              level: 5,
              note: '不在任何一步的路线上（离最近的路线 ${anchorFar[c]} 米）；说它的 NPC 在 ${optional[c]} 开始时离场，所以只在那之前路过才会听到',),
      ]);
    }
    // What no data places: one folded group (whether the game still plays
    // it is not known either).
    if (uncarried.isNotEmpty || unused.isNotEmpty) {
      out.add(const StepItem('未定位的对话', tail: true, unplaced: true));
      out.addAll([
        for (final c in uncarried) ConversationItem(c, level: 4, note: '只在它自己的文本表里有，没有 NPC、路人组、脚本或区域引用'),
        for (final c in unused) ConversationItem(c, level: 4, note: '字符串池和各表里都没有它'),
      ]);
    }
    return out;
  }
}
