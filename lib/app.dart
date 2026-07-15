import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ai/ai_chat_page.dart';
import 'features/materials/materials_page.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/settings_page.dart';
import 'features/wiki/wiki_browser_page.dart';
import 'shared/l10n/l10n.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/theme/app_theme.dart';

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
      backgroundColor: Colors.transparent,
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
      bottomNavigationBar: _IndustrialNavigation(
        theme: theme,
        currentIndex: _currentIndex,
        onSelected: (index) => setState(() => _currentIndex = index),
        items: [
          (Icons.language_rounded, context.t.navWiki),
          (Icons.psychology_alt_rounded, context.t.navAI),
          (Icons.menu_book_rounded, context.t.navMaterials),
          (Icons.settings_rounded, context.t.navSettings),
        ],
      ),
    );
  }
}

class _IndustrialNavigation extends StatelessWidget {
  const _IndustrialNavigation({
    required this.theme,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
  });

  final AppThemeTokens theme;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.bgSecondary,
      child: SafeArea(
        top: false,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.cardBorder)),
          ),
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _NavigationItem(
                    theme: theme,
                    icon: items[index].$1,
                    label: items[index].$2,
                    selected: index == currentIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.theme,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppThemeTokens theme;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? (theme.isEndfield ? theme.textPrimary : theme.navSelectedItem)
        : theme.navUnselectedItem;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selected)
              Positioned(
                top: 0,
                left: 18,
                right: 18,
                child: Container(height: 3, color: theme.accentPrimary),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyFont.copyWith(
                    color: color,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
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
