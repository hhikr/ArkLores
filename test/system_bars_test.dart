import 'dart:async';
import 'dart:io';

import 'package:arklores/core/agent/agent_provider.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/settings/settings_sections.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/providers/bars_provider.dart';
import 'package:arklores/shared/providers/handoff_provider.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/system_bars_style.dart';
import 'package:arklores/shared/widgets/ef_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_webview.dart';
import 'support/screenshot.dart';
import 'support/temp_dir.dart';

void main() {
  for (final dark in [false, true]) {
    test('system bars fields dark=$dark', () {
      final style = systemBarsStyle(dark: dark);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarDividerColor, Colors.transparent);
      expect(style.systemStatusBarContrastEnforced, false);
      expect(style.systemNavigationBarContrastEnforced, false);
      expect(
        style.statusBarIconBrightness,
        dark ? Brightness.light : Brightness.dark,
      );
      expect(
        style.systemNavigationBarIconBrightness,
        style.statusBarIconBrightness,
      );
      expect(
        style.statusBarBrightness,
        dark ? Brightness.dark : Brightness.light,
      );
    });
    testWidgets('edge layout and screenshots dark=$dark', (tester) async {
      final docs = Directory.systemTemp.createTempSync('p6');
      FlutterSecureStorage.setMockInitialValues({});
      InAppWebViewPlatform.instance = FakeWebViewPlatform();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => docs.path);
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await deleteTempDir(docs);
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      for (final family in ['Saira', 'NotoSansSC']) {
        await (FontLoader(family)
              ..addFont(rootBundle.load('assets/fonts/$family.ttf')))
            .load();
      }
      await (FontLoader('EndfieldCipher')
            ..addFont(rootBundle.load('assets/fonts/EndfieldByButan.ttf')))
          .load();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialThemeProvider
                .overrideWithValue(dark ? AppTheme.ark : AppTheme.endfield),
            onboardingDoneProvider.overrideWithValue(true),
            initialMainTabIndexProvider.overrideWithValue(2),
            initialApiConfigProvider
                .overrideWithValue(const LLMConfig(chatApiKey: 'test')),
          ],
          child: const Shot(child: ArkLoresApp()),
        ),
      );
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      SystemUiOverlayStyle rootStyle() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
          )
          .value;
      expect(rootStyle(), systemBarsStyle(dark: dark));
      final nav = tester.getRect(find.byKey(const ValueKey('main-navigation')));
      expect(nav.bottom, 844);
      expect(nav.height, 85);
      expect(tester.getRect(find.byKey(const ValueKey('main-top-bar'))).top, 0);
      await shoot(tester, '${dark}_library');
      container.read(mainTabRequestProvider.notifier).state = 1;
      await tester.pumpAndSettle();
      final chat = container
          .read(askChatProvider(container.read(shownAskProvider)).notifier);
      // ignore: invalid_use_of_protected_member
      chat.state = [
        ChatMessage(
          id: 'answer',
          role: MessageRole.assistant,
          content:
              List.generate(70, (i) => '第 $i 段。资料与剧情原文的阅读内容。').join('\n\n'),
          timestamp: DateTime(2026),
        ),
      ];
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('ask-chat-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await shoot(tester, '${dark}_ask');
      await tester.drag(
        find.byKey(const ValueKey('ask-chat-list')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      expect(container.read(barsHiddenProvider), true);
      final topBar = find.byKey(const ValueKey('main-top-bar'));
      final plate =
          find.descendant(of: topBar, matching: find.byType(Transform)).first;
      expect(tester.widget<Transform>(plate).transform.getTranslation().y, -88);
      expect(
        tester.getRect(find.byKey(const ValueKey('ask-input-bar'))).bottom,
        lessThanOrEqualTo(820),
      );
      await shoot(tester, '${dark}_ask_hidden');
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const AppearanceSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(AppearanceSettingsPage),
        matching: find.byType(ListView),
      );
      expect((tester.widget<ListView>(list).padding as EdgeInsets).bottom, 64);
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      await shoot(tester, '${dark}_settings_bottom');
      final context = tester.element(find.byType(AppearanceSettingsPage));
      unawaited(showAppSheet<void>(
        context,
        (_) => const SheetFrame(
          title: '测试面板',
          children: [ActionRow(label: '内容')],
        ),
      ),);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(SheetFrame)).bottom, 844);
      expect(
        tester.getRect(find.byType(ActionRow).last).bottom,
        lessThanOrEqualTo(820),
      );
      await shoot(tester, '${dark}_sheet');
      navigator.pop();
      await tester.pumpAndSettle();
      unawaited(showAppDialog<void>(
        context,
        (_) => const AppDialog(title: '测试对话框', content: Text('内容')),
      ),);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(AppDialog)).bottom, lessThan(820));
      expect(rootStyle(), systemBarsStyle(dark: dark));
      await shoot(tester, '${dark}_dialog');
      container.read(themeProvider.notifier).toggle();
      await tester.pumpAndSettle();
      expect(rootStyle(), systemBarsStyle(dark: !dark));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
