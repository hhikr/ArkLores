// The reader's say over underlined names in answers: a switch, and names
// never to underline (typed in Settings or added by holding a name).
import 'package:arklores/core/library/portrait_provider.dart';
import 'package:arklores/features/ai/widgets/story_answer_body.dart';
import 'package:arklores/features/settings/blocked_names_page.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/app_theme.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/screenshot.dart';

const _names = ['林舟', '青石', '林舟？'];

Widget _app(Widget home, {bool light = true}) {
  final tokens = light ? EndfieldThemeTokens() : ArkThemeTokens();
  return ProviderScope(
    overrides: [
      indexedNamesProvider.overrideWith((ref) async => _names),
      initialThemeProvider
          .overrideWithValue(light ? AppTheme.endfield : AppTheme.ark),
    ],
    child: MaterialApp(
      theme: buildAppTheme(tokens),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The overlay (the card) is in the shot too.
      builder: (_, child) => Shot(child: child!),
      home: ColoredBox(color: tokens.bgPrimary, child: home),
    ),
  );
}

Widget _answer() => Consumer(
      builder: (context, ref, _) {
        final theme = ref.watch(themeProvider);
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: StoryAnswerBody(
              content: '林舟带着青石出发。',
              streaming: false,
              revealImmediately: true,
              styleSheet: MarkdownStyleSheet(
                p: theme.text(18, height: 1.6),
              ),
            ),
          ),
        );
      },
    );

void main() {
  setUpAll(() async {
    for (final font in {
      'Saira': 'assets/fonts/Saira.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('the switch and the blocked names shape what answers underline, '
      'and are kept', () async {
    ProviderContainer open() => ProviderContainer(
          overrides: [
            indexedNamesProvider.overrideWith((ref) async => _names),
          ],
        );
    final first = open();
    addTearDown(first.dispose);
    expect(await first.read(highlightNamesProvider.future), _names);
    final links = first.read(nameLinksProvider.notifier);
    await first.read(nameLinksProvider.future);
    expect(await links.block(' 林舟 '), isTrue);
    expect(await links.block('林舟'), isFalse);
    expect(await links.block('  '), isFalse);
    expect(await first.read(highlightNamesProvider.future), ['青石', '林舟？']);
    await links.setOn(false);
    expect(await first.read(highlightNamesProvider.future), isEmpty);

    final again = open();
    addTearDown(again.dispose);
    final kept = await again.read(nameLinksProvider.future);
    expect(kept.on, isFalse);
    expect(kept.blocked, ['林舟']);
    await again.read(nameLinksProvider.notifier).unblock('林舟');
    await again.read(nameLinksProvider.notifier).setOn(true);
    expect(await again.read(highlightNamesProvider.future), _names);
  });

  for (final light in [true, false]) {
    testWidgets('holding an underlined name offers to block it light=$light',
        (tester) async {
      tester.view.physicalSize = const Size(390, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(_answer(), light: light));
      await tester.pumpAndSettle();
      String data() =>
          tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data;
      expect(data(), contains('[林舟]'));
      expect(data(), contains('[青石]'));

      // Held on plain text: nothing.
      final rich = find
          .descendant(
            of: find.byType(MarkdownBody),
            matching: find.byType(RichText),
          )
          .first;
      final origin = tester.getTopLeft(rich);
      await tester.longPressAt(origin + const Offset(60, 12));
      await tester.pumpAndSettle();
      expect(find.text('屏蔽这个名字？'), findsNothing);

      // Held on the first name: the card, beside it.
      await tester.longPressAt(origin + const Offset(9, 12));
      await tester.pumpAndSettle();
      expect(find.text('屏蔽这个名字？'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('block-name-card')),
          matching: find.text('林舟'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await shoot(tester, 'block_name_card_${light ? 'light' : 'dark'}');

      await tester.tap(find.byKey(const ValueKey('block-name-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('屏蔽这个名字？'), findsNothing);
      expect(data(), isNot(contains('[林舟]')));
      expect(data(), contains('[青石]'));
      final container =
          ProviderScope.containerOf(tester.element(find.byType(MarkdownBody)));
      expect(container.read(nameLinksProvider).value!.blocked, ['林舟']);

      // The switch off: no name underlined.
      await container.read(nameLinksProvider.notifier).setOn(false);
      await tester.pumpAndSettle();
      expect(data(), isNot(contains('arklores-speaker:')));
    });
  }

  for (final light in [true, false]) {
    testWidgets('settings list adds, refuses a repeat and removes light=$light',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(const BlockedNamesPage(), light: light));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有屏蔽词'), findsOneWidget);

      for (final name in ['博士', '孩子']) {
        await tester.enterText(
          find.byKey(const ValueKey('blocked-names-input')),
          name,
        );
        await tester.tap(find.byKey(const ValueKey('blocked-names-add')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('blocked-name-博士')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocked-name-孩子')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('blocked-names-input')),
        '博士',
      );
      await tester.tap(find.byKey(const ValueKey('blocked-names-add')));
      await tester.pumpAndSettle();
      expect(find.text('这个名字已经在屏蔽词里了。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'blocked_names_${light ? 'light' : 'dark'}');

      await tester.tap(find.byTooltip('取消屏蔽 博士'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('blocked-name-博士')), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BlockedNamesPage)),
      );
      expect(container.read(nameLinksProvider).value!.blocked, ['孩子']);
    });
  }
}
