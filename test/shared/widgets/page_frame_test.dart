// The top bar of a pushed page: a back button with a cut corner, the title
// (ellipsised when long), the actions on the right, a hairline below;
// content that scrolls under it is padded clear of it.
import 'package:arklores/shared/widgets/dock_scaffold.dart';
import 'package:arklores/shared/widgets/page_frame.dart';
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

void main() {
  testWidgets(
      'back, title and actions sit in one bar; no app bar; '
      'the back button is 48 to the finger', (tester) async {
    await _push(
      tester,
      PageScaffold(
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
    final bar = tester.getRect(find.byKey(const ValueKey('page-top-bar')));
    final back = tester.getRect(find.byKey(const ValueKey('page-back')));
    final title = tester.getRect(find.text('短标题'));
    final action = tester.getRect(find.byTooltip('find'));
    expect(back.width, greaterThanOrEqualTo(48));
    expect(back.height, greaterThanOrEqualTo(48));
    expect(title.left, greaterThan(back.right));
    expect(action.right, lessThanOrEqualTo(bar.right));
    expect(back.top, greaterThanOrEqualTo(bar.top));
    expect(back.bottom, lessThanOrEqualTo(bar.bottom));

    await tester.tap(find.byKey(const ValueKey('page-back')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a long title takes the free width and ends in an ellipsis',
      (tester) async {
    await _push(
      tester,
      PageScaffold(
        title: '很长的标题' * 20,
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () {})],
        body: const SizedBox.expand(),
      ),
    );
    final title = tester.getRect(find.textContaining('很长的标题'));
    final action = tester.getRect(find.byIcon(Icons.search));
    expect(title.right, lessThanOrEqualTo(action.left));
    expect(title.width, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'scrollUnder: the list starts under the bar, padded clear of '
      'it; otherwise the body starts below it', (tester) async {
    await _push(
      tester,
      PageScaffold(
        title: 'T',
        scrollUnder: true,
        body: Builder(
          builder: (context) => ListView(
            padding: pagePadding(context, EdgeInsets.zero),
            children: const [SizedBox(height: 20, child: Text('first'))],
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byKey(const ValueKey('page-top-bar')));
    expect(tester.getRect(find.byType(ListView)).top, 0);
    expect(
      tester.getTopLeft(find.text('first')).dy,
      greaterThanOrEqualTo(bar.bottom),
    );

    await tester.tap(find.byKey(const ValueKey('page-back')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _push(
      tester,
      const PageScaffold(title: 'T', body: SizedBox.expand(key: Key('b'))),
    );
    expect(tester.getRect(find.byKey(const Key('b'))).top, topBarInset);
  });

  testWidgets(
      'a dock page: separate plates float over the body near the '
      'bottom', (tester) async {
    var opened = 0;
    Widget page() => DockScaffold(
          title: '章节',
          status: const Text('3 / 10'),
          onTitleTap: () => opened++,
          actions: [
            DockAction(
              key: const ValueKey('find'),
              tooltip: 'find',
              icon: Icons.search,
              onPressed: () {},
            ),
          ],
          body: const SizedBox.expand(key: Key('b')),
        );
    await _push(tester, page());
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final back = tester.getRect(find.byKey(const ValueKey('page-back')));
    final title = tester.getRect(find.byKey(const ValueKey('page-title')));
    final find_ = tester.getRect(find.byKey(const ValueKey('find')));
    // The body runs under them, to the bottom of the screen.
    expect(tester.getRect(find.byKey(const Key('b'))).bottom, screen.height);
    for (final plate in [back, title, find_]) {
      expect(plate.height, floatingDockHeight);
      expect(plate.bottom, lessThan(screen.height - 4), reason: 'floating');
    }
    expect(back.left, greaterThanOrEqualTo(8), reason: 'off the edge');
    expect(title.left - back.right, greaterThanOrEqualTo(6), reason: 'apart');
    expect(find_.left - title.right, greaterThanOrEqualTo(6));
    expect(find_.right, lessThanOrEqualTo(screen.width - 8));
    expect(
      floatingDockRoom(tester.element(find.byKey(const Key('b')))),
      greaterThanOrEqualTo(screen.height - title.top),
    );
    await tester.tap(find.byKey(const ValueKey('page-title')));
    expect(opened, 1);
    await tester.tap(find.byKey(const ValueKey('page-back')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the tab bar slides one block to the tab chosen', (tester) async {
    var current = 0;
    late StateSetter set;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return AppTabBar(
                  items: const [('A', '甲'), ('B', '乙'), ('C', '丙')],
                  current: current,
                  onSelected: (i) => set(() => current = i),
                );
              },
            ),
          ),
        ),
      ),
    );
    final block = find.byKey(const ValueKey('main-navigation-block'));
    expect(block, findsOneWidget);
    final from = tester.getRect(block).left;
    await tester.tap(find.text('丙'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final mid = tester.getRect(block).left;
    await tester.pumpAndSettle();
    final to = tester.getRect(block).left;
    expect(mid, greaterThan(from));
    expect(mid, lessThan(to));
    expect(
      tester.getCenter(block).dx,
      closeTo(tester.getCenter(find.text('丙')).dx, 4),
    );
  });
}
