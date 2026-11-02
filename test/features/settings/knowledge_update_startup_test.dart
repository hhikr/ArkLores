import 'package:arklores/core/gamedata/gamedata_channel.dart';
import 'package:arklores/core/gamedata/gamedata_installer.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/core/gamedata/story_art_pack_installer.dart';
import 'package:arklores/core/gamedata/story_art_pack_provider.dart';
import 'package:arklores/features/settings/update_startup.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GameDataInstallStatus _status({
  required bool installed,
  String? offered,
  String? have,
}) =>
    GameDataInstallStatus(
      installed: installed,
      dbPath: 'unused',
      bytes: 0,
      manifest: const {},
      installedAssetSha: have,
      releaseAssetSha: offered,
    );

void main() {
  const art = StoryArtPackAsset(
    url: 'https://example.test/pack',
    sha256: 'new-pack',
    size: 406 * 1024 * 1024,
  );

  var channelReads = 0;

  Widget app({
    required GameDataInstallStatus arknights,
    GameDataInstallStatus? endfield,
    StoryArtPackStatus art = const StoryArtPackStatus(),
  }) =>
      ProviderScope(
        overrides: [
          gameDataChannelProvider.overrideWith((ref) async {
            channelReads++;
            return null;
          }),
          gameDataInstallStatusProvider.overrideWith((ref) async => arknights),
          endfieldInstallStatusProvider.overrideWith(
            (ref) async =>
                endfield ??
                _status(installed: false, offered: 'endfield-offered'),
          ),
          storyArtPackStatusProvider.overrideWith((ref) async => art),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routes: {
            '/knowledge-base': (_) => const Scaffold(body: Text('KB page')),
          },
          home: const UpdateStartup(child: Scaffold(body: Text('Home'))),
        ),
      );

  setUp(() => channelReads = 0);

  final newer = _status(installed: true, offered: 'new', have: 'old');
  final current = _status(installed: true, offered: 'same', have: 'same');

  testWidgets('a new knowledge base asks at once and leads to its page',
      (tester) async {
    expect(newer.updateAvailable, isTrue);
    await tester.pumpWidget(app(arknights: newer));
    await tester.pumpAndSettle();
    expect(find.text('知识库有更新'), findsOneWidget);
    expect(find.text('明日方舟知识库'), findsOneWidget);
    expect(find.text('终末地知识库'), findsNothing, reason: 'not installed');
    await tester.tap(find.byKey(const ValueKey('kb-update-found-open')));
    await tester.pumpAndSettle();
    expect(find.text('KB page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing new, nothing asked', (tester) async {
    await tester.pumpWidget(app(arknights: current));
    await tester.pumpAndSettle();
    expect(find.text('知识库有更新'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a new art pack is named with its size', (tester) async {
    await tester.pumpWidget(
      app(
        arknights: current,
        art: const StoryArtPackStatus(
          installed: true,
          installedSha: 'old-pack',
          asset: art,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('剧情美术包（406 MB）'), findsOneWidget);
  });

  testWidgets('a download on its way is not asked about', (tester) async {
    await tester.pumpWidget(
      app(
        arknights: newer,
        art: const StoryArtPackStatus(
          installed: true,
          downloading: true,
          asset: art,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('知识库有更新'), findsNothing);
  });

  testWidgets('coming back looks again but does not repeat the question',
      (tester) async {
    await tester.pumpWidget(app(arknights: newer));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    final reads = channelReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(channelReads, greaterThan(reads));
    expect(find.text('知识库有更新'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
