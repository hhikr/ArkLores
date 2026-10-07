import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ai/ai_chat_page.dart';
import 'features/materials/materials_page.dart';
import 'features/settings/settings_page.dart';
import 'features/wiki/wiki_browser_page.dart';
import 'shared/l10n/l10n.dart';
import 'shared/providers/handoff_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/providers/wiki_navigation_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/floating_bar.dart';

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
  bool _pageRevealActive = false;
  int _pageRevealToken = 0;

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
        // The navigation floats over the pages; they get its height as
        // bottom padding (MediaQuery) and scroll underneath it.
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _pages,
            ),
            _buildPageTransitionOverlay(theme),
          ],
        ),
        bottomNavigationBar: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          // Hidden while the keyboard is up: the question box then sits on
          // the keyboard, not on the navigation.
          child: (wikiReaderFullscreen && _currentIndex == 0) ||
                  MediaQuery.viewInsetsOf(context).bottom > 0
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
      _pageRevealActive = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _pageTransitioning = false;
        _pageRevealActive = true;
        _pageRevealToken++;
      });
    });
    ref.read(settingsServiceProvider).saveMainTabIndex(index).catchError(
          (Object error) => debugPrint(
            '[MainShell] Error saving selected tab: $error',
          ),
        );
  }

  Widget _buildPageTransitionOverlay(AppThemeTokens theme) {
    if (_pageTransitioning) {
      return Positioned.fill(
        child: IgnorePointer(
          child: ColoredBox(color: theme.bgPrimary),
        ),
      );
    }
    if (!_pageRevealActive) return const SizedBox.shrink();

    final token = _pageRevealToken;
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(token),
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (!mounted || token != _pageRevealToken) return;
            setState(() => _pageRevealActive = false);
          },
          builder: (context, opacity, child) {
            return Opacity(opacity: opacity, child: child);
          },
          child: ColoredBox(color: theme.bgPrimary),
        ),
      ),
    );
  }
}

/// The bottom navigation: a floating pill (52 high) off the screen edges,
/// the selected tab's icon in a small pill inside it.
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

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: FloatingBar(
          key: const ValueKey('main-navigation'),
          theme: theme,
          radius: 26,
          height: height,
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
    final theme = widget.theme;
    final color = widget.selected
        ? (theme.isEndfield ? theme.textPrimary : theme.navSelectedItem)
        : theme.navUnselectedItem;
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 26,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? theme.accentPrimary.withValues(alpha: 0.28)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(widget.icon, color: color, size: 20),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyFont.copyWith(
                  color: color,
                  fontSize: 10.5,
                  fontWeight:
                      widget.selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}