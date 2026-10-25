// The opening: the word pushed out left to right over the app, then gone;
// nothing in tests' plain builds or with reduced motion.
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:arklores/shared/widgets/launch_curtain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plain_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool on = true,
    bool reduced = false,
  }) =>
      tester.pumpWidget(ProviderScope(
        overrides: [
          plainThemeOverride(),
          launchCurtainProvider.overrideWithValue(on),
        ],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => LaunchCurtain(child: child!),
            home: const Scaffold(body: Text('app')),
          ),
        ),
      ),);

  testWidgets('pushes the word out, then leaves the app', (tester) async {
    await pump(tester);
    expect(find.text('app'), findsOneWidget); // built behind it
    expect(find.text('ARKLORES'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('剧情阅读与问答'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('ARKLORES'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('nothing with reduced motion, nor when not asked for',
      (tester) async {
    await pump(tester, reduced: true);
    expect(find.text('ARKLORES'), findsNothing);
    await pump(tester, on: false);
    expect(find.text('ARKLORES'), findsNothing);
  });
}
