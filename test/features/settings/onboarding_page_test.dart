import 'package:arklores/features/settings/onboarding_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOnboarding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingPage(onComplete: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('swiping does not advance the onboarding steps', (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('开始使用'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();

    expect(find.text('开始使用'), findsOneWidget);
    expect(find.text('配置对话 API'), findsNothing);
  });

  testWidgets('no "跳过" wording; API key field is visible but not learned',
      (tester) async {
    await pumpOnboarding(tester);
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    expect(find.text('配置对话 API'), findsOneWidget);
    expect(find.textContaining('跳过'), findsNothing);
    expect(find.text('以后再说'), findsOneWidget);

    final keyField = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) => field.decoration?.hintText == 'sk-...');
    expect(keyField.obscureText, isFalse);
    expect(keyField.enableSuggestions, isFalse);
    expect(keyField.autocorrect, isFalse);
  });
}
