import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ai/ai_chat_page.dart';
import 'features/materials/materials_page.dart';
import 'features/settings/settings_page.dart';
import 'features/wiki/wiki_browser_page.dart';
import 'shared/l10n/l10n.dart';
import 'shared/providers/bars_provider.dart';
import 'shared/providers/handoff_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/wiki_navigation_provider.dart';
import 'shared/widgets/page_frame.dart';

/// Main shell that wraps the app with bottom navigation and four tabs.
///
/// The tabs switch at once; the accent block in the tab bar moves.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    WikiBrowserPage(),
    AiChatPage(),
    MaterialsPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = ref.read(initialMainTabIndexProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Another page asked for a tab (the library's "ask about it").
    ref.listen<int?>(mainTabRequestProvider, (_, tab) {
      if (tab == null) return;
      ref.read(mainTabRequestProvider.notifier).state = null;
      _selectTab(tab);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentIndex == 0) {
          final handled = await (ref.read(wikiBackHandlerProvider)?.call() ??
              Future.value(false));
          if (handled) return;
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The pages run under the tab bar; they get its height as bottom
        // padding (MediaQuery).
        extendBody: true,
        // Tabs switch at once: the accent block in the tab bar is what
        // moves. The hidden tabs stay built but not running (TickerMode):
        // the wiki's web pages pause there, which otherwise redraw on the
        // thread the app's frames start on and slowed every tab. Nor do they
        // follow the keyboard (_TabSlot).
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _pages.length; i++)
              TickerMode(
                enabled: i == _currentIndex,
                child: _TabSlot(
                  shown: i == _currentIndex,
                  systemBottom: MediaQuery.viewPaddingOf(context).bottom,
                  child: _pages[i],
                ),
              ),
          ],
        ),
        // Under the keyboard once the keyboard is taller than it: until then
        // the question box stays on the bar, after that it rides the
        // keyboard, with no jump in between (dropping the bar on the first
        // frame of the keyboard took its height from under the box at once).
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom >
                AppTabBar.height + MediaQuery.viewPaddingOf(context).bottom
            ? const SizedBox.shrink()
            // Off the bottom while the wiki or Ask reads full screen; its
            // room stays (the pages are not laid out again), the page shows
            // through it.
            : BarsAway(
                distance:
                    AppTabBar.height + MediaQuery.viewPaddingOf(context).bottom,
                child: AppTabBar(
                  current: _currentIndex,
                  onSelected: _selectTab,
                  items: [
                    ('LOOKUP', context.t.navWiki),
                    ('ASK', context.t.navAI),
                    ('LIBRARY', context.t.navMaterials),
                    ('SETTINGS', context.t.navSettings),
                  ],
                ),
              ),
      ),
    );
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    ref.read(barsHiddenProvider.notifier).state = false;
    setState(() => _currentIndex = index);
    ref.read(settingsServiceProvider).saveMainTabIndex(index).catchError(
          (Object error) => debugPrint(
            '[MainShell] Error saving selected tab: $error',
          ),
        );
  }
}

/// One tab of [MainShell]. A hidden tab is laid out at the screen's full
/// height and sees no keyboard: while the keyboard moves the shell's body
/// changes height every frame, and the stack lays out all its children, so
/// every tab rebuilt and laid out its text again each frame (the question
/// box rose in stutters). The same widgets either way, so a tab keeps its
/// state when it is shown or hidden.
class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.shown,
    required this.systemBottom,
    required this.child,
  });

  final bool shown;
  final double systemBottom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Scaffold removes the bottom view padding when it owns a tab bar.
    // Keep the system inset so floating controls stop above the gesture bar.
    final inherited = MediaQuery.of(context);
    final media = inherited.copyWith(
      viewPadding: inherited.viewPadding.copyWith(bottom: systemBottom),
    );
    final height = shown ? null : media.size.height;
    return MediaQuery(
      data: shown ? media : media.removeViewInsets(removeBottom: true),
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: height,
        maxHeight: height,
        child: child,
      ),
    );
  }
}
