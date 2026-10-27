import 'dart:io';

import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/portrait_provider.dart';
import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_provider.dart';
import 'package:arklores/features/ai/widgets/story_answer_body.dart';
import 'package:arklores/features/library/material_pages.dart';
import 'package:arklores/features/materials/materials_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/screenshot.dart';

const source = MaterialSource(
    id: 'book',
    title: '大地巡旅',
    builtin: true,
    enabled: true,
    kind: '官方世界观补充',
    policy: '本书采用世界观内叙述。正文与批注分开署名，来源说明不等同于已证实事实。',);
final doc = parseMaterial(
    id: 'book/intro',
    sourceId: 'book',
    title: '源石',
    body:
        '# 源石\n\n源石是泰拉大地上普遍存在的一种蕴含能量的结晶矿物。\n\n## 自然增长\n\n在天然环境中，源石有时会进行某种程度的自我复制。',);

class _Library extends MaterialLibraryController {
  _Library(super.ref) : super(load: false) {
    state = MaterialLibraryState(sources: [
      source,
      const MaterialSource(id: 'personal/note', title: '关于移动城市的笔记'),
    ], documents: [
      doc,
    ], status: const {
      'book': (state: 'ready', error: null),
    },);
  }
  @override
  Future<void> select(MaterialSource s, bool enabled) async {
    state = MaterialLibraryState(sources: [
      for (final x in state.sources)
        if (x.id == s.id) x.copyWith(enabled: enabled) else x,
    ], documents: state.documents, status: state.status,);
  }
}

void main() {
  setUpAll(() async {
    final saira = FontLoader('Saira')
      ..addFont(rootBundle.load('assets/fonts/Saira.ttf'));
    await saira.load();
    final chinese = File('C:/Windows/Fonts/msyh.ttc');
    if (await chinese.exists()) {
      final loader = FontLoader('Noto Sans SC')
        ..addFont(chinese.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
    final icons = File(
        'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',);
    if (await icons.exists()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  Future<void> pump(WidgetTester tester, Widget page,
      {bool dark = false, double width = 390,}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          gameLibraryStatusProvider
              .overrideWith((ref, g) async => LibraryStatus.notInstalled),
          materialLibraryProvider.overrideWith((ref) => _Library(ref)),
          citedMaterialProvider.overrideWith((ref, id) async => doc),
          highlightNamesProvider.overrideWith((ref) async => const []),
          themeProvider.overrideWith((ref) =>
              ThemeNotifier(dark ? ArkThemeTokens() : EndfieldThemeTokens()),),
        ],
        child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(fontFamily: 'Noto Sans SC'),
            home: Shot(
                child: ColoredBox(
                    color: dark
                        ? ArkThemeTokens().bgPrimary
                        : EndfieldThemeTokens().bgPrimary,
                    child: page is SupplementalMaterialsView
                        ? const MaterialsPage()
                        : page,),),),),);
    await tester.pumpAndSettle();
    if (page is SupplementalMaterialsView) {
      await tester.tap(find.text('补充资料').first);
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'mobile reference controls use existing design and persist controller choice',
      (tester) async {
    await pump(tester, const SupplementalMaterialsView());
    expect(find.text('大地巡旅'), findsOneWidget);
    expect(find.textContaining('已就绪'), findsOneWidget);
    await shoot(tester, 'materials_light_mobile');
    await tester.tap(find.byType(SquareSwitch).first);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SupplementalMaterialsView)),);
    expect(
        container.read(materialLibraryProvider).sources.first.enabled, isFalse,);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dark and narrow layouts have no overflow', (tester) async {
    await pump(tester, const SupplementalMaterialsView(),
        dark: true, width: 320,);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'materials_dark_narrow');
  });
  testWidgets('a paragraph cited from a material counts as a source',
      (tester) async {
    await pump(
      tester,
      Scaffold(
        body: StoryAnswerBody(
          content: '源石有时会自我复制。`${doc.pageId}:P3`',
          styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 16)),
          streaming: false,
          revealImmediately: true,
        ),
      ),
    );
    expect(find.text('出处 1'), findsOneWidget);
    await tester.tap(find.text('出处 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 4 段'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-P3')), findsOneWidget);
    expect(find.byKey(const ValueKey('material-P0')), findsNothing);
  });
  testWidgets('an included source is not opened from the list', (tester) async {
    await pump(tester, const SupplementalMaterialsView());
    await tester.tap(find.text('大地巡旅'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialReaderPage), findsNothing);
    expect(find.text('来源说明'), findsWidgets);
  });
  testWidgets('a citation of an included source shows only the cited paragraphs',
      (tester) async {
    await pump(
        tester, MaterialReaderPage(pageId: doc.pageId, start: 3, end: 3),);
    expect(find.byKey(const ValueKey('material-P3')), findsOneWidget);
    expect(find.textContaining('自我复制'), findsOneWidget);
    expect(find.byKey(const ValueKey('material-P0')), findsNothing);
    expect(find.text('这份资料只显示问答引用的段落。'), findsOneWidget);
    await shoot(tester, 'materials_reader_mobile');
    expect(tester.takeException(), isNull);
  });
}
