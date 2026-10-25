// The onboarding: one step per part of the setup, each starting with what
// is saved on the device; unchanged steps just go on, changed ones save.
import 'package:arklores/core/background/background_work.dart';
import 'package:arklores/core/gamedata/gamedata_provider.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/features/settings/background_access.dart';
import 'package:arklores/features/settings/onboarding_page.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_installer.dart';
import '../../support/plain_theme.dart';

const _channel = MethodChannel('test/background_work');

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// [calls] collects the methods the background channel is called with;
  /// with [android] the system has background access to ask for.
  Future<ProviderContainer> pumpOnboarding(
    WidgetTester tester, {
    LLMConfig chat = const LLMConfig(),
    EmbeddingConfig embedding = defaultEmbeddingConfig,
    bool android = false,
    List<String>? calls,
    VoidCallback? onComplete,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var exempt = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls?.add(call.method);
      if (call.method == 'requestBatteryExempt') exempt = true;
      if (call.method == 'access') {
        return {'notifications': true, 'batteryExempt': exempt};
      }
      return true;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plainThemeOverride(),
          initialApiConfigProvider.overrideWithValue(chat),
          initialEmbeddingConfigProvider.overrideWithValue(embedding),
          backgroundWorkProvider.overrideWithValue(
            BackgroundWork(channel: _channel, enabled: android),
          ),
          // Arknights downloaded, Endfield not.
          gameDataInstallStatusProvider.overrideWith(
            (ref) async => installStatus(installed: true, installedSha: 'aa', releaseSha: 'aa'),
          ),
          endfieldInstallStatusProvider
              .overrideWith((ref) async => installStatus(installed: false)),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingPage(onComplete: onComplete ?? () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(OnboardingPage)));
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
  }

  Finder step(String name) => find.byKey(ValueKey('onboarding-$name'));

  String nextLabel(WidgetTester tester) => tester
      .widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('onboarding-next')),
        matching: find.byType(Text),
      ),)
      .data!;

  testWidgets('swiping does not advance the onboarding steps', (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('开始使用'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();

    expect(find.text('开始使用'), findsOneWidget);
    expect(step('appearance'), findsNothing);
  });

  testWidgets('every part of the setup has its step, in order; what is '
      'saved is read in and unchanged steps just go on', (tester) async {
    const saved = LLMConfig(
      chatBaseUrl: 'https://llm.example.com/v1',
      chatApiKey: 'saved-key',
      chatModel: 'saved-model',
    );
    await pumpOnboarding(tester, chat: saved);
    expect(find.text('01 / 08'), findsOneWidget); // no background step here

    await next(tester); // welcome
    expect(step('appearance'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-theme')), findsOneWidget);
    await next(tester);
    expect(step('profile'), findsOneWidget);
    await next(tester);

    // The chat service as saved; nothing to save, so just "next".
    expect(step('chat'), findsOneWidget);
    expect(find.text('https://llm.example.com/v1'), findsOneWidget);
    expect(find.text('saved-model'), findsOneWidget);
    expect(nextLabel(tester), '下一步');
    expect(find.byKey(const ValueKey('onboarding-later')), findsNothing);
    await next(tester);

    expect(step('embedding'), findsOneWidget);
    // (The hint says the same.)
    expect(find.text(defaultEmbeddingConfig.model), findsWidgets);
    await next(tester);

    // The knowledge bases say which is downloaded.
    expect(step('knowledgeBase'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget); // Endfield only
    await next(tester);

    expect(step('wiki'), findsOneWidget);
    expect(find.text(SettingsService.defaultWikiSites.first.url), findsOneWidget);
    await next(tester);

    expect(step('done'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-skip')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed service is saved on the way', (tester) async {
    final container = await pumpOnboarding(tester);
    for (var i = 0; i < 3; i++) {
      await next(tester);
    }
    expect(step('chat'), findsOneWidget);
    // No key yet: it can be left for later.
    expect(find.byKey(const ValueKey('onboarding-later')), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('onboarding-chat-key')),
        matching: find.byType(TextField),
      ),
      'new-key',
    );
    await tester.pump();
    expect(nextLabel(tester), '保存并继续');
    await next(tester);
    expect(step('embedding'), findsOneWidget);
    expect(container.read(apiConfigProvider).chatApiKey, 'new-key');
    expect((await SettingsService().loadApiConfig()).chatApiKey, 'new-key');
  });

  testWidgets('on Android the background step asks the system', (tester) async {
    resetBackgroundExplained();
    final calls = <String>[];
    await pumpOnboarding(tester, android: true, calls: calls);
    expect(find.text('01 / 09'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      await next(tester);
    }
    expect(step('background'), findsOneWidget);
    expect(find.text('已允许'), findsOneWidget); // notifications
    await tester.tap(find.byKey(const ValueKey('background-access-battery-grant')));
    await tester.pumpAndSettle();
    expect(calls, contains('requestBatteryExempt'));
    // Back from the system's dialog: read again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('已允许'), findsNWidgets(2));
    // Ask need not explain it again.
    expect(await SettingsService().isBackgroundExplained(), isTrue);
  });

  testWidgets('skipping the guide finishes it', (tester) async {
    var done = false;
    await pumpOnboarding(tester, onComplete: () => done = true);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(await SettingsService().isOnboardingDone(), isTrue);
  });

  testWidgets('the API key field is hidden and not learned', (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < 3; i++) {
      await next(tester);
    }
    final keyField = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) => field.decoration?.hintText == 'sk-...');
    // Hidden until the eye is tapped; never learned by the keyboard.
    expect(keyField.obscureText, isTrue);
    expect(keyField.enableSuggestions, isFalse);
    expect(keyField.autocorrect, isFalse);
    await tester.tap(find.byIcon(Icons.visibility_sharp).first);
    await tester.pump();
    final shown = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) => field.decoration?.hintText == 'sk-...');
    expect(shown.obscureText, isFalse);
  });
}
