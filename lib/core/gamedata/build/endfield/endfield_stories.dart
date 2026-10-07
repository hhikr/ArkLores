/// 0.12: the Endfield conversations.
///
/// Two sources, the same output (one story per conversation, grouped into a
/// collection per mission, missions on a shelf by their kind):
/// - [importPublication]: the research kit's Story publication
///   (`webui/data`), which reconstructs the order, the options and the
///   mission each conversation belongs to from the game's own structures;
/// - [importDialogTables]: the dialog tables alone (`DialogTextTable`,
///   `RadioTable`, `SNSDialogTable`), ordered by their row ids — the
///   fallback when no publication is available.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

/// The shelf of a mission id from its letter prefix, as the game's ids are
/// formed (`e<n>m<n>` main story, `c…` character stories, the rest side
/// stories). The publication's own kind replaces this when present.
String shelfOfMission(String mission) {
  final letters = RegExp(r'^[a-z]+').firstMatch(mission)?.group(0) ?? '';
  return switch (letters) {
    'e' => 'main',
    'c' => 'character',
    _ => 'side',
  };
}

class EndfieldStoryImporter {
  EndfieldStoryImporter(this.tables, this.writer, this.importer, {this.log});

  final EndfieldTables tables;
  final EndfieldWriter writer;
  final EndfieldImporter importer;
  final void Function(String message)? log;

  final Map<String, ({String name, String kind, int sort})> _missions = {};

  String _clean(Object? field) => endfieldText(tables.text(field));

  /// The official one-paragraph summary of a conversation, if any.
  String? _summary(String conversation) {
    final key = tables.table('DialogSummaryMapTable')[conversation];
    if (key == null) return null;
    final text = _clean(tables.table('DialogSummaryTable')['$key']);
    return text.isEmpty ? null : text;
  }

  Future<void> _ensureMission(String id, {String? name, String? kind}) async {
    if (_missions.containsKey(id)) return;
    final shelf = kind ?? shelfOfMission(id);
    final owner = operatorOfMission(id, importer.operators);
    final entry = (name: name ?? id, kind: shelf, sort: _missions.length);
    _missions[id] = entry;
    await writer.collection(
      id: 'mission_$id',
      kind: shelf,
      name: entry.name,
      // A character mission hangs below its operator (the operator page
      // lists it, like an Arknights record set).
      parentId: owner,
      sortKey: entry.sort,
      sourcePath: 'mission:$id',
    );
  }

  /// A speaker as players see it: the game appends an internal note in
  /// braces (`工作人员{c13-…}`, a hidden identity) that is not shown.
  String _speaker(Object? field) =>
      _clean(field).replaceAll(RegExp(r'\{[^{}]*\}'), '').trim();

  Future<void> _story({
    required String id,
    required String mission,
    required List<EndfieldLine> lines,
    required String source,
    String? name,
    int? sort,
  }) async {
    await _ensureMission(mission);
    final m = _missions[mission]!;
    await writer.story(
      rawId: id,
      name: name ?? conversationLabel(id),
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
    final ids = byConversation.keys.toList()..sort(_naturalCompare);
    final source = tables.sourcePath('DialogTextTable');
    for (final (i, id) in ids.indexed) {
      final rows = byConversation[id]!..sort((a, b) => a.$1.compareTo(b.$1));
      await _story(
        id: id,
        mission: missionOfConversation(id),
        source: source,
        sort: i,
        lines: [
          for (final (_, r) in rows)
            EndfieldLine(
              _clean(r['dialogText']),
              speaker: _speaker(r['actorName']),
              kind: _speaker(r['actorName']).isEmpty ? 'narration' : 'dialogue',
            ),
        ],
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
        mission: missionOfConversation(id),
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
        mission: missionOfConversation(id),
        source: source,
        sort: 200000 + i,
        name: chat is Map && _clean(chat['name']).isNotEmpty
            ? '${conversationLabel(id)} · ${_clean(chat['name'])}'
            : null,
        lines: lines,
      );
      count++;
    }
    log?.call('sns: $count');
  }

  /// Conversations from the research kit's Story publication. Reads
  /// `lang/CN/index.json` for the tree (kind → story line → mission →
  /// conversations) and `lang/CN/conv/<key>.json` for each conversation.
  Future<void> importPublication(Directory data) async {
    final lang = Directory(p.join(data.path, 'lang', 'CN'));
    final index = jsonDecode(
      await File(p.join(lang.path, 'index.json')).readAsString(),
    );
    log?.call('publication index: ${index is Map ? index.keys.take(12).join(', ') : index.runtimeType}');
    throw UnimplementedError('publication format to be mapped');
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
