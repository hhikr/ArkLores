import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/core/library/portrait_provider.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/ai/widgets/name_linked_text.dart';
import 'package:arklores/features/library/portrait_speaker_name.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_user_store.dart';
import '../../support/screenshot.dart';
import '../library/library_ui_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    if (shotDir == null) return;
    for (final font in {
      'Roboto': 'assets/fonts/NotoSansSC.ttf',
      'Saira': 'assets/fonts/Saira.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  const lines = [
    StoryLineEntry(lineIndex: 0, content: '林舟和林舟都在。', speaker: '洛青'),
    StoryLineEntry(lineIndex: 1, content: '没有名字的一句。', speaker: '洛青'),
  ];

  Future<void> open(
    WidgetTester tester, {
    String storyId = 'activities/a/story.txt',
    StoryPlace? place,
    List<LibraryEntry> stories = const [],
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          hasPortraitIndexProvider.overrideWith((ref) async => true),
          indexedNamesProvider.overrideWith((ref) async => const ['林舟']),
          storyFullLinesProvider.overrideWith((ref, id) async => lines),
          storyPlaceProvider.overrideWith((ref, id) async => place),
          collectionStoriesProvider.overrideWith((ref, id) async => stories),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => Shot(child: child!),
          home: StoryReaderPage(storyId: storyId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  int underlined(WidgetTester tester) {
    var count = 0;
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(NameLinkedText),
        matching: find.byType(Text),
      ),
    )) {
      text.textSpan?.visitChildren((span) {
        if (span.style?.decoration == TextDecoration.underline) count++;
        return true;
      });
    }
    return count;
  }

  testWidgets('names in the lines are underlined by default, every time',
      (tester) async {
    await open(tester);
    expect(underlined(tester), 2);
    expect(find.text('没有名字的一句。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a name in the line right under its speaker is its own target',
      (tester) async {
    await open(tester);
    // The first line starts with the name, inside the speaker's tall target.
    final speaker = tester.getBottomLeft(find.byType(PortraitSpeakerName).first);
    await tester.tapAt(speaker + const Offset(12, 14));
    await tester.pumpAndSettle();
    // The card of the name tapped; the speaker's label is the only 洛青.
    expect(find.text('林舟'), findsOneWidget);
    expect(find.text('洛青'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contents lists the collection and opens at this story',
      (tester) async {
    final stories = [
      for (var i = 0; i < 40; i++)
        LibraryEntry(
          id: 'story:activities/a/story$i.txt',
          type: 'story',
          name: '第$i篇',
          code: 'A-$i',
          rawId: 'activities/a/story$i.txt',
          collectionId: 'act',
        ),
    ];
    await open(
      tester,
      storyId: 'activities/a/story30.txt',
      place: StoryPlace(entry: stories[30]),
      stories: stories,
    );
    await tester.tap(find.byKey(const ValueKey('story-reader-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('story-reader-contents')));
    await tester.pumpAndSettle();
    await shoot(tester, 'reader_contents', pixelRatio: 1);
    final current = find.byKey(
      const ValueKey('story-contents-activities/a/story30.txt'),
    );
    expect(current, findsOneWidget);
    expect(find.text('第0篇'), findsNothing);
    final list = tester.getRect(find.byKey(const ValueKey('story-contents')));
    expect(tester.getCenter(current).dy, closeTo(list.center.dy, 30));
    await tester.tap(find.text('第31篇'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<StoryReaderPage>(find.byType(StoryReaderPage)).storyId,
      'activities/a/story31.txt',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tool button holds find and the underline switch',
      (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('story-reader-find')), findsNothing);
    final tools = find.byKey(const ValueKey('story-reader-tools'));
    await tester.tap(tools);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('story-reader-find')), findsOneWidget);
    await shoot(tester, 'reader_tools', pixelRatio: 1);
    await tester.tap(find.byKey(const ValueKey('story-reader-name-links')));
    await tester.pumpAndSettle();
    expect(underlined(tester), 0);
    await tester.tap(find.byKey(const ValueKey('story-reader-name-links')));
    await tester.pumpAndSettle();
    expect(underlined(tester), 2);
    await tester.tap(tools);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('story-reader-find')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
