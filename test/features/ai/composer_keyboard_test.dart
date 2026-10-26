import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_webview.dart';
import '../../support/screenshot.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('composer stays between header and keyboard dark=$dark',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      InAppWebViewPlatform.instance = FakeWebViewPlatform();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      if (shotDir != null) {
        for (final family in ['Saira', 'NotoSansSC']) {
          await (FontLoader(family)
                ..addFont(rootBundle.load('assets/fonts/$family.ttf')))
              .load();
        }
        await (FontLoader('EndfieldCipher')
              ..addFont(rootBundle.load('assets/fonts/EndfieldByButan.ttf')))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialThemeProvider
                .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
            onboardingDoneProvider.overrideWithValue(true),
            initialMainTabIndexProvider.overrideWithValue(1),
            initialApiConfigProvider
                .overrideWithValue(const LLMConfig(chatApiKey: 'test')),
          ],
          child: const Shot(child: ArkLoresApp()),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ask-input-field'));
      final bar = find.byKey(const ValueKey('ask-input-bar'));
      final expand = find.byKey(const ValueKey('ask-input-expand-toggle'));
      final full = find.byKey(const ValueKey('ask-input-fullscreen-toggle'));
      void bounds() {
        final frame = tester.getRect(bar);
        final field = tester.getRect(input);
        final header =
            tester.getRect(find.byKey(const ValueKey('main-top-bar')));
        expect(frame.top, greaterThanOrEqualTo(header.bottom));
        expect(
          frame.bottom,
          lessThanOrEqualTo(844 - tester.view.viewInsets.bottom),
        );
        expect(field.left, greaterThanOrEqualTo(frame.left));
        expect(field.right, lessThanOrEqualTo(frame.right));
        expect(field.top, greaterThanOrEqualTo(frame.top));
        expect(field.bottom, lessThanOrEqualTo(frame.bottom));
        expect(frame.height.isFinite, isTrue);
      }

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      bounds();
      await tester.tap(input);
      await tester.enterText(input, List.filled(30, '请说明剧情背景与后续事件。').join());
      await tester.pumpAndSettle();
      bounds();
      final keyboard = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 300,
          child: IgnorePointer(
            child: ColoredBox(
              color: dark ? const Color(0xff292929) : const Color(0xffd8dadd),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final row in [
                    'QWERTYUIOP',
                    'ASDFGHJKL',
                    'ZXCVBNM',
                    '123  SPACE  ↵',
                  ])
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final letter in row.split(''))
                          Text(
                            letter,
                            style: TextStyle(
                              fontSize: 20,
                              fontFamily: 'Saira',
                              decoration: TextDecoration.none,
                              color: dark ? Colors.white : Colors.black,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      Overlay.of(tester.element(input)).insert(keyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shoot(tester, '${dark}_keyboard_collapsed');
      for (final step in [expand, full, full, expand]) {
        await tester.tap(step);
        await tester.pump();
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          bounds();
        }
        await tester.pumpAndSettle();
        bounds();
        if (step == expand && full.evaluate().isNotEmpty) {
          await shoot(tester, '${dark}_keyboard_half');
        } else if (step == full) {
          final icon = tester.widget<Icon>(
            find.descendant(of: full, matching: find.byType(Icon)),
          );
          if (icon.icon == Icons.close_fullscreen_sharp) {
            await shoot(tester, '${dark}_keyboard_full');
          }
        }
      }
      keyboard.remove();
      for (final inset in [0.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        bounds();
        await tester.tap(expand);
        await tester.pumpAndSettle();
        bounds();
        await tester.tap(full);
        await tester.pumpAndSettle();
        bounds();
        await tester.tap(expand);
        await tester.pumpAndSettle();
        bounds();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
