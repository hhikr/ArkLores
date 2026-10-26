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

class PortraitPack {
  PortraitPack(this.path);
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
          return (await db.rawQuery(
                  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pack_manifest'",))
              .isNotEmpty;
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

  Future<void> _close() async {
    await _db?.close();
    _db = null;
    _stamp = null;
  }

  Future<void> close() => _serial(_close);
}
