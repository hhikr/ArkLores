import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart' as sqflite;

class PortraitLayers {
  const PortraitLayers({
    required this.base,
    this.patch,
    this.x = 0,
    this.y = 0,
    this.blank = false,
  });
  final Uint8List base;
  final Uint8List? patch;
  final int x, y;
  final bool blank;
}

class StoryArtImage {
  const StoryArtImage(
      this.webp, this.width, this.height, this.category, this.solid,);
  final Uint8List webp;
  final int width, height;
  final String category;
  final bool solid;
}

class StoryArtTitle {
  const StoryArtTitle(this.title, this.description, this.groupKey);
  final String? title, description, groupKey;
}

class StoryArtPack {
  StoryArtPack(this.path);
  final String path;
  sqflite.Database? _db;
  FileStat? _stamp;
  Future<void> _tail = Future.value();

  // Serialize reads and close so replacement cannot close a query's handle.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<sqflite.Database?> _open() async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      await _close();
      return null;
    }
    if (_db?.isOpen == true &&
        _stamp?.size == stat.size &&
        _stamp?.modified == stat.modified &&
        _stamp?.changed == stat.changed) {
      return _db;
    }
    await _close();
    _db =
        await sqflite.openDatabase(path, readOnly: true, singleInstance: false);
    _stamp = stat;
    return _db;
  }

  Future<bool> get installed => _serial(() async {
        try {
          final db = await _open();
          if (db == null) return false;
          final rows = await db.query('pack_manifest',
              where: 'key = ?', whereArgs: ['pack_version'],);
          return rows.isNotEmpty && rows.first['value'] == '2';
        } catch (_) {
          await _close();
          return false;
        }
      });

  Future<Map<String, String>> manifest() => _serial(() async {
        final db = await _open();
        if (db == null) return {};
        return {
          for (final row in await db.query('pack_manifest'))
            row['key'] as String: row['value'] as String,
        };
      });

  /// The layers to draw [sprite]; null when the pack has no row for it.
  Future<PortraitLayers?> layers(String sprite) => _serial(() async {
        final db = await _open();
        if (db == null) return null;
        final rows = await db
            .query('portrait_images', where: 'sprite = ?', whereArgs: [sprite]);
        if (rows.isEmpty) return null;
        final row = rows.single;
        if (row['blank'] == 1) {
          return PortraitLayers(base: Uint8List(0), blank: true);
        }
        final baseId = row['base_id'];
        if (baseId == null) {
          return PortraitLayers(base: row['webp'] as Uint8List);
        }
        final bases = await db
            .query('portrait_bases', where: 'base_id = ?', whereArgs: [baseId]);
        return PortraitLayers(
          base: bases.single['webp'] as Uint8List,
          patch: row['webp'] as Uint8List?,
          x: row['x'] as int? ?? 0,
          y: row['y'] as int? ?? 0,
        );
      });

  Future<StoryArtImage?> artImage(String imageId, String kind) =>
      _serial(() async {
        final db = await _open();
        if (db == null) return null;
        final tables = await db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'art_images'",);
        if (tables.isEmpty) return null;
        final categories = switch (kind) {
          'background' || 'scene' => ['background', 'illustration', 'item'],
          'item' => ['item', 'illustration', 'background'],
          _ => ['illustration', 'background', 'item'],
        };
        for (final category in categories) {
          final rows = await db.query('art_images',
              where: 'category = ? AND image_id = ?',
              whereArgs: [category, imageId],
              limit: 1,);
          if (rows.isNotEmpty) {
            final row = rows.first;
            return StoryArtImage(row['webp'] as Uint8List, row['width'] as int,
                row['height'] as int, category, row['solid'] == 1,);
          }
        }
        return null;
      });

  Future<StoryArtTitle?> artTitle(String imageId) => _serial(() async {
        final db = await _open();
        if (db == null) return null;
        final tables = await db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'art_titles'",);
        if (tables.isEmpty) return null;
        final rows = await db.query('art_titles',
            where: 'image_id = ?', whereArgs: [imageId], limit: 1,);
        if (rows.isEmpty) return null;
        final row = rows.first;
        return StoryArtTitle(row['title'] as String?,
            row['description'] as String?, row['group_key'] as String?,);
      });

  Future<void> _close() async {
    await _db?.close();
    _db = null;
    _stamp = null;
  }

  Future<void> close() => _serial(_close);
}
