import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arklores/main.dart';

void main() {
  testWidgets('App renders with bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ArkLoresApp(),
      ),
    );

    // Verify the four bottom nav tabs are present.
    expect(find.text('Wiki'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
