import '../../gamedata/gamedata_knowledge_store.dart';
import 'agent_tool.dart';

/// Returns chapter profiles (line range, speakers, entity density, summary,
/// triage keyword hits) for choosing which stories to read closely.
/// Profiles are browsing aids, not evidence.
class GetStoryMapTool extends AgentTool {
  GetStoryMapTool({GameDataKnowledgeStore? gameDataStore})
      : _gameDataStore = gameDataStore ?? GameDataKnowledgeStore();
  static const int _maxObservationChars = 4800;

  final GameDataKnowledgeStore? _gameDataStore;

  @override
  String get name => 'get_story_map';

  @override
  String get description =>
      'Get chapter profiles (line range, speaker set, top entities, extractive '
      'summary, triage keyword hits) for a list of story_ids or all stories of '
      'a scope_id. Use after search_story_coverage to choose which chapters to '
      'read. Returns machine-readable Mapped Stories / Scope markers.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'story_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional list of story ids. Mutually exclusive with scope_id.',
          },
          'scope_id': {
            'type': 'string',
            'description':
                'Optional canonical scope key (e.g. activity:act21mini) to list '
                'all its chapters. Mutually exclusive with story_ids.',
          },
        },
      };

  @override
  Future<dynamic> execute(Map<String, dynamic> arguments) async {
    final rawStoryIds = arguments['story_ids'];
    final storyIds = rawStoryIds is List
        ? rawStoryIds.map((item) => '$item').toList(growable: false)
        : null;
    final scopeId = (arguments['scope_id'] as String?)?.trim();
    if ((storyIds == null || storyIds.isEmpty) &&
        (scopeId == null || scopeId.isEmpty)) {
      return 'Error: provide either story_ids or scope_id';
    }

    final store = _gameDataStore;
    if (store == null || !await store.isAvailable) {
      return const ToolExecutionResult(
        observation:
            'Local GameData knowledge DB is not installed. Install the Chinese GameData knowledge base before searching lore.',
      );
    }

    final profiles = await store.getStoryMap(
      storyIds: storyIds,
      scopeId: scopeId,
    );
    if (profiles.isEmpty) {
      return ToolExecutionResult(
        observation:
            'No chapter profiles found for the requested story ids/scope. The '
            'coverage layer may be missing (old schema) or the ids are invalid.\n'
            'Mapped Stories: 0',
      );
    }

    final buffer = StringBuffer();
    var omitted = 0;
    for (var i = 0; i < profiles.length; i++) {
      final profile = profiles[i];
      final remaining = _maxObservationChars - buffer.length;
      if (remaining <= 600) {
        omitted = profiles.length - i;
        break;
      }
      buffer.writeln('=== Chapter #${i + 1} ===');
      buffer.writeln('Story: ${profile.storyId}');
      buffer.writeln('Scope: ${profile.scopeId}');
      buffer.writeln('Title: ${profile.title ?? '-'}');
      buffer.writeln('Lines: ${profile.lineStart}-${profile.lineEnd}');
      buffer.writeln('Speakers: ${profile.speakerSet.length} '
          '[${profile.speakerSet.take(8).join(', ')}${profile.speakerSet.length > 8 ? ', …' : ''}]');
      if (profile.entityDensity.isNotEmpty) {
        final top = profile.entityDensity.entries.take(5).map(
              (entry) => '${entry.key}(${entry.value})',
            ).join(', ');
        buffer.writeln('Top Entities: $top');
      }
      if (profile.keywordHits.isNotEmpty) {
        final hits = profile.keywordHits.entries
            .map((entry) => '${entry.key}(${entry.value})')
            .join(', ');
        buffer.writeln('Keyword Hits: $hits');
      }
      if (profile.summary != null && profile.summary!.isNotEmpty) {
        buffer.writeln('Summary: ${profile.summary}');
      }
      buffer.writeln();
    }

    buffer.writeln('Mapped Stories: ${profiles.length}');
    if (omitted > 0) {
      buffer.writeln(
        'Note: $omitted additional profile(s) omitted to keep the agent context concise.',
      );
    }
    return ToolExecutionResult(observation: buffer.toString().trim());
  }
}
