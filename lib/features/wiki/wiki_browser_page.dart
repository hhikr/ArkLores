import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
import 'bookmark_page.dart';
import 'bookmark_service.dart' show Bookmark;
import 'wiki_dark_mode.dart';
import 'wiki_toolbar.dart';

/// Wiki site configuration.
class _WikiSite {
  final String label;
  final String icon;
  final String initialUrl;

  const _WikiSite(this.label, this.icon, this.initialUrl);
}

const _wikiSites = [
  _WikiSite('PRTS Wiki', 'https://prts.wiki/favicon.ico', 'https://prts.wiki'),
  _WikiSite(
    'Endfield Wiki',
    'https://warfarin.wiki/cn/favicon.ico',
    'https://warfarin.wiki/cn',
  ),
];

/// Wiki Browser tab — hosts dual-site WebView with custom toolbar.
///
/// Two wiki sites (PRTS and Endfield) are available via a top TabBar.
/// Each site keeps its own [InAppWebViewController] and browsing history.
class WikiBrowserPage extends ConsumerStatefulWidget {
  const WikiBrowserPage({super.key});

  @override
  ConsumerState<WikiBrowserPage> createState() => _WikiBrowserPageState();
}

class _WikiBrowserPageState extends ConsumerState<WikiBrowserPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  /// Controllers for each site tab.
  final List<InAppWebViewController?> _controllers =
      List.filled(_wikiSites.length, null);

  /// Current page title per tab.
  final List<String> _titles =
      List.filled(_wikiSites.length, '');

  /// Current page URL per tab.
  final List<String> _currentUrls = List.filled(_wikiSites.length, '');

  /// Navigation state per tab.
  final List<bool> _canGoBack = List.filled(_wikiSites.length, false);
  final List<bool> _canGoForward = List.filled(_wikiSites.length, false);

  /// Dark mode toggle state for Wiki WebView pages.
  bool _isDarkMode = true;
  bool _trayExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _wikiSites.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  // ─── Toolbar action callbacks ────────────────────────────────────

  void _goBack() {
    _controllers[_tabController.index]?.goBack();
  }

  void _goForward() {
    _controllers[_tabController.index]?.goForward();
  }

  void _reload() {
    _controllers[_tabController.index]?.reload();
  }

  void _toggleDarkMode() {
    final newValue = !_isDarkMode;
    setState(() => _isDarkMode = newValue);
    for (final c in _controllers) {
      if (c != null) WikiDarkMode.setEnabled(c, newValue);
    }
  }

  /// Syncs dark mode with the app theme without toggling UI state
  /// back and forth during build.
  void _toggleDarkModeFromTheme(bool value) {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    for (final c in _controllers) {
      if (c != null) WikiDarkMode.setEnabled(c, value);
    }
  }

  void _toggleBookmark() {
    final idx = _tabController.index;
    final url = _currentUrls[idx];
    if (url.isEmpty) return;
    final title = _titles[idx].isNotEmpty ? _titles[idx] : _wikiSites[idx].label;
    final site = idx == 0 ? 'prts' : 'endfield';
    ref.read(bookmarkProvider.notifier).toggle(
          title: title,
          url: url,
          site: site,
        );
  }

  Future<void> _openBookmarks() async {
    final bookmark = await Navigator.of(context).push<Bookmark>(
      MaterialPageRoute(
        builder: (_) => const BookmarkPage(),
      ),
    );
    if (bookmark == null || !mounted) return;

    // Determine which tab to switch to.
    final targetIndex = bookmark.site == 'prts' ? 0 : 1;

    // Switch tab if needed.
    if (_tabController.index != targetIndex) {
      _tabController.animateTo(targetIndex);
    }

    // Load the bookmarked URL in the corresponding WebView.
    final controller = _controllers[targetIndex];
    if (controller != null) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(bookmark.url)),
      );
    }
  }

  // ─── WebView tab state callbacks ─────────────────────────────────

  void _onControllerCreated(int index, InAppWebViewController controller) {
    _controllers[index] = controller;
  }

  void _onTitleChanged(int index, String? title) {
    if (title != null && title != _titles[index]) {
      setState(() => _titles[index] = title);
    }
  }

  void _onUrlChanged(int index, String url) {
    if (url != _currentUrls[index]) {
      setState(() => _currentUrls[index] = url);
    }
  }

  Future<void> _onHistoryChanged(
    int index,
    bool back,
    bool forward,
  ) async {
    if (back != _canGoBack[index] || forward != _canGoForward[index]) {
      setState(() {
        _canGoBack[index] = back;
        _canGoForward[index] = forward;
      });
    }
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final bookmarkAsync = ref.watch(bookmarkProvider);

    // Sync dark mode toggle with app theme on first build or theme switch.
    if (_isDarkMode != theme.isDark) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toggleDarkModeFromTheme(theme.isDark);
      });
    }

    // Determine if the current page is bookmarked.
    final currentUrl = _currentUrls[_tabController.index];
    final isBookmarked = bookmarkAsync.whenOrNull(
          data: (_) => ref.read(bookmarkProvider.notifier).isBookmarked(currentUrl),
        ) ??
        false;

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main content column ────────────────────────────
            Column(
              children: [
                // ── Site tab bar ─────────────────────────────────
                Container(
                  color: theme.bgSecondary,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: theme.accentPrimary,
                    labelColor: theme.accentPrimary,
                    unselectedLabelColor: theme.textSecondary,
                    labelStyle: theme.titleFont.copyWith(fontSize: 14),
                    unselectedLabelStyle:
                        theme.bodyFont.copyWith(fontSize: 14),
                    indicatorWeight: 2,
                    tabs: _wikiSites.map((site) {
                      return Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 16,
                              color: theme.accentPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(site.label),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // ── WebView area (IndexedStack = no horizontal swipes) ──
                Expanded(
                  child: IndexedStack(
                    index: _tabController.index,
                    children: List.generate(_wikiSites.length, (i) {
                      return _WikiTabView(
                        index: i,
                        initialUrl: _wikiSites[i].initialUrl,
                        isDarkMode: _isDarkMode,
                        onControllerCreated: _onControllerCreated,
                        onTitleChanged: _onTitleChanged,
                        onUrlChanged: _onUrlChanged,
                        onHistoryChanged: _onHistoryChanged,
                      );
                    }),
                  ),
                ),
              ],
            ),

            // ── Expandable floating tray (FAB ⇄ vertical toolbar) ──
            _ExpandableTray(
              expanded: _trayExpanded,
              onToggle: () => setState(() => _trayExpanded = !_trayExpanded),
              canGoBack: _canGoBack[_tabController.index],
              canGoForward: _canGoForward[_tabController.index],
              isDarkMode: _isDarkMode,
              isBookmarked: isBookmarked,
              onBack: _goBack,
              onForward: _goForward,
              onRefresh: _reload,
              onToggleDarkMode: _toggleDarkMode,
              onToggleBookmark: _toggleBookmark,
              onOpenBookmarks: _openBookmarks,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single wiki tab whose WebView is kept alive by [IndexedStack] in the
/// parent, so browsing state is preserved across tab switches.
class _WikiTabView extends StatefulWidget {
  final int index;
  final String initialUrl;
  final bool isDarkMode;
  final void Function(int, InAppWebViewController) onControllerCreated;
  final void Function(int, String?) onTitleChanged;
  final void Function(int, String) onUrlChanged;
  final Future<void> Function(int, bool, bool) onHistoryChanged;

  const _WikiTabView({
    required this.index,
    required this.initialUrl,
    required this.isDarkMode,
    required this.onControllerCreated,
    required this.onTitleChanged,
    required this.onUrlChanged,
    required this.onHistoryChanged,
  });

  @override
  State<_WikiTabView> createState() => _WikiTabViewState();
}

class _WikiTabViewState extends State<_WikiTabView> {

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(widget.initialUrl),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        verticalScrollBarEnabled: true,
        horizontalScrollBarEnabled: false,
        cacheEnabled: true,
        domStorageEnabled: true,
        useWideViewPort: true,
        supportZoom: true,
        // Transparent background to avoid white flash on dark themes.
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        widget.onControllerCreated(widget.index, controller);
      },
      onLoadStop: (controller, url) async {
        if (widget.isDarkMode) {
          await WikiDarkMode.inject(controller);
        }
      },
      onTitleChanged: (controller, title) {
        widget.onTitleChanged(widget.index, title);
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        if (url != null) {
          widget.onUrlChanged(widget.index, url.toString());
        }
        final back = await controller.canGoBack();
        final forward = await controller.canGoForward();
        await widget.onHistoryChanged(widget.index, back, forward);
      },
      onReceivedError: (controller, request, error) {
        // WebView shows its own error page; we handle it silently.
      },
    );
  }
}

// ─── Sizing constants for the expandable tray ───────────────────
const double _traySize = 52;
const double _trayMargin = 16;
const double _trayHeightFactor = 0.45;

/// Floating tray anchored at bottom-right that morphs between a FAB and a
/// tall vertical toolbar.
///
/// Collapsed: a small round button.
/// Expanded: the same-width container "stretches" upward into a floating
/// vertical toolbar with [WikiToolbar] inside and a close toggle at bottom.
class _ExpandableTray extends ConsumerWidget {
  const _ExpandableTray({
    required this.expanded,
    required this.onToggle,
    required this.canGoBack,
    required this.canGoForward,
    required this.isDarkMode,
    required this.isBookmarked,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleBookmark,
    required this.onOpenBookmarks,
  });

  final bool expanded;
  final VoidCallback onToggle;

  final bool canGoBack;
  final bool canGoForward;
  final bool isDarkMode;
  final bool isBookmarked;

  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenBookmarks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Positioned(
      right: _trayMargin,
      bottom: _trayMargin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: _traySize,
        height: expanded
            ? (MediaQuery.of(context).size.height * _trayHeightFactor)
            : _traySize,
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: BorderRadius.circular(expanded ? 16 : _traySize / 2),
          boxShadow: theme.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Toolbar buttons (only when expanded) ──────────────
            if (expanded)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: WikiToolbar(
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    isDarkMode: isDarkMode,
                    isBookmarked: isBookmarked,
                    onBack: onBack,
                    onForward: onForward,
                    onRefresh: onRefresh,
                    onToggleDarkMode: onToggleDarkMode,
                    onToggleBookmark: onToggleBookmark,
                    onOpenBookmarks: onOpenBookmarks,
                  ),
                ),
              ),

            // ── Toggle button (always visible at the bottom) ──────
            SizedBox(
              height: _traySize,
              child: IconButton(
                icon: Icon(
                  expanded ? Icons.close_rounded : Icons.tune_rounded,
                  size: 22,
                ),
                color: theme.textPrimary,
                onPressed: onToggle,
                padding: EdgeInsets.zero,
                splashRadius: 22,
                tooltip: expanded ? 'Close' : 'Tools',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
