// Why the app asks to run in the background: said once, before the system
// is asked; never when the app is exempt already or there is nothing to ask.
import 'package:arklores/core/background/background_work.dart';
import 'package:arklores/features/settings/background_access.dart';
import 'package:arklores/features/settings/settings_service.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plain_theme.dart';

const _channel = MethodChannel('test/background_work');

void main() {
  late List<String> calls;
  late bool exempt;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    resetBackgroundExplained();
    calls = [];
    exempt = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      if (call.method == 'access') {
        return {'notifications': true, 'batteryExempt': exempt};
      }
      return true;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> pump(WidgetTester tester, {bool android = true}) =>
      tester.pumpWidget(ProviderScope(
        overrides: [
          plainThemeOverride(),
          backgroundWorkProvider.overrideWithValue(
            BackgroundWork(channel: _channel, enabled: android),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                key: const ValueKey('ask'),
                onPressed: () => explainBackgroundOnce(context, ref),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),);

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
  }

  final dialog = find.byKey(const ValueKey('background-access-dialog'));

  testWidgets('said once; "allow" asks the system', (tester) async {
    await pump(tester);
    await ask(tester);
    expect(dialog, findsOneWidget);
    expect(find.textContaining('没有自己的服务器'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('background-access-allow')));
    await tester.pumpAndSettle();
    expect(calls, contains('requestBatteryExempt'));
    expect(await SettingsService().isBackgroundExplained(), isTrue);

    // Not again in this run, nor after a restart.
    await ask(tester);
    expect(dialog, findsNothing);
    resetBackgroundExplained();
    await ask(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('nothing when exempt already', (tester) async {
    exempt = true;
    await pump(tester);
    await ask(tester);
    expect(dialog, findsNothing);
    expect(calls, isNot(contains('requestBatteryExempt')));
  });

  testWidgets('nothing where there is nothing to ask', (tester) async {
    await pump(tester, android: false);
    await ask(tester);
    expect(dialog, findsNothing);
    expect(calls, isEmpty);
  });
}
