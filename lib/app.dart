import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ai/ai_chat_page.dart';
import 'features/materials/materials_page.dart';
import 'features/settings/knowledge_base_page.dart';
import 'features/settings/settings_page.dart';
import 'features/wiki/wiki_browser_page.dart';
import 'shared/l10n/l10n.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/providers/wiki_navigation_provider.dart';
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
  bool _pageTransitioning = false;

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
    final theme = ref.watch(themeProvider);
    final wikiReaderFullscreen = ref.watch(wikiReaderFullscreenProvider);

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
        body: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          opacity: _pageTransitioning ? 0.72 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            scale: _pageTransitioning ? 0.985 : 1,
            child: IndexedStack(
              index: _currentIndex,
              children: _pages,
            ),
          ),
        ),
        bottomNavigationBar: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          child: wikiReaderFullscreen && _currentIndex == 0
              ? const SizedBox.shrink()
              : _IndustrialNavigation(
                  theme: theme,
                  currentIndex: _currentIndex,
                  onSelected: _selectTab,
                  items: [
                    (Icons.language_rounded, context.t.navWiki),
                    (Icons.psychology_alt_rounded, context.t.navAI),
                    (Icons.menu_book_rounded, context.t.navMaterials),
                    (Icons.settings_rounded, context.t.navSettings),
                  ],
                ),
        ),
      ),
    );
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _pageTransitioning = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _pageTransitioning = false);
    });
    ref.read(settingsServiceProvider).saveMainTabIndex(index).catchError(
          (Object error) => debugPrint(
            '[MainShell] Error saving selected tab: $error',
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

class _NavigationItem extends StatefulWidget {
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
  State<_NavigationItem> createState() => _NavigationItemState();
}

class _NavigationItemState extends State<_NavigationItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? (widget.theme.isEndfield
            ? widget.theme.textPrimary
            : widget.theme.navSelectedItem)
        : widget.theme.navUnselectedItem;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onTap();
          });
        },
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? widget.theme.accentPrimary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  bottom: 3,
                  left: widget.selected ? 26 : 32,
                  right: widget.selected ? 26 : 32,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? widget.theme.accentPrimary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: widget.selected ? 1.04 : 1,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      child: Icon(widget.icon, color: color, size: 24),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.theme.bodyFont.copyWith(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            widget.selected ? FontWeight.w700 : FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      return smoothAppRoute(
        settings: settings,
        builder: (_) => const KnowledgeBaseRoute(),
      );
    default:
      return null;
  }
}

PageRoute<T> smoothAppRoute<T>({
  required RouteSettings settings,
  required WidgetBuilder builder,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  );
}
