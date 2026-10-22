import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ai/ai_chat_page.dart';
import 'features/materials/materials_page.dart';
import 'features/settings/settings_page.dart';
import 'features/wiki/wiki_browser_page.dart';
import 'shared/l10n/l10n.dart';
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
        // moves.
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        // Hidden while the keyboard is up: the question box then sits on
        // the keyboard, not on the tab bar.
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? const SizedBox.shrink()
            : AppTabBar(
                current: _currentIndex,
                onSelected: _selectTab,
                items: [
                  ('WIKI', context.t.navWiki),
                  ('ASK', context.t.navAI),
                  ('LIBRARY', context.t.navMaterials),
                  ('SETTINGS', context.t.navSettings),
                ],
              ),
      ),
    );
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    ref.read(settingsServiceProvider).saveMainTabIndex(index).catchError(
          (Object error) => debugPrint(
            '[MainShell] Error saving selected tab: $error',
          ),
        );
  }
}
