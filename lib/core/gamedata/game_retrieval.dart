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

/// 0.14: one record found by [GameDataRetrieval.searchRecordsLike].
class RecordHit {
  const RecordHit({
    required this.id,
    required this.category,
    required this.subtype,
    required this.title,
    required this.snippet,
    required this.score,
    this.owner = '',
  });
  final String id;
  final String category;
  final String subtype;
  final String title;

  /// Whose record it is (the name of its `entity_id`: the operator of a
  /// voice line, the owner of a module), or '' when it has none.
  final String owner;

  /// The text around the first matched term.
  final String snippet;

  /// From [GameDataRetrieval.searchRecordsLike], per term: 3 when the
  /// record is about what it names (`entity_name`), 2 when its title has
  /// it, 1 when its text does. From
  /// [GameDataRetrieval.searchRecordsByVector]: the cosine similarity.
  final double score;
}

/// 0.14: one record read whole ([GameDataRetrieval.readRecord]).
class RecordText {
  const RecordText({
    required this.id,
    required this.category,
    required this.subtype,
    required this.title,
    required this.owner,
    required this.content,
  });
  final String id;
  final String category;
  final String subtype;
  final String title;

  /// See [RecordHit.owner].
  final String owner;
  final String content;
}

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
  /// `activity:act21mini`). Locating hints, not evidence. [termLines], when
  /// given, receives how many lines each term matches (0.14; added to what
  /// it holds, so one map can collect several games).
  Future<List<StoryLineHit>> searchStoryLinesLike(
    List<String> terms, {
    String? scopeId,
    int storyLimit,
    int linesPerStory,
    Map<String, int>? termLines,
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

  /// R15: names in the DB that are spelled or pronounced like [term] (a
  /// name the DB does not contain), best first. String similarity only —
  /// never a claim that they refer to the same person.
  Future<List<SimilarName>> similarNames(String term, {int limit});

  /// 0.14: whether [term] is a name the DB has, written exactly so (an
  /// operator, a speaker, a collection …). [similarNames] leaves the term
  /// itself out, so its result alone cannot tell "not there" from "there".
  Future<bool> hasName(String term);

  /// 0.14: the record with [id] (`normalized_records`, or an operator's
  /// file in `entity_documents`), or null.
  Future<RecordText?> readRecord(String id);

  /// 0.14: records outside the story text (`normalized_records`: archives,
  /// profiles, voice lines, item and enemy texts) whose title or text
  /// contains any of [terms] — title matches first, then by how many terms
  /// they hold; each with the text around its first match.
  /// [weights] scales what each term counts for (a common word less).
  Future<List<RecordHit>> searchRecordsLike(
    List<String> terms, {
    int limit,
    Map<String, double>? weights,
  });

  /// 0.14: records closest in meaning to [queryVector] (an embedding from
  /// the model in [storyVectorInfo]), each with the part of its text that
  /// matched; empty when the DB has no record vectors. Locating hints.
  Future<List<RecordHit>> searchRecordsByVector(
    List<double> queryVector, {
    int limit,
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