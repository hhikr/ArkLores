/// Names for story files the catalog does not name (training, guides,
/// tutorials, roguelike and sandbox dialogs …), and the stage they belong to.
///
/// The catalog (`story_review_table`) names the chapters players read. The
/// other files only have their native file names (`training_act53side_01_a`,
/// `endbook_rogue_5_1_1`). Everything here is derived from the source tables
/// and from the id structure, in this order:
///
/// 1. a name the tables give the file itself (roguelike ending books and
///    month chats, sandbox NPC dialogs, archive entries that read it);
/// 2. the stage the file belongs to — found through the stage id the file
///    name is built from (`level_<stage>_beg`, `training_<activity>_<nn>_a`
///    → stage `<activity>_tr<nn>`) or through the stage's `levelId` — and
///    named after that stage;
/// 3. the kind of file (`训练`, `指引`, `教程` …, from path keywords) with a
///    running number.
///
/// No story, activity or character is named here; only generic file kinds.
library;

/// Lower-cased story path without extension: the key of every lookup.
String storyKey(String id) {
  var k = id.trim().toLowerCase().replaceAll('\\', '/');
  while (k.startsWith('/')) {
    k = k.substring(1);
  }
  return k.endsWith('.txt') ? k.substring(0, k.length - 4) : k;
}

String _baseOf(String key) {
  final cut = key.lastIndexOf('/');
  return cut < 0 ? key : key.substring(cut + 1);
}

/// A name the source tables give one story file.
class StoryHint {
  const StoryHint(this.name, {this.group, this.sort});

  final String name;
  final String? group;

  /// Order inside the collection (lower first).
  final int? sort;
}

/// The result for one story.
class StoryNaming {
  const StoryNaming({
    required this.name,
    this.group,
    this.stageEntryId,
    this.sort,
    this.fromTables = false,
  });

  final String name;
  final String? group;

  /// `stage:<id>` entry when the story belongs to an imported stage.
  final String? stageEntryId;
  final int? sort;

  /// False when only the kind of file could be told (`训练 3`).
  final bool fromTables;
}

/// A stage entry of the knowledge base.
class StageRef {
  const StageRef(this.entryId, this.id, this.name, this.code);

  final String entryId;

  /// Stage id as the tables spell it.
  final String id;
  final String name;
  final String? code;
}

const List<(String, String)> _kinds = [
  ('traininglevel', '训练关卡'),
  ('training', '训练'),
  ('tutorial', '教程'),
  ('battleavg', '战斗对话'),
  ('dialog', '对话'),
  ('monthrecord', '月度对话'),
  ('month_record', '月度对话'),
  ('month_chat', '月度对话'),
  ('endbook', '结局文集'),
  ('guide', '指引'),
  ('task', '任务'),
  ('mark', '地标'),
  ('record', '记录'),
  ('chat', '对话'),
  ('level', '关卡剧情'),
];

/// What kind of file a story is, from words in its path (`训练`, `指引` …).
String storyKindLabel(String id) {
  final key = storyKey(id);
  for (final (word, label) in _kinds) {
    if (key.contains(word)) return label;
  }
  return '剧情';
}

/// Compares two ids so that `x_2` sorts before `x_10`.
int naturalCompare(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m[0]!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i], y = rb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

/// `act05` → `act5`, `01-02` → `1-2`: digit runs without leading zeros, so
/// `01` in a file name meets `1` in a stage id.
String _plain(String s) =>
    s.replaceAllMapped(RegExp(r'\d+'), (m) => '${int.parse(m[0]!)}');

/// Words of a file name that only say what the file is.
const Set<String> _leading = {'level', 'training', 'guide', 'tutorial'};

/// Resolves names for the story files of one build.
class StoryNamer {
  StoryNamer({
    required this.hints,
    required this.readBy,
    required List<StageRef> stages,
    required Map<String, String> collectionOfStage,
    required this.levelNames,
    required this.stageNames,
  }) {
    for (final stage in stages) {
      final owner = collectionOfStage[stage.entryId];
      if (owner == null) continue;
      final own = owner.toLowerCase();
      var local = stage.id.toLowerCase();
      if (local.startsWith('${own}_')) local = local.substring(own.length + 1);
      final bucket = _byCollection.putIfAbsent(own, () => {});
      final key = _plain(local);
      // An ambiguous suffix binds nothing.
      bucket[key] = bucket.containsKey(key) ? _ambiguous : stage;
    }
  }

  static const StageRef _ambiguous = StageRef('', '', '', null);

  /// Names the tables give single files, by [storyKey].
  final Map<String, StoryHint> hints;

  /// Name of the archive entry that reads a story, by [storyKey].
  final Map<String, String> readBy;

  /// Stage names by the base name of their `levelId` (lower case).
  final Map<String, String> levelNames;

  /// Stage names by stage id (lower case), including stages the library does
  /// not import (guide stages, sandbox stages).
  final Map<String, String> stageNames;

  /// Stage entries per collection, by the stage id without the collection
  /// prefix and without leading zeros.
  final Map<String, Map<String, StageRef>> _byCollection = {};

  /// The stage a file belongs to and the words of its name that follow the
  /// stage's part (`a`, `beg`, `2` …).
  ({String? entryId, String? name, List<String> rest})? _stageOf(
    String key,
    String? collectionId,
  ) {
    final base = _baseOf(key);
    var tokens = base.split('_');
    final training = tokens.first == 'training';
    while (tokens.length > 1 && _leading.contains(tokens.first)) {
      tokens = tokens.sublist(1);
    }
    final own = collectionId?.toLowerCase();
    if (own != null) {
      final prefix = own.split('_');
      if (tokens.length > prefix.length &&
          [for (var i = 0; i < prefix.length; i++) tokens[i]]
                  .join('_') ==
              own) {
        tokens = tokens.sublist(prefix.length);
      }
    }
    final stages = own == null ? null : _byCollection[own];
    for (var k = tokens.length; k >= 1; k--) {
      final part = _plain(tokens.sublist(0, k).join('_'));
      final rest = tokens.sublist(k);
      if (stages != null) {
        // A training file belongs to a training stage, never to the
        // chapter stage with the same number.
        for (final candidate in training
            ? ['tr$part', if (part.startsWith('tr')) part]
            : [part]) {
          final hit = stages[candidate];
          if (hit != null && hit != _ambiguous) {
            return (entryId: hit.entryId, name: hit.name, rest: rest);
          }
        }
      }
    }
    // The file is named after a stage id or a level file, with or without
    // the leading `level_` / `guide_` word.
    final parts = base.split('_');
    for (var k = parts.length; k >= 1; k--) {
      final part = parts.sublist(0, k).join('_');
      final rest = parts.sublist(k);
      final stripped = _leading.contains(parts.first) && k > 1
          ? parts.sublist(1, k).join('_')
          : null;
      for (final id in [part, if (stripped != null) stripped]) {
        final name = stageNames[id] ?? levelNames[id];
        if (name != null) return (entryId: null, name: name, rest: rest);
      }
    }
    return null;
  }

  /// Words after the stage part as a short suffix: `beg` → 行动前, `end` →
  /// 行动后, a lone letter → its number (`a` → 1).
  static String suffixOf(List<String> rest) {
    final out = <String>[];
    for (final word in rest) {
      if (word == 'beg') {
        out.add('行动前');
      } else if (word == 'end') {
        out.add('行动后');
      } else if (RegExp(r'^[a-z]$').hasMatch(word)) {
        out.add('${word.codeUnitAt(0) - 96}');
      } else if (word.isNotEmpty) {
        out.add(word);
      }
    }
    return out.join(' ');
  }

  /// The best name for [storyId] from the tables and the stage; null when
  /// only the kind of file is known (the caller numbers those).
  StoryNaming? resolve(String storyId, {String? collectionId}) {
    final key = storyKey(storyId);
    final hint = hints[key];
    if (hint != null) {
      return StoryNaming(
        name: hint.name,
        group: hint.group,
        sort: hint.sort,
        fromTables: true,
      );
    }
    final read = readBy[key];
    if (read != null && read.isNotEmpty) {
      return StoryNaming(name: read, fromTables: true);
    }
    final stage = _stageOf(key, collectionId);
    if (stage == null || stage.name == null || stage.name!.isEmpty) return null;
    final kind = storyKindLabel(key);
    final suffix = suffixOf(stage.rest);
    final tail = [
      if (kind != '关卡剧情' && kind != '剧情') kind,
      if (suffix.isNotEmpty) suffix,
    ].join(' ');
    return StoryNaming(
      name: tail.isEmpty ? stage.name! : '${stage.name} · $tail',
      stageEntryId: stage.entryId,
      group: kind,
      fromTables: true,
    );
  }
}

/// Numbers the files that only have a kind (`训练 1`, `训练 2` …) per
/// collection. [ids] is every story id of the collection without a name.
Map<String, StoryNaming> numberedKinds(List<String> ids) {
  final byKind = <String, List<String>>{};
  for (final id in ids) {
    byKind.putIfAbsent(storyKindLabel(id), () => []).add(id);
  }
  final out = <String, StoryNaming>{};
  for (final entry in byKind.entries) {
    final list = [...entry.value]..sort(naturalCompare);
    for (var i = 0; i < list.length; i++) {
      out[list[i]] = StoryNaming(
        name: list.length == 1 ? entry.key : '${entry.key} ${i + 1}',
        group: entry.key,
      );
    }
  }
  return out;
}

// ─── Table readers ───────────────────────────────────────────────────

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const <dynamic>[];
String _s(Object? v) => v == null ? '' : '$v'.trim();

/// Names from the roguelike topic table: the pages of the ending books
/// (named by the ending they belong to) and the month chats (named by their
/// own caption, else by the floor, under the month squad's name).
Map<String, StoryHint> roguelikeStoryHints(
  Map<String, dynamic> topicTable,
  String Function(Object?) clean,
) {
  final out = <String, StoryHint>{};
  for (final topic in _map(topicTable['details']).values) {
    final d = _map(topic);
    final archive = _map(d['archiveComp']);
    final book = _map(_map(archive['endbook'])['endbook']);
    for (final end in book.values) {
      final e = _map(end);
      final title = clean(e['title']);
      final endSort = (e['sortId'] as num?)?.toInt() ?? 0;
      final avg = _s(e['avgId']);
      if (avg.isNotEmpty && title.isNotEmpty) {
        out[storyKey(avg)] = StoryHint(title, group: '结局', sort: endSort * 100);
      }
      for (final item in _list(e['clientEndbookItemDatas'])) {
        final i = _map(item);
        final text = _s(i['textId']);
        final name = clean(i['endbookName']);
        if (text.isEmpty || name.isEmpty) continue;
        out[storyKey(text)] = StoryHint(
          name,
          group: title.isEmpty ? '结局文集' : title,
          sort: endSort * 100 + ((i['sortId'] as num?)?.toInt() ?? 0),
        );
      }
    }
    final squadOfChat = <String, String>{};
    for (final squad in _map(d['monthSquad']).values) {
      final s = _map(squad);
      final chat = _s(s['chatId']);
      final name = clean(s['teamName']);
      if (chat.isNotEmpty && name.isNotEmpty) squadOfChat[chat] = name;
    }
    final chats = _map(_map(archive['chat'])['chat']);
    for (final entry in chats.entries) {
      final c = _map(entry.value);
      final group = squadOfChat[entry.key] ?? '月度对话';
      final sort = ((c['sortId'] as num?)?.toInt() ?? 0) * 100;
      for (final item in _list(c['chatItemList'])) {
        final i = _map(item);
        final story = _s(i['chatStoryId']);
        if (story.isEmpty) continue;
        final floor = (i['floor'] as num?)?.toInt() ?? 0;
        final desc = clean(i['chatDesc']);
        out[storyKey(story)] = StoryHint(
          desc.isNotEmpty ? desc : '第$floor层',
          group: group,
          sort: sort + floor,
        );
      }
    }
  }
  return out;
}

/// Names from the sandbox table: dialogs named after the NPC that speaks
/// them, stage names by level file.
({Map<String, StoryHint> hints, Map<String, String> levelNames})
    sandboxStoryNames(
  Map<String, dynamic> table,
  String Function(Object?) clean,
) {
  final hints = <String, StoryHint>{};
  final levels = <String, String>{};
  final dialogAvg = <String, String>{};
  final dialogOwner = <String, String>{};

  void walk(Object? node) {
    if (node is List) {
      for (final v in node) {
        walk(v);
      }
      return;
    }
    if (node is! Map) return;
    final m = node.cast<String, dynamic>();
    final avg = _s(m['avgId']);
    final dialog = _s(m['dialogId']);
    if (avg.isNotEmpty && dialog.isNotEmpty) dialogAvg[dialog] = avg;
    final levelId = _s(m['levelId']);
    final name = clean(m['name']);
    if (levelId.isNotEmpty && name.isNotEmpty) {
      levels[_baseOf(storyKey(levelId))] = name;
    }
    final npc = clean(m['picName']);
    final dialogs = _map(m['dialogIds']);
    if (npc.isNotEmpty) {
      for (final id in dialogs.values) {
        dialogOwner[_s(id)] = npc;
      }
    }
    for (final v in m.values) {
      walk(v);
    }
  }

  walk(table);
  for (final entry in dialogOwner.entries) {
    final avg = dialogAvg[entry.key];
    hints[avg != null ? storyKey(avg) : entry.key.toLowerCase()] =
        StoryHint(entry.value, group: '战斗对话');
  }
  return (hints: hints, levelNames: levels);
}

/// Stage names by stage id and by level file, from a table's stage maps.
void collectStageNames(
  Map<String, dynamic> stages,
  Map<String, String> byId,
  Map<String, String> byLevel,
  String Function(Object?) clean,
) {
  for (final entry in stages.entries) {
    final s = _map(entry.value);
    final name = clean(s['name']);
    if (name.isEmpty) continue;
    final id = _s(s['stageId']).isEmpty ? entry.key : _s(s['stageId']);
    byId.putIfAbsent(id.toLowerCase(), () => name);
    final level = _s(s['levelId']);
    if (level.isNotEmpty) {
      byLevel.putIfAbsent(_baseOf(storyKey(level)), () => name);
    }
  }
}
