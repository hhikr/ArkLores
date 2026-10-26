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
import 'package:arklores/features/library/portrait_preview.dart';
import 'package:arklores/features/library/portrait_sheet.dart';
import 'package:arklores/features/library/portrait_speaker_name.dart';
import 'package:arklores/features/library/portrait_speakers_page.dart';
import 'package:arklores/features/library/portrait_stories_page.dart';
import 'package:arklores/features/library/speaker_portraits_page.dart';
import 'package:arklores/main.dart' show buildAppTheme;
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/app_theme.dart';
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

var _sprite = 'char_fixture#4\$1';
List<String> _sprites = [];
List<PortraitStory> _stories = const [
  PortraitStory(storyId: 'fixture.txt', firstLine: 2, lines: 9),
];
const _speaker = '测试角色';
SpeakerPortraits get _name => SpeakerPortraits(
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
        SpeakerGroup(
          groupId: 'avg_npc_passing',
          lines: 1,
          stories: 1,
          topSprite: 'avg_npc_passing#1\$1',
          groupSpeakers: 7,
        ),
      ],
    );
PortraitGroup get _group => PortraitGroup(
      groupId: 'char_fixture',
      lines: 360,
      sprites: _sprites.isEmpty ? 12 : _sprites.length,
      topSprite: _sprite,
      speakers: [
        GroupSpeaker(speaker: _speaker, lines: 340, stories: 12),
        GroupSpeaker(speaker: '另一说话人', lines: 20, stories: 2),
        GroupSpeaker(
          speaker: '画外音',
          lines: 1,
          stories: 1,
          mainElsewhere: true,
        ),
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

class _RealMemoryPack extends PortraitPack {
  _RealMemoryPack(this.images) : super('real-pack-snapshot');
  final Map<String, PortraitLayers> images;
  @override
  Future<bool> get installed async => true;
  @override
  Future<PortraitLayers?> layers(String sprite) async => images[sprite];
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
    final real = Platform.environment['P8_REAL_PACK'];
    if (real != null) {
      final realPack = PortraitPack(real);
      final kb = await databaseFactoryFfi.openDatabase(
        '${Directory.current.path}/build/gamedata_portraits/arklores_gamedata_zh.db',
        options: OpenDatabaseOptions(readOnly: true),
      );
      final row = (await kb.rawQuery(
              'SELECT * FROM portrait_groups ORDER BY sprites DESC LIMIT 1',))
          .single;
      _sprite = row['top_sprite'] as String;
      _sprites = await portraitSprites(kb, row['group_id'] as String);
      _stories = await portraitStories(
          kb,
          (await kb.rawQuery(
                  'SELECT speaker FROM speaker_portraits WHERE group_id = ? ORDER BY lines DESC LIMIT 1',
                  [row['group_id']],))
              .single['speaker'] as String,
          row['group_id'] as String,);
      await kb.close();
      final images = <String, PortraitLayers>{};
      for (final sprite in _sprites) {
        final layers = await realPack.layers(sprite);
        if (layers != null) images[sprite] = layers;
      }
      await realPack.close();
      pack = _RealMemoryPack(images);
    }
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
          (ref, id) async => id == 'child.txt' ? 'host.txt' : null,
        ),
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
              rawId: 'child.txt',
            ),
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

  Future<void> settlePortraits(WidgetTester tester) async {
    if (Platform.environment['P8_REAL_PACK'] == null) return;
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      if (find.byType(RawImage).evaluate().length >=
          find.byType(PortraitImage).evaluate().length) {
        break;
      }
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await settlePortraits(tester);
    await shoot(tester, name, pixelRatio: 1);
  }

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
          portraitSpritesProvider.overrideWith((ref, id) async =>
              _sprites.isEmpty ? [_sprite, 'char_fixture#2\$2'] : _sprites,),
          portraitStoriesProvider.overrideWith((ref, key) async => _stories),
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
    await settlePortraits(tester);
  }

  Widget launcher({
    bool fromLine = false,
    String? sprite = 'default',
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
              sprite: sprite == 'default' ? _sprite : sprite,
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
    await settlePortraits(tester);
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

  testWidgets('thumbnails switch the image and face/body metadata',
      (tester) async {
    await pump(tester, launcher(fromLine: true));
    await open(tester);
    expect(find.text('表情 4 / 服装 1'), findsOneWidget);
    expect(find.byType(PortraitImage), findsNWidgets(3));
    final thumb = find.byWidgetPredicate(
        (w) => w is PortraitImage && w.sprite == 'char_fixture#2\$2',);
    await tester.tap(thumb);
    await tester.pumpAndSettle();
    expect(find.text('表情 2 / 服装 2'), findsOneWidget);
    expect(
        tester.widget<PortraitImage>(find.byType(PortraitImage).first).sprite,
        'char_fixture#2\$2',);
  });

  testWidgets('story row opens reader at the first matching line',
      (tester) async {
    await pump(
      tester,
      const PortraitStoriesPage(
        speaker: _speaker,
        groupId: 'char_fixture',
        origin: PortraitOrigin.ask,
      ),
    );
    await tester.tap(find.byType(PressRow).first);
    await tester.pumpAndSettle();
    final reader = tester.widget<StoryReaderPage>(find.byType(StoryReaderPage));
    expect(reader.storyId, 'fixture.txt');
    expect(reader.highlightStart, 2);
    expect(reader.highlightEnd, 2);
    expect(reader.portraitOrigin, PortraitOrigin.ask);
  });

  testWidgets('preview closes outside, on back and on scroll', (tester) async {
    await pump(tester, const StoryReaderPage(storyId: 'fixture.txt'));
    Future<void> preview() async {
      await tester.tap(find.byType(PortraitSpeakerName).first);
      await tester.pumpAndSettle();
      expect(find.text('更多'), findsOneWidget);
    }

    await preview();
    final nameBottom =
        tester.getBottomLeft(find.byType(PortraitSpeakerName).first).dy;
    expect(tester.getTopLeft(find.text('更多')).dy, greaterThan(nameBottom));
    await tester.tapAt(const Offset(380, 800));
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsNothing);
    await preview();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsNothing);
    expect(find.byType(StoryReaderPage), findsOneWidget);
    await preview();
    final nameContext = tester.element(find.byType(PortraitSpeakerName).first);
    final position = Scrollable.of(nameContext).position;
    position.jumpTo(1);
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('a tap outside the preview only closes it', (tester) async {
    await pump(tester, const StoryReaderPage(storyId: 'fixture.txt'));
    final names = find.byType(PortraitSpeakerName);
    await tester.tap(names.first);
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsOneWidget);
    // The search button under the barrier: the first tap closes the card
    // and does not open the search field.
    final search = find.byIcon(Icons.search_sharp);
    expect(search, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(search, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    // With the card gone, a name opens its card again.
    await tester.tap(names.last);
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsOneWidget);
  });

  testWidgets('preview keeps the answer input focused', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            StoryAnswerBody(
              content: '$_speaker 的回答。',
              styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 16)),
              streaming: false,
            ),
            TextField(focusNode: focus),
          ],
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    final rich = find
        .descendant(
            of: find.byType(MarkdownBody), matching: find.byType(RichText),)
        .first;
    await tester.tapAt(tester.getTopLeft(rich) + const Offset(12, 8));
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    await tester.tapAt(const Offset(380, 800));
    await tester.pumpAndSettle();
  });

  for (final dark in [false, true]) {
    testWidgets('reader name style dark=$dark', (tester) async {
      await pump(tester, const StoryReaderPage(storyId: 'fixture.txt'),
          dark: dark,);
      final name = find.byType(PortraitSpeakerName).first;
      final text = tester.widget<Text>(
          find.descendant(of: name, matching: find.byType(Text)).first,);
      final context = tester.element(name);
      final theme = ProviderScope.containerOf(context).read(themeProvider);
      expect(text.style!.decoration, isNot(TextDecoration.underline));
      expect(text.style!.fontFamily, theme.heading(14).fontFamily);
      expect(text.style!.fontVariations, theme.heading(14).fontVariations);
      expect(text.style!.color, dark ? theme.accentText : theme.textPrimary);
      final old = TextPainter(
        text: TextSpan(
          text: _speaker,
          style: theme.ui(14, weight: 700, color: theme.textSecondary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(tester.getSize(name).height, old.height);
      debugPrint(
          'P8 name height: old ${old.height}, current ${tester.getSize(name).height}',);
      old.dispose();
      if (!dark) {
        expect(
            find.descendant(
                of: name,
                matching: find.byWidgetPredicate(
                    (w) => w is ColoredBox && w.color == theme.accentPrimary,),),
            findsOneWidget,);
      }
    });
  }

  testWidgets('pages open over the sheet, back returns to it; origin kept',
      (tester) async {
    await pump(tester, launcher(origin: PortraitOrigin.materials));
    await open(tester);
    await tester.tap(find.text('还有谁使用了这个立绘？'));
    await tester.pumpAndSettle();
    // The card stays under the page (offstage).
    expect(find.byType(PortraitSheet), findsNothing);
    expect(find.byType(PortraitSheet, skipOffstage: false), findsOneWidget);
    expect(
      tester
          .widget<PortraitSpeakersPage>(find.byType(PortraitSpeakersPage))
          .origin,
      PortraitOrigin.materials,
    );
    // A speaker passing by is folded under one row until it is opened.
    expect(find.text('3 个说话人'), findsOneWidget);
    expect(find.text('画外音'), findsNothing);
    expect(find.text('出现次数过少，可能是画外音'), findsOneWidget);
    await tester.tap(find.text('另有 1 人出现很少，主要立绘在别处'));
    await tester.pumpAndSettle();
    expect(find.text('画外音'), findsOneWidget);
    expect(find.text('No.03'), findsOneWidget);
    await tester.tap(find.text(_speaker));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PortraitStoriesPage>(find.byType(PortraitStoriesPage))
          .origin,
      PortraitOrigin.materials,
    );
    // Back from the stories, then from the speakers: the card again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PortraitSheet), findsOneWidget);
  });

  testWidgets('no sprite hides image and group action', (tester) async {
    await pump(tester, launcher(fromLine: true, sprite: null));
    await open(tester);
    expect(find.byType(PortraitImage), findsNothing);
    expect(find.text('还有谁使用了这个立绘？'), findsNothing);
    expect(find.text('这个人还有哪些立绘？'), findsOneWidget);
  });

  testWidgets('unknown speaker keeps only the exact portrait actions',
      (tester) async {
    await pump(tester, launcher(fromLine: true), names: () async => null);
    await open(tester);
    expect(find.text('还有谁使用了这个立绘？'), findsOneWidget);
    expect(find.text('这个人还有哪些立绘？'), findsNothing);
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
        // An underline in the body's colour, not an accent fill.
        expect(markdown.styleSheet!.a!.backgroundColor, isNull);
        expect(markdown.styleSheet!.a!.decoration, TextDecoration.underline);
        expect(markdown.styleSheet!.a!.decorationColor, theme.accentPrimary);
        expect(markdown.styleSheet!.a!.decorationThickness, 2);
        expect(markdown.styleSheet!.a!.color, markdown.styleSheet!.p?.color ?? theme.textPrimary);
        final rich = find
            .descendant(
              of: find.byType(MarkdownBody),
              matching: find.byType(RichText),
            )
            .first;
        await tester.tapAt(tester.getTopLeft(rich) + const Offset(12, 8));
        await tester.pumpAndSettle();
        expect(find.text('更多'), findsOneWidget);
        await tester.tap(find.text('更多'));
        await tester.pumpAndSettle();
        expect(find.byType(PortraitSheet), findsOneWidget);
      }
    });
  }

  testWidgets('an answer from Endfield stories alone links no names',
      (tester) async {
    await pump(
      tester,
      Scaffold(
        body: StoryAnswerBody(
          content: '$_speaker 的回答。`ef/mission_a.txt:3`',
          styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 16)),
          streaming: false,
        ),
      ),
    );
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.data.contains('arklores-speaker:'), isFalse);
  });

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
        expect(find.text('更多'), findsOneWidget);
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
      await capture(tester, '${mode}_reader');
      await tester.tap(find.byType(PortraitSpeakerName).first);
      await tester.pumpAndSettle();
      await capture(tester, '${mode}_preview_below');
      await tester.tapAt(const Offset(380, 800));
      await tester.pumpAndSettle();
      await pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Builder(
              builder: (context) => AppButton(
                '打开',
                onPressed: () => showPortraitPreview(
                  context,
                  speaker: _speaker,
                  origin: PortraitOrigin.ask,
                  anchor: const Rect.fromLTWH(24, 760, 80, 20),
                ),
              ),
            ),
          ),
        ),
        dark: dark,
      );
      await open(tester);
      // Above the name the card is held by its bottom edge, by the name, so
      // it grows up from there.
      final card = find.byWidgetPredicate(
        (w) => w is Positioned && w.width == 172 && w.bottom != null,
      );
      expect(card, findsOneWidget);
      expect(tester.getRect(card).bottom, closeTo(760 - 6, 0.5));
      await capture(tester, '${mode}_preview_above');
      await tester.tapAt(const Offset(380, 100));
      await tester.pumpAndSettle();

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
        await capture(tester, '${mode}_sheet_$kind');
        if (kind == 'ask' && _sprites.length > 10) {
          final strip = find.byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal,);
          expect(find.byType(PortraitImage).evaluate().length, lessThan(12));
          final watch = Stopwatch()..start();
          await tester.fling(strip, const Offset(-2500, 0), 1800);
          await tester.pumpAndSettle();
          debugPrint(
              'P8 thumbnails: ${_sprites.length}, fling elapsed ${watch.elapsedMilliseconds} ms (widget test, not device FPS)',);
        }
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
      await capture(tester, '${mode}_speakers');
      await tester.tap(find.byKey(const ValueKey('portrait-passing-speakers')));
      await tester.pumpAndSettle();
      await capture(tester, '${mode}_speakers_open');
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
      await capture(tester, '${mode}_portraits');
      // A portrait the speaker passes by folds under one row.
      expect(
        find.byKey(const ValueKey('speaker-portrait-avg_npc_passing')),
        findsNothing,
      );
      expect(find.text('另有 1 个立绘出现很少'), findsOneWidget);
      expect(find.text('出现次数过少，可能是画外音'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('speaker-passing-portraits')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('speaker-portrait-avg_npc_passing')),
        findsOneWidget,
      );
      await capture(tester, '${mode}_portraits_open');
      // A row opens that portrait's card: no name on it (the list holds
      // others' portraits too), who uses it and this speaker's stories.
      await tester.tap(
        find.byKey(const ValueKey('speaker-portrait-char_fixture')),
      );
      await tester.pumpAndSettle();
      expect(find.text('谁在用这个立绘？'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('portrait-stories-of-list-speaker')),
        findsOneWidget,
      );
      expect(find.text(_speaker), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, '${mode}_portrait_card_from_list');
      await pump(
          tester,
          const PortraitStoriesPage(
              speaker: _speaker,
              groupId: 'char_fixture',
              origin: PortraitOrigin.ask,),
          dark: dark,);
      await capture(tester, '${mode}_stories');

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
      await capture(tester, '${mode}_answer');
    });
  }
}
