/// Abstraction over the GameData retrieval layer that the investigation tools
/// consume, so the SAME tool classes run in the Flutter app (backed by the
/// mobile Sqlite store) and on the desktop CLI (backed by an FFI store)
/// without duplicating tool logic.
///
/// The mobile [GameDataKnowledgeStore] implements this interface; the desktop
/// CLI implements it with `sqflite_common_ffi`. Tool classes type their store
/// as this interface, which keeps them Flutter-free and identical everywhere.
library;

import 'game.dart';
import 'name_similarity.dart';
import 'readonly_sql.dart';
import 'story_catalog.dart';
import 'story_coverage_models.dart';
import 'story_vectors.dart';

export 'game.dart';
export 'name_similarity.dart' show SimilarName, describeSimilarNames;
export 'readonly_sql.dart' show SqlQueryResult;
export 'story_catalog.dart'
    show
        StoryCatalogEntry,
        StoryCollection,
        collectionReleaseKey,
        compareReleaseKeys,
        fallbackStoryLabel,
        releaseMonthOf;
export 'story_coverage_models.dart';
export 'story_vectors.dart' show StoryChunkHit;

/// The retrieval surface the investigation tools depend on.
abstract interface class GameDataRetrieval {
  /// Whether the local knowledge DB is present and readable.
  Future<bool> get isAvailable;

  /// Raw story lines window for a story id.
  Future<StoryLinesPage> readStoryLines({
    required String storyId,
    int? startLine,
    int? endLine,
    int? maxLines,
    String? pageToken,
  });

  /// R12/R14: stories whose lines (content or speaker) contain any of
  /// [terms], ranked by their best line (IDF-weighted matched terms, so lines
  /// with every term come first), each with up to [linesPerStory] best
  /// matching lines. [scopeId] is a canonical scope key (e.g.
  /// `activity:act21mini`). Locating hints, not evidence.
  Future<List<StoryLineHit>> searchStoryLinesLike(
    List<String> terms, {
    String? scopeId,
    int storyLimit,
    int linesPerStory,
  });

  /// R12: model/dims of the DB's optional story-chunk vectors, or null when
  /// the DB has none (vector recall then stays off).
  Future<({String model, int dims})?> get storyVectorInfo;

  /// R12: top story-line chunks by cosine similarity to [queryVector]
  /// (from the model in [storyVectorInfo]). Locating hints, not evidence.
  Future<List<StoryChunkHit>> searchStoryChunksByVector(
    List<double> queryVector, {
    String? scopeId,
    int topK,
  });

  /// R14: catalog entries (readable names, order, official synopsis) of
  /// [storyIds]; empty when the DB has no story catalog.
  Future<Map<String, StoryCatalogEntry>> storyCatalogEntries(
    Iterable<String> storyIds,
  );

  /// R14: the ordered chapters of the collection named/identified by
  /// [query] (collection name, collection id, scope key or story id).
  Future<StoryCollection?> storyCollection(String query);

  /// R16: catalog entries with level code [code] (e.g. `10-10`).
  Future<List<StoryCatalogEntry>> storiesByCode(String code);

  /// R14: collections whose name contains [like] and/or of [type].
  Future<List<({String id, String label, int chapters})>> storyCollectionIndex({
    String? like,
    String? type,
  });

  /// R14: catalog entries whose official synopsis / chapter name contains
  /// any of [terms], best first. Locating hints, not evidence.
  Future<List<StoryCatalogEntry>> searchStorySynopses(
    List<String> terms, {
    String? collectionId,
    int limit,
  });

  /// R15: names in the DB that are spelled or pronounced like [term] (a
  /// name the DB does not contain), best first. String similarity only —
  /// never a claim that they refer to the same person.
  Future<List<SimilarName>> similarNames(String term, {int limit});

  /// 0.14: names of the DB (people, speakers, collections) written in
  /// [text], longest first — the names a question mentions.
  Future<List<String>> namesInText(String text, {int limit});

  /// R15: per term, story lines containing it in the whole DB and inside
  /// [scopeId] (equal to the total without a scope).
  Future<Map<String, ({int all, int inScope})>> storyLineTermCounts(
    List<String> terms, {
    String? scopeId,
  });

  /// R17: one read-only `SELECT`/`WITH` query (the agent's `sql` tool), at
  /// most [maxRows] rows; rejections, errors and timeouts come back in
  /// [SqlQueryResult.error]. [game] picks the database where there is more
  /// than one (0.12); null is the default one.
  Future<SqlQueryResult> readOnlySql(String sql, {int maxRows, Game? game});

  /// R17: story lines whose content or speaker contains any of [terms], in
  /// [storyIds] (every story when null), by story then line; at most
  /// [limit] rows.
  Future<List<StoryLineHitRow>> grepStoryLines(
    List<String> terms, {
    Iterable<String>? storyIds,
    int limit,
  });

  /// R17: per story, the number of lines whose content or speaker contains
  /// any of [terms] (stories without a hit are left out).
  Future<Map<String, int>> storyLineHitCounts(
    List<String> terms, {
    Iterable<String>? storyIds,
  });
}

/// R17: one line found by [GameDataRetrieval.grepStoryLines].
class StoryLineHitRow {
  const StoryLineHitRow({
    required this.storyId,
    required this.lineIndex,
    required this.content,
    this.speaker,
  });

  final String storyId;
  final int lineIndex;
  final String? speaker;
  final String content;
}