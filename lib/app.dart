import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ai/ai_chat_page.dart';
import 'features/materials/materials_page.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/settings_page.dart';
import 'features/wiki/wiki_browser_page.dart';
import 'shared/providers/theme_provider.dart';

/// Main shell that wraps the app with bottom navigation and four tabs.
///
/// When the theme switches, the body area fades through a 300ms
/// cross-fade transition driven by [AnimatedSwitcher].
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
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey('page_${theme.themeName}'),
          child: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
        ),
      ),
      bottomNavigationBar: Theme(
        data: ThemeData(
          canvasColor: theme.bgSecondary,
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: theme.bgSecondary,
          selectedItemColor: theme.navSelectedItem,
          unselectedItemColor: theme.navUnselectedItem,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.language_rounded),
              label: 'Wiki',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.psychology_rounded),
              label: 'AI',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_rounded),
              label: '资料',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}

/// Knowledge base page route wrapper.
///
/// Called from [MainShell] via Navigator.pushNamed.
class KnowledgeBaseRoute extends ConsumerWidget {
  const KnowledgeBaseRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const KnowledgeBasePage();
  }
}

/// Route generator for sub-pages pushed over the main shell.
Route<dynamic>? generateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/knowledge-base':
      return MaterialPageRoute(
        builder: (_) => const KnowledgeBaseRoute(),
        settings: settings,
      );
    default:
      return null;
  }
}
