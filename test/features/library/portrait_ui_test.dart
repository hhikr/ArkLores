import 'dart:async';
import 'dart:io';

import 'package:arklores/core/gamedata/portrait_pack.dart';
import 'package:arklores/core/gamedata/portrait_pack_provider.dart';
import 'package:arklores/core/gamedata/story_coverage_models.dart';
import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/core/library/portrait_provider.dart';
import 'package:arklores/core/library/portrait_queries.dart';
import 'package:arklores/core/userdata/user_data_provider.dart';
import 'package:arklores/features/ai/story_labels_provider.dart';
import 'package:arklores/features/ai/story_reader_page.dart';
import 'package:arklores/features/ai/widgets/story_answer_body.dart';
import 'package:arklores/features/library/portrait_sheet.dart';
import 'package:arklores/features/library/portrait_speaker_name.dart';
import 'package:arklores/features/library/portrait_speakers_page.dart';
import 'package:arklores/features/library/speaker_portraits_page.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:arklores/shared/widgets/portrait_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/memory_user_store.dart';
import '../../support/portrait_pack_fixture.dart';
import '../../support/screenshot.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

const _sprite = 'char_fixture#4\$1';
const _speaker = '测试角色';
const _name = SpeakerPortraits(
  speaker: _speaker,
  lines: 340,
  topSprite: _sprite,
  highlight: true,
  groups: [
    SpeakerGroup(
      groupId: 'char_fixture',
      lines: 340,
      stories: 12,
      topSprite: _sprite,
      groupSpeakers: 2,
    ),
  ],
);
const _group = PortraitGroup(
  groupId: 'char_fixture',
  lines: 360,
  sprites: 12,
  topSprite: _sprite,
  speakers: [
    GroupSpeaker(speaker: _speaker, lines: 340, stories: 12),
    GroupSpeaker(speaker: '另一说话人', lines: 20, stories: 2),
  ],
);

class _MemoryPack extends PortraitPack {
  _MemoryPack(this.data) : super('fixture');
  final PortraitLayers data;
  @override
  Future<bool> get installed async => true;
  @override
  Future<PortraitLayers?> layers(String sprite) async =>
      sprite == _sprite ? data : null;
}

void main() {
  late Directory dir;
  late PortraitPack pack;
  setUpAll(() async {
    useSqfliteFfi();
    for (final font in {
      'Saira': 'Saira.ttf',
      'NotoSansSC': 'NotoSansSC.ttf',
      'EndfieldCipher': 'EndfieldByButan.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)
            ..addFont(
              rootBundle.load(
                font.key == 'MaterialIcons'
                    ? font.value
                    : 'assets/fonts/${font.value}',
              ),
            ))
          .load();
    }
    dir = Directory.systemTemp.createTempSync('portrait-ui');
    final file = await createPortraitPack(dir);
    final db = await databaseFactoryFfi.openDatabase(file.path);
    await db.rawInsert(
      'INSERT INTO portrait_images SELECT ?, base_id, x, y, width, height, blank, webp FROM portrait_images WHERE sprite = ?',
      [_sprite, 'whole'],
    );
    await db.close();
    final source = PortraitPack(file.path);
    pack = _MemoryPack((await source.layers(_sprite))!);
    await source.close();
  });
  tearDownAll(() async {
    await pack.close();
    await deleteTempDir(dir);
  });

  test('merged dialogue retains the source key for every portrait lookup',
      () async {
    final container = ProviderContainer(
      overrides: [
        storyHostProvider.overrideWith(
            (ref, id) async => id == 'child.txt' ? 'host.txt' : null,),
        storyFullLinesProvider.overrideWith(
          (ref, id) async => [
            StoryLineEntry(lineIndex: 0, content: id),
            StoryLineEntry(lineIndex: 2, content: id),
          ],
        ),
        attachedStoriesProvider.overrideWith(
          (ref, id) async => const [
            LibraryEntry(
                id: 'story:child.txt',
                type: 'story',
                name: '附属对话',
                rawId: 'child.txt',),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    final reading =
        await container.read(storyReadingProvider('child.txt').future);
    expect(reading.hostId, 'host.txt');
    expect(reading.offset, 4);
    expect(reading.portraitSources, {
      4: (storyId: 'child.txt', lineIndex: 0),
      6: (storyId: 'child.txt', lineIndex: 2),
    });
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    bool dark = false,
    bool index = true,
    Future<SpeakerPortraits?> Function()? names,
    Future<String?> Function(({String storyId, int lineIndex}))? sprite,
    StoryReading? reading,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tokens = dark ? ArkThemeTokens() : EndfieldThemeTokens();
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          initialThemeProvider
              .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
          portraitPackProvider.overrideWith((ref) async => pack),
          hasPortraitIndexProvider.overrideWith((ref) async => index),
          speakerPortraitsProvider.overrideWith(
            (ref, name) =>
                names?.call() ?? Future.value(name == _speaker ? _name : null),
          ),
          portraitGroupProvider.overrideWith((ref, id) async => _group),
          highlightNamesProvider.overrideWith((ref) async => [_speaker]),
          spriteOfLineProvider.overrideWith(
            (ref, key) => sprite?.call(key) ?? Future.value(_sprite),
          ),
          userDataStoreProvider.overrideWith((ref) async => MemoryUserStore()),
          storyReadingProvider.overrideWith(
            (ref, id) async =>
                reading ??
                const StoryReading(
                  hostId: 'fixture.txt',
                  lines: [
                    StoryLineEntry(
                      lineIndex: 0,
                      speaker: _speaker,
                      content: '这段对话用于检查说话人的立绘入口。',
                    ),
                    StoryLineEntry(
                      lineIndex: 1,
                      speaker: _speaker,
                      content: '同一个说话人的后一句不重复显示名字。',
                    ),
                    StoryLineEntry(
                      lineIndex: 2,
                      speaker: '另一说话人',
                      content: '从这一句可以查看另一张立绘。',
                    ),
                  ],
                ),
          ),
          storyCatalogEntryProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(tokens).copyWith(
            textTheme:
                buildAppTheme(tokens).textTheme.apply(fontFamily: 'Saira'),
          ),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => Shot(child: child!),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  Widget launcher({
    bool fromLine = false,
    String? sprite = _sprite,
    Future<String?>? future,
    PortraitOrigin origin = PortraitOrigin.ask,
  }) =>
      Scaffold(
        body: Builder(
          builder: (context) => AppButton(
            '打开',
            onPressed: () => showPortraitSheet(
              context,
              speaker: _speaker,
              fromLine: fromLine,
              sprite: sprite,
              spriteFuture: future,
              origin: origin,
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('sheet appears before query or exact sprite completes',
      (tester) async {
    final names = Completer<SpeakerPortraits?>();
    final sprite = Completer<String?>();
    await pump(
      tester,
      launcher(fromLine: true, future: sprite.future),
      names: () => names.future,
    );
    await tester.tap(find.text('打开'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PortraitSheet), findsOneWidget);
    expect(find.text('这一句没有显示立绘。'), findsNothing);
    names.complete(_name);
    sprite.complete(_sprite);
    await tester.pumpAndSettle();
    expect(find.text('表情 4 / 服装 1'), findsOneWidget);
  });

  testWidgets('sheet closes before opening pages and preserves origin',
      (tester) async {
    await pump(tester, launcher(origin: PortraitOrigin.materials));
    await open(tester);
    await tester.tap(find.text('用这个立绘的说话人'));
    await tester.pumpAndSettle();
    expect(find.byType(PortraitSheet), findsNothing);
    expect(
      tester
          .widget<PortraitSpeakersPage>(find.byType(PortraitSpeakersPage))
          .origin,
      PortraitOrigin.materials,
    );
    await tester.tap(find.text(_speaker));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SpeakerPortraitsPage>(find.byType(SpeakerPortraitsPage))
          .origin,
      PortraitOrigin.materials,
    );
    await tester.tap(find.byType(PressRow).last);
    await tester.pumpAndSettle();
    expect(find.byType(PortraitSpeakersPage), findsOneWidget);
  });

  testWidgets('no sprite hides image and group action', (tester) async {
    await pump(tester, launcher(fromLine: true, sprite: null));
    await open(tester);
    expect(find.byType(PortraitImage), findsNothing);
    expect(find.text('用这个立绘的说话人'), findsNothing);
    expect(find.text('“测试角色”用过的立绘'), findsOneWidget);
  });

  testWidgets('unknown speaker keeps only the exact portrait actions',
      (tester) async {
    await pump(tester, launcher(fromLine: true), names: () async => null);
    await open(tester);
    expect(find.text('用这个立绘的说话人'), findsOneWidget);
    expect(find.text('“测试角色”用过的立绘'), findsNothing);
    expect(find.text('干员资料'), findsNothing);
  });

  testWidgets('Endfield has no tappable names even with a portrait index',
      (tester) async {
    await pump(
      tester,
      const StoryReaderPage(storyId: 'ef/fixture.txt'),
      reading: const StoryReading(
        hostId: 'ef/fixture.txt',
        lines: [
          StoryLineEntry(lineIndex: 0, speaker: _speaker, content: '对话'),
        ],
      ),
    );
    expect(find.byType(PortraitSpeakerName), findsNothing);
  });

  for (final streaming in [false, true]) {
    testWidgets('answer highlight streaming=$streaming', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: StoryAnswerBody(
            content: '$_speaker 的回答。',
            styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 16)),
            streaming: streaming,
          ),
        ),
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.data.contains('arklores-speaker:'), !streaming);
      if (!streaming) {
        final context = tester.element(find.byType(StoryAnswerBody));
        final theme = ProviderScope.containerOf(context).read(themeProvider);
        expect(markdown.styleSheet!.a!.backgroundColor, theme.accentPrimary);
        expect(markdown.styleSheet!.a!.color, theme.onAccent);
        final rich = find
            .descendant(
              of: find.byType(MarkdownBody),
              matching: find.byType(RichText),
            )
            .first;
        await tester.tapAt(tester.getTopLeft(rich) + const Offset(12, 8));
        await tester.pumpAndSettle();
        expect(find.byType(PortraitSheet), findsOneWidget);
      }
    });
  }

  testWidgets('speaker target extends to 48 px without moving dialogue',
      (tester) async {
    var taps = 0;
    await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            PortraitSpeakerName(
              name: '甲乙',
              style: const TextStyle(fontSize: 14),
              onTap: () => taps++,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
    final target = find.byType(PortraitSpeakerName);
    expect(tester.getSize(target).height, lessThan(48));
    await tester.tapAt(tester.getTopLeft(target) + const Offset(24, 46));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
  });

  for (final index in [false, true]) {
    testWidgets('reader portrait availability=$index', (tester) async {
      await pump(
        tester,
        const StoryReaderPage(storyId: 'fixture.txt'),
        index: index,
      );
      expect(
        find.byType(PortraitSpeakerName),
        index ? findsNWidgets(2) : findsNothing,
      );
      if (index) {
        final name = find.byType(PortraitSpeakerName).first;
        await tester.tapAt(tester.getTopLeft(name) + const Offset(24, 46));
        await tester.pumpAndSettle();
        expect(find.text('表情 4 / 服装 1'), findsOneWidget);
      }
    });
  }

  testWidgets('attached dialogue uses original story and line', (tester) async {
    ({String storyId, int lineIndex})? requested;
    await pump(
      tester,
      const StoryReaderPage(storyId: 'fixture.txt'),
      sprite: (key) async {
        requested = key;
        return _sprite;
      },
      reading: const StoryReading(
        hostId: 'fixture.txt',
        lines: [
          StoryLineEntry(
            lineIndex: 40,
            shownIndex: 2,
            speaker: _speaker,
            content: '附属对话',
          ),
        ],
        portraitSources: {
          40: (storyId: 'child.txt', lineIndex: 2),
        },
      ),
    );
    await tester.tap(find.byType(PortraitSpeakerName));
    await tester.pumpAndSettle();
    expect(requested, (storyId: 'child.txt', lineIndex: 2));
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('screenshots $mode', (tester) async {
      await pump(
        tester,
        const StoryReaderPage(storyId: 'fixture.txt'),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      await shoot(tester, '${mode}_reader');
      for (final kind in ['reader', 'ask', 'none']) {
        await pump(
          tester,
          launcher(
            fromLine: kind != 'ask',
            sprite: kind == 'none' ? null : _sprite,
          ),
          dark: dark,
        );
        await open(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, '${mode}_sheet_$kind');
      }
      await pump(
        tester,
        const PortraitSpeakersPage(
          groupId: 'char_fixture',
          origin: PortraitOrigin.ask,
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RawImage), findsOneWidget);
      await shoot(tester, '${mode}_speakers');
      await pump(
        tester,
        const SpeakerPortraitsPage(
          speaker: _speaker,
          origin: PortraitOrigin.ask,
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RawImage), findsOneWidget);
      await shoot(tester, '${mode}_portraits');
      await pump(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
            child: StoryAnswerBody(
              content:
                  '$_speaker 在这段故事里与另一位说话人交谈。\n\n$_speaker 的名字在每段首次出现时可以点击。',
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'NotoSansSC',
                  height: 1.7,
                ),
              ),
              streaming: false,
            ),
          ),
        ),
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      await shoot(tester, '${mode}_answer');
    });
  }
}
