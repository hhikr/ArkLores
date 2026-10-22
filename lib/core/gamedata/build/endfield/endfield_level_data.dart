/// The Endfield client's level data, read for where and when each
/// conversation plays: the level scripts (what starts each chain of actions,
/// the trigger areas, the story ids each chain plays, the NPCs it drives, the
/// segments it switches), the levels' mission sub-data (objects and radio
/// zones that carry a conversation, entity groups that exist only in some
/// mission state), and the tables that place NPCs, crowds and mission areas.
///
/// The level scripts and the sub-data are binary in the client the build
/// reads (`LevelScriptData/<level>/<id>.json`, `LevelData/<level>/…_lv_data_sub_<mission>.json`
/// despite the extension): strings are indexes into the StringPool
/// (`StringPool/StringPool<n>.byte`, LZ4 blocks). The byte layouts below were
/// read by hand against the last client that kept the strings in place and
/// the research kit's union-tag table (`levelscript_union_tags.json`, same
/// build), matched to this client by the records' uids. See
/// docs/ENDFIELD_STORY_ORDER.md §2.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A point in a level (metres).
typedef Vec3 = (double, double, double);

double distance(Vec3 a, Vec3 b) {
  final dx = a.$1 - b.$1, dy = a.$2 - b.$2, dz = a.$3 - b.$3;
  return math.sqrt(dx * dx + dy * dy + dz * dz);
}

double _round2(double x) => (x * 100).round() / 100;
Vec3 _round3(Vec3 v) => (_round2(v.$1), _round2(v.$2), _round2(v.$3));

/// A JSON position `{x, y, z}`.
Vec3? vecOf(Object? p) {
  if (p is! Map) return null;
  final x = p['x'], y = p['y'], z = p['z'];
  if (x is! num || y is! num || z is! num) return null;
  return (x.toDouble(), y.toDouble(), z.toDouble());
}

/// Record types of the level scripts, by their union tag in this client
/// (one byte; `fa <u16>` for the action family). Only the ones the story
/// order reads.
const Map<String, String> levelScriptTypeNames = {
  'b:19': 'CheckMissionOrQuestIsComplete',
  'b:1a': 'CheckMissionOrQuestIsProcessing',
  'b:54': 'LevelEvent_OnDialogEnter',
  'b:55': 'LevelEvent_OnDialogExit',
  'b:89': 'LevelEvent_OnQuestStateChanged',
  'b:c4': 'ScriptEvent_OnLeaderEnterTriggerVolume',
  'b:c9': 'ScriptEvent_OnScriptActive',
  'b:cf': 'ScriptEvent_OnScriptStageChanged',
  'fa:10b': 'IfElseAction',
  'fa:10f': 'IfElseAction',
  'fa:126': 'LevelCameraLookAt',
  'fa:30f': 'MainCharMoveTo',
  'fa:330': 'NpcPatrolStart',
  'fa:339': 'NpcProxyPatrolStart',
  'fa:34f': 'OverrideCameraParams',
  'fa:35d': 'Play3DRadio',
  'fa:35e': 'Play3DRadioAndWait',
  'fa:36e': 'PlayDialogAndHideSceneObjectAction',
  'fa:374': 'PlayLevelSequenceAction',
  'fa:377': 'PlayRadio',
  'fa:3b4': 'RestoreCharacterGait',
  'fa:403': 'SetCharacterGait',
  'fa:413': 'SetEnablePlayerMove',
  'fa:414': 'SetEnablePlayerMoveCamera',
  'fa:4ab': 'ShowSceneDecorationNew',
  'fa:4c5': 'StartDialogAction',
  'fa:4c6': 'StartDialogAndTeleportAction',
  'fa:4d2': 'StartTrackCamera',
  'fa:4e9': 'SwitchToCamera',
  'fa:4f2': 'ToggleClearScreen',
  'fa:4f3': 'ToggleClearScreenButRadio',
  'fa:524': 'WaitForNpcProxyReady',
};

/// Actions that take the camera or the player's control (or slow the
/// player's walk): a chain with one is a staged entry, run on entering
/// however wide its area.
const Set<String> stagedEntryActions = {
  'LevelCameraLookAt',
  'SetEnablePlayerMove',
  'SetEnablePlayerMoveCamera',
  'MainCharMoveTo',
  'ToggleClearScreen',
  'ToggleClearScreenButRadio',
  'SwitchToCamera',
  'StartTrackCamera',
  'OverrideCameraParams',
  'PlayLevelSequenceAction',
  'SetCharacterGait',
};

/// The conversation ids of the dialog tables (`dlg_…`, `radio_…`, …).
final RegExp storyIdPattern = RegExp(r'^(dlg|radio|cutscene|cs_video|remotecomm|envTalk|sns)_');
final RegExp _uid = RegExp(r'^[0-9a-f]{8}$');

// ─── StringPool ──────────────────────────────────────────────────────

/// The client's string pool: `StringPool<n>.byte` files in number order,
/// each an LZ4 block of `<count> <count + 1 offsets> <strings>` (each string
/// ends in four bytes that are not part of it).
List<String> readStringPool(Directory dir) {
  final files = <int, File>{};
  for (final f in dir.listSync().whereType<File>()) {
    final m = RegExp(r'^StringPool(\d+)\.byte$').firstMatch(f.uri.pathSegments.last);
    if (m != null) files[int.parse(m.group(1)!)] = f;
  }
  final out = <String>[];
  for (final n in files.keys.toList()..sort()) {
    final b = files[n]!.readAsBytesSync();
    final h = ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'USPC' ? 0 : 4;
    final d = ByteData.sublistView(b);
    final usize = d.getUint32(h + 16, Endian.little);
    final csize = d.getUint32(h + 20, Endian.little);
    final raw = lz4Block(Uint8List.sublistView(b, h + 24, h + 24 + csize), usize);
    final r = ByteData.sublistView(raw);
    final count = r.getUint32(0, Endian.little);
    final base = 4 + (count + 1) * 4;
    for (var k = 0; k < count; k++) {
      final s = math.min(raw.length, base + r.getUint32(4 + k * 4, Endian.little));
      final e = math.min(raw.length, base + r.getUint32(8 + k * 4, Endian.little) - 4);
      // (an entry whose end comes before its start is empty; it keeps its index)
      out.add(e > s ? utf8.decode(raw.sublist(s, e), allowMalformed: true) : '');
    }
  }
  return out;
}

/// An LZ4 block (no frame) of [size] bytes.
Uint8List lz4Block(Uint8List src, int size) {
  final dst = Uint8List(size);
  var i = 0, o = 0;
  while (i < src.length) {
    final token = src[i++];
    var lit = token >> 4;
    if (lit == 15) {
      int b;
      do {
        b = src[i++];
        lit += b;
      } while (b == 255);
    }
    dst.setRange(o, o + lit, src, i);
    i += lit;
    o += lit;
    if (i >= src.length) break;
    final off = src[i] | (src[i + 1] << 8);
    i += 2;
    var ml = token & 15;
    if (ml == 15) {
      int b;
      do {
        b = src[i++];
        ml += b;
      } while (b == 255);
    }
    ml += 4;
    final start = o - off;
    for (var k = 0; k < ml; k++) {
      dst[o++] = dst[start + k];
    }
  }
  return o == size ? dst : Uint8List.sublistView(dst, 0, o);
}

// ─── Bytes ───────────────────────────────────────────────────────────

class _Bytes {
  _Bytes(this.b) : d = ByteData.sublistView(b);
  final Uint8List b;
  final ByteData d;
  int get length => b.length;
  int i32(int o) => d.getInt32(o, Endian.little);
  int u16(int o) => d.getUint16(o, Endian.little);
  int u64(int o) => d.getUint64(o, Endian.little);
  double f32(int o) => d.getFloat32(o, Endian.little);
  Vec3 vec(int o) => (f32(o), f32(o + 4), f32(o + 8));

  bool at(int o, List<int> pattern) {
    if (o < 0 || o + pattern.length > b.length) return false;
    for (var k = 0; k < pattern.length; k++) {
      if (pattern[k] >= 0 && b[o + k] != pattern[k]) return false;
    }
    return true;
  }

  /// Non-overlapping matches of [pattern] (-1 matches any byte), as a
  /// regular expression's finditer would give them.
  Iterable<int> findAll(List<int> pattern, [int from = 0, int? to]) sync* {
    final end = (to ?? b.length) - pattern.length;
    var o = from;
    while (o <= end) {
      if (at(o, pattern)) {
        yield o;
        o += pattern.length;
      } else {
        o++;
      }
    }
  }

  int find(List<int> pattern, [int from = 0]) => findIn(pattern, from, b.length);

  /// The first match lying wholly in [from, to).
  int findIn(List<int> pattern, int from, int to) {
    for (var o = from; o + pattern.length <= to; o++) {
      if (at(o, pattern)) return o;
    }
    return -1;
  }

  int rfind(List<int> pattern, int before) {
    for (var o = before - pattern.length; o >= 0; o--) {
      if (at(o, pattern)) return o;
    }
    return -1;
  }
}

final List<int> _scale = [
  for (final v in [1.0, 1.0, 1.0]) ...(ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List(),
];
List<int> _int32(int v) => (ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List();

bool _plausible(Vec3 v, {double small = 1e-3}) {
  final xs = [v.$1, v.$2, v.$3];
  return xs.every((x) => x.abs() < 1e5) && xs.where((x) => x.abs() > small).length >= 2;
}

// ─── Level scripts ───────────────────────────────────────────────────

/// A trigger area of a script (`<slot> 01 08 00 ff*4 00 01 00 00 00 <?> 00*4 <x y z>`,
/// then a float, a rotation, the shape (1 box, 2 sphere) and the box size).
typedef TriggerSlot = ({Vec3 pos, double size, int shape, double radius});

/// One chain of actions started by a header: the story ids it plays in
/// order, how many actions run before each, the trigger area that starts it
/// (or the object a click on starts it), and what the header waits for.
class ScriptChain {
  ScriptChain({
    required this.root,
    required this.items,
    required this.depth,
    required this.trigger,
    required this.size,
    required this.sphere,
    required this.after,
    required this.quest,
  });
  final int root;
  final List<String> items;
  final Map<String, int> depth;
  final Vec3? trigger;
  final double size;
  final double sphere;
  final List<String> after;
  final List<String> quest;
}

/// What a header's chain does, read with the record types.
typedef ChainInfo = ({String header, bool staged, String? gait, List<String> npcs});

/// A segment (a script, or the NPC registered under the same id) switched
/// on or off: when (the script's activation, a conversation starting or
/// ending, a step's state changing), inside which branch of a "step complete
/// / in progress" condition, and by which script.
typedef SegmentSwitch = ({
  String when,
  String? arg,
  (String getter, String? step, String branch)? cond,
  bool on,
  String by,
});

class LevelScript {
  LevelScript(this.key);

  /// `<level>/<id>.json`.
  final String key;
  String get level => key.split('/').first;
  String get id => key.split('/').last.split('.').first;

  final List<ScriptChain> chains = [];
  final Map<String, Vec3?> entities = {};
  final Map<int, TriggerSlot> slots = {};
  final List<String> npcs = [];
  final Map<int, ({List<String> after, List<String> quest})> waits = {};
  final Map<int, ChainInfo> chainInfo = {};

  /// NPCs it sets walking (patrol start), by proxy name.
  final List<String> moves = [];

  /// Steps a stage-changed header of it names.
  final List<String> stages = [];

  /// The story ids its actions play, chain by chain.
  List<String> get order => [for (final c in chains) ...c.items];
}

/// Story ids, quest and mission ids the level data refer to, as indexes
/// into the string pool.
class LevelStrings {
  LevelStrings(this.strings, {required Set<String> questIds, required Set<String> missionIds, required Set<String> proxies}) {
    for (final (i, s) in strings.indexed) {
      if (storyIdPattern.hasMatch(s)) story.add(i);
      if (questIds.contains(s)) quests.add(i);
      if (questIds.contains(s) || missionIds.contains(s)) owners.add(i);
      if (proxies.contains(s)) proxyNames.add(i);
    }
  }
  final List<String> strings;
  final Set<int> story = {};
  final Set<int> quests = {};
  final Set<int> owners = {};
  final Set<int> proxyNames = {};
  bool valid(int i) => i >= 0 && i < strings.length;
}

class _Record {
  _Record(this.id, this.key, this.at, this.body);
  final int id;
  final String key;
  final int at;
  final Uint8List body;
  String get name => levelScriptTypeNames[key] ?? key;
  List<int> next = [];
  int? cond, then, otherwise, entry;
  bool header = false;
  final List<String> strs = [];
  final List<String> any = [];
  final List<int> ids = [];
  final List<bool> bools = [];
}

/// Reads one level script ([key] `<level>/<id>.json`).
LevelScript readLevelScript(String key, Uint8List bytes, LevelStrings ls, Map<int, String> proxyOfSegment) {
  final b = _Bytes(bytes);
  final s = ls.strings;
  final script = LevelScript(key);

  // Actions with their next ones: `01 00 00 00 01 01 <next>` or a fork
  // `01 00 00 00 00 01 ff*4 <n> <ids>`; `_ID` and the uid sit before.
  final acts = <int, ({int at, List<int> next})>{};
  final actPattern = [1, 0, 0, 0];
  for (var p = 0; p + 6 <= b.length;) {
    final simple = b.at(p, [...actPattern, 1, 1]);
    final fork = !simple && b.at(p, [...actPattern, 0, 1, 255, 255, 255, 255]);
    if (!simple && !fork) {
      p++;
      continue;
    }
    final end = p + (simple ? 6 : 10);
    if (p >= 10) {
      final aid = b.i32(p - 9), uid = b.i32(p - 4);
      if (aid > 0 && aid < 100000 && ls.valid(uid) && _uid.hasMatch(s[uid])) {
        if (simple && end + 4 <= b.length) {
          acts[aid] = (at: p, next: [b.i32(end)]);
        } else if (fork && end + 4 <= b.length) {
          final n = b.i32(end);
          if (n > 0 && n < 64 && end + 4 + 4 * n <= b.length) {
            acts[aid] = (at: p, next: [for (var k = 0; k < n; k++) b.i32(end + 4 + 4 * k)]);
          }
        }
      }
    }
    p = end;
  }

  // Trigger areas.
  final slotPattern = [1, 8, 0, 255, 255, 255, 255, 0, 1, 0, 0, 0, -1, 0, 0, 0, 0];
  for (var o = 4; o + slotPattern.length <= b.length;) {
    if (!b.at(o, slotPattern)) {
      o++;
      continue;
    }
    final mEnd = o + slotPattern.length;
    final slot = b.i32(o - 4);
    o = mEnd + 4; // the next match starts after this one (its 4 lead bytes)
    if (slot < 1000 || slot >= 10000000 || mEnd + 44 > b.length) continue;
    final v = b.vec(mEnd);
    final radius = b.f32(mEnd + 12);
    final shape = b.i32(mEnd + 28);
    final size = b.vec(mEnd + 32);
    final extent = _plausible(size) ? [size.$1, size.$2, size.$3].reduce(math.max) : 0.0;
    if (_plausible(v)) {
      script.slots.putIfAbsent(
        slot,
        () => (pos: _round3(v), size: (extent * 10).round() / 10, shape: shape, radius: (radius * 10).round() / 10),
      );
    }
  }

  // Headers: `01 00 00 00 00 01 00*8 (00|01) <entry>`, an enter-area one
  // names its slot a little later (`04 <slot>`), a click one its object.
  final hdrs = <({int entry, int? slot, int at, Vec3? place})>[];
  final hdrPattern = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0];
  for (var o = 0; o + hdrPattern.length + 5 <= b.length;) {
    if (!b.at(o, hdrPattern) || (b.b[o + 14] != 0 && b.b[o + 14] != 1)) {
      o++;
      continue;
    }
    final mEnd = o + 15;
    final entry = b.i32(mEnd);
    final winStart = mEnd + 4, winEnd = math.min(b.length, mEnd + 90);
    int? slot;
    for (final sl in script.slots.keys) {
      if (b.findIn([4, ..._int32(sl)], winStart, winEnd) >= 0) {
        slot = sl;
        break;
      }
    }
    Vec3? place;
    if (slot == null) {
      for (var k = winStart; k + 14 <= winEnd; k++) {
        if (b.at(k, [4, 3, 0, 0, 0, 0, 0, 0, 0, 0])) {
          final ent = b.b.sublist(k + 10, k + 14);
          final r = b.find([...ent, 0x19, 0, 0, 0, 0]);
          final sc = r >= 0 ? b.find(_scale, r) : -1;
          if (sc > 24) {
            final v = b.vec(sc - 24);
            if (_plausible(v)) place = _round3(v);
          }
          break;
        }
      }
    }
    hdrs.add((entry: entry, slot: slot, at: o, place: place));
    o = mEnd;
  }
  final hdrAll = [for (final h in hdrs) if (acts.containsKey(h.entry)) h];
  final firstHdr = hdrAll.isEmpty ? b.length : hdrAll.map((h) => h.at).reduce(math.min);

  Vec3? entityPos(int off) {
    final k = b.rfind(_scale, off);
    if (k < 24) return null;
    final v = b.vec(k - 24);
    return _plausible(v) ? _round3(v) : null;
  }

  final actAt = acts.entries.toList()..sort((x, y) => x.value.at.compareTo(y.value.at));
  final plays = <int, List<String>>{};
  final cond = <int, ({List<String> after, List<String> quest})>{};
  ({int entry, int? slot, int at, Vec3? place})? lastHeader(int off) {
    ({int entry, int? slot, int at, Vec3? place})? best;
    for (final h in hdrAll) {
      if (h.at < off && (best == null || h.at > best.at)) best = h;
    }
    return best;
  }

  for (var off = 6; off < b.length - 16; off++) {
    final v = b.i32(off);
    if (ls.quests.contains(v) && b.b[off - 1] == 4 && off > firstHdr) {
      final h = lastHeader(off);
      if (h != null && off - h.at < 100) {
        cond.putIfAbsent(h.entry, () => (after: [], quest: [])).quest.add(s[v]);
      }
      continue;
    }
    if (!ls.story.contains(v)) continue;
    final param = b.b[off - 1] == 4 &&
        b.at(off + 4, [255, 255, 255, 255, 0, 0, 0, 0]) &&
        (b.b[off + 12] == 0xfe || b.b[off + 12] == 0xff) &&
        b.at(off + 13, [255, 255, 255]);
    final plain = b.at(off - 6, [0, 0, 0, 0, 0, 0]) &&
        (b.b[off + 4] == 2 && b.b[off + 9] == 2 || b.at(off + 4, [255, 255, 255, 255, 255, 255, 255, 255, 1]));
    if (plain) {
      script.entities.putIfAbsent(s[v], () => entityPos(off));
    } else if (param && off > firstHdr) {
      final h = lastHeader(off);
      if (h != null && off - h.at < 100) {
        cond.putIfAbsent(h.entry, () => (after: [], quest: [])).after.add(s[v]);
      }
    } else if (param) {
      int? owner;
      for (final e in actAt) {
        if (e.value.at < off) owner = e.key;
      }
      if (owner != null) {
        final list = plays.putIfAbsent(owner, () => []);
        if (!list.contains(s[v])) list.add(s[v]);
      }
    }
  }

  // Chains: from each header (or each action no header reaches).
  final referenced = {for (final a in acts.values) ...a.next};
  final roots = <int>[
    ...{for (final h in hdrAll) h.entry},
  ];
  if (roots.isEmpty) roots.addAll([for (final a in acts.keys) if (!referenced.contains(a)) a]..sort());
  final slotOf = <int, int?>{};
  final withSlot = {for (final h in hdrAll) if (h.slot != null && h.slot != 0) h.entry};
  for (final h in hdrAll) {
    if (h.slot != null && h.slot != 0) slotOf[h.entry] = h.slot;
  }
  for (final h in hdrAll) {
    if (!withSlot.contains(h.entry)) slotOf[h.entry] = null;
  }
  final placeOf = {for (final h in hdrAll) if (h.place != null) h.entry: h.place};
  final seen = <int>{};
  for (final r in [...roots, ...(acts.keys.toList()..sort())]) {
    final out = <String>[];
    final depth = <String, int>{};
    void visit(int a, int n) {
      if (seen.contains(a) || !acts.containsKey(a)) return;
      seen.add(a);
      for (final c in plays[a] ?? const <String>[]) {
        if (!out.contains(c)) {
          out.add(c);
          depth[c] = n;
        }
      }
      for (final x in acts[a]!.next) {
        visit(x, n + 1);
      }
    }

    visit(r, 0);
    if (out.isEmpty) continue;
    final sl = slotOf[r];
    final slot = sl == null ? null : script.slots[sl];
    final c = cond[r];
    script.chains.add(ScriptChain(
      root: r,
      items: out,
      depth: depth,
      trigger: sl != null ? slot?.pos : placeOf[r],
      size: slot?.size ?? 0,
      sphere: slot != null && slot.shape == 2 ? slot.radius : 0,
      after: c?.after ?? const [],
      quest: c?.quest ?? const [],
    ),);
  }

  // NPCs it drives: by proxy name or by logic id (not its own id).
  final sid = int.tryParse(script.id);
  final npcs = <String>{};
  for (var off = 1; off + 4 <= b.length; off++) {
    final v = b.i32(off);
    if (ls.proxyNames.contains(v) && b.b[off - 1] == 4) npcs.add(s[v]);
  }
  for (var off = 0; off + 8 <= b.length; off++) {
    final q = b.u64(off);
    final p = proxyOfSegment[q];
    if (p != null && q != sid) npcs.add(p);
  }
  script.npcs.addAll(npcs.toList()..sort());
  for (final MapEntry(:key, :value) in cond.entries) {
    script.waits[key] = value;
  }
  _readRecords(script, b, ls, proxyOfSegment);
  return script;
}

/// Second pass with the record types: per header, whether its chain is a
/// staged entry, sets or restores the player's gait, which NPCs it waits for
/// or has speak; the patrols the script starts; the steps its stage headers
/// name. The segment switches are collected by [readSegmentSwitches].
void _readRecords(LevelScript script, _Bytes b, LevelStrings ls, Map<int, String> proxyOfSegment) {
  final recs = _records(b, ls);
  final proxies = proxyOfSegment.values.toSet();
  _recsOf[script] = recs;
  script.moves.addAll(({
    for (final r in recs.values)
      if (r.name == 'NpcProxyPatrolStart' || r.name == 'NpcPatrolStart')
        for (final x in r.any)
          if (proxies.contains(x)) x,
  }).toList()
    ..sort(),);
  for (final h in recs.values.where((r) => r.header)) {
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
            for (final x in r.any)
              if (proxies.contains(x)) x,
      }).toList()
        ..sort(),
    );
    if (h.name == 'ScriptEvent_OnScriptStageChanged') {
      script.stages.addAll([for (final x in h.strs) if (!storyIdPattern.hasMatch(x)) x]);
    }
  }
}

/// Each script's typed records, for [readSegmentSwitches].
final Expando<Map<int, _Record>> _recsOf = Expando();

Map<int, _Record> _records(_Bytes b, LevelStrings ls) {
  final s = ls.strings;
  final found = <(int start, int id, String key, int p)>[];
  for (var p = 0; p + 6 <= b.length;) {
    if (!(b.at(p, [1, 0, 0, 0, 1, 1]) || b.at(p, [1, 0, 0, 0, 0, 1]))) {
      p++;
      continue;
    }
    if (p >= 12) {
      final rid = b.i32(p - 9), uid = b.i32(p - 4);
      if (rid > 0 && rid < 100000 && ls.valid(uid) && _uid.hasMatch(s[uid])) {
        if (p >= 14 && b.b[p - 14] == 0xfa) {
          found.add((p - 14, rid, 'fa:${b.u16(p - 13).toRadixString(16)}', p));
        } else {
          found.add((p - 12, rid, 'b:${b.b[p - 12].toRadixString(16)}', p));
        }
      }
    }
    p += 6;
  }
  found.sort((x, y) => x.$1.compareTo(y.$1));
  final recs = <int, _Record>{};
  for (final (i, (start, rid, key, p)) in found.indexed) {
    final end = i + 1 < found.length ? found[i + 1].$1 : b.length;
    final body = Uint8List.sublistView(b.b, p, math.max(p, end));
    final r = _Record(rid, key, start, body);
    final bb = _Bytes(body);
    if (bb.at(4, [1, 1]) && body.length >= 10) {
      r.next = [bb.i32(6)];
    } else if (r.name == 'IfElseAction') {
      final lim = math.min(40, body.length);
      for (var k = 0; k + 22 <= lim; k++) {
        if (bb.at(k, [4, 1, -1, -1, -1, -1, 255, 255, 255, 255, 0xfe, 255, 255, 255])) {
          r.cond = bb.i32(k + 2);
          r.then = bb.i32(k + 14);
          r.otherwise = bb.i32(k + 18);
          r.next = [for (final x in [r.then!, r.otherwise!]) if (x > 0) x];
          break;
        }
      }
    } else if (bb.at(4, [0, 1, 255, 255, 255, 255]) && body.length >= 14) {
      final n = bb.i32(10);
      if (n > 0 && n < 64 && 14 + 4 * n <= body.length) {
        r.next = [for (var k = 0; k < n; k++) if (bb.i32(14 + 4 * k) > 0) bb.i32(14 + 4 * k)];
      }
    } else if (bb.at(0, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]) &&
        body.length >= 19 &&
        (body[14] == 0 || body[14] == 1)) {
      r.entry = bb.i32(15);
      r.header = true;
    }
    for (var o = 1; o + 4 <= body.length; o++) {
      if (body[o - 1] != 4) continue;
      final v = bb.i32(o);
      if (ls.valid(v)) {
        if ((ls.owners.contains(v) || storyIdPattern.hasMatch(s[v])) && s[v].length > 3) r.strs.add(s[v]);
        r.any.add(s[v]);
      }
      if (o + 8 <= body.length) {
        final q = bb.u64(o);
        if (q > 1000000000 && q < 100000000000) r.ids.add(q);
      }
    }
    for (var k = 0; k + 18 <= body.length;) {
      if (bb.at(k, [255, 255, 255, 255, 0, 0, 0, 0, 0xfe, 255, 255, 255, 4, -1, 255, 255, 255, 255]) &&
          (body[k + 13] == 0 || body[k + 13] == 1)) {
        r.bools.add(body[k + 13] == 1);
        k += 18;
      } else {
        k++;
      }
    }
    recs[rid] = r;
  }
  return recs;
}

List<_Record> _chainFrom(Map<int, _Record> recs, int root) {
  final seen = <int>{};
  final out = <_Record>[];
  void visit(int a) {
    if (seen.contains(a) || !recs.containsKey(a)) return;
    seen.add(a);
    out.add(recs[a]!);
    for (final n in recs[a]!.next) {
      visit(n);
    }
    if (recs[a]!.entry case final e?) visit(e);
  }

  visit(root);
  return out;
}

const Map<String, String> _switchWhen = {
  'ScriptEvent_OnScriptActive': 'active',
  'LevelEvent_OnDialogEnter': 'dialog_enter',
  'LevelEvent_OnDialogExit': 'dialog_exit',
  'LevelEvent_OnQuestStateChanged': 'quest',
};

/// The segment switches (`ShowSceneDecorationNew(<segment>, <bool>)`) the
/// scripts' headers reach, by segment id.
Map<String, List<SegmentSwitch>> readSegmentSwitches(Iterable<LevelScript> scripts, LevelStrings ls) {
  final out = <String, List<SegmentSwitch>>{};
  for (final script in scripts) {
    final recs = _recsOf[script] ?? const <int, _Record>{};
    for (final h in recs.values.where((r) => r.header)) {
      final when = _switchWhen[h.name];
      if (when == null) continue;
      final arg = h.strs.firstOrNull;
      void walk(int a, (String, String?, String)? cond, Set<int> seen) {
        if (seen.contains(a) || !recs.containsKey(a)) return;
        seen = {...seen, a};
        final r = recs[a]!;
        if (r.name == 'ShowSceneDecorationNew' && r.ids.isNotEmpty && r.bools.isNotEmpty) {
          out.putIfAbsent('${r.ids.first}', () => []).add(
                (when: when, arg: arg, cond: cond, on: r.bools.first, by: script.key),
              );
        }
        if (r.name == 'IfElseAction' && recs.containsKey(r.cond)) {
          final c = recs[r.cond]!;
          final step = c.strs.where((x) => !storyIdPattern.hasMatch(x)).firstOrNull;
          if (r.then! > 0) walk(r.then!, (c.name, step, 'then'), seen);
          if (r.otherwise! > 0) walk(r.otherwise!, (c.name, step, 'else'), seen);
          return;
        }
        for (final n in r.next) {
          walk(n, cond, seen);
        }
      }

      walk(h.entry!, null, const {});
    }
  }
  return out;
}

// ─── Level sub-data ──────────────────────────────────────────────────

/// A conversation carried by a level's mission sub-data: an object (with
/// its position and the quest ids that come before it in the file) or a
/// radio zone (with the step it plays in, from its state list).
typedef SubDataEntry = ({
  String file,
  Vec3? pos,
  List<String> questsBefore,
  bool zone,
  String? zoneStep,
});

/// The objects and radio zones of the levels' mission sub-data that carry a
/// conversation, by conversation id.
Map<String, List<SubDataEntry>> readSubData(Directory levelData, LevelStrings ls) {
  final s = ls.strings;
  final out = <String, List<SubDataEntry>>{};
  for (final lv in _dirs(levelData)) {
    for (final f in _files(lv)) {
      final name = f.uri.pathSegments.last;
      if (!name.contains('_lv_data_sub_')) continue;
      final file = '${lv.uri.pathSegments.where((x) => x.isNotEmpty).last}/$name';
      final b = _Bytes(f.readAsBytesSync());
      final qpos = <(int, String)>[];
      for (var off = 4; off + 4 <= b.length; off++) {
        final v = b.i32(off);
        if (ls.owners.contains(v) && b.at(off - 4, [3, 0, 0, 0])) qpos.add((off, s[v]));
      }
      var lastZone = 0;
      for (var off = 6; off < b.length - 16; off++) {
        final v = b.i32(off);
        if (!ls.story.contains(v)) continue;
        final plain = b.at(off - 6, [0, 0, 0, 0, 0, 0]) &&
            (b.b[off + 4] == 2 && b.b[off + 9] == 2 || b.at(off + 4, [255, 255, 255, 255, 255, 255, 255, 255, 1]));
        final r = b.f32(off - 4);
        final zone = b.at(off + 4, [0, 0, 0, 0, 0, 0, 0, 0]) && r > 0 && r < 1000 && b.at(off - 6, [0, 0]);
        if (!plain && !zone) continue;
        if (zone) {
          // the zone's state list before it: `04 <state> <step>`; the step
          // that must be in progress (state 2) is where it plays
          final states = <(String, int)>[];
          for (var k = lastZone; k + 9 <= off;) {
            if (b.b[k] == 4 && b.b[k + 1] <= 5 && b.at(k + 2, [0, 0, 0])) {
              final idx = b.i32(k + 5);
              if (ls.valid(idx) && ls.quests.contains(idx)) states.add((s[idx], b.b[k + 1]));
              k += 9;
            } else {
              k++;
            }
          }
          lastZone = off;
          final processing = [for (final (q, st) in states) if (st == 2) q];
          Vec3? zpos;
          if (processing.isEmpty) {
            for (var o2 = off - 8; o2 > math.max(0, off - 48); o2--) {
              final p2 = b.vec(o2);
              if ([p2.$1, p2.$2, p2.$3].every((x) => x.abs() > 1 && x.abs() < 1e4)) {
                zpos = _round3(p2);
                break;
              }
            }
          }
          out.putIfAbsent(s[v], () => []).add(
                (file: file, pos: zpos, questsBefore: const [], zone: true, zoneStep: processing.firstOrNull),
              );
          continue;
        }
        final k = b.rfind(_scale, off);
        Vec3? pos;
        if (k >= 24 && off - k < 400) {
          final p = b.vec(k - 24);
          if (_plausible(p, small: 1e-2)) pos = _round3(p);
        }
        if (pos == null) {
          // a route node: the nearest plausible float triple before it
          for (var o = off - 4; o > math.max(0, off - 200); o--) {
            final p = b.vec(o);
            if (_plausible(p, small: 1e-2) && [p.$1, p.$2, p.$3].every((x) => x.abs() > 1)) {
              pos = _round3(p);
              break;
            }
          }
        }
        out.putIfAbsent(s[v], () => []).add((
          file: file,
          pos: pos,
          questsBefore: [for (final (o, q) in qpos) if (o < off) q],
          zone: false,
          zoneStep: null,
        ),);
      }
    }
  }
  return out;
}

/// An entity group of the sub-data that exists only while a mission (or a
/// step) is in a state: `0d 03 <cmp> <state> <owner>` (mission) or
/// `12 03 …` (step), compare 0 equal / 1 not equal, state 0 none,
/// 1 available, 2 processing, 3 completed, 4 failed, 5 disabled; the group's
/// entities follow as `<n> <n logic ids>`.
typedef EntityGroup = ({String owner, bool mission, int op, int state, String file});

Map<String, List<EntityGroup>> readEntityGroups(Directory levelData, LevelStrings ls, Set<int> knownEntities) {
  final s = ls.strings;
  final out = <String, List<EntityGroup>>{};
  for (final lv in _dirs(levelData)) {
    for (final f in _files(lv)) {
      final file = '${lv.uri.pathSegments.where((x) => x.isNotEmpty).last}/${f.uri.pathSegments.last}';
      final b = _Bytes(f.readAsBytesSync());
      for (var o = 0; o + 14 <= b.length;) {
        if (!((b.b[o] == 0x0d || b.b[o] == 0x12) && b.b[o + 1] == 3)) {
          o++;
          continue;
        }
        final op = b.i32(o + 2), state = b.i32(o + 6), idx = b.i32(o + 10);
        final mEnd = o + 14;
        if (op != 0 && op != 1 || state < 0 || state > 5 || !ls.valid(idx) || !ls.owners.contains(idx)) {
          o = mEnd;
          continue;
        }
        var ids = const <int>[];
        for (var p = mEnd; p < math.min(b.length - 12, mEnd + 120); p++) {
          final n = b.i32(p);
          if (n > 0 && n <= 30 && p + 4 + 8 * n <= b.length) {
            final cand = [for (var k = 0; k < n; k++) b.u64(p + 4 + 8 * k)];
            if (cand.every(knownEntities.contains)) {
              ids = cand;
              break;
            }
          }
        }
        for (final i in ids) {
          out.putIfAbsent('$i', () => []).add((owner: s[idx], mission: b.b[o] == 0x0d, op: op, state: state, file: file));
        }
        o = mEnd;
      }
    }
  }
  return out;
}

Iterable<Directory> _dirs(Directory d) =>
    d.existsSync() ? (d.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path))) : const [];
Iterable<File> _files(Directory d) =>
    d.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));

// ─── All of it ───────────────────────────────────────────────────────

/// An NPC proxy (`NpcProxyTable`): where it stands and the talk it carries.
typedef NpcProxy = ({String? level, Vec3? pos, List<String> envTalks});

/// The level data of a JSON data dump (`Data/Json` of the client).
class EndfieldLevelData {
  EndfieldLevelData._();

  /// Nothing read yet (filled by hand in tests).
  EndfieldLevelData.empty();

  /// The string pool.
  List<String> strings = const [];

  /// Level scripts by `<level>/<id>.json`.
  final Map<String, LevelScript> scripts = {};
  Map<String, List<SegmentSwitch>> segments = {};
  Map<String, List<SubDataEntry>> subData = {};
  Map<String, List<EntityGroup>> groups = {};

  /// NPC proxy name → its logic id (= its segment id), and back.
  final Map<String, String> logicOfProxy = {};
  final Map<String, String> proxyOfLogic = {};
  final Map<String, NpcProxy> proxies = {};

  /// Proxy name → the dialogue of each of its states (`NpcProxyExDataTable`),
  /// then its talk (`envTalkIds`).
  final Map<String, List<String>> proxySays = {};

  /// Crowds (`AtmosphericNpcClusterDataTable`): their place and talk.
  final List<({String? level, Vec3? pos, List<String> says})> crowds = [];

  /// Mission areas by id, then level (ids repeat across levels).
  final Map<String, Map<String, Vec3>> areas = {};

  /// Reads [jsonData] (`…/Data/Json`); [questIds] and [missionIds] say which
  /// strings name steps and missions.
  static EndfieldLevelData read(Directory jsonData, {required Set<String> questIds, required Set<String> missionIds}) {
    final out = EndfieldLevelData._();
    final g = Directory('${jsonData.path}/GameplayConfig');
    Map<String, dynamic> json(String name) =>
        jsonDecode(File('${g.path}/$name').readAsStringSync()) as Map<String, dynamic>;
    final registry = json('WorldEntityRegistry.json');
    final proxyOfSegment = <int, String>{};
    void walk(Object? o) {
      if (o is Map) {
        if (o['proxyId'] != null && o['segmentIdGlobal'] != null) {
          proxyOfSegment[(o['segmentIdGlobal'] as num).toInt()] = '${o['proxyId']}';
        }
        o.values.forEach(walk);
      } else if (o is List) {
        o.forEach(walk);
      }
    }

    walk(registry);
    for (final MapEntry(:key, :value) in (registry['npcProxyBriefInfos'] as Map).entries) {
      final pid = '${(value as Map)['proxyId']}';
      out.proxyOfLogic['$key'] = pid;
      out.logicOfProxy[pid] = '$key';
    }
    final known = <int>{
      for (final k in (registry['npcProxyBriefInfos'] as Map).keys) int.parse('$k'),
      for (final k in (registry['worldEntityBriefInfos'] as Map).keys) int.parse('$k'),
    };
    final pt = json('NpcProxyTable.json')['dataTable'] as Map<String, dynamic>;
    final ex = json('NpcProxyExDataTable.json')['data'] as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in ex.entries) {
      for (final r in (value as List).whereType<Map<String, dynamic>>()) {
        final d = '${r['dialogId'] ?? ''}';
        if (d.isNotEmpty) out.proxySays.putIfAbsent(key, () => []).add(d);
      }
    }
    for (final MapEntry(:key, :value) in pt.entries) {
      final p = value as Map;
      final talks = [for (final t in (p['envTalkIds'] as List? ?? const [])) '$t'];
      out.proxySays.putIfAbsent(key, () => []).addAll(talks);
      out.proxies[key] = (level: p['levelId'] as String?, pos: vecOf(p['position']), envTalks: talks);
    }
    for (final v in (json('AtmosphericNpcClusterDataTable.json')['dataTable'] as Map).values) {
      final c = v as Map;
      out.crowds.add((
        level: c['levelId'] as String?,
        pos: vecOf(c['position']),
        says: [
          for (final x in [c['envTalkId'], c['dialogId'], ...(c['envTalkIds'] as List? ?? const [])])
            if (x != null && '$x'.isNotEmpty) '$x',
        ],
      ),);
    }
    final ls = LevelStrings(
      readStringPool(Directory('${jsonData.path}/StringPool')),
      questIds: questIds,
      missionIds: missionIds,
      proxies: pt.keys.toSet(),
    );
    out.strings = ls.strings;
    final scriptDir = Directory('${jsonData.path}/LevelScriptData');
    final levelOfScript = <int, String>{};
    for (final lv in _dirs(scriptDir)) {
      final level = lv.uri.pathSegments.where((x) => x.isNotEmpty).last;
      for (final f in _files(lv)) {
        final name = f.uri.pathSegments.last;
        final id = int.tryParse(name.split('.').first);
        if (id == null) continue;
        levelOfScript[id] = level;
        final key = '$level/$name';
        out.scripts[key] = readLevelScript(key, f.readAsBytesSync(), ls, proxyOfSegment);
      }
    }
    out.segments = readSegmentSwitches(out.scripts.values, ls);
    final levelData = Directory('${jsonData.path}/LevelData');
    out.subData = readSubData(levelData, ls);
    out.groups = readEntityGroups(levelData, ls, known);
    for (final scene in (json('MissionAreaTable.json')['m_areas'] as Map).values) {
      for (final MapEntry(:key, :value) in (scene as Map).entries) {
        final a = value as Map;
        final level = levelOfScript[(a['subDataParentId'] as num?)?.toInt()];
        final pos = vecOf((a['shape'] as Map?)?['position']);
        if (level != null && pos != null) out.areas.putIfAbsent('$key', () => {})[level] = pos;
      }
    }
    return out;
  }
}
