/// Offline seed database builder.
///
/// Fetches wiki pages, formats, chunks, and writes a bundled seed database
/// and wiki cache zip for first-start distribution.
///
/// Usage:
///   dart run tool/build_seed_database.dart [options]
///
/// Options:
///   --sources=endfield,prts   (default: endfield,prts)
///   --limit=N                 (limit total items per source, for testing)
///   --output=build/seeds      (output directory, default: build/seeds)
///   --force                   (overwrite existing output)
library;
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/core/rag/chunker.dart' show Chunker;
import '../lib/core/wiki/warfarin_crawler.dart';

// ── Entry point ──────────────────────────────────────────────────────────────

void main(List<String> args) async {
  sqfliteFfiInit();

  final sources = _parseArg(args, 'sources', 'endfield,prts').split(',');
  final limit = int.tryParse(_parseArg(args, 'limit', '0')) ?? 0;
  final outputDir = _parseArg(args, 'output', 'build/seeds');
  final force = args.contains('--force');

  final out = Directory(outputDir);
  if (await out.exists()) {
    if (!force) {
      print('Output directory "$outputDir" already exists. Use --force to overwrite.');
      exit(1);
    }
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);

  // ── Initialize database ────────────────────────────────────────────
  final dbPath = p.join(out.path, 'arklores_knowledge.db');
  final db = await _createDatabase(dbPath);

  // ── Crawl, format, chunk, embed, store ──────────────────────────────
  final chunker = Chunker();
  var totalChunks = 0;
  final wikiCacheDir = Directory(p.join(out.path, 'wiki_cache'));

  for (final raw in sources) {
    final trimmed = raw.trim();
    if (trimmed == 'endfield') {
      totalChunks += await _buildEndfield(
        db: db,
        chunker: chunker,
        wikiCacheDir: wikiCacheDir,
        limit: limit,
      );
    } else {
      print('Skipping unsupported source: $trimmed');
    }
  }

  // ── Finalize ────────────────────────────────────────────────────────
  await db.close();

  // Sync write manifest
  final now = DateTime.now().toUtc().toIso8601String();
  final manifest = {
    'schemaVersion': 1,
    'seedVersion': now.substring(0, 10),
    'builtAt': now,
    'embedding': {
      'profileId': 'builtin:builtin-embedding',
      'backend': 'builtin',
      'model': 'builtin-embedding',
      'dimension': 512,
    },
    'chunker': {
      'version': 1,
      'targetTokens': 500,
      'overlapTokens': 50,
      'maxChars': 4000,
    },
    'sources': {
      for (final s in sources) s.trim(): {'enabled': true, 'snapshotAt': now},
    },
  };
  final manifestPath = p.join(out.path, 'seed_manifest.json');
  await File(manifestPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

  // Zip wiki cache
  final zipPath = p.join(out.path, 'wiki_cache.zip');
  await _zipDirectory(wikiCacheDir, zipPath);

  final dbSize = await File(dbPath).length();
  final zipSize = await File(zipPath).length();
  print('''
┌─────────────────────────────────────────────────────────
│ Seed build complete
│   Database: $dbPath ($dbSize bytes)
│   Wiki cache: $zipPath ($zipSize bytes)
│   Manifest: $manifestPath
│   Total chunks: $totalChunks
└─────────────────────────────────────────────────────────''');

  // Copy to assets/seeds for bundling
  final assetDir = Directory('assets/seeds');
  if (!await assetDir.exists()) await assetDir.create(recursive: true);
  await File(dbPath).copy(p.join(assetDir.path, 'arklores_knowledge.db'));
  await File(zipPath).copy(p.join(assetDir.path, 'wiki_cache.zip'));
  await File(manifestPath).copy(p.join(assetDir.path, 'seed_manifest.json'));
  print('Copied seed assets to ${assetDir.path}/');
}

// ─── Endfield source ─────────────────────────────────────────────────────────

Future<int> _buildEndfield({
  required Database db,
  required Chunker chunker,
  required Directory wikiCacheDir,
  required int limit,
}) async {
  final crawler = WarfarinWikiCrawler();
  var totalChunks = 0;

  print('  Fetching operator listings...');
  final operators = await crawler.fetchOperatorListings();
  print('  Fetching lore listings...');
  final lore = await crawler.fetchLoreListings();
  print('  Fetching mission listings...');
  final missions = await crawler.fetchMissionListings();
  print('  Found: ${operators.length} operators, ${lore.length} lore, ${missions.length} missions');

  final items = <_Item>[];
  for (final op in operators) {
    items.add(_Item(slug: op.slug, title: op.name, type: 'operator'));
  }
  for (final l in lore) {
    items.add(_Item(slug: l.slug, title: l.name, type: 'lore'));
  }
  for (final m in missions) {
    items.add(_Item(slug: m.slug, title: m.name, type: 'mission'));
  }

  final toProcess = limit > 0 ? items.take(limit).toList() : items;
  print('  Processing ${toProcess.length} items...');

  for (var i = 0; i < toProcess.length; i++) {
    final item = toProcess[i];
    stdout.write('    [${i + 1}/${toProcess.length}] ${item.type} / ${item.title}... ');

    try {
      // Fetch detail
      dynamic detail;
      if (item.type == 'operator') {
        detail = await crawler.fetchOperatorDetail(item.slug);
      } else if (item.type == 'lore') {
        detail = await crawler.fetchLoreDetail(item.slug);
      } else {
        detail = await crawler.fetchMissionDetail(item.slug);
      }

      // Format
      String markdown;
      if (item.type == 'operator') {
        markdown = crawler.formatOperatorToMarkdown(detail);
      } else if (item.type == 'lore') {
        markdown = crawler.formatLoreToMarkdown(detail);
      } else {
        markdown = crawler.formatMissionToMarkdown(detail);
      }

      if (markdown.isEmpty) {
        print('⚠ empty');
        continue;
      }

      // Save raw markdown to wiki cache
      final typeDir = Directory(p.join(wikiCacheDir.path, 'endfield', '${item.type}s'));
      if (!await typeDir.exists()) await typeDir.create(recursive: true);
      final sanitized = item.slug.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      await File(p.join(typeDir.path, '$sanitized.md')).writeAsString(markdown);

      // Chunk
      final chunks = chunker.chunkByHeadings(markdown, pageTitle: item.title);
      if (chunks.isEmpty) {
        print('⚠ 0 chunks');
        continue;
      }

      final sourceUrl = _endfieldSourceUrl(item.type, item.slug);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.transaction((txn) async {
        for (final c in chunks) {
          await txn.insert('chunks', {
            'id': c.id,
            'source_type': 'wiki',
            'source_url': sourceUrl,
            'wiki': 'endfield',
            'book_id': null,
            'page_title': c.pageTitle,
            'section': c.section,
            'content': c.content,
            'updated_at': now,
            'embedding_status': 'needs_embedding',
            'profile_id': 'builtin:builtin-embedding',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      totalChunks += chunks.length;
      print('${chunks.length} chunks');
    } catch (e) {
      print('✗ $e');
    }

    // Rate limit
    await Future.delayed(const Duration(milliseconds: 500));
  }

  crawler.dispose();
  return totalChunks;
}

String _endfieldSourceUrl(String type, String slug) {
  final path = type == 'operator'
      ? 'operators'
      : type == 'lore'
          ? 'lore'
          : 'missions';
  return 'https://warfarin.wiki/cn/$path/${Uri.encodeComponent(slug)}';
}

// ── Database helpers ─────────────────────────────────────────────────────────

Future<Database> _createDatabase(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
  await file.parent.create(recursive: true);

  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('''
    CREATE TABLE chunks (
      id          TEXT PRIMARY KEY,
      source_type TEXT NOT NULL,
      source_url  TEXT,
      wiki        TEXT,
      book_id     TEXT,
      page_title  TEXT,
      section     TEXT,
      content     TEXT NOT NULL,
      updated_at  INTEGER,
      embedding_status TEXT DEFAULT 'ok',
      profile_id  TEXT DEFAULT 'legacy'
    )
  ''');
  await db.execute('''
    CREATE TABLE chunk_embeddings (
      chunk_id  TEXT PRIMARY KEY,
      embedding BLOB NOT NULL,
      FOREIGN KEY (chunk_id) REFERENCES chunks(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE books (
      id           TEXT PRIMARY KEY,
      file_name    TEXT NOT NULL,
      display_name TEXT,
      chunk_count  INTEGER,
      imported_at  INTEGER,
      profile_id   TEXT DEFAULT 'legacy'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS seed_metadata (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  return db;
}

// ── Zip helper ───────────────────────────────────────────────────────────────

Future<void> _zipDirectory(Directory src, String destPath) async {
  final archive = Archive();
  final files = <File>[];
  await for (final entity in src.list(recursive: true)) {
    if (entity is File) files.add(entity);
  }
  for (final file in files) {
    final relative = p.relative(file.path, from: src.path);
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(relative, bytes.length, bytes));
  }
  final zipData = ZipEncoder().encode(archive);
  if (zipData != null) {
    await File(destPath).writeAsBytes(zipData);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _parseArg(List<String> args, String key, String defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('--$key=')) return arg.substring('--$key='.length);
  }
  return defaultValue;
}

class _Item {
  final String slug;
  final String title;
  final String type;
  const _Item({required this.slug, required this.title, required this.type});
}
