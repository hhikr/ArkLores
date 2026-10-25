// A long plain text (or voice lines) on an entry page is a lazy list in its
// panel: only the paragraphs near the screen are built and laid out, the
// rest as it scrolls near.
import 'package:arklores/core/library/library_queries.dart';
import 'package:arklores/features/library/entry_page.dart';
import 'package:arklores/features/library/reading_text.dart';
import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const entry = LibraryEntry(id: 'item:x', type: 'item', name: 'X');

  Future<void> pump(WidgetTester tester, EntryTextBlock block) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => CustomScrollView(
                  slivers: [
                    EntryPage.textSliver(
                      ref.watch(themeProvider),
                      entry,
                      block,
                      '',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a long text builds only what is near the screen',
      (tester) async {
    final text = [for (var i = 0; i < 300; i++) '第$i段。' * 8].join('\n\n');
    await pump(tester, EntryTextBlock(title: '描述', content: text));
    final built = find.byType(ReadingParagraphView).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60), reason: '$built of 300 paragraphs built');
    expect(find.textContaining('第0段'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('第299段'),
      2000,
      scrollable: find.byType(Scrollable),
    );
    expect(find.textContaining('第299段'), findsOneWidget);
  });

  testWidgets('voice lines too, under their heading', (tester) async {
    final text = [for (var i = 0; i < 200; i++) '交谈$i：第$i句台词。'].join('\n');
    await pump(tester, EntryTextBlock(title: '语音记录', content: text));
    expect(find.text('语音记录'), findsOneWidget);
    final built = find.byType(VoiceLine).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60), reason: '$built of 200 lines built');
  });
}
