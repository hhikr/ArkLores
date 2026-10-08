/// 0.12: a conversation's lines in the order the game plays them, read from
/// its dialog tree (`TextAsset` `dlg_…`, a `Beyond.Gameplay.DialogTree`).
///
/// The text table numbers the lines of a conversation, but the numbers are
/// not the order: a reply to a choice is often numbered after the lines that
/// follow the choice, and the player's options (`DialogOptionTable`) carry no
/// line number at all. The tree says both. Its line nodes
/// (`DialogTreeTrunkNode`) name their text row (`_trunkId`); an option node
/// (`DialogTreeOptionNode`) lists its options, its outgoing connections lead
/// to each option's reply in the same order, and the branches meet again.
///
/// A tree is read as a wiki shows it: from its first node along the
/// connections; at a choice whose options lead to different replies, each
/// option and its reply in turn, then on from where the branches meet; a
/// choice whose options all lead to the same next line is one step. Only the
/// tree's own structure decides; nothing is inferred from the text.
///
/// A cutscene node plays a timeline; the timeline's lines carry their start
/// time ([loadTimelineLines]) and take the cutscene's place.
library;

import 'dart:convert';
import 'dart:io';

/// One step of a conversation read from its tree: a text row, a choice, or
/// the place a cutscene timeline plays.
class DialogStep {
  const DialogStep.line(String this.rowId)
      : options = const [],
        cutscene = null;
  const DialogStep.choice(this.options)
      : rowId = null,
        cutscene = null;
  const DialogStep.cutscene(String this.cutscene)
      : rowId = null,
        options = const [];

  /// The `DialogTextTable` row of a line.
  final String? rowId;

  /// The `DialogOptionTable` ids of a choice: every option of a choice that
  /// does not branch, or the one option whose branch follows.
  final List<String> options;

  /// The timeline a cutscene node plays (`dlgtl_…`); its lines are in the
  /// timeline's clips ([TimelineLine]), not in the tree.
  final String? cutscene;

  bool get isChoice => rowId == null && cutscene == null;
  bool get isCutscene => cutscene != null;

  @override
  String toString() => isCutscene
      ? '<$cutscene>'
      : isChoice
          ? '[${options.join('/')}]'
          : rowId!;
}

/// A line a cutscene timeline shows (`DialogTrunkPlayableAsset`): its text
/// row, when it starts, and the options offered once it is read
/// (`bindingOptionAssets` → `DialogOptionPlayableAsset`).
class TimelineLine {
  const TimelineLine(this.rowId, this.start, {this.options = const []});

  final String rowId;
  final double start;
  final List<String> options;
}

/// The cutscene lines of each conversation, in the order they start, from an
/// AnimeStudio JSON export of the `DialogTrunkPlayableAsset` and
/// `DialogOptionPlayableAsset` MonoBehaviours (one file per object, each
/// with its `$animestudio` identity: source file and path id). Later
/// directories replace earlier ones' lines of the same row (list the
/// hot-update layer last). A row shown twice keeps its first start.
Map<String, List<TimelineLine>> loadTimelineLines(Iterable<Directory> dirs) {
  final byRow = <String, TimelineLine>{};
  for (final dir in dirs) {
    if (!dir.existsSync()) continue;
    final trunks = <Map<String, dynamic>>[];
    final options = <String, List<String>>{};
    final files = dir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (!file.path.endsWith('.json')) continue;
      final Object? json;
      try {
        json = jsonDecode(file.readAsStringSync());
      } catch (_) {
        continue;
      }
      if (json is! Map<String, dynamic>) continue;
      final meta = json[r'$animestudio'];
      if (meta is! Map) continue;
      if (json['_trunkId'] is String) {
        trunks.add(json);
      } else if (json.containsKey('options')) {
        // One option, or the list of a choice's options.
        final raw = json['options'];
        final ids = [
          for (final o in raw is List ? raw : [raw])
            if (o is Map && '${o['_optionId'] ?? ''}'.isNotEmpty) '${o['_optionId']}',
        ];
        if (ids.isNotEmpty) options['${meta['sourceFile']}:${meta['pathId']}'] = ids;
      }
    }
    final layer = <String, TimelineLine>{};
    for (final t in trunks) {
      final row = '${t['_trunkId']}';
      final start = (t['startTime'] as num?)?.toDouble();
      if (row.isEmpty || start == null) continue;
      final meta = t[r'$animestudio'] as Map;
      final bound = <String>[
        for (final r in (meta['pptrReferences'] as List?) ?? const [])
          if (r is Map && '${r['path']}'.startsWith(r'$.bindingOptionAssets._valueData'))
            ...?options['${r['expectedTargetSourceFile'] ?? meta['sourceFile']}:${r['pathId']}'],
      ];
      final seen = layer[row];
      if (seen != null && seen.start <= start) continue;
      layer[row] = TimelineLine(row, start, options: bound);
    }
    byRow.addAll(layer);
  }
  final out = <String, List<TimelineLine>>{};
  for (final line in byRow.values) {
    final cut = line.rowId.lastIndexOf('_');
    if (cut <= 0) continue;
    out.putIfAbsent(line.rowId.substring(0, cut), () => []).add(line);
  }
  for (final lines in out.values) {
    lines.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.rowId.compareTo(b.rowId));
  }
  return out;
}

/// The steps of [tree] (a decoded dialog tree), in reading order. Empty when
/// it has no line or choice (a tree that only starts a cutscene timeline).
List<DialogStep> readDialogTree(Map<String, dynamic> tree) {
  final nodes = <String, Map<String, dynamic>>{};
  final order = <String>[];
  for (final n in (tree['nodes'] as List?) ?? const []) {
    if (n is! Map<String, dynamic>) continue;
    final id = '${n[r'$id'] ?? ''}';
    if (id.isEmpty) continue;
    nodes[id] = n;
    order.add(id);
  }
  final out = <String, List<String>>{};
  final incoming = <String>{};
  for (final c in (tree['connections'] as List?) ?? const []) {
    if (c is! Map) continue;
    final from = '${(c['_sourceNode'] as Map?)?[r'$ref'] ?? ''}';
    final to = '${(c['_targetNode'] as Map?)?[r'$ref'] ?? ''}';
    if (!nodes.containsKey(from) || !nodes.containsKey(to)) continue;
    out.putIfAbsent(from, () => []).add(to);
    incoming.add(to);
  }
  String typeOf(String id) =>
      '${nodes[id]?[r'$type'] ?? ''}'.replaceFirst('Beyond.Gameplay.DialogTree', '');
  // The `Ex…` nodes (actor, camera, light, summary, option and line
  // overrides) hang off a step as its settings; they are not steps on the
  // way.
  bool onTheWay(String id) => !typeOf(id).startsWith('Ex');
  String? next(String id) {
    for (final t in out[id] ?? const <String>[]) {
      if (onTheWay(t)) return t;
    }
    return null;
  }

  // Every node reachable from [start] (itself included), breadth first.
  List<String> reach(String start) {
    final seen = <String>{start};
    final queue = [start];
    for (var i = 0; i < queue.length; i++) {
      for (final t in out[queue[i]] ?? const <String>[]) {
        if (onTheWay(t) && seen.add(t)) queue.add(t);
      }
    }
    return queue;
  }

  final steps = <DialogStep>[];
  final visited = <String>{};

  void walk(String? start, Set<String> stop) {
    var node = start;
    while (node != null && !stop.contains(node) && visited.add(node)) {
      final n = nodes[node]!;
      switch (typeOf(node)) {
        case 'TrunkNode':
          final row = '${((n['_actorNodeData'] as Map?)?['mfTrunkActionData'] as Map?)?['_trunkId'] ?? ''}';
          if (row.isNotEmpty) steps.add(DialogStep.line(row));
          node = next(node);
        case 'OptionNode':
          final options = [
            for (final o in (n['_normalOptions'] as List?) ?? const [])
              if (o is Map && '${o['_optionId'] ?? ''}'.isNotEmpty) '${o['_optionId']}',
          ];
          final targets = [
            for (final t in out[node] ?? const <String>[])
              if (onTheWay(t)) t,
          ];
          if (targets.isEmpty) {
            if (options.isNotEmpty) steps.add(DialogStep.choice(options));
            node = null;
            break;
          }
          final reaches = [for (final t in targets) reach(t).toSet()];
          final meet = reach(targets.first).firstWhere(
            (id) => reaches.every((r) => r.contains(id)),
            orElse: () => '',
          );
          final branches = targets.toSet().length > 1 &&
              targets.length == options.length &&
              targets.any((t) => t != meet);
          if (!branches) {
            if (options.isNotEmpty) steps.add(DialogStep.choice(options));
            node = targets.first;
            break;
          }
          for (final (i, t) in targets.indexed) {
            steps.add(DialogStep.choice([options[i]]));
            walk(t, {...stop, if (meet.isNotEmpty) meet});
          }
          node = meet.isEmpty ? null : meet;
        case 'FinishNode' || 'OpenUINode':
          node = null;
        case 'CinematicNode':
          final name = '${(n['_actionData'] as Map?)?['name'] ?? ''}';
          if (name.isNotEmpty) steps.add(DialogStep.cutscene(name));
          node = next(node);
        default:
          // Cutscenes, conditions, summaries: go on along the first way out.
          node = next(node);
      }
    }
  }

  // The tree starts at its node nothing leads to (the first such one).
  final root = order.firstWhere(
    (id) => !incoming.contains(id) && onTheWay(id),
    orElse: () => order.isEmpty ? '' : order.first,
  );
  if (root.isNotEmpty) walk(root, const {});
  return steps;
}
