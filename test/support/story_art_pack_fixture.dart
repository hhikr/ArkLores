import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Test-only PNG bytes in the webp columns: Flutter decodes either format.
Future<File> createStoryArtPack(
  Directory dir, {
  String name = 'pack.db',
  String version = '2',
  bool empty = false,
  String commit = 'fixture',
}) async {
  final file = File('${dir.path}/$name');
  final db = await databaseFactoryFfi.openDatabase(file.path);
  try {
    await db.execute(
        'CREATE TABLE pack_manifest (key TEXT PRIMARY KEY, value TEXT NOT NULL)',);
    await db.execute('''CREATE TABLE portrait_bases (base_id TEXT PRIMARY KEY,
      width INTEGER NOT NULL, height INTEGER NOT NULL, sprite TEXT NOT NULL, webp BLOB NOT NULL)''');
    await db.execute('''CREATE TABLE portrait_images (sprite TEXT PRIMARY KEY,
      base_id TEXT, x INTEGER, y INTEGER, width INTEGER NOT NULL, height INTEGER NOT NULL,
      blank INTEGER NOT NULL, webp BLOB)''');
    await db.execute(
        'CREATE TABLE pack_groups (base_id TEXT PRIMARY KEY, signature TEXT NOT NULL)',);
    for (final e in {
      'pack_version': version,
      'source': 'arkwaifu',
      'source_artwork_version': 'test',
      'kb_commit': commit,
      'sprite_count': empty ? '0' : '4',
      'missing_count': '0',
      'max_height': '4',
      'built_at': '2026-10-26',
    }.entries) {
      await db.insert('pack_manifest', {'key': e.key, 'value': e.value});
    }
    await db.execute('CREATE TABLE art_images (category TEXT NOT NULL, image_id TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, solid INTEGER NOT NULL, webp BLOB NOT NULL, PRIMARY KEY(category, image_id))');
    await db.execute('CREATE TABLE art_titles (image_id TEXT PRIMARY KEY, title TEXT, description TEXT, group_key TEXT)');
    if (empty) return file;
    Uint8List png(int width, int height, img.Color color) => Uint8List.fromList(
          img.encodePng(
            img.fill(
              img.Image(width: width, height: height, numChannels: 4),
              color: color,
            ),
          ),
        );
    final base = png(4, 4, img.ColorRgba8(80, 100, 120, 255));
    for (final entry in [('background', 'scene', 4, 4), ('illustration', 'cg', 4, 4), ('illustration', 'tall', 4, 8), ('item', 'item', 4, 4), ('illustration', 'scene', 4, 4)]) {
      await db.insert('art_images', {'category': entry.$1, 'image_id': entry.$2, 'width': entry.$3, 'height': entry.$4, 'solid': 0, 'webp': png(entry.$3, entry.$4, img.ColorRgba8(80, 100, 120, 255))});
    }
    await db.insert('art_titles', {'image_id': 'cg', 'title': 'Title', 'description': 'Description', 'group_key': 'group'});

    final patchImage = img.Image(width: 2, height: 2, numChannels: 4);
    img.fill(patchImage, color: img.ColorRgba8(200, 40, 60, 255));
    patchImage.setPixelRgba(0, 0, 0, 0, 0, 0);
    await db.insert('portrait_bases', {
      'base_id': 'test\$1',
      'width': 4,
      'height': 4,
      'sprite': 'same',
      'webp': base,
    });
    Future<void> image(
      String sprite, {
      String? baseId,
      Uint8List? bytes,
      int? x,
      int? y,
      int blank = 0,
      int size = 4,
    }) async {
      await db.insert('portrait_images', {
        'sprite': sprite,
        'base_id': baseId,
        'webp': bytes,
        'x': x,
        'y': y,
        'width': size,
        'height': size,
        'blank': blank,
      });
    }

    await image('same', baseId: 'test\$1');
    await image('patch',
        baseId: 'test\$1',
        bytes: Uint8List.fromList(img.encodePng(patchImage)),
        x: 1,
        y: 1,
        size: 2,);
    await image('whole', bytes: png(4, 4, img.ColorRgba8(30, 50, 70, 255)));
    await image('blank', blank: 1);
  } finally {
    await db.close();
  }
  return file;
}
