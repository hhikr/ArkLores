import '../../gamedata/game_retrieval.dart';
import 'agent_tool.dart';
import 'observation_data.dart';

/// R14 `OUTLINE`: the chapters of one story collection (an event, a main
/// story chapter, an operator record) in game order, each with its code,
/// name, tag (行动前/行动后/幕间), official synopsis and story id.
///
/// This is how the agent sees the WHOLE story before reading: where an
/// event is set up, where it happens, how it is resolved. Synopses are
/// locating hints (CLAUDE.md principle 5); only READ lines are evidence.
class GetStoryOutlineTool extends AgentTool {
  GetStoryOutlineTool({GameDataRetrieval? gameDataStore})
      : _gameDataStore = gameDataStore;

  /// Long collections (main story arcs) keep a window around the focus
  /// chapter; the rest is listed by code only.
  static const int _maxObservationChars = 6000;
  static const int _synopsisChars = 160;

  final GameDataRetrieval? _gameDataStore;

  @override
  String get name => 'get_story_outline';

  @override
  String get description =>
      'Outline one story collection (event / main chapter / operator record) '
      'in game order: code, name, tag, official synopsis and story_id of '
      'every chapter. Target: a collection name, a scope id '
      '(activity:act21mini) or a story_id (outlines its collection).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'description':
                'Collection name, collection/scope id, or a story_id.',
          },
        },
        'required': ['target'],
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final target = '${arguments['target'] ?? ''}'.trim();
    if (target.isEmpty) return 'Error: target is empty';
    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final collection = await store.storyCollection(target);
    if (collection == null) {
      final like = target.contains(':') ? null : target;
      final type = target == 'obt:main' ? 'MAINLINE' : null;
      final index = like == null && type == null
          ? const <({String id, String label, int chapters})>[]
          : await store.storyCollectionIndex(like: like, type: type);
      final buffer = StringBuffer(
        'No single story collection matches "$target".',
      );
      if (index.isNotEmpty) {
        buffer.writeln(' Candidates (OUTLINE <id>):');
        for (final c in index) {
          buffer.writeln('  ${c.id} 《${c.label}》 ${c.chapters} 章');
        }
      } else {
        buffer.write(' Use a collection name, an activity scope id, or a '
            'story_id from FIND/COVER results. (Knowledge bases built before '
            'the story catalog have no outlines; use MAP instead.)');
      }
      return ToolExecutionResult(observation: buffer.toString().trim());
    }

    final entries = collection.entries;
    final focus = collection.focusStoryId == null
        ? -1
        : entries.indexWhere((e) => e.storyId == collection.focusStoryId);
    final profiles = {
      for (final p in await store.getStoryMap(
        storyIds: [for (final e in entries) e.storyId],
      ))
        p.storyId: p,
    };

    String row(int i, {required bool full}) {
      final e = entries[i];
      final profile = profiles[e.storyId];
      final lines = profile == null
          ? '（无原文）'
          : '行 ${profile.lineStart}-${profile.lineEnd}';
      final mark = i == focus ? ' ← 当前章' : '';
      final head = '${i + 1}. ${e.chapterLabel.isEmpty ? e.collectionName : e.chapterLabel}'
          ' | ${e.storyId} | $lines$mark';
      if (!full) return head;
      final synopsis = (e.synopsis ?? '').trim();
      return synopsis.isEmpty
          ? head
          : '$head\n   梗概: ${synopsis.length > _synopsisChars ? '${synopsis.substring(0, _synopsisChars)}…' : synopsis}';
    }

    final buffer = StringBuffer()
      ..writeln('Outline: 《${collection.label}》（${collection.collectionId}，'
          '共 ${entries.length} 章，按游戏内顺序）')
      ..writeln('梗概是官方剧情回顾的简介，只是定位线索：要用作证据必须 READ 原文。');
    // Full rows for every chapter when they fit; otherwise full rows in a
    // window around the focus chapter (or the start) and short rows outside.
    final fullRows = [for (var i = 0; i < entries.length; i++) row(i, full: true)];
    final fullLength = fullRows.fold<int>(0, (n, r) => n + r.length + 1);
    if (fullLength <= _maxObservationChars) {
      fullRows.forEach(buffer.writeln);
    } else {
      final center = focus < 0 ? 0 : focus;
      var lo = center;
      var hi = center;
      var used = fullRows[center].length;
      while (true) {
        final canLo = lo > 0 && used + fullRows[lo - 1].length < _maxObservationChars * 0.7;
        if (canLo) {
          lo--;
          used += fullRows[lo].length;
        }
        final canHi = hi < entries.length - 1 &&
            used + fullRows[hi + 1].length < _maxObservationChars * 0.7;
        if (canHi) {
          hi++;
          used += fullRows[hi].length;
        }
        if (!canLo && !canHi) break;
      }
      for (var i = 0; i < entries.length; i++) {
        if (buffer.length > _maxObservationChars) {
          buffer.writeln('…（其余 ${entries.length - i} 章省略；OUTLINE <story_id> '
              '可查看其附近章节）');
          break;
        }
        buffer.writeln(row(i, full: i >= lo && i <= hi));
      }
    }
    return ToolExecutionResult(
      observation: appendDataBlock(buffer.toString().trim(), {
        'type': 'get_story_outline',
        'collection_id': collection.collectionId,
        'chapters': entries.length,
      }),
    );
  }
}
