import 'package:arklores/core/library/library_provider.dart';
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/features/library/collection_page.dart';
import 'package:arklores/features/library/shelf_page.dart';
import 'package:arklores/shared/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_user_store.dart';
import 'library_ui_test.dart' as fixtures;

void main() {
  const shelf = [
    LibraryCollection(
      id: 'new',
      kind: 'activity',
      name: '新的短篇',
      stories: 2,
      others: 0,
      startTime: 2000,
    ),
    LibraryCollection(
      id: 'old',
      kind: 'activity',
      name: '旧的长篇',
      stories: 2,
      others: 0,
      startTime: 1000,
    ),
  ];

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixtures.overrides(MemoryUserStore()),
          collectionsOfKindProvider.overrideWith((ref, _) async => shelf),
          collectionWordCountsProvider
              .overrideWith((ref, _) async => {'new': 900, 'old': 123000}),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String name) =>
      tester.getTopLeft(find.text(name)).dy;

  testWidgets('a shelf sorts its collections by time or by length',
      (tester) async {
    await pump(tester, const ShelfPage(kind: 'activity'));
    expect(top(tester, '新的短篇'), lessThan(top(tester, '旧的长篇')));
    expect(find.textContaining('12.3 万字'), findsOneWidget);
    expect(find.textContaining('900 字'), findsOneWidget);
    await tester.tap(find.text('字数'));
    await tester.pumpAndSettle();
    expect(top(tester, '旧的长篇'), lessThan(top(tester, '新的短篇')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the stories in a collection stay in reading order',
      (tester) async {
    await pump(tester, const CollectionPage(collectionId: 'main_9'));
    expect(find.byKey(const ValueKey('shelf-sort')), findsNothing);
    expect(find.text('字数'), findsNothing);
  });
}
