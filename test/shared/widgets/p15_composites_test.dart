// Real-library contact sheets, opt in with P15_REAL_DATA=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:arklores/core/gamedata/story_art_pack.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/shared/widgets/story_art_composite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/library/story_art_viewer_test.dart' as viewer;
import '../../support/sqlite.dart';

void main() {
  final enabled = Platform.environment['P15_REAL_DATA'] == 'true';
  final shots = <({String id, StoryArtShot shot})>[];
  setUpAll(() async {
    if (!enabled) return;
    useSqfliteFfi();
    await (FontLoader('Saira')
          ..addFont(rootBundle.load('assets/fonts/Saira.ttf')))
        .load();
    final db = await databaseFactoryFfi.openDatabase(
      File('build/gamedata_portraits/arklores_gamedata_zh.db').absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final pack = StoryArtPack(
        File('build/story_art/arklores_story_art_zh.db').absolute.path,);
    final ids = await db.rawQuery(
        "SELECT DISTINCT story_id FROM story_art_events WHERE kind='item' ORDER BY story_id",);
    for (final row in ids) {
      final id = row['story_id'] as String;
      final events = await readStoryArtEvents(db, [id]);
      final info = await pack.artInfo([
        for (final e in events)
          if (e.image != null) (e.image!, e.kind),
      ]);
      shots.addAll(
        arrangeStoryArt(events, (image, kind) => info[(image, kind)]?.solid)
            .where((s) => s.layers.isNotEmpty)
            .map((s) => (id: id, shot: s)),
      );
    }
    await db.close();
    await pack.close();
    debugPrint(
        'P15 composites: ${shots.length}; stories: ${shots.map((s) => s.id).toSet().length}',);
  });
  testWidgets(
    'all layered shots in contact sheets',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory('build/shots/v020_p15');
      await tester.runAsync(() => directory.create(recursive: true));
      final labels = <String>[];
      for (var offset = 0; offset < shots.length; offset += 12) {
        final page = shots.skip(offset).take(12).toList();
        final pack = await tester.runAsync(
          () => viewer.memoryPack(
              File('build/story_art/arklores_story_art_zh.db').absolute.path, [
            for (final entry in page) ...[
              (entry.shot.image, entry.shot.kind),
              for (final layer in entry.shot.layers) (layer.image, 'item'),
            ],
          ]),
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(offset),
            overrides: [
              storyArtPackProvider.overrideWith((ref) async => pack!),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: Colors.white,
                  child: Column(
                    children: [
                      for (var row = 0; row < 4; row++)
                        Row(
                          children: [
                            for (var col = 0; col < 3; col++)
                              SizedBox(
                                width: 480,
                                height: 310,
                                child: row * 3 + col >= page.length
                                    ? const SizedBox()
                                    : Builder(
                                        builder: (context) {
                                          final entry = page[row * 3 + col];
                                          return Column(
                                            children: [
                                              SizedBox(
                                                  width: 480,
                                                  height: 270,
                                                  child: StoryArtComposite(
                                                      entry.shot,),),
                                              SizedBox(
                                                  height: 40,
                                                  child: Center(
                                                      child: Text(
                                                          '${entry.id}:${entry.shot.at}',
                                                          style: const TextStyle(
                                                              fontSize: 11,
                                                              color:
                                                                  Colors.black,
                                                              fontFamily:
                                                                  'Saira',
                                                              decoration:
                                                                  TextDecoration
                                                                      .none,
                                                              height: 1.3,),),),),
                                            ],
                                          );
                                        },
                                      ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        var expected = 0;
        for (final entry in page) {
          for (final key in [
            (entry.shot.image, entry.shot.kind),
            for (final layer in entry.shot.layers) (layer.image, 'item'),
          ]) {
            if (await tester.runAsync(() => pack!.artImage(key.$1, key.$2)) !=
                null) {
              expected++;
            }
          }
        }
        int decoded() => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((image) => image.image != null)
            .length;
        for (var pass = 0; pass < 60 && decoded() < expected; pass++) {
          await tester.pumpAndSettle();
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 300)),);
        }
        await tester.pumpAndSettle();
        expect(decoded(), expected,
            reason: 'Every stored base and layer must decode before capture',);
        expect(tester.takeException(), isNull);
        final number = (offset ~/ 12 + 1).toString().padLeft(2, '0');
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${directory.path}/composites_$number.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        labels.addAll(page.map((e) =>
            '$number ${e.id}:${e.shot.at} ${e.shot.kind} ${e.shot.image} ${e.shot.layers.map((l) => l.image).join(",")}',),);
      }
      await tester.runAsync(() => File('${directory.path}/composites.txt')
          .writeAsString(labels.join('\n')),);
    },
    skip: !enabled,
  );
}
