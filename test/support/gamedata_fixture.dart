// GameData databases for tests, always with the production schema
// (`createGamedataSchema`), never a hand-written copy: a copy drifts from the
// real tables (other columns, another FTS tokenizer) and the tests then pass
// on a database the app never sees.
import 'package:arklores/core/gamedata/build/gamedata_schema.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Manifest of a valid schema-5 database: the counts the installer and the
/// builder check are all positive.
const Map<String, String> validManifest = {
  'schema_version': '$gamedataSchemaVersion',
  'language': gamedataLanguage,
  'entity_count': '1',
  'normalized_record_count': '1',
  'lore_chunk_count': '1',
  'story_line_count': '1',
};

/// Creates an empty GameData database at [path] (or in memory) with the
/// production schema, the optional story catalog / vector tables, and
/// [manifest]. The caller closes it.
Future<Database> createGameDataDb(
  String path, {
  Map<String, String> manifest = validManifest,
  bool catalog = false,
  bool vectors = false,
}) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await createGamedataSchema(db);
  if (catalog) await db.execute(storyCatalogDdl);
  if (vectors) await db.execute(storyChunkVectorsDdl);
  await writeGamedataManifest(db, manifest);
  return db;
}

/// Inserts one story: its scope row and its lines. A line written
/// `说话人：文字` gets that speaker; other lines are narration.
Future<void> insertStory(
  Database db,
  String storyId,
  List<String> lines, {
  String scopeType = 'activity',
  String? scopeId,
  String kind = 'dialogue',
}) async {
  await db.insert('story_scopes', {
    'story_id': storyId,
    'scope_type': scopeType,
    'scope_id': scopeId ?? storyId.split('/').reversed.skip(1).first,
    'source_path': 'zh_CN/gamedata/story/$storyId',
  });
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i];
    final colon = text.indexOf('：');
    final speaker = colon > 0 && colon <= 12 ? text.substring(0, colon) : null;
    await db.insert('story_lines', {
      'id': '$storyId#$i',
      'game': gamedataGame,
      'story_id': storyId,
      'line_index': i,
      'speaker': speaker,
      'content': speaker == null ? text : text.substring(colon + 1),
      'source_path': 'zh_CN/gamedata/story/$storyId',
      'kind': kind,
    });
  }
}

/// Inserts an entity with its canonical name and [aliases].
Future<void> insertEntity(
  Database db,
  String id,
  String name, {
  String type = 'operator',
  String sourceType = 'operator_profile',
  Map<String, double> aliases = const {},
  String sourcePath = 'zh_CN/gamedata/excel/character_table.json',
}) async {
  await db.insert('entities', {
    'id': id,
    'name': name,
    'aliases': '[${aliases.keys.map((a) => '"$a"').join(',')}]',
    'entity_type': type,
    'source_type': sourceType,
    'game': gamedataGame,
    'source_path': sourcePath,
  });
  await db.insert('entity_aliases', {
    'alias': name,
    'entity_id': id,
    'alias_type': 'canonical',
    'confidence': 1.0,
    'source_path': sourcePath,
  });
  for (final MapEntry(key: alias, value: confidence) in aliases.entries) {
    await db.insert('entity_aliases', {
      'alias': alias,
      'entity_id': id,
      'alias_type': 'alias',
      'confidence': confidence,
      'source_path': sourcePath,
    });
  }
}

/// Inserts a `normalized_records` row; [fields] fill the optional columns.
Future<void> insertRecord(
  Database db,
  String id, {
  required String contentType,
  required String content,
  String category = 'story',
  String subtype = 'text',
  String sourcePath = 'zh_CN/gamedata/excel/test_table.json',
  Map<String, Object?> fields = const {},
}) =>
    db.insert('normalized_records', {
      'id': id,
      'game': gamedataGame,
      'language': gamedataLanguage,
      'category': category,
      'subtype': subtype,
      'content_type': contentType,
      'content': content,
      'source_path': sourcePath,
      ...fields,
    });
