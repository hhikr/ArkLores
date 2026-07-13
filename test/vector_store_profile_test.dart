import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arklores/core/rag/chunker.dart';
import 'package:arklores/core/rag/vector_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  PathProviderPlatform? previousPathProvider;
  late sqflite.DatabaseFactory? previousDatabaseFactory;

  setUp(() async {
    sqfliteFfiInit();
    try {
      previousDatabaseFactory = sqflite.databaseFactory;
    } catch (_) {
      previousDatabaseFactory = null;
    }
    sqflite.databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp('arklores_vector_store_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (previousPathProvider != null) {
      PathProviderPlatform.instance = previousPathProvider!;
    }
    if (previousDatabaseFactory != null) {
      sqflite.databaseFactory = previousDatabaseFactory!;
    }
    await tempDir.delete(recursive: true);
  });

  test('search, stats, books, and delete are scoped by profile', () async {
    final store = VectorStore();
    addTearDown(store.dispose);

    await store.insertChunk(
      Chunk(
        id: 'api-chunk',
        content: 'API profile lore',
        pageTitle: 'API Page',
        section: 'Overview',
        seqIndex: 0,
        tokenCount: 3,
      ),
      [1, 0, 0],
      sourceType: 'wiki',
      wiki: 'prts',
      profileId: 'api-profile',
    );
    await store.insertChunk(
      Chunk(
        id: 'builtin-chunk',
        content: 'Builtin profile lore',
        pageTitle: 'Builtin Page',
        section: 'Overview',
        seqIndex: 0,
        tokenCount: 3,
      ),
      [0, 1, 0],
      sourceType: 'book',
      bookId: 'builtin-book',
      profileId: 'builtin-profile',
    );
    await store.upsertBook(
      id: 'api-book',
      fileName: 'api.txt',
      profileId: 'api-profile',
    );
    await store.upsertBook(
      id: 'builtin-book',
      fileName: 'builtin.txt',
      profileId: 'builtin-profile',
    );

    final apiResults = await store.search([1, 0, 0], profileId: 'api-profile');
    final builtinResults =
        await store.search([1, 0, 0], profileId: 'builtin-profile');
    final apiStats = await store.getStats(profileId: 'api-profile');
    final builtinStats = await store.getStats(profileId: 'builtin-profile');
    final apiBooks = await store.getBooks(profileId: 'api-profile');
    final builtinBooks = await store.getBooks(profileId: 'builtin-profile');

    expect(apiResults.map((result) => result.chunk.id), ['api-chunk']);
    expect(builtinResults.map((result) => result.chunk.id), ['builtin-chunk']);
    expect(apiStats.totalChunks, 1);
    expect(apiStats.wikiChunks, 1);
    expect(apiStats.bookChunks, 0);
    expect(apiStats.totalBooks, 1);
    expect(builtinStats.totalChunks, 1);
    expect(builtinStats.wikiChunks, 0);
    expect(builtinStats.bookChunks, 1);
    expect(builtinStats.totalBooks, 1);
    expect(apiBooks.single['id'], 'api-book');
    expect(builtinBooks.single['id'], 'builtin-book');

    await store.deleteProfileData('api-profile');

    expect(await store.search([1, 0, 0], profileId: 'api-profile'), isEmpty);
    expect(
      (await store.search([0, 1, 0], profileId: 'builtin-profile'))
          .single
          .chunk
          .id,
      'builtin-chunk',
    );
    expect((await store.getBooks(profileId: 'api-profile')), isEmpty);
    expect((await store.getBooks(profileId: 'builtin-profile')).single['id'],
        'builtin-book');
  });
}

class _FakePathProvider extends PathProviderPlatform {
  final String path;

  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
