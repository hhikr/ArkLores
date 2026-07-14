/// Offline seed database builder.
///
/// Fetches wiki pages (Endfield + PRTS), formats, chunks, and writes a bundled
/// seed database and wiki cache zip for first-start distribution.
///
/// Since TFLite native libraries are not available in `dart run` CLI context,
/// chunks are written with `embedding_status = 'pending_embedding'`. On the
/// app's first launch, the builtin embedding model generates the vectors.
///
/// Usage:
///   dart run tool/build_seed_database.dart [options]
///
/// Options:
///   --sources=endfield,prts   (default: endfield)
///   --prts-categories=...     (default: Category:干员,Category:剧情)
///   --limit=N                 (limit total items per source, 0=unlimited)
///   --embed-batch-size=N      (default: 16)
///   --crawl-delay-ms=N        (default: 500)
///   --max-chunks-per-page=N   (default: 120)
///   --output=build/seeds      (output directory)
///   --force                   (overwrite existing output)
///   --resume                  (reuse existing output and skip completed pages)
///   --allow-large-pages       (write pages over max-chunks-per-page)
///   --no-copy-assets          (skip copying to assets/seeds/)
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/core/rag/chunker.dart' show Chunker;
import '../lib/core/wiki/warfarin_crawler.dart';
import '../lib/core/wiki/wiki_crawler.dart';
import '../lib/core/wiki/wiki_models.dart';
import '../lib/core/wiki/prts_utils.dart' as prts;

// ── Entry point ──────────────────────────────────────────────────────────────

void main(List<String> args) async {
  sqfliteFfiInit();
  final cfg = _Config.parse(args);

  if (cfg.force && cfg.resume) {
    print('Cannot use --force and --resume together.');
    exit(1);
  }

  final out = Directory(cfg.outputDir);
  if (await out.exists()) {
    if (cfg.force) {
      await out.delete(recursive: true);
    } else if (!cfg.resume) {
      print(
          'Output directory "${cfg.outputDir}" already exists. Use --force or --resume.');
      exit(1);
    }
  }
  await out.create(recursive: true);

  print('''
\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
\u2551 Seed Database Builder
\u2551   Sources: ${cfg.sources.join(', ')}
\u2551   Limit:   ${cfg.limit > 0 ? cfg.limit.toString() : 'unlimited'}
\u2551   Output:  ${cfg.outputDir}
\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550''');

  final dbPath = p.join(out.path, 'arklores_knowledge.db');
  final db = await _openOrCreateDatabase(dbPath, resume: cfg.resume);
  final chunker = Chunker();
  final wikiCacheDir = Directory(p.join(out.path, 'wiki_cache'));
  final allStats = <_SrcStats>[];

  for (final src in cfg.sources) {
    final s = src.trim();
    if (s == 'endfield') {
      allStats.add(await _buildEndfield(db, chunker, wikiCacheDir, cfg));
    } else if (s == 'prts') {
      allStats.add(await _buildPrts(db, chunker, wikiCacheDir, cfg));
    } else {
      print('Unknown source: $s');
    }
  }

  final now = DateTime.now().toUtc().toIso8601String();
  await _writeSeedMetadata(db, allStats, now);
  await db.close();

  // Compress the DB for GitHub release asset distribution. The raw DB is too
  // large for normal Git storage and should not be copied into Flutter assets.
  final dbGzPath = '$dbPath.gz';
  final dbGzBytes = gzip.encode(await File(dbPath).readAsBytes());
  await File(dbGzPath).writeAsBytes(dbGzBytes, flush: true);
  final dbGzSha256 = sha256.convert(dbGzBytes).toString();

  // Manifest
  final manifest = _buildManifest(allStats, now);
  final manifestPath = p.join(out.path, 'seed_manifest.json');
  await File(manifestPath)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

  // Zip wiki cache
  final zipPath = p.join(out.path, 'wiki_cache.zip');
  await _zipDirectory(wikiCacheDir, zipPath);

  final dbSize = await File(dbPath).length();
  final dbGzSize = await File(dbGzPath).length();
  final zipSize = await File(zipPath).length();
  var totalChunks = 0;
  for (final s in allStats) totalChunks += s.chunkCount;

  print('''
\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
\u2551 Seed build complete
\u2551   Database: $dbPath ($dbSize bytes)
\u2551   Wiki cache: $zipPath ($zipSize bytes)
\u2551   Total chunks: $totalChunks
${allStats.map((s) => '  \u2551   ${s.name}: ${s.pageCount} pages, ${s.chunkCount} chunks').join('\n')}
\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550''');

  print('Database gzip: $dbGzPath ($dbGzSize bytes)');
  print('Database gzip SHA256: $dbGzSha256');

  if (cfg.copyToAssets) {
    final assetDir = Directory('assets/seeds');
    if (!await assetDir.exists()) await assetDir.create(recursive: true);
    await File(dbGzPath)
        .copy(p.join(assetDir.path, 'arklores_knowledge.db.gz'));
    await File(zipPath).copy(p.join(assetDir.path, 'wiki_cache.zip'));
    await File(manifestPath).copy(p.join(assetDir.path, 'seed_manifest.json'));
    print('Copied release seed artifacts to ${assetDir.path}/');
  }
}

// ─── Shared store pipeline ───────────────────────────────────────────────────

class _SrcStats {
  final String name;
  int pageCount = 0;
  int chunkCount = 0;
  _SrcStats(this.name);
}

/// Saves a formatted markdown page: cache file + chunk + no-embed marker.
Future<int> _storePage({
  required Database db,
  required Directory wikiCacheDir,
  required Chunker chunker,
  required String wiki,
  required String title,
  required String markdown,
  required String sourceUrl,
  required int maxChunksPerPage,
  required bool allowLargePages,
}) async {
  if (markdown.trim().isEmpty) return 0;

  // Save raw markdown
  final sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final mdFile = File(p.join(wikiCacheDir.path, wiki, '$sanitized.md'));
  await mdFile.parent.create(recursive: true);
  await mdFile.writeAsString(markdown);

  // Chunk
  final chunks = chunker.chunkByHeadings(markdown, pageTitle: title);
  if (chunks.isEmpty) return 0;
  if (!allowLargePages && chunks.length > maxChunksPerPage) {
    print(
      '⚠ skipped large page: $title produced ${chunks.length} chunks '
      '(limit $maxChunksPerPage)',
    );
    return 0;
  }

  // Write chunks (no embeddings yet — app fills on first launch)
  final updatedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await db.transaction((txn) async {
    for (final c in chunks) {
      await txn.insert(
          'chunks',
          {
            'id': c.id,
            'source_type': 'wiki',
            'source_url': sourceUrl,
            'wiki': wiki,
            'book_id': null,
            'page_title': c.pageTitle,
            'section': c.section,
            'content': c.content,
            'updated_at': updatedAt,
            'embedding_status': 'pending_embedding',
            'profile_id': 'builtin:builtin-embedding',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });

  return chunks.length;
}

Future<void> _writeSeedMetadata(
    Database db, List<_SrcStats> allStats, String now) async {
  final metadata = <String, String>{
    'schema_version': '1',
    'seed_version': now.substring(0, 10),
    'embedding_profile_id': 'builtin:builtin-embedding',
    'embedding_dimension': '512',
    'embedding_model': 'builtin-embedding',
    'chunker_version': '1',
    'built_at': now,
  };
  for (final s in allStats) {
    metadata['source_${s.name}_page_count'] = s.pageCount.toString();
    metadata['source_${s.name}_chunk_count'] = s.chunkCount.toString();
  }
  for (final e in metadata.entries) {
    await db.insert('seed_metadata', {'key': e.key, 'value': e.value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Map<String, dynamic> _buildManifest(List<_SrcStats> allStats, String now) {
  return {
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
      for (final s in allStats)
        s.name: {
          'enabled': true,
          'pageCount': s.pageCount,
          'chunkCount': s.chunkCount,
          'snapshotAt': now,
        },
    },
  };
}

// ─── Endfield builder ─────────────────────────────────────────────────────────

Future<_SrcStats> _buildEndfield(
    Database db, Chunker chunker, Directory wikiCacheDir, _Config cfg) async {
  final stats = _SrcStats('endfield');
  final crawler = WarfarinWikiCrawler();
  final delay = Duration(milliseconds: cfg.crawlDelayMs);

  print('  Fetching Endfield listings...');
  final operators = await crawler.fetchOperatorListings();
  final lore = await crawler.fetchLoreListings();
  final missions = await crawler.fetchMissionListings();
  print(
      '  Found: ${operators.length}op, ${lore.length}lore, ${missions.length}mission');

  final items = <_Item>[];
  for (final op in operators) {
    items.add(_Item(op.slug, op.name, 'operator'));
  }
  for (final l in lore) {
    items.add(_Item(l.slug, l.name, 'lore'));
  }
  for (final m in missions) {
    items.add(_Item(m.slug, m.name, 'mission'));
  }

  final toProcess = cfg.limit > 0 ? items.take(cfg.limit).toList() : items;
  print('  Processing ${toProcess.length} items...');

  for (var i = 0; i < toProcess.length; i++) {
    final item = toProcess[i];
    stdout.write(
        '    [${i + 1}/${toProcess.length}] ${item.type} / ${item.title}... ');

    try {
      if (cfg.resume && await _pageExists(db, 'endfield', item.title)) {
        print('skipped (exists)');
        continue;
      }

      dynamic detail;
      if (item.type == 'operator') {
        detail = await crawler.fetchOperatorDetail(item.slug);
      } else if (item.type == 'lore') {
        detail = await crawler.fetchLoreDetail(item.slug);
      } else {
        detail = await crawler.fetchMissionDetail(item.slug);
      }

      final markdown = item.type == 'operator'
          ? crawler.formatOperatorToMarkdown(detail)
          : item.type == 'lore'
              ? crawler.formatLoreToMarkdown(detail)
              : crawler.formatMissionToMarkdown(detail);

      final n = await _storePage(
        db: db,
        wikiCacheDir: wikiCacheDir,
        chunker: chunker,
        wiki: 'endfield',
        title: item.title,
        markdown: markdown,
        sourceUrl: _endfieldUrl(item.type, item.slug),
        maxChunksPerPage: cfg.maxChunksPerPage,
        allowLargePages: cfg.allowLargePages,
      );
      if (n > 0) {
        stats.pageCount++;
        stats.chunkCount += n;
        print('$n chunks');
      } else {
        print('\u26a0 empty');
      }
    } catch (e) {
      print('\u2717 $e');
    }
    await Future.delayed(delay);
  }

  crawler.dispose();
  return stats;
}

String _endfieldUrl(String type, String slug) {
  final path = type == 'operator'
      ? 'operators'
      : type == 'lore'
          ? 'lore'
          : 'missions';
  return 'https://warfarin.wiki/cn/$path/${Uri.encodeComponent(slug)}';
}

// ─── PRTS builder ────────────────────────────────────────────────────────────

Future<_SrcStats> _buildPrts(
    Database db, Chunker chunker, Directory wikiCacheDir, _Config cfg) async {
  final stats = _SrcStats('prts');
  final crawler = MediaWikiCrawler();
  final delay = Duration(milliseconds: cfg.crawlDelayMs);

  final categoryNames = cfg.prtsCategories.split(',');
  print('  Fetching PRTS categories: ${categoryNames.join(', ')}');

  final operatorTitles = <String>{};
  final storyTitles = <String>{};
  for (final cat in categoryNames) {
    final trimmed = cat.trim();
    if (trimmed.isEmpty) continue;
    final titles = await crawler.fetchCategoryTitles(
      site: WikiSite.prts,
      categoryName: trimmed,
    );
    if (trimmed == 'Category:干员') {
      operatorTitles.addAll(titles);
    } else {
      storyTitles
          .addAll(titles.where((title) => !_isPrtsStandaloneRecord(title)));
    }
    print('    $trimmed: ${titles.length} pages');
  }

  final allTitles = [...operatorTitles, ...storyTitles];
  print('  Total titles to process: ${allTitles.length}');

  final toProcess =
      cfg.limit > 0 ? allTitles.take(cfg.limit).toList() : allTitles;

  for (var i = 0; i < toProcess.length; i++) {
    final title = toProcess[i];
    stdout.write('    [${i + 1}/${toProcess.length}] $title... ');

    try {
      // Skip list/nav pages
      if (_shouldSkipPrtsStandalonePage(title)) {
        print(_isPrtsStandaloneRecord(title)
            ? '⚠ skipped (operator record page; included via operator assembly)'
            : '⚠ skipped (nav)');
        continue;
      }

      if (cfg.resume && await _pageExists(db, 'prts', title)) {
        print('skipped (exists)');
        continue;
      }

      final isOperator = operatorTitles.contains(title);
      String markdown;

      if (isOperator) {
        // Fetch operator sub-pages
        final allOpTitles = [title, '$title/语音记录', '${title}的信物'];
        final wikitexts =
            await crawler.fetchRawWikitexts(WikiSite.prts, allOpTitles);
        final mainPage = wikitexts[title];
        final voicePage = wikitexts['$title/语音记录'];
        final tokenPage = wikitexts['${title}的信物'];

        if (mainPage == null) {
          print('\u2717 main page not found');
          continue;
        }

        // Parse record story pages
        final recordStoryTitles = <String>{};
        final miluTemplates =
            prts.parseAllTemplates(mainPage.content, '干员密录/list');
        for (final m in miluTemplates) {
          for (int j = 1; j <= 20; j++) {
            final rawPage = m['storyTxt$j'] ?? '';
            if (rawPage.isEmpty) break;
            final resolved =
                rawPage.replaceAll('{{FULLPAGENAME}}', title).trim();
            if (resolved.isNotEmpty) recordStoryTitles.add(resolved);
          }
        }

        final recordStoryWikitexts = <String, String>{};
        if (recordStoryTitles.isNotEmpty) {
          final recordPages = await crawler.fetchRawWikitexts(
              WikiSite.prts, recordStoryTitles.toList());
          for (final e in recordPages.entries) {
            if (e.value.content.isNotEmpty) {
              recordStoryWikitexts[e.value.title] = e.value.content;
            }
          }
        }

        markdown = prts.assembleOperatorMarkdown(
          title,
          mainPage.content,
          voicePage?.content ?? '',
          tokenPage?.content ?? '',
          recordStoryWikitexts: recordStoryWikitexts,
        );
      } else {
        // Story page
        final pages = await crawler.fetchRawWikitexts(WikiSite.prts, [title]);
        final page = pages[title];
        if (page == null || page.content.trim().isEmpty) {
          print('\u2717 not found');
          continue;
        }
        markdown = prts.cleanStoryContent(page.content);
      }

      if (markdown.trim().isEmpty) {
        print('\u26a0 empty markdown');
        continue;
      }

      final sourceUrl = 'https://prts.wiki/w/${Uri.encodeComponent(title)}';
      final n = await _storePage(
        db: db,
        wikiCacheDir: wikiCacheDir,
        chunker: chunker,
        wiki: 'prts',
        title: title,
        markdown: markdown,
        sourceUrl: sourceUrl,
        maxChunksPerPage: cfg.maxChunksPerPage,
        allowLargePages: cfg.allowLargePages,
      );
      if (n > 0) {
        stats.pageCount++;
        stats.chunkCount += n;
        print('$n chunks');
      } else {
        print('\u26a0 0 chunks');
      }
    } catch (e) {
      print('\u2717 $e');
    }
    await Future.delayed(delay);
  }

  return stats;
}

// ── Database ─────────────────────────────────────────────────────────────────

Future<Database> _openOrCreateDatabase(String path,
    {required bool resume}) async {
  final absolutePath = p.absolute(path);
  final file = File(absolutePath);
  if (!resume && await file.exists()) await file.delete();
  await file.parent.create(recursive: true);

  final db = await databaseFactoryFfi.openDatabase(absolutePath);
  await db.setVersion(1);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS chunks (
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
    CREATE TABLE IF NOT EXISTS chunk_embeddings (
      chunk_id  TEXT PRIMARY KEY,
      embedding BLOB NOT NULL,
      FOREIGN KEY (chunk_id) REFERENCES chunks(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS books (
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

// ── Helpers ──────────────────────────────────────────────────────────────────

class _Config {
  final List<String> sources;
  final int limit;
  final int embedBatchSize;
  final int crawlDelayMs;
  final int maxChunksPerPage;
  final String outputDir;
  final bool force;
  final bool resume;
  final bool copyToAssets;
  final bool failOnEmptyChunks;
  final bool allowLargePages;
  final String prtsCategories;

  const _Config({
    required this.sources,
    this.limit = 0,
    this.embedBatchSize = 16,
    this.crawlDelayMs = 500,
    this.maxChunksPerPage = 120,
    this.outputDir = 'build/seeds',
    this.force = false,
    this.resume = false,
    this.copyToAssets = true,
    this.failOnEmptyChunks = false,
    this.allowLargePages = false,
    this.prtsCategories = 'Category:干员,Category:剧情',
  });

  factory _Config.parse(List<String> args) {
    String g(String k, [String d = '']) =>
        args
            .where((a) => a.startsWith('--$k='))
            .map((a) => a.split('=').skip(1).join('='))
            .firstOrNull ??
        d;
    final sources = g('sources', 'endfield')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return _Config(
      sources: sources,
      limit: int.tryParse(g('limit', '0')) ?? 0,
      embedBatchSize: int.tryParse(g('embed-batch-size', '16')) ?? 16,
      crawlDelayMs: int.tryParse(g('crawl-delay-ms', '500')) ?? 500,
      maxChunksPerPage: int.tryParse(g('max-chunks-per-page', '120')) ?? 120,
      outputDir: g('output', 'build/seeds'),
      force: args.contains('--force'),
      resume: args.contains('--resume'),
      copyToAssets: !args.contains('--no-copy-assets'),
      failOnEmptyChunks: args.contains('--fail-on-empty'),
      allowLargePages: args.contains('--allow-large-pages'),
      prtsCategories: g('prts-categories', 'Category:干员,Category:剧情'),
    );
  }
}

Future<bool> _pageExists(Database db, String wiki, String title) async {
  final rows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS c FROM chunks
    WHERE source_type = 'wiki'
      AND wiki = ?
      AND page_title = ?
      AND profile_id = 'builtin:builtin-embedding'
      AND embedding_status IN ('pending_embedding', 'ok')
    ''',
    [wiki, title],
  );
  return (rows.first['c'] as int? ?? 0) > 0;
}

bool _isPrtsStandaloneRecord(String title) => title.contains('/干员密录/');

bool _shouldSkipPrtsStandalonePage(String title) {
  return _isPrtsStandaloneRecord(title) ||
      title.contains('一览') ||
      title.contains('列表') ||
      title.contains('导航') ||
      title.contains('Category:');
}

class _Item {
  final String slug;
  final String title;
  final String type;
  const _Item(this.slug, this.title, this.type);
}

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
