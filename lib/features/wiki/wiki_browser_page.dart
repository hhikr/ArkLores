import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/providers/wiki_navigation_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../ai/ai_chat_page.dart';
import '../ai/wiki_ai_context.dart';
import '../settings/settings_service.dart';
import 'bookmark_page.dart';
import 'bookmark_service.dart' show Bookmark;
import 'wiki_dark_mode.dart';
import 'wiki_reader_mode.dart';
import 'wiki_toolbar.dart';

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<WikiSiteConfig> _wikiSites = SettingsService.defaultWikiSites;

  /// Controllers for each site tab.
  var _controllers = <InAppWebViewController?>[];

  /// Current page title per tab.
  var _titles = <String>[];

  /// Current page URL per tab.
  var _currentUrls = <String>[];

  /// Navigation state per tab.
  var _canGoBack = <bool>[];
  var _canGoForward = <bool>[];

  /// Dark mode toggle state for Wiki WebView pages.
  bool _isDarkMode = false;
  bool _isReaderMode = false;
  double _readerFontScale = 1.0;
  double _pageScale = 1.0;
  bool _trayExpanded = false;
  bool _readerControlsVisible = true;
  bool _restoredState = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isDarkMode =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    _resetTabState(SettingsService.defaultWikiSites);
    _tabController = TabController(length: _wikiSites.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    ref.read(wikiBackHandlerProvider.notifier).state = _handleSystemBack;
    _restoreBrowsingState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistBrowsingState();
    ref.read(wikiReaderFullscreenProvider.notifier).state = false;
    ref.read(wikiBackHandlerProvider.notifier).state = null;
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
      _saveWikiTabIndex(_tabController.index);
    }
  }

  void _resetTabState(List<WikiSiteConfig> sites) {
    _wikiSites = sites.isEmpty ? SettingsService.defaultWikiSites : sites;
    _controllers = List.filled(_wikiSites.length, null);
    _titles = List.filled(_wikiSites.length, '');
    _currentUrls = [for (final site in _wikiSites) site.url];
    _canGoBack = List.filled(_wikiSites.length, false);
    _canGoForward = List.filled(_wikiSites.length, false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistBrowsingState();
    }
  }

  @override
  void didChangePlatformBrightness() {
    final prefersDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    if (prefersDark == _isDarkMode) return;
    setState(() => _isDarkMode = prefersDark);
    _applyAppearanceToControllers();
  }

  Future<void> _restoreBrowsingState() async {
    var tabIndex = 0;
    var readerMode = false;
    var readerFontScale = 1.0;
    var sites = SettingsService.defaultWikiSites;
    var urls = <String>[];
    try {
      final service = ref.read(settingsServiceProvider);
      sites = await service.loadWikiSites();
      urls = [
        for (var i = 0; i < sites.length; i++)
          await service.loadWikiUrl(i) ?? sites[i].url,
      ];
      tabIndex = await service.loadWikiTabIndex();
      readerMode = await service.loadWikiReaderMode();
      readerFontScale = await service.loadWikiReaderFontScale();
    } catch (e) {
      debugPrint('[WikiBrowser] Error restoring browsing state: $e');
    }
    if (!mounted) return;
    setState(() {
      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _resetTabState(sites);
      for (var i = 0; i < urls.length && i < _currentUrls.length; i++) {
        _currentUrls[i] = urls[i];
      }
      _tabController = TabController(length: _wikiSites.length, vsync: this);
      _tabController.addListener(_onTabChanged);
      _tabController.index = tabIndex.clamp(0, _wikiSites.length - 1).toInt();
      _isReaderMode = readerMode;
      _readerFontScale = readerFontScale;
      _restoredState = true;
    });
    ref.read(wikiReaderFullscreenProvider.notifier).state = readerMode;
  }

  Future<void> _reloadWikiSites() async {
    if (!_restoredState) return;
    final service = ref.read(settingsServiceProvider);
    final sites = await service.loadWikiSites();
    if (!mounted) return;

    final oldIndex = _tabController.index;
    final oldSites = _wikiSites;
    final oldControllers = _controllers;
    final oldTitles = _titles;
    final oldUrls = _currentUrls;
    final oldBack = _canGoBack;
    final oldForward = _canGoForward;

    setState(() {
      _resetTabState(sites);
      for (var i = 0; i < _wikiSites.length; i++) {
        final oldSiteIndex =
            oldSites.indexWhere((site) => site.id == _wikiSites[i].id);
        if (oldSiteIndex < 0) continue;
        if (oldSites[oldSiteIndex].url != _wikiSites[i].url) continue;
        _controllers[i] = oldControllers[oldSiteIndex];
        _titles[i] = oldTitles[oldSiteIndex];
        _currentUrls[i] = oldUrls[oldSiteIndex].trim().isNotEmpty
            ? oldUrls[oldSiteIndex]
            : _wikiSites[i].url;
        _canGoBack[i] = oldBack[oldSiteIndex];
        _canGoForward[i] = oldForward[oldSiteIndex];
      }

      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _tabController = TabController(length: _wikiSites.length, vsync: this);
      _tabController.addListener(_onTabChanged);
      _tabController.index = oldIndex.clamp(0, _wikiSites.length - 1).toInt();
    });
    _saveWikiTabIndex(_tabController.index);
  }

  Future<void> _persistBrowsingState() async {
    try {
      final service = ref.read(settingsServiceProvider);
      await service.saveWikiTabIndex(_tabController.index);
      await service.saveWikiReaderMode(_isReaderMode);
      await service.saveWikiReaderFontScale(_readerFontScale);
      await Future.wait([
        for (var i = 0; i < _currentUrls.length; i++)
          if (_currentUrls[i].trim().isNotEmpty)
            service.saveWikiUrl(i, _currentUrls[i]),
      ]);
    } catch (e) {
      debugPrint('[WikiBrowser] Error saving browsing state: $e');
    }
  }

  void _saveWikiTabIndex(int index) {
    ref.read(settingsServiceProvider).saveWikiTabIndex(index).catchError(
          (Object error) => debugPrint(
            '[WikiBrowser] Error saving wiki tab: $error',
          ),
        );
  }

  void _saveWikiUrl(int index, String url) {
    ref.read(settingsServiceProvider).saveWikiUrl(index, url).catchError(
          (Object error) => debugPrint(
            '[WikiBrowser] Error saving wiki URL: $error',
          ),
        );
  }

  // ─── Toolbar action callbacks ────────────────────────────────────

  Future<bool> _handleSystemBack() async {
    if (_isReaderMode) {
      _setReaderMode(false);
      return true;
    }
    final controller = _controllers[_tabController.index];
    if (controller == null) return true;
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
    return true;
  }

  void _zoomOut() {
    _setPageScale(_pageScale - 0.08);
  }

  void _zoomIn() {
    _setPageScale(_pageScale + 0.08);
  }

  void _setPageScale(double value) {
    final next = value.clamp(0.72, 1.36).toDouble();
    if (next == _pageScale) return;
    setState(() => _pageScale = next);
    _applyPageScaleToControllers();
  }

  void _applyPageScaleToControllers() {
    for (final c in _controllers) {
      if (c != null) _applyPageScale(c);
    }
  }

  Future<void> _applyPageScale(InAppWebViewController controller) async {
    final scale = _isReaderMode ? 1.0 : _pageScale;
    final js = '''
(function() {
  var html = document.documentElement;
  if (!html) return;
  html.style.setProperty('zoom', '$scale');
  html.style.setProperty('transform-origin', '0 0');
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Page scale is best-effort across WebView engines.
    }
  }

  void _reload() {
    _controllers[_tabController.index]?.reload();
  }

  void _toggleDarkMode() {
    final newValue = !_isDarkMode;
    setState(() => _isDarkMode = newValue);
    _applyAppearanceToControllers();
  }

  void _toggleReaderMode() {
    final enabled = !_isReaderMode;
    _setReaderMode(enabled);
  }

  void _setReaderMode(bool enabled) {
    setState(() {
      _isReaderMode = enabled;
      if (enabled) {
        _trayExpanded = false;
        _readerControlsVisible = true;
      }
    });
    ref.read(wikiReaderFullscreenProvider.notifier).state = enabled;
    ref.read(settingsServiceProvider).saveWikiReaderMode(enabled).catchError(
          (Object error) => debugPrint(
            '[WikiBrowser] Error saving reader mode: $error',
          ),
        );
    _applyAppearanceToControllers();
  }

  void _toggleReaderControls() {
    if (!_isReaderMode) return;
    setState(() => _readerControlsVisible = !_readerControlsVisible);
  }

  void _decreaseReaderFont() {
    _setReaderFontScale(_readerFontScale - 0.1);
  }

  void _increaseReaderFont() {
    _setReaderFontScale(_readerFontScale + 0.1);
  }

  void _setReaderFontScale(double value) {
    final next = value.clamp(0.62, 1.38).toDouble();
    if (next == _readerFontScale) return;
    setState(() => _readerFontScale = next);
    ref.read(settingsServiceProvider).saveWikiReaderFontScale(next).catchError(
          (Object error) => debugPrint(
            '[WikiBrowser] Error saving reader font scale: $error',
          ),
        );
    if (_isReaderMode) _applyAppearanceToControllers();
  }

  void _applyAppearanceToControllers() {
    for (final c in _controllers) {
      if (c != null) {
        _applyAppearanceToController(c);
      }
    }
  }

  Future<void> _applyAppearanceToController(
    InAppWebViewController controller,
  ) async {
    if (_isReaderMode) {
      await WikiDarkMode.remove(controller);
      await _applyPageScale(controller);
      await WikiReaderMode.inject(
        controller,
        dark: _isDarkMode,
        fontScale: _readerFontScale,
      );
      return;
    }

    await WikiReaderMode.remove(controller);
    await WikiDarkMode.setEnabled(controller, _isDarkMode);
    await _applyPageScale(controller);
  }

  void _toggleBookmark() {
    final idx = _tabController.index;
    final url = _currentUrls[idx];
    if (url.isEmpty) return;
    final title =
        _titles[idx].isNotEmpty ? _titles[idx] : _wikiSites[idx].label;
    ref.read(bookmarkProvider.notifier).toggle(
          title: title,
          url: url,
          site: _wikiSites[idx].id,
        );
  }

  Future<void> _openBookmarks() async {
    final bookmark = await Navigator.of(context).push<Bookmark>(
      MaterialPageRoute(
        builder: (_) => const BookmarkPage(),
      ),
    );
    if (bookmark == null || !mounted) return;

    final targetIndex = _wikiSites.indexWhere(
      (site) => site.id == bookmark.site,
    );
    if (targetIndex < 0) return;

    // Switch tab if needed.
    if (_tabController.index != targetIndex) {
      _tabController.animateTo(targetIndex);
      _saveWikiTabIndex(targetIndex);
    }

    // Load the bookmarked URL in the corresponding WebView.
    final controller = _controllers[targetIndex];
    if (controller != null) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(bookmark.url)),
      );
    }
  }

  Future<void> _sendSelectionToAi() async {
    final idx = _tabController.index;
    final controller = _controllers[idx];
    if (controller == null) return;
    final selectedText = await _readSelectedText(controller);
    if (!mounted) return;

    final target = await showModalBottomSheet<WikiAiTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _WikiAiTargetSheet(theme: ref.read(themeProvider)),
    );
    if (target == null || !mounted) return;

    final contextPayload = WikiAiContext(
      selectedText: selectedText,
      pageTitle:
          _titles[idx].trim().isNotEmpty ? _titles[idx] : _wikiSites[idx].label,
      pageUrl: _currentUrls[idx].trim().isNotEmpty
          ? _currentUrls[idx]
          : _wikiSites[idx].url,
      siteLabel: _wikiSites[idx].label,
      target: target,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiChatPage(initialWikiContext: contextPayload),
      ),
    );
  }

  Future<String> _readSelectedText(InAppWebViewController controller) async {
    try {
      final value = await controller.evaluateJavascript(
        source: 'window.getSelection ? window.getSelection().toString() : ""',
      );
      return value?.toString().trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ─── WebView tab state callbacks ─────────────────────────────────

  void _onControllerCreated(int index, InAppWebViewController controller) {
    if (index >= _controllers.length) return;
    _controllers[index] = controller;
  }

  void _onTitleChanged(int index, String? title) {
    if (index >= _titles.length) return;
    if (title != null && title != _titles[index]) {
      setState(() => _titles[index] = title);
    }
  }

  void _onUrlChanged(int index, String url) {
    if (index >= _currentUrls.length) return;
    if (url != _currentUrls[index]) {
      setState(() => _currentUrls[index] = url);
      _saveWikiUrl(index, url);
    }
  }

  Future<void> _onHistoryChanged(
    int index,
    bool back,
    bool forward,
  ) async {
    if (index >= _canGoBack.length || index >= _canGoForward.length) return;
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
    ref.listen<int>(wikiSourcesRevisionProvider, (_, __) => _reloadWikiSites());

    if (!_restoredState) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: theme.accentPrimary),
          ),
        ),
      );
    }

    // Determine if the current page is bookmarked.
    final currentUrl = _currentUrls[_tabController.index];
    final isBookmarked = bookmarkAsync.whenOrNull(
          data: (_) =>
              ref.read(bookmarkProvider.notifier).isBookmarked(currentUrl),
        ) ??
        false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: !_isReaderMode,
        bottom: false,
        child: Stack(
          children: [
            // ── Main content column ────────────────────────────
            Column(
              children: [
                // ── Site tab bar ─────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  child: _isReaderMode
                      ? const SizedBox.shrink()
                      : Container(
                          color: theme.bgSecondary,
                          child: Row(
                            children: [
                              Expanded(
                                child: TabBar(
                                  controller: _tabController,
                                  indicatorColor: theme.accentPrimary,
                                  labelColor: theme.accentPrimary,
                                  unselectedLabelColor: theme.textSecondary,
                                  labelStyle:
                                      theme.titleFont.copyWith(fontSize: 14),
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
                              IconButton(
                                icon: const Icon(Icons.bookmarks_rounded),
                                color: theme.textSecondary,
                                tooltip: 'Bookmarks',
                                onPressed: _openBookmarks,
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                ),

                // ── WebView area (IndexedStack = no horizontal swipes) ──
                Expanded(
                  child: IndexedStack(
                    index: _tabController.index,
                    children: List.generate(_wikiSites.length, (i) {
                      return _WikiTabView(
                        key: ValueKey(_wikiSites[i].id),
                        index: i,
                        initialUrl: _currentUrls[i].trim().isNotEmpty
                            ? _currentUrls[i]
                            : _wikiSites[i].url,
                        theme: theme,
                        isDarkMode: _isDarkMode,
                        isReaderMode: _isReaderMode,
                        readerDark: _isDarkMode,
                        readerFontScale: _readerFontScale,
                        onReaderTapped: _toggleReaderControls,
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

            if (_isReaderMode)
              _ReaderToolbar(
                visible: _readerControlsVisible,
                isDarkMode: _isDarkMode,
                onToggleDarkMode: _toggleDarkMode,
                onDecreaseReaderFont: _decreaseReaderFont,
                onIncreaseReaderFont: _increaseReaderFont,
                onExitReader: () => _setReaderMode(false),
              )
            else
              _ExpandableTray(
                expanded: _trayExpanded,
                onToggle: () => setState(() => _trayExpanded = !_trayExpanded),
                isDarkMode: _isDarkMode,
                isReaderMode: _isReaderMode,
                isBookmarked: isBookmarked,
                onZoomOut: _zoomOut,
                onZoomIn: _zoomIn,
                onRefresh: _reload,
                onToggleDarkMode: _toggleDarkMode,
                onToggleReaderMode: _toggleReaderMode,
                onDecreaseReaderFont: _decreaseReaderFont,
                onIncreaseReaderFont: _increaseReaderFont,
                onToggleBookmark: _toggleBookmark,
                onSendToAi: _sendSelectionToAi,
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
  final AppThemeTokens theme;
  final bool isDarkMode;
  final bool isReaderMode;
  final bool readerDark;
  final double readerFontScale;
  final VoidCallback onReaderTapped;
  final void Function(int, InAppWebViewController) onControllerCreated;
  final void Function(int, String?) onTitleChanged;
  final void Function(int, String) onUrlChanged;
  final Future<void> Function(int, bool, bool) onHistoryChanged;

  const _WikiTabView({
    super.key,
    required this.index,
    required this.initialUrl,
    required this.theme,
    required this.isDarkMode,
    required this.isReaderMode,
    required this.readerDark,
    required this.readerFontScale,
    required this.onReaderTapped,
    required this.onControllerCreated,
    required this.onTitleChanged,
    required this.onUrlChanged,
    required this.onHistoryChanged,
  });

  @override
  State<_WikiTabView> createState() => _WikiTabViewState();
}

class _WikiTabViewState extends State<_WikiTabView> {
  InAppWebViewController? _controller;
  String? _loadError;
  double? _edgeDragStartX;

  @override
  void didUpdateWidget(covariant _WikiTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;
    if (oldWidget.isReaderMode != widget.isReaderMode ||
        oldWidget.readerDark != widget.readerDark ||
        oldWidget.readerFontScale != widget.readerFontScale ||
        oldWidget.isDarkMode != widget.isDarkMode) {
      _applyAppearance();
    }
  }

  Future<void> _applyAppearance() async {
    final controller = _controller;
    if (controller == null) return;

    if (widget.isReaderMode) {
      await WikiDarkMode.remove(controller);
      await WikiReaderMode.inject(
        controller,
        dark: widget.readerDark,
        fontScale: widget.readerFontScale,
      );
      return;
    }

    await WikiReaderMode.remove(controller);
    await WikiDarkMode.setEnabled(controller, widget.isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
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
            _controller = controller;
            controller.addJavaScriptHandler(
              handlerName: 'arkloresReaderTap',
              callback: (_) {
                if (widget.isReaderMode) widget.onReaderTapped();
                return null;
              },
            );
            widget.onControllerCreated(widget.index, controller);
          },
          onLoadStart: (controller, url) {
            if (_loadError != null) {
              setState(() => _loadError = null);
            }
          },
          onLoadStop: (controller, url) async {
            await _applyAppearance();
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
            final isMainFrame = request.isForMainFrame ?? true;
            if (!isMainFrame) return;
            setState(() {
              _loadError = _friendlyWebViewError(error.description);
            });
          },
        ),
        if (!widget.isReaderMode) _buildEdgeGestureLayer(),
        if (_loadError != null) _buildErrorOverlay(context),
      ],
    );
  }

  Widget _buildEdgeGestureLayer() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const edgeWidth = 28.0;
          return IgnorePointer(
            ignoring: false,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (details) {
                      _edgeDragStartX = details.globalPosition.dx;
                    },
                    onHorizontalDragEnd: (details) async {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity > 320 || (_edgeDragStartX ?? 0) < 12) {
                        if (await _controller?.canGoForward() ?? false) {
                          await _controller?.goForward();
                        }
                      }
                      _edgeDragStartX = null;
                    },
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: edgeWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) async {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity < -320) {
                        if (await _controller?.canGoBack() ?? false) {
                          await _controller?.goBack();
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorOverlay(BuildContext context) {
    final theme = widget.theme;
    return ColoredBox(
      color: theme.bgPrimary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.cardSurface,
                borderRadius: theme.cardRadius,
                border: Border.all(color: theme.divider),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: theme.danger, size: 28),
                    const SizedBox(height: 12),
                    Text(
                      'Wiki 页面加载失败',
                      style: theme.titleFont.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loadError!,
                      style: theme.bodyFont.copyWith(
                        color: theme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _loadError = null);
                          _controller?.reload();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          '重试',
                          style: theme.titleFont.copyWith(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accentPrimary,
                          foregroundColor: theme.bgPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyWebViewError(String description) {
    final lower = description.toLowerCase();
    if (lower.contains('host') || lower.contains('dns')) {
      return '无法解析 Wiki 域名。请确认网络、DNS 或代理已对 ArkLores 生效后重试。';
    }
    if (lower.contains('timeout')) {
      return '连接超时。请切换网络或确认代理/VPN 已连接后重试。';
    }
    if (lower.contains('net::err_internet_disconnected')) {
      return '设备当前没有可用网络连接。';
    }
    return description;
  }
}

class _WikiAiTargetSheet extends StatelessWidget {
  final AppThemeTokens theme;

  const _WikiAiTargetSheet({required this.theme});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: theme.cardBorder)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t.wikiSendToAi,
                style: theme.titleFont.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                context.t.wikiSendToAiDesc,
                style: theme.bodyFont.copyWith(
                  color: theme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              _TargetTile(
                theme: theme,
                icon: Icons.summarize_rounded,
                title: context.t.aiTabSummary,
                subtitle: context.t.wikiSendToSummaryDesc,
                onTap: () => Navigator.pop(context, WikiAiTarget.summary),
              ),
              _TargetTile(
                theme: theme,
                icon: Icons.verified_outlined,
                title: context.t.aiTabFactCheck,
                subtitle: context.t.wikiSendToFactCheckDesc,
                onTap: () => Navigator.pop(context, WikiAiTarget.factCheck),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final AppThemeTokens theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TargetTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.accentPrimary),
      title: Text(title, style: theme.titleFont.copyWith(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: theme.bodyFont.copyWith(color: theme.textSecondary),
      ),
      onTap: onTap,
    );
  }
}

class _ReaderToolbar extends ConsumerWidget {
  const _ReaderToolbar({
    required this.visible,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.onDecreaseReaderFont,
    required this.onIncreaseReaderFont,
    required this.onExitReader,
  });

  final bool visible;
  final bool isDarkMode;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onDecreaseReaderFont;
  final VoidCallback onIncreaseReaderFont;
  final VoidCallback onExitReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Positioned(
      left: 18,
      right: 18,
      bottom: 22,
      child: SafeArea(
        top: false,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, 1.2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: visible ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.cardSurface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.cardBorder),
                  boxShadow: theme.cardShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ReaderToolButton(
                        theme: theme,
                        icon: isDarkMode
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        onTap: onToggleDarkMode,
                      ),
                      _ReaderToolButton(
                        theme: theme,
                        label: 'A-',
                        onTap: onDecreaseReaderFont,
                      ),
                      _ReaderToolButton(
                        theme: theme,
                        label: 'A+',
                        onTap: onIncreaseReaderFont,
                      ),
                      _ReaderToolButton(
                        theme: theme,
                        icon: Icons.close_rounded,
                        onTap: onExitReader,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderToolButton extends StatelessWidget {
  const _ReaderToolButton({
    required this.theme,
    required this.onTap,
    this.icon,
    this.label,
  });

  final AppThemeTokens theme;
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 44,
      child: IconButton(
        onPressed: onTap,
        color: theme.textPrimary,
        splashRadius: 22,
        icon: icon != null
            ? Icon(icon, size: 22)
            : Text(
                label ?? '',
                style: theme.titleFont.copyWith(fontSize: 18),
              ),
      ),
    );
  }
}

// ─── Sizing constants for the expandable tray ───────────────────
const double _traySize = 52;
const double _trayMargin = 16;
const double _trayBottomOffset = 64;
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
    required this.isDarkMode,
    required this.isReaderMode,
    required this.isBookmarked,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onRefresh,
    required this.onToggleDarkMode,
    required this.onToggleReaderMode,
    required this.onDecreaseReaderFont,
    required this.onIncreaseReaderFont,
    required this.onToggleBookmark,
    required this.onSendToAi,
  });

  final bool expanded;
  final VoidCallback onToggle;

  final bool isDarkMode;
  final bool isReaderMode;
  final bool isBookmarked;

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onToggleReaderMode;
  final VoidCallback onDecreaseReaderFont;
  final VoidCallback onIncreaseReaderFont;
  final VoidCallback onToggleBookmark;
  final VoidCallback onSendToAi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Positioned(
      right: _trayMargin,
      bottom: _trayBottomOffset,
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
                    isDarkMode: isDarkMode,
                    isReaderMode: isReaderMode,
                    isBookmarked: isBookmarked,
                    onZoomOut: onZoomOut,
                    onZoomIn: onZoomIn,
                    onRefresh: onRefresh,
                    onToggleDarkMode: onToggleDarkMode,
                    onToggleReaderMode: onToggleReaderMode,
                    onDecreaseReaderFont: onDecreaseReaderFont,
                    onIncreaseReaderFont: onIncreaseReaderFont,
                    onToggleBookmark: onToggleBookmark,
                    onSendToAi: onSendToAi,
                    sendToAiTooltip: context.t.wikiSendToAi,
                    readerModeTooltip: context.t.wikiReaderMode,
                    readerFontSmallerTooltip: context.t.wikiReaderFontSmaller,
                    readerFontLargerTooltip: context.t.wikiReaderFontLarger,
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
