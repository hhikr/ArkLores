import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_channel.dart';
import 'package:arklores/core/gamedata/story_art_pack_installer.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/core/library/portrait_provider.dart';
import 'package:arklores/features/settings/story_art_pack_card.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/screenshot.dart';

const _asset = StoryArtPackAsset(
  url: 'https://example.test/pack',
  sha256: 'current',
  size: 200 * 1024 * 1024,
);

const _hdAsset = StoryArtPackAsset(
  url: 'https://example.test/pack-hd',
  sha256: 'current-hd',
  size: 700 * 1024 * 1024,
);

class _Download extends StoryArtPackDownloadNotifier {
  _Download(super.ref, super.variant);
  int starts = 0, deletes = 0, cancels = 0;
  @override
  Future<void> start(String label) async {
    starts++;
  }

  @override
  Future<void> delete() async {
    deletes++;
  }

  @override
  void cancel() {
    cancels++;
  }
}

Finder _in(StoryArtVariant variant, Finder finder) => find.descendant(
      of: find.byKey(ValueKey('story-art-${variant.name}')),
      matching: finder,
    );

void main() {
  setUpAll(() async {
    for (final font
        in {'Saira': 'Saira.ttf', 'NotoSansSC': 'NotoSansSC.ttf'}.entries) {
      await (FontLoader(font.key)
            ..addFont(rootBundle.load('assets/fonts/${font.value}')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  /// [status] is the standard pack's, [hd] the HD one's.
  Future<Map<StoryArtVariant, _Download>> pump(
    WidgetTester tester, {
    bool index = true,
    StoryArtPackStatus status = const StoryArtPackStatus(asset: _asset),
    StoryArtPackStatus hd = const StoryArtPackStatus(asset: _hdAsset),
    Game game = Game.arknights,
    bool dark = false,
    // False: the channel file could not be read.
    bool channelRead = true,
  }) async {
    final downloads = <StoryArtVariant, _Download>{};
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeProvider
              .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
          hasPortraitIndexProvider.overrideWith((ref) async => index),
          gameDataChannelProvider.overrideWith(
            (ref) async => channelRead ? const GameDataChannel({}) : null,
          ),
          storyArtPackStatusProvider.overrideWith(
            (ref, variant) async =>
                variant == StoryArtVariant.hd ? hd : status,
          ),
          storyArtPackDownloadProvider.overrideWith(
            (ref, variant) => downloads[variant] = _Download(ref, variant),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(dark ? ArkThemeTokens() : EndfieldThemeTokens())
              .copyWith(
                  textTheme: buildAppTheme(
                          dark ? ArkThemeTokens() : EndfieldThemeTokens(),)
                      .textTheme
                      .apply(fontFamily: 'Saira'),),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
          home: Shot(
            child: Scaffold(
              backgroundColor: dark ? ArkThemeTokens().bgPrimary : EndfieldThemeTokens().bgPrimary,
              body: SizedBox(
                width: 390,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [StoryArtPackCard(game: game)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The fake action providers are lazy until read.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(StoryArtPackCard)));
    for (final variant in StoryArtVariant.values) {
      container.read(storyArtPackDownloadProvider(variant));
    }
    await tester.pumpAndSettle();
    return downloads;
  }

  testWidgets('old knowledge base has no actions', (tester) async {
    await pump(tester, index: false);
    expect(find.textContaining('装的知识库还没有立绘数据'), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
  });
  testWidgets('a pack installed under an old knowledge base can be deleted',
      (tester) async {
    await pump(
      tester,
      index: false,
      status: const StoryArtPackStatus(asset: _asset, installed: true, inUse: true),
    );
    expect(find.textContaining('装的知识库还没有立绘数据'), findsOneWidget);
    expect(_in(StoryArtVariant.standard, find.text('删除')), findsOneWidget);
    expect(find.text('下载'), findsNothing);
  });
  testWidgets('an unreleased version has no download action', (tester) async {
    await pump(tester, hd: const StoryArtPackStatus());
    expect(_in(StoryArtVariant.hd, find.text('这个版本还没有发布。')), findsOneWidget);
    expect(_in(StoryArtVariant.hd, find.byType(AppButton)), findsNothing);
    expect(_in(StoryArtVariant.standard, find.text('下载')), findsOneWidget);
  });
  testWidgets('an unread channel is said so and can be tried again, not '
      '"unreleased"', (tester) async {
    await pump(
      tester,
      channelRead: false,
      status: const StoryArtPackStatus(),
      hd: const StoryArtPackStatus(),
    );
    expect(find.text('这个版本还没有发布。'), findsNothing);
    expect(find.text('没能读到发布信息，可能是网络连不上 GitHub。'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('story-art-retry-hd')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-art-retry-hd')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('each version is downloaded on its own', (tester) async {
    final downloads = await pump(tester);
    expect(find.text('标准版'), findsOneWidget);
    expect(find.text('高清版'), findsOneWidget);
    expect(_in(StoryArtVariant.standard, find.textContaining('下载大小：200.0 MB')),
        findsOneWidget,);
    expect(_in(StoryArtVariant.hd, find.textContaining('下载大小：700.0 MB')),
        findsOneWidget,);
    await tester.tap(find.byKey(const ValueKey('story-art-download-hd')));
    expect(downloads[StoryArtVariant.hd]!.starts, 1);
    expect(downloads[StoryArtVariant.standard]!.starts, 0);
  });
  testWidgets('download progress and cancellation; the other waits',
      (tester) async {
    final downloads = await pump(
      tester,
      hd: const StoryArtPackStatus(
        asset: _hdAsset,
        downloading: true,
        received: 1024 * 1024,
        total: 2 * 1024 * 1024,
      ),
    );
    expect(find.text('1.0 MB / 2.0 MB（50%）'), findsOneWidget);
    expect(
      tester.widget<SegmentProgress>(find.byType(SegmentProgress)).value,
      0.5,
    );
    await tester.tap(find.text('取消'));
    expect(downloads[StoryArtVariant.hd]!.cancels, 1);
  });
  testWidgets('both installed: one in use, the other can be chosen',
      (tester) async {
    await pump(
      tester,
      status: const StoryArtPackStatus(
        asset: _asset,
        installed: true,
        inUse: true,
        installedSha: 'current',
      ),
      hd: const StoryArtPackStatus(
        asset: _hdAsset,
        installed: true,
        installedSha: 'current-hd',
      ),
    );
    expect(find.byKey(const ValueKey('story-art-in-use-standard')),
        findsOneWidget,);
    expect(find.byKey(const ValueKey('story-art-in-use-hd')), findsNothing);
    expect(find.byKey(const ValueKey('story-art-use-hd')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-art-use-standard')), findsNothing);
  });
  testWidgets('installed latest requires confirmation to delete',
      (tester) async {
    final downloads = await pump(
      tester,
      status: const StoryArtPackStatus(
        asset: _asset,
        installed: true,
        inUse: true,
        installedSha: 'current',
        bytes: 100 * 1024 * 1024,
        spriteCount: 10000,
      ),
    );
    final download = downloads[StoryArtVariant.standard]!;
    expect(find.text('立绘 10000 / 场景 0 / CG 0 / 100.0 MB'), findsOneWidget);
    expect(find.text('更新'), findsNothing);
    final delete = find.byKey(const ValueKey('story-art-delete-standard'));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(download.deletes, 0);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(download.deletes, 1);
  });
  testWidgets('update offers update and delete', (tester) async {
    final downloads = await pump(
      tester,
      status: const StoryArtPackStatus(
        asset: _asset,
        installed: true,
        inUse: true,
        installedSha: 'old',
      ),
    );
    expect(find.text('有新的剧情美术包（200.0 MB）。'), findsOneWidget);
    expect(_in(StoryArtVariant.standard, find.text('删除')), findsOneWidget);
    await tester.tap(find.text('更新'));
    expect(downloads[StoryArtVariant.standard]!.starts, 1);
  });
  testWidgets('Endfield shows its empty state', (tester) async {
    await pump(tester, game: Game.endfield);
    expect(find.text('剧情美术'), findsOneWidget);
    expect(find.text('终末地的剧情没有美术数据。'), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
  });
  for (final dark in [false, true]) {
    for (final installed in [false, true]) {
      testWidgets(
          'screenshot ${dark ? 'dark' : 'light'} ${installed ? 'installed' : 'missing'}',
          (tester) async {
        await pump(
          tester,
          dark: dark,
          status: StoryArtPackStatus(
            asset: _asset,
            installed: installed,
            inUse: installed,
            installedSha: 'current',
            spriteCount: 10207,
            backgroundCount: 1025,
            illustrationCount: 1488,
            bytes: 395993088,
          ),
        );
        await shoot(
          tester,
          'card_${dark ? 'dark' : 'light'}_${installed ? 'installed' : 'missing'}',
          pixelRatio: 1,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
