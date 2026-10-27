import 'package:arklores/features/ai/widgets/ask_composer.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/theme/app_theme.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/screenshot.dart';

void main() {
  setUpAll(() async {
    if (shotDir != null) {
      for (final family in ['Saira', 'NotoSansSC']) {
        await (FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/$family.ttf')))
            .load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
  });
  const tabHeight = 600.0;
  final input = find.byKey(const ValueKey('ask-input-field'));
  final bar = find.byKey(const ValueKey('ask-input-bar'));
  final expand = find.byKey(const ValueKey('ask-input-expand-toggle'));
  final full = find.byKey(const ValueKey('ask-input-fullscreen-toggle'));
  var sends = 0;
  late TextEditingController controller;
  TextField field(WidgetTester tester) => tester.widget<TextField>(input);
  double height(WidgetTester tester) => tester.getSize(bar).height;
  Future<void> mount(
    WidgetTester tester, {
    bool sending = false,
    bool dark = false,
    double maxHeight = tabHeight,
  }) async {
    final AppThemeTokens theme =
        dark ? ArkThemeTokens() : EndfieldThemeTokens();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Shot(
            child: Scaffold(
              backgroundColor: theme.bgPrimary,
              body: Column(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  AskComposer(
                    controller: controller,
                    theme: theme,
                    isSending: sending,
                    onSend: () => sends++,
                    hintText: '问点什么',
                    maxHeight: maxHeight,
                    leading: (_) => ComposerButton(
                      key: const ValueKey('options'),
                      theme: theme,
                      tooltip: '选项',
                      icon: Icons.tune_sharp,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester) async {
    await tester.tap(input);
    await tester.pumpAndSettle();
  }

  setUp(() {
    sends = 0;
    controller = TextEditingController();
  });
  tearDown(() => controller.dispose());

  testWidgets('compact row, blank taps and stable editable state',
      (tester) async {
    controller.text = '草稿第一行\n第二行';
    controller.selection = const TextSelection.collapsed(offset: 2);
    await mount(tester);
    final compact = height(tester);
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final selection = controller.selection;
    final rect = tester.getRect(input);
    for (final button in [
      find.byKey(const ValueKey('options')),
      find.byKey(const ValueKey('ask-send')),
    ]) {
      final bounds = tester.getRect(button);
      expect(bounds.top, lessThan(rect.bottom));
      expect(bounds.bottom, greaterThan(rect.top));
    }
    expect(field(tester).maxLines, 1);
    expect(expand, findsNothing);
    await tester.tapAt(tester.getTopLeft(bar) + const Offset(2, 6));
    await tester.pumpAndSettle();
    expect(field(tester).focusNode!.hasFocus, isTrue);
    expect(height(tester), greaterThan(compact));
    expect(
      identical(
        state,
        tester.state<EditableTextState>(find.byType(EditableText)),
      ),
      isTrue,
    );
    expect(controller.selection, selection);
    expect(expand, findsOneWidget);
    await tester.tapAt(tester.getBottomLeft(bar) + const Offset(120, -20));
    await tester.pumpAndSettle();
    expect(field(tester).focusNode!.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('options')));
    await tester.pumpAndSettle();
    expect(field(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('grows to four lines then scrolls', (tester) async {
    await mount(tester);
    await focus(tester);
    final one = height(tester);
    expect(expand, findsOneWidget);
    controller.text = '一\n二';
    await tester.pumpAndSettle();
    expect(height(tester), greaterThan(one));
    controller.text = '一\n二\n三\n四';
    await tester.pumpAndSettle();
    final four = height(tester);
    controller.text = '一\n二\n三\n四\n五\n六\n七';
    await tester.pumpAndSettle();
    expect(height(tester), four);
    expect(tester.takeException(), isNull);
  });

  testWidgets('half, full, half, normal preserve draft and focus',
      (tester) async {
    await mount(tester);
    await focus(tester);
    controller.text = '一\n二\n三\n四';
    await tester.pumpAndSettle();
    final normal = height(tester);
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    for (final step in [
      (expand, (tabHeight - 15) * .5),
      (full, tabHeight - 15),
      (full, (tabHeight - 15) * .5),
      (expand, normal),
    ]) {
      await tester.tap(step.$1);
      await tester.pumpAndSettle();
      expect(height(tester), closeTo(step.$2, 1));
      expect(field(tester).focusNode!.hasFocus, isTrue);
      expect(controller.text, '一\n二\n三\n四');
      expect(
        identical(
          state,
          tester.state<EditableTextState>(find.byType(EditableText)),
        ),
        isTrue,
      );
    }
  });

  testWidgets('newline never sends in any size', (tester) async {
    await mount(tester);
    expect(field(tester).textInputAction, TextInputAction.newline);
    expect(field(tester).onSubmitted, isNull);
    await focus(tester);
    await tester.enterText(input, '问题');
    for (var size = 0; size < 3; size++) {
      await tester.pumpAndSettle();
      expect(field(tester).textInputAction, TextInputAction.newline);
      expect(field(tester).keyboardType, TextInputType.multiline);
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      expect(sends, 0);
      if (size == 0) await tester.tap(expand);
      if (size == 1) await tester.tap(full);
    }
  });

  testWidgets('focus loss resets expanded size and preserves draft',
      (tester) async {
    await mount(tester);
    final compact = height(tester);
    await focus(tester);
    controller.text = '草稿\n第二行';
    await tester.pumpAndSettle();
    final normal = height(tester);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    field(tester).focusNode!.unfocus();
    await tester.pumpAndSettle();
    expect(height(tester), compact);
    expect(controller.text, '草稿\n第二行');
    await focus(tester);
    expect(height(tester), normal);
  });

  testWidgets('sending collapses, unfocuses and shows stop', (tester) async {
    await mount(tester);
    final compact = height(tester);
    await focus(tester);
    controller.text = '问题';
    await tester.tap(expand);
    await tester.pumpAndSettle();
    await mount(tester, sending: true);
    expect(height(tester), compact);
    expect(field(tester).focusNode!.hasFocus, isFalse);
    expect(expand, findsNothing);
    expect(find.byTooltip('取消'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ask-send')));
    expect(sends, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('390x844 screenshots dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mount(tester, dark: dark, maxHeight: 844);
      final prefix = dark ? 'dark' : 'light';
      await shoot(tester, '${prefix}_compact_empty');
      controller.text = '尚未发送的草稿，保留完整内容以便继续编辑。\n补充内容';
      await tester.pumpAndSettle();
      await shoot(tester, '${prefix}_compact_draft');
      await focus(tester);
      controller.text = '请说明剧情背景\n补充后续事件';
      await tester.pumpAndSettle();
      await shoot(tester, '${prefix}_focused');
      await tester.tap(expand);
      await tester.pumpAndSettle();
      await shoot(tester, '${prefix}_half');
      await tester.tap(full);
      await tester.pumpAndSettle();
      await shoot(tester, '${prefix}_full');
      expect(tester.takeException(), isNull);
    });
  }
}
