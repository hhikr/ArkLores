// The Ask question box: grows to four lines, opens to half and full
// height keeping the draft and the focus, and the send key's two roles.
import 'package:arklores/features/ai/widgets/ask_composer.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  group('Ask composer', () {
    const tabHeight = 600.0;
    var sends = 0;
    late TextEditingController controller;

    Future<void> pumpComposer(
      WidgetTester tester, {
      bool isSending = false,
    }) async {
      await tester.pumpWidget(_app(
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.shrink()),
              AskComposer(
                controller: controller,
                theme: EndfieldThemeTokens(),
                isSending: isSending,
                onSend: () => sends++,
                hintText: '问点什么',
                maxHeight: tabHeight,
              ),
            ],
          ),
        ),
      ),);
      await tester.pump();
    }

    double barHeight(WidgetTester tester) =>
        tester.getSize(find.byKey(const ValueKey('ask-input-bar'))).height;

    setUp(() {
      sends = 0;
      controller = TextEditingController();
    });
    tearDown(() => controller.dispose());

    testWidgets('grows with the text up to four lines, then stops',
        (tester) async {
      await pumpComposer(tester);
      final one = barHeight(tester);
      expect(find.byKey(const ValueKey('ask-input-expand-toggle')), findsOneWidget);
      // The expand button is hidden (transparent, not hit-testable) for a
      // short text.
      controller.text = '一\n二';
      await tester.pumpAndSettle();
      final two = barHeight(tester);
      expect(two, greaterThan(one));
      controller.text = '一\n二\n三\n四';
      await tester.pumpAndSettle();
      final four = barHeight(tester);
      controller.text = '一\n二\n三\n四\n五\n六\n七';
      await tester.pumpAndSettle();
      expect(barHeight(tester), four, reason: 'capped at four lines');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'opens to half and to the full tab; the draft and the focus stay',
        (tester) async {
      await pumpComposer(tester);
      await tester.tap(find.byKey(const ValueKey('ask-input-field')));
      await tester.enterText(
        find.byKey(const ValueKey('ask-input-field')),
        '一\n二\n三\n四',
      );
      await tester.pumpAndSettle();
      final focusNode = tester
          .widget<TextField>(find.byKey(const ValueKey('ask-input-field')))
          .focusNode!;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), closeTo((tabHeight - 15) * 0.5, 1));
      expect(controller.text, '一\n二\n三\n四');
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-input-fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), closeTo(tabHeight - 15, 1));
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('ask-input-fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), closeTo((tabHeight - 15) * 0.5, 1));

      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      expect(barHeight(tester), lessThan((tabHeight - 15) * 0.5));
      expect(controller.text, '一\n二\n三\n四');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keyboard key sends when collapsed, writes a line when open',
        (tester) async {
      await pumpComposer(tester);
      await tester.tap(find.byKey(const ValueKey('ask-input-field')));
      await tester.enterText(
        find.byKey(const ValueKey('ask-input-field')),
        '问题',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sends, 1);

      // Open up (the toggle shows from three lines on, or when open).
      controller.text = '一\n二\n三';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('ask-input-field')));
      expect(field.textInputAction, TextInputAction.newline);
    });

    testWidgets('sending gives the room back', (tester) async {
      controller.text = '一\n二\n三';
      await pumpComposer(tester);
      await tester.tap(find.byKey(const ValueKey('ask-input-expand-toggle')));
      await tester.pumpAndSettle();
      final open = barHeight(tester);
      await pumpComposer(tester, isSending: true);
      await tester.pumpAndSettle();
      expect(barHeight(tester), lessThan(open));
      // The send button became a cancel button.
      expect(find.byTooltip('取消'), findsOneWidget);
    });
  });
}
