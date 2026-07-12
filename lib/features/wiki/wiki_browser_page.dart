import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
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

  void _openBookmarks() {
    // Placeholder — will navigate to BookmarkPage in T7.
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
        child: Column(
          children: [
            // ── Custom toolbar ────────────────────────────────
            WikiToolbar(
              canGoBack: _canGoBack[_tabController.index],
              canGoForward: _canGoForward[_tabController.index],
              currentTitle: _titles[_tabController.index],
              isDarkMode: _isDarkMode,
              isBookmarked: isBookmarked,
              onBack: _goBack,
              onForward: _goForward,
              onRefresh: _reload,
              onToggleDarkMode: _toggleDarkMode,
              onToggleBookmark: _toggleBookmark,
              onOpenBookmarks: _openBookmarks,
            ),

            // ── Site tab bar ───────────────────────────────────
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

            // ── WebView area ───────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
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
      ),
    );
  }
}

/// A single wiki tab that keeps its WebView alive across tab switches.
///
/// Uses [AutomaticKeepAliveClientMixin] so [TabBarView] does not dispose
/// the WebView when the user switches to another tab.
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

class _WikiTabViewState extends State<_WikiTabView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

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
