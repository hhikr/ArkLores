import 'package:arklores/core/gamedata/story_art_pack.dart' as pack;
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/story_art.dart';
import 'package:arklores/shared/widgets/story_art_composite.dart';
import 'package:arklores/shared/widgets/story_art_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pack extends pack.StoryArtPack {
  _Pack() : super('memory');
  @override
  Future<Map<(String, String), pack.StoryArtInfo>> artInfo(
          Iterable<(String, String)> keys,) async =>
      {
        for (final key in keys)
          if (key.$1 != 'absent')
            key: const pack.StoryArtInfo(1600, 900, 'item', false),
      };
  @override
  Future<pack.StoryArtImage?> artImage(String id, String kind) async => null;
}

void main() {
  testWidgets(
      'layers use original pixels, positive y goes up, absent layers skip',
      (tester) async {
    const shot = StoryArtShot(
      kind: 'cg',
      image: 'missing',
      at: 0,
      layers: [
        StoryArtLayer(image: 'actor', x: 200, y: 100, scale: 1.4, alpha: .4),
        StoryArtLayer(image: 'absent'),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storyArtPackProvider.overrideWith((ref) async => _Pack())],
        child: const MaterialApp(
            home: Center(
                child: SizedBox(
                    width: 384, height: 216, child: StoryArtComposite(shot),),),),
      ),
    );
    await tester.pumpAndSettle();
    final layer = tester.widget<Positioned>(find
        .ancestor(
            of: find.byWidgetPredicate(
                (w) => w is StoryArtImage && w.kind == 'item',),
            matching: find.byType(Positioned),)
        .first,);
    expect(layer.width, closeTo(1600 * 1.5 * 1.4 * .2, .001));
    expect(layer.height, closeTo(900 * 1.5 * 1.4 * .2, .001));
    expect(layer.left, closeTo((960 + 200 - 1600 * 1.5 * 1.4 / 2) * .2, .001));
    expect(layer.top, closeTo((540 - 100 - 900 * 1.5 * 1.4 / 2) * .2, .001));
    expect(find.byType(StoryArtImage), findsNWidgets(2));
    expect(
        tester
            .widget<StoryArtImage>(find.byWidgetPredicate(
                (w) => w is StoryArtImage && w.kind == 'item',),)
            .transparent,
        isTrue,);
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, .4);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'a scene strip crops the whole 16:9 stage without stretching layers',
      (tester) async {
    const shot = StoryArtShot(
        kind: 'scene',
        image: 'missing',
        at: 0,
        layers: [StoryArtLayer(image: 'actor')],);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storyArtPackProvider.overrideWith((ref) async => _Pack())],
        child: const MaterialApp(
            home: Center(
                child: SizedBox(
                    width: 384,
                    height: 56,
                    child: StoryArtComposite(shot, fit: BoxFit.cover),),),),
      ),
    );
    await tester.pumpAndSettle();
    final layer = tester.widget<Positioned>(find
        .ancestor(
            of: find.byWidgetPredicate(
                (w) => w is StoryArtImage && w.kind == 'item',),
            matching: find.byType(Positioned),)
        .first,);
    expect(layer.width, 480);
    expect(layer.height, 270);
    expect(tester.takeException(), isNull);
  });
}
