// The app as main() starts it: onboarding first, then the four-tab shell
// (Wiki, AI, library, settings) with its remembered tab, tab requests from
// other pages and the named routes.
import 'dart:io';

import 'package:arklores/app.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/ai/ai_chat_page.dart';
import 'package:arklores/features/materials/materials_page.dart';
import 'package:arklores/features/settings/api_settings_page.dart';
import 'package:arklores/features/settings/knowledge_base_page.dart';
import 'package:arklores/features/settings/onboarding_page.dart';
import 'package:arklores/features/settings/settings_page.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/features/wiki/wiki_browser_page.dart';
import 'package:arklores/main.dart';
import 'package:arklores/shared/providers/handoff_provider.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:arklores/shared/widgets/page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_webview.dart';
import 'support/plain_theme.dart';
import 'support/temp_dir.dart';

void main() {
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('app_shell');
    FlutterSecureStorage.setMockInitialValues({});
    InAppWebViewPlatform.instance = FakeWebViewPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteTempDir(docs);
  });

  /// The app with the values main() reads at startup.
  Future<ProviderContainer> start(
    WidgetTester tester, {
    bool onboardingDone = true,
    int tab = 0,
  }) async {
    // Wide: the Wiki tab labels do not shrink, and the test font is wider
    // than real ones.
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        onboardingDoneProvider.overrideWithValue(onboardingDone),
        initialApiConfigProvider.overrideWithValue(const LLMConfig()),
        initialMainTabIndexProvider.overrideWithValue(tab),
        initialSessionLogsEnabledProvider.overrideWithValue(false),
        plainThemeOverride(),
      ],
      child: const ArkLoresApp(),
    ),);
    await tester.pump(const Duration(milliseconds: 500));
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  /// Which of the four pages is on screen.
  Type visiblePage(WidgetTester tester) {
    final stack = tester.widget<IndexedStack>(find.descendant(
      of: find.byType(MainShell),
      matching: find.byType(IndexedStack),
    ).first,);
    return stack.children[stack.index!].runtimeType;
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(MainShell),
      matching: find.text(label),
    ).last,);
    await tester.pump(); // the tap acts after the frame
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a first start shows the onboarding, not the shell',
      (tester) async {
    await start(tester, onboardingDone: false);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('opens on the remembered tab; tabs switch and are remembered',
      (tester) async {
    await start(tester, tab: 3);
    expect(visiblePage(tester), SettingsPage);
    expect(find.byKey(const ValueKey('fake-webview'), skipOffstage: false),
        findsWidgets,);

    for (final (label, page, index) in [
      ('AI', AiChatPage, 1),
      ('资料', MaterialsPage, 2),
      ('Wiki', WikiBrowserPage, 0),
    ]) {
      await tapTab(tester, label);
      expect(visiblePage(tester), page, reason: label);
      expect(await SettingsService().loadMainTabIndex(), index, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tab bar spans the bottom, the pages reach under it, it '
      'marks the current tab and steps aside for the keyboard', (tester) async {
    await start(tester, tab: 3);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final nav = tester.getRect(find.byKey(const ValueKey('main-navigation')));
    expect(nav.left, 0);
    expect(nav.right, screen.width);
    expect(nav.bottom, screen.height);
    expect(nav.height, greaterThanOrEqualTo(AppTabBar.height));
    final page = tester.getRect(find.byType(IndexedStack).first);
    expect(page.bottom, screen.height);
    // Every tab says its name, and the current one says it is current.
    final tabs = tester
        .widgetList<Semantics>(find.descendant(
          of: find.byKey(const ValueKey('main-navigation')),
          matching: find.byType(Semantics),
        ),)
        .where((s) => s.properties.button ?? false)
        .toList();
    expect([for (final s in tabs) s.properties.label],
        ['Wiki', 'AI', '资料', '设置'],);
    expect([for (final s in tabs) s.properties.selected],
        [false, false, false, true],);

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('main-navigation')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a main page has one top bar: its tabs on the left, its '
      'action on the right', (tester) async {
    await start(tester, tab: 2);
    final bar = tester.getRect(find.byKey(const ValueKey('main-top-bar')));
    final tabs = tester.getRect(find.byKey(const ValueKey('library-tabs')));
    final action = tester.getRect(find.byKey(const ValueKey('library-search')));
    expect(tabs.left, lessThan(action.left));
    expect(action.right, lessThanOrEqualTo(bar.right));
    expect(action.width, greaterThanOrEqualTo(48));

    await tapTab(tester, 'Wiki');
    final sites = tester.getRect(find.byKey(const ValueKey('wiki-site-0')));
    final bookmarks = tester.getRect(find.byTooltip('书签'));
    expect(bookmarks.left, greaterThan(sites.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('another page can ask for a tab', (tester) async {
    final container = await start(tester);
    container.read(mainTabRequestProvider.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(visiblePage(tester), AiChatPage);
    expect(container.read(mainTabRequestProvider), isNull);
  });

  testWidgets('the named routes open their pages', (tester) async {
    await start(tester, tab: 3);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final (route, page) in [
      ('/knowledge-base', KnowledgeBasePage),
      ('/api-settings', ApiSettingsPage),
    ]) {
      navigator.pushNamed(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(page), findsOneWidget, reason: route);
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(tester.takeException(), isNull);
  });
}
