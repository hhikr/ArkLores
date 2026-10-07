// The floating docks of a pushed page: a round back button, the title in
// a pill as wide as the title, the actions in a pill on the right, the
// page showing between them; content that scrolls under them is padded.
import 'package:arklores/shared/widgets/floating_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _push(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(780, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Rect _pillAround(WidgetTester tester, Finder child) => tester.getRect(
      find.ancestor(of: child, matching: find.byType(FloatingBar)).first,
    );

void main() {
  testWidgets('back, title and actions are separate pills; no app bar',
      (tester) async {
    await _push(
      tester,
      FloatingScaffold(
        title: '短标题',
        actions: [
          IconButton(
            tooltip: 'find',
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
        body: const SizedBox.expand(),
      ),
    );
    expect(find.byType(AppBar), findsNothing);
    final back = _pillAround(tester, find.byType(BackButton));
    final title = _pillAround(tester, find.text('短标题'));
    final actions = _pillAround(tester, find.byTooltip('find'));
    expect(back.width, back.height); // round
    expect(title.left, greaterThan(back.right));
    expect(title.width, lessThan(150)); // hugs the title
    expect(actions.left - title.right, greaterThan(100)); // page between
    expect(actions.right, lessThan(390));

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a long title takes the free width and ends in an ellipsis',
      (tester) async {
    await _push(
      tester,
      FloatingScaffold(
        title: '很长的标题' * 20,
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () {})],
        body: const SizedBox.expand(),
      ),
    );
    final title = _pillAround(tester, find.textContaining('很长的标题'));
    final actions = _pillAround(tester, find.byIcon(Icons.search));
    expect(title.right, lessThanOrEqualTo(actions.left));
    expect(title.width, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrollUnder: the list starts under the docks, padded clear of '
      'them; otherwise the body starts below them', (tester) async {
    await _push(
      tester,
      FloatingScaffold(
        title: 'T',
        scrollUnder: true,
        body: Builder(
          builder: (context) => ListView(
            padding: floatingPadding(context, EdgeInsets.zero),
            children: const [SizedBox(height: 20, child: Text('first'))],
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byKey(const ValueKey('floating-page-bar')));
    expect(tester.getRect(find.byType(ListView)).top, 0);
    expect(tester.getTopLeft(find.text('first')).dy,
        greaterThanOrEqualTo(bar.bottom),);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _push(
      tester,
      const FloatingScaffold(title: 'T', body: SizedBox.expand(key: Key('b'))),
    );
    expect(tester.getRect(find.byKey(const Key('b'))).top,
        floatingTopInset,);
  });
}
