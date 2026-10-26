import 'dart:io';
import 'dart:ui' as ui;

import 'package:arklores/core/gamedata/portrait_pack.dart';
import 'package:arklores/core/gamedata/portrait_pack_provider.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/widgets/portrait_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plain_theme.dart';
import '../../support/portrait_pack_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;
  ui.Image? first;
  setUpAll(useSqfliteFfi);
  setUp(() => dir = Directory.systemTemp.createTempSync('portrait-image'));
  tearDown(() => deleteTempDir(dir));

  test('patch replaces opaque and transparent pixels; LRU retains owned clones',
      () async {
    final pack = PortraitPack((await createPortraitPack(dir)).path);
    addTearDown(pack.close);
    final layers = (await pack.layers('patch'))!;
    final cache = PortraitImageCache();
    addTearDown(cache.dispose);
    final image = await cache.image('patch', layers);
    addTearDown(image.dispose);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    List<int> pixel(int x, int y) =>
        bytes.sublist((y * 4 + x) * 4, (y * 4 + x) * 4 + 4);
    expect(pixel(0, 0), [80, 100, 120, 255]);
    expect(pixel(1, 1), [0, 0, 0, 0]);
    expect(pixel(2, 1), [200, 40, 60, 255]);
    expect(pixel(3, 3), [80, 100, 120, 255]);
    for (var i = 0; i < 26; i++) {
      (await cache.image('sprite$i', layers)).dispose();
    }
    expect(image.debugDisposed, isFalse);
    expect(await image.toByteData(), isNotNull);
  });

  testWidgets('another sprite: the last picture stays until the new is made',
      (tester) async {
    late PortraitPack pack;
    await tester.runAsync(() async {
      pack = PortraitPack((await createPortraitPack(dir)).path);
    });
    var sprite = 'whole';
    late StateSetter set;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plainThemeOverride(),
          portraitPackProvider.overrideWith((ref) async => pack),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return SizedBox(
                  width: 200,
                  height: 200,
                  child: PortraitImage(sprite: sprite),
                );
              },
            ),
          ),
        ),
      ),
    );
    Future<ui.Image?> settled() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final raw = find.byType(RawImage);
        if (raw.evaluate().isNotEmpty) {
          final image = tester.widget<RawImage>(raw).image;
          if (sprite == 'whole' || image != first) return image;
        }
      }
      return null;
    }

    first = await settled();
    expect(first, isNotNull);
    set(() => sprite = 'patch');
    await tester.pump();
    final between = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(between, same(first), reason: 'no empty frame between the two');
    expect(between!.debugDisposed, isFalse);
    final next = await settled();
    expect(next, isNot(same(first)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(pack.close);
  });

  for (final state in [
    'missingPack',
    'missingSprite',
    'blank',
    'whole',
    'fallback',
  ]) {
    testWidgets('renders $state', (tester) async {
      late PortraitPack pack;
      await tester.runAsync(() async {
        pack = PortraitPack(
          state == 'missingPack'
              ? '${dir.path}/missing.db'
              : (await createPortraitPack(dir)).path,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plainThemeOverride(),
            portraitPackProvider.overrideWith((ref) async => pack),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: PortraitImage(
                  sprite: switch (state) {
                    'blank' => 'blank',
                    'whole' => 'whole',
                    _ => 'missing'
                  },
                  fallbackSprite: state == 'fallback' ? 'whole' : null,
                  semanticLabel: 'portrait',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(RawImage), findsNothing);
      for (var attempt = 0;
          attempt < 30 &&
              find.byType(RawImage).evaluate().isEmpty &&
              find.byType(Text).evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      if (state == 'whole' || state == 'fallback') {
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image, isNotNull);
        expect(raw.fit, BoxFit.contain);
        expect(raw.alignment, Alignment.bottomCenter);
      } else {
        expect(
          find.text(
            switch (state) {
              'missingPack' => '没有安装立绘包。',
              'blank' => '这一句的立绘是空的。',
              _ => '立绘包里没有这一张。'
            },
          ),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(pack.close);
    });
  }
}
