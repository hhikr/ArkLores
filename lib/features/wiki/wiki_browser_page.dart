import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bars_provider.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/handoff_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/providers/wiki_navigation_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/motion.dart';
import '../../shared/widgets/ef_widgets.dart';
import '../../shared/widgets/page_frame.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../settings/settings_service.dart';
import 'bookmark_page.dart';
import 'bookmark_service.dart' show Bookmark;
import 'wiki_appearance.dart';
import 'wiki_browser_controls.dart';
import 'wiki_site_adapter.dart';

/// Wiki Browser tab — hosts dual-site WebView with custom toolbar.
///
/// Wiki sites are available via a top TabBar.
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

  /// Source URL that each WebView last applied.
  var _appliedSourceUrls = <String>[];

  /// Navigation state per tab.
  var _canGoBack = <bool>[];
  var _canGoForward = <bool>[];

  /// Whether the Wiki pages are dark: the app's theme, unless the reader
  /// switched them ([_ownDarkMode]) since the theme last changed.
  bool _isDarkMode = false;
  double _pageScale = 1.0;
  bool _trayExpanded = false;
  bool _restoredState = false;

  /// The reader's switch, against the theme. Kept (and saved) until the
  /// app's theme next turns light or dark, by hand or with the system.
  bool _ownDarkMode = false;
  late final SettingsService _settings;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(settingsServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    _isDarkMode = ref.read(themeProvider).isDark;
    _resetTabState(SettingsService.defaultWikiSites);
    _tabController = TabController(length: _wikiSites.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Defer the provider write to after the first frame: Riverpod 2.x rejects
    // modifying a provider during initState/build ("Tried to modify a provider
    // while the widget tree was building"), which crashed the whole shell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(wikiBackHandlerProvider.notifier).state = _handleSystemBack;
      }
    });
    _restoreBrowsingState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistBrowsingState();
    // Intentionally NOT writing providers here: the Wiki page lives in the
    // MainShell IndexedStack for the whole app lifetime, so provider cleanup
    // on dispose is unnecessary, and modifying providers during dispose is
    // rejected by Riverpod 2.x.
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
    _appliedSourceUrls = [for (final site in _wikiSites) site.url];
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

  Future<void> _restoreBrowsingState() async {
    var tabIndex = 0;
    bool? storedDarkMode;
    var sites = SettingsService.defaultWikiSites;
    var urls = <String>[];
    var appliedUrls = <String>[];
    try {
      final service = _settings;
      sites = await service.loadWikiSites();
      final loadedSites = sites;
      // Each read is a secure-storage platform call: run them together.
      (urls, appliedUrls, tabIndex, storedDarkMode) = await (
        Future.wait([
          for (var i = 0; i < loadedSites.length; i++)
            service.loadWikiUrl(i).then((url) => url ?? loadedSites[i].url),
        ]),
        Future.wait([
          for (var i = 0; i < loadedSites.length; i++)
            service
                .loadWikiAppliedUrl(i)
                .then((url) => url ?? loadedSites[i].url),
        ]),
        service.loadWikiTabIndex(),
        service.loadWikiDarkMode(),
      ).wait;
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
      for (var i = 0;
          i < appliedUrls.length && i < _appliedSourceUrls.length;
          i++) {
        _appliedSourceUrls[i] = appliedUrls[i];
      }
      _tabController = TabController(length: _wikiSites.length, vsync: this);
      _tabController.addListener(_onTabChanged);
      _tabController.index = tabIndex.clamp(0, _wikiSites.length - 1).toInt();
      // A switch saved against the theme. One that equals the theme now
      // was made before the theme turned: the theme wins.
      if (storedDarkMode != null &&
          storedDarkMode != ref.read(themeProvider).isDark) {
        _isDarkMode = storedDarkMode;
        _ownDarkMode = true;
      }
      _restoredState = true;
    });
    final pending = _pendingOpen;
    if (pending != null) {
      _pendingOpen = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRequested(pending);
      });
    }
  }

  /// Saves the tabs, URLs and the appearance. Called from [dispose] too,
  /// where `ref` can no longer be used: the service was taken in
  /// [initState] and the state is copied before the first await.
  Future<void> _persistBrowsingState() async {
    final service = _settings;
    final tabIndex = _tabController.index;
    final darkMode = _ownDarkMode ? _isDarkMode : null;
    final urls = List.of(_currentUrls);
    final appliedUrls = List.of(_appliedSourceUrls);
    try {
      await service.saveWikiTabIndex(tabIndex);
      if (darkMode != null) {
        await service.saveWikiDarkMode(darkMode);
      } else {
        await service.clearWikiDarkMode();
      }
      await Future.wait([
        for (var i = 0; i < urls.length; i++)
          if (urls[i].trim().isNotEmpty) service.saveWikiUrl(i, urls[i]),
        for (var i = 0; i < appliedUrls.length; i++)
          if (appliedUrls[i].trim().isNotEmpty)
            service.saveWikiAppliedUrl(i, appliedUrls[i]),
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
    final scale = _pageScale;
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
    _refreshCurrentWiki();
  }

  Future<void> _refreshCurrentWiki() async {
    if (!_restoredState || _wikiSites.isEmpty) return;

    final index = _tabController.index;
    final controller = _controllers[index];
    if (controller == null) return;

    final configuredSites =
        await ref.read(settingsServiceProvider).loadWikiSites();
    if (!mounted) return;

    final activeSite = _wikiSites[index];
    final configuredIndex =
        configuredSites.indexWhere((site) => site.id == activeSite.id);
    final configuredSite =
        configuredIndex >= 0 ? configuredSites[configuredIndex] : null;

    if (configuredSite != null &&
        configuredSite.url != _appliedSourceUrls[index]) {
      final nextSites = [..._wikiSites];
      nextSites[index] = configuredSite;
      setState(() {
        _wikiSites = nextSites;
        _currentUrls[index] = configuredSite.url;
        _appliedSourceUrls[index] = configuredSite.url;
        _titles[index] = '';
        _canGoBack[index] = false;
        _canGoForward[index] = false;
      });
      await ref
          .read(settingsServiceProvider)
          .saveWikiAppliedUrl(index, configuredSite.url);
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(configuredSite.url)),
      );
      return;
    }

    await controller.reload();
  }

  void _toggleDarkMode() {
    final newValue = !_isDarkMode;
    setState(() {
      _isDarkMode = newValue;
      // Switched back to the theme's: following it again.
      _ownDarkMode = newValue != ref.read(themeProvider).isDark;
    });
    _saveDarkMode();
  }

  /// The app's theme turned light or dark: the pages follow it, whatever
  /// the reader had switched them to.
  void _followTheme(bool dark) {
    if (!_ownDarkMode && _isDarkMode == dark) return;
    setState(() {
      _isDarkMode = dark;
      _ownDarkMode = false;
    });
    _saveDarkMode();
  }

  void _saveDarkMode() {
    (_ownDarkMode
            ? _settings.saveWikiDarkMode(_isDarkMode)
            : _settings.clearWikiDarkMode())
        .catchError(
      (Object error) => debugPrint(
        '[WikiBrowser] Error saving wiki appearance: $error',
      ),
    );
  }

  /// Room the floating docks take over the web page (logical px = CSS px):
  /// the site plate at the top, the navigation at the bottom. Set in
  /// [build].
  double _dockTop = 0;
  double _dockBottom = 0;
  double _visibleDockTop = 0;
  double _visibleDockBottom = 0;
  Duration _dockDuration = Duration.zero;

  /// Records the docks' room and, when it changed, pads every open page.
  void _syncDockInsets(double top, double bottom, bool hidden) {
    final visibleTop = hidden ? MediaQuery.paddingOf(context).top : top;
    final visibleBottom =
        hidden ? MediaQuery.viewPaddingOf(context).bottom : bottom;
    final duration = Motion.of(context, hidden ? Motion.row : Motion.press * 2);
    if (top == _dockTop &&
        bottom == _dockBottom &&
        visibleTop == _visibleDockTop &&
        visibleBottom == _visibleDockBottom &&
        duration == _dockDuration) {
      return;
    }
    _dockTop = top;
    _dockBottom = bottom;
    _visibleDockTop = visibleTop;
    _visibleDockBottom = visibleBottom;
    _dockDuration = duration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in _controllers) {
        if (controller != null) unawaited(_applyDockInsets(controller));
      }
    });
  }

  /// Pads the page by the docks' room, so its top and its end can be
  /// scrolled clear of them, and moves the site's own fixed/sticky bars
  /// (which ignore padding) down/up by the same amount.
  Future<void> _applyDockInsets(InAppWebViewController controller) async {
    final js = wikiDockInsetsScript(
      top: _dockTop,
      bottom: _dockBottom,
      visibleTop: _visibleDockTop,
      visibleBottom: _visibleDockBottom,
      duration: _dockDuration,
    );
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // A page that is still loading gets it with its appearance pass.
    }
  }

  Future<void> _applyNormalWebViewEnhancements(
    InAppWebViewController controller,
  ) async {
    await _applyDockInsets(controller);
    await _applyPageScale(controller);
    await _applyPrtsOperatorResponsiveLayout(controller);
    await _applyPrtsScenarioFit(controller);
  }

  Future<void> _applyPrtsOperatorResponsiveLayout(
    InAppWebViewController controller,
  ) async {
    const js = '''
(function() {
  var styleId = 'arklores-prts-paradox-mobile-fit';
  if (!document.getElementById(styleId)) {
    var style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      .arklores-prts-paradox-table {
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
        table-layout: fixed !important;
      }
      .arklores-prts-paradox-table :where(tbody, tr, td, th) {
        max-width: 100% !important;
        min-width: 0 !important;
        overflow-wrap: anywhere !important;
        word-break: break-word !important;
      }
      .arklores-prts-paradox-table img {
        max-width: 100% !important;
        height: auto !important;
      }
      @media (max-width: 600px) {
        .arklores-prts-paradox-table .nomobile { display: none !important; }
        .arklores-prts-paradox-table .nodesktop {
          display: table !important;
          width: min(100%, 15rem) !important;
          max-width: 100% !important;
          min-width: 0 !important;
          margin: 0.55em auto !important;
          table-layout: auto !important;
        }
        .arklores-prts-paradox-table .nodesktop > tbody > tr > td > a > div {
          width: 100% !important;
          max-width: 100% !important;
          margin-left: 0 !important;
        }
        .arklores-prts-paradox-table .nodesktop > tbody > tr > td > span {
          width: auto !important;
          max-width: 100% !important;
          margin: 0.7em auto 0 !important;
          padding: 0.4em 0.5em !important;
          height: auto !important;
          flex-wrap: wrap !important;
          justify-content: center !important;
          gap: 0.35em !important;
        }
      }
      @media (min-width: 601px) {
        .arklores-prts-paradox-table .nodesktop { display: none !important; }
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  function findHeading() {
    var headings = document.querySelectorAll('#mw-content-text h2, .mw-parser-output h2');
    for (var i = 0; i < headings.length; i++) {
      var heading = headings[i];
      var id = heading.querySelector('[id="悖论模拟"]');
      if (id || (heading.textContent || '').trim() === '悖论模拟') return heading;
    }
    return null;
  }

  function markParadoxTables() {
    var heading = findHeading();
    if (!heading) return;
    var node = heading.nextElementSibling;
    while (node && node.tagName !== 'H2') {
      if (node.tagName === 'TABLE') {
        var nested = node.querySelectorAll('table');
        for (var i = 0; i < nested.length; i++) {
          nested[i].classList.remove('arklores-prts-paradox-table');
        }
        node.classList.add('arklores-prts-paradox-table');
      }
      node = node.nextElementSibling;
    }
  }

  markParadoxTables();
  window.setTimeout(markParadoxTables, 500);
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // PRTS operator tables are enhanced only when the page exposes them.
    }
  }

  Future<void> _applyPrtsScenarioFit(
    InAppWebViewController controller,
  ) async {
    const js = '''
(function() {
  var shell = document.getElementById('sys_fullscreen');
  var offset = document.getElementById('sys_offset');
  var main = document.getElementById('sys_main');
  var fullscreenButton = document.getElementById('button_fullscreen');
  if (!shell || !offset || !main || !fullscreenButton) return;

  var alreadyWrapped = document.documentElement.dataset.arkloresPrtsFitWrapped === '1';
  var alreadyListening = document.documentElement.dataset.arkloresPrtsFitListening === '1';
  var baseWidth = 960;
  var baseHeight = 540;

  function viewportSize() {
    var viewport = window.visualViewport;
    var width = viewport && viewport.width ? viewport.width : window.innerWidth;
    var height = viewport && viewport.height ? viewport.height : window.innerHeight;
    return {
      width: Math.max(1, Math.floor(width || baseWidth)),
      height: Math.max(1, Math.floor(height || baseHeight))
    };
  }

  function isFullscreenActive() {
    return !!(document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement ||
      document.msFullscreenElement ||
      document.webkitIsFullScreen ||
      document.webkitFullScreen);
  }

  function fitScenario() {
    var viewport = viewportSize();
    var scale = Math.min(viewport.width / baseWidth, viewport.height / baseHeight);
    if (!isFinite(scale) || scale <= 0) scale = 1;
    scale = Math.min(scale, 1.0);
    var width = Math.round(baseWidth * scale);
    var height = Math.round(baseHeight * scale);
    var left = isFullscreenActive() ? Math.max(Math.round((viewport.width - width) / 2), 0) : 0;
    var top = isFullscreenActive() ? Math.max(Math.round((viewport.height - height) / 2), 0) : 0;

    main.style.transformOrigin = '0 0';
    main.style.transform = 'scale(' + scale + ')';
    offset.style.width = width + 'px';
    offset.style.height = height + 'px';
    offset.style.left = left + 'px';
    offset.style.top = top + 'px';

    if (isFullscreenActive()) {
      fullscreenButton.classList.remove('normal');
      fullscreenButton.classList.add('return');
    } else {
      fullscreenButton.classList.add('normal');
      fullscreenButton.classList.remove('return');
    }
  }

  function wrapFullscreen() {
    if (document.documentElement.dataset.arkloresPrtsFitWrapped === '1') return;
    if (typeof window.fun_fullscreen !== 'function') return;
    if (window.fun_fullscreen.__arkloresWrapped === '1') {
      document.documentElement.dataset.arkloresPrtsFitWrapped = '1';
      return;
    }
    var originalFullscreen = window.fun_fullscreen;
    var wrapped = function() {
      try {
        originalFullscreen.apply(this, arguments);
      } catch (e) {}
      try {
        fitScenario();
      } catch (e) {}
    };
    wrapped.__arkloresWrapped = '1';
    window.fun_fullscreen = wrapped;
    document.documentElement.dataset.arkloresPrtsFitWrapped = '1';
  }

  function installPolling() {
    if (document.documentElement.dataset.arkloresPrtsFitPolling === '1') return;
    document.documentElement.dataset.arkloresPrtsFitPolling = '1';
    var timer = window.setInterval(function() {
      wrapFullscreen();
      fitScenario();
    }, 350);
    window.addEventListener('pagehide', function() {
      window.clearInterval(timer);
      document.documentElement.dataset.arkloresPrtsFitPolling = '0';
    }, { once: true });
  }

  if (!alreadyWrapped) {
    wrapFullscreen();
  }

  if (!alreadyListening) {
    var schedule = function() {
      if (window.requestAnimationFrame) {
        window.requestAnimationFrame(fitScenario);
      } else {
        window.setTimeout(fitScenario, 0);
      }
    };
    window.addEventListener('resize', schedule, { passive: true });
    window.addEventListener('orientationchange', schedule, { passive: true });
    document.addEventListener('fullscreenchange', schedule, true);
    document.addEventListener('webkitfullscreenchange', schedule, true);
    document.addEventListener('mozfullscreenchange', schedule, true);
    document.addEventListener('MSFullscreenChange', schedule, true);
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', schedule, { passive: true });
      window.visualViewport.addEventListener('scroll', schedule, { passive: true });
    }
    document.documentElement.dataset.arkloresPrtsFitListening = '1';
  }

  installPolling();
  fitScenario();
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Best-effort PRTS simulator fit for mobile/fullscreen layouts.
    }
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
      smoothPageRoute(
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
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(bookmark.url)),
      );
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
      // Another page: the bars back.
      if (index == _tabController.index) _bars.show(ref);
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

  /// The site switch: the sites in a floating plate on the left (as wide as
  /// they need), bookmarks in a square plate on the right. The web page starts
  /// below them (a page cannot be told to leave room under a dock).
  Widget _buildSiteBar(AppThemeTokens theme) {
    return MainTopBar(
      hides: true,
      leading: SingleChildScrollView(
        key: const ValueKey('wiki-site-bar'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _wikiSites.length; i++) _siteSegment(theme, i),
          ],
        ),
      ),
      trailing: SquareIconButton(
        icon: Icons.bookmarks_sharp,
        tooltip: context.t.bookmarksTitle,
        onPressed: _openBookmarks,
      ),
    );
  }

  Widget _siteSegment(AppThemeTokens theme, int index) => TopTab(
        key: ValueKey('wiki-site-$index'),
        label: _wikiSites[index].label,
        selected: _tabController.index == index,
        onTap: () => _tabController.index = index,
        compact: true,
      );

  /// Hides the bars as the page is scrolled on, shows them back (and at its
  /// top), for the site shown.
  final BarsFollower _bars = BarsFollower();
  final Map<int, int> _scrollY = {};

  void _onScrolled(int index, int y) {
    final before = _scrollY[index];
    _scrollY[index] = y;
    if (index != _tabController.index || before == null || !mounted) return;
    _bars.moved(ref, (y - before).toDouble(), atTop: y <= 0);
  }

  /// A tap on the page's text or empty space: the bars back, or away again.
  void _onBlankTap(int index) {
    if (index != _tabController.index || !mounted) return;
    _bars.tapped(ref, canHide: (_scrollY[index] ?? 0) > 0);
  }
  // ─── Build ───────────────────────────────────────────────────────

  /// 0.13: a page asked for by another page (an answer's wiki citation)
  /// before the tabs were restored; opened right after.
  WikiOpenRequest? _pendingOpen;

  /// Opens [request] in the tab of its site (by id, else by host, else the
  /// first tab).
  void _openRequested(WikiOpenRequest request) {
    if (!_restoredState) {
      _pendingOpen = request;
      return;
    }
    var index = _wikiSites.indexWhere((s) => s.id == request.siteId);
    if (index < 0) {
      index = _wikiSites.indexWhere(
        (s) => Uri.tryParse(s.url)?.host == request.url.host,
      );
    }
    if (index < 0) index = 0;
    if (_tabController.index != index) {
      _tabController.index = index;
      _saveWikiTabIndex(index);
    }
    final url = '${request.url}';
    final controller = _controllers[index];
    if (controller != null) {
      controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } else {
      setState(() => _currentUrls[index] = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    ref.listen<bool>(themeProvider.select((t) => t.isDark), (before, dark) {
      if (before != dark) _followTheme(dark);
    });
    final bookmarkAsync = ref.watch(bookmarkProvider);
    ref.listen<WikiOpenRequest?>(wikiOpenRequestProvider, (_, request) {
      if (request == null) return;
      ref.read(wikiOpenRequestProvider.notifier).state = null;
      _openRequested(request);
    });
    if (!_restoredState) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: const LoadingView(),
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

    _syncDockInsets(
      MediaQuery.paddingOf(context).top + topBarInset,
      MediaQuery.paddingOf(context).bottom,
      ref.watch(barsHiddenProvider) &&
          MediaQuery.viewInsetsOf(context).bottom == 0,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            // ── The web page fills the page; the docks float over it and
            // the page is padded to match (_applyDockInsets). IndexedStack:
            // no horizontal swipes between sites. ──
            Positioned.fill(
              child: IndexedStack(
                index: _tabController.index,
                children: List.generate(_wikiSites.length, (i) {
                  return TickerMode(
                    enabled: i == _tabController.index,
                    child: _WikiTabView(
                      key: ValueKey(_wikiSites[i].id),
                      index: i,
                      initialUrl: _currentUrls[i].trim().isNotEmpty
                          ? _currentUrls[i]
                          : _wikiSites[i].url,
                      theme: theme,
                      isDarkMode: _isDarkMode,
                      onNormalAppearance: _applyNormalWebViewEnhancements,
                      onControllerCreated: _onControllerCreated,
                      onTitleChanged: _onTitleChanged,
                      onUrlChanged: _onUrlChanged,
                      onHistoryChanged: _onHistoryChanged,
                      onScrolled: _onScrolled,
                      onBlankTap: _onBlankTap,
                    ),
                  );
                }),
              ),
            ),
            _buildSiteBar(theme),

            ExpandableTray(
              expanded: _trayExpanded,
              onToggle: () => setState(() => _trayExpanded = !_trayExpanded),
              isDarkMode: _isDarkMode,
              isBookmarked: isBookmarked,
              onZoomOut: _zoomOut,
              onZoomIn: _zoomIn,
              onRefresh: _reload,
              onToggleDarkMode: _toggleDarkMode,
              onToggleBookmark: _toggleBookmark,
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
  const _WikiTabView({
    super.key,
    required this.index,
    required this.initialUrl,
    required this.theme,
    required this.isDarkMode,
    required this.onNormalAppearance,
    required this.onControllerCreated,
    required this.onTitleChanged,
    required this.onUrlChanged,
    required this.onHistoryChanged,
    required this.onScrolled,
    required this.onBlankTap,
  });
  final int index;

  /// A tap ended on the page where nothing answers it.
  final void Function(int index) onBlankTap;

  /// The page scrolled to [y] (CSS pixels from its top).
  final void Function(int index, int y) onScrolled;
  final String initialUrl;
  final AppThemeTokens theme;
  final bool isDarkMode;
  final Future<void> Function(InAppWebViewController) onNormalAppearance;
  final void Function(int, InAppWebViewController) onControllerCreated;
  final void Function(int, String?) onTitleChanged;
  final void Function(int, String) onUrlChanged;
  final Future<void> Function(int, bool, bool) onHistoryChanged;

  @override
  State<_WikiTabView> createState() => _WikiTabViewState();
}

/// Counts the page's animation frames (the rate the web view is given
/// frames at) and logs them once a second.
const _webFpsScript = '''
(function () {
  var n = 0, start = 0;
  function tick(t) {
    if (!start) start = t;
    n++;
    if (t - start >= 1000) {
      if (n > 2) console.log('[webfps] ' + Math.round(n * 1000 / (t - start)) + ' fps');
      n = 0; start = t;
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
''';

class _WikiTabViewState extends State<_WikiTabView> {
  InAppWebViewController? _controller;
  String? _loadError;
  double? _edgeDragStartX;
  bool _isPreparingWebView = true;
  bool _hasLoadedPage = false;
  int _appearanceRequest = 0;
  bool _paused = false;

  /// The page's load progress (0–1), null before the web view reports it.
  double? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPaused();
  }

  /// An Android WebView keeps drawing its page (animations, video) while it
  /// is off screen, on the app's main thread, which is also where the app's
  /// frames start: off screen (another tab, the other site, a page pushed
  /// over it; TickerMode) it is paused.
  void _syncPaused() {
    final controller = _controller;
    if (controller == null || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final pause = !TickerMode.valuesOf(context).enabled;
    if (pause == _paused) return;
    _paused = pause;
    (pause ? controller.pause() : controller.resume()).catchError(
      (Object error) =>
          debugPrint('[WikiBrowser] Error pausing WebView: $error'),
    );
  }

  @override
  void didUpdateWidget(covariant _WikiTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;
    if (oldWidget.isDarkMode != widget.isDarkMode) {
      if (_hasLoadedPage) {
        _prepareWebViewAppearance();
      }
    }
  }

  void _showLoadingOverlay() {
    _appearanceRequest++;
    if (mounted && !_isPreparingWebView) {
      setState(() => _isPreparingWebView = true);
    }
  }

  Future<void> _prepareWebViewAppearance() async {
    final request = ++_appearanceRequest;
    var needsFrame = false;
    if (mounted && !_isPreparingWebView) {
      setState(() => _isPreparingWebView = true);
      needsFrame = true;
    }

    if (needsFrame) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || request != _appearanceRequest) return;
    }

    try {
      await _applyAppearance();
    } catch (error) {
      debugPrint('[WikiBrowser] Error applying WebView appearance: $error');
    }

    if (!mounted || request != _appearanceRequest) return;
    setState(() => _isPreparingWebView = false);
  }

  Future<void> _applyAppearance() async {
    final controller = _controller;
    if (controller == null) return;

    await WikiAppearance.inject(
      controller,
      dark: widget.isDarkMode,
    );
    await widget.onNormalAppearance(controller);
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
            transparentBackground: false,
            // Android: the page is a view of its own the system composes.
            // Drawn into a texture instead, the page rendered every vsync
            // but Flutter picked the frames up unevenly: a quarter of them
            // never shown, the scroll jerked (traced 2026-10-24, 120 Hz).
            // Hybrid Composition once made the whole app stutter, but that
            // was the 60 Hz cap and the hidden tabs' redraws, since fixed.
            useHybridComposition: true,
          ),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              groupName: 'arklores-theme-bootstrap',
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
              source: WikiSiteAdapter.documentStartThemeScript(
                dark: widget.isDarkMode,
              ),
            ),
            // Profile builds (`-FrameLog`): the page's own frames a second,
            // next to Flutter's `[frame]` lines — whether the page draws
            // fewer, or Flutter composes fewer of them.
            UserScript(
              groupName: 'arklores-blank-tap',
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
              source: wikiBlankTapScript,
            ),
            if (kProfileMode)
              UserScript(
                groupName: 'arklores-web-fps',
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
                source: _webFpsScript,
              ),
          ]),
          onConsoleMessage: kProfileMode
              ? (controller, message) {
                  if (message.message.startsWith('[webfps]')) {
                    debugPrint(message.message);
                  }
                }
              : null,
          onWebViewCreated: (controller) {
            _controller = controller;
            controller.addJavaScriptHandler(
              handlerName: wikiBlankTapHandler,
              callback: (_) => widget.onBlankTap(widget.index),
            );
            widget.onControllerCreated(widget.index, controller);
            _syncPaused();
          },
          onProgressChanged: (controller, progress) {
            if (!mounted || !_isPreparingWebView) return;
            setState(() => _progress = progress / 100);
          },
          onLoadStart: (controller, url) {
            _hasLoadedPage = false;
            _progress = null;
            _showLoadingOverlay();
            if (_loadError != null) setState(() => _loadError = null);
          },
          onLoadStop: (controller, url) async {
            _hasLoadedPage = true;
            await _prepareWebViewAppearance();
          },
          onTitleChanged: (controller, title) {
            widget.onTitleChanged(widget.index, title);
          },
          onScrollChanged: (controller, x, y) =>
              widget.onScrolled(widget.index, y),
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
              _isPreparingWebView = false;
            });
            _appearanceRequest++;
          },
        ),
        _buildEdgeGestureLayer(),
        if (_isPreparingWebView) _buildLoadingOverlay(),
        if (_loadError != null) _buildErrorOverlay(context),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return AbsorbPointer(
      child: ColoredBox(
        color: widget.theme.bgPrimary,
        // The page's own load progress (the web view reports it), as a
        // browser shows it; before the first report, the walking mark.
        child: Center(
          child: SizedBox(
            width: 144,
            child: SegmentProgress(value: _progress, cells: 12, height: 6),
          ),
        ),
      ),
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
                        if (await _controller?.canGoBack() ?? false) {
                          await _controller?.goBack();
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
                        if (await _controller?.canGoForward() ?? false) {
                          await _controller?.goForward();
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
            child: NoticeBox(
              _loadError!,
              title: context.t.wikiLoadFailed,
              action: AppButton(
                context.t.wikiRetry,
                kind: ButtonKind.go,
                icon: Icons.refresh_sharp,
                onPressed: () {
                  setState(() => _loadError = null);
                  _controller?.reload();
                },
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
      return context.t.wikiErrorDns;
    }
    if (lower.contains('timeout')) {
      return context.t.wikiErrorTimeout;
    }
    if (lower.contains('net::err_internet_disconnected')) {
      return context.t.wikiErrorOffline;
    }
    return description;
  }
}

/// The handler the page calls when a tap ends where nothing on it answers.
const String wikiBlankTapHandler = 'arkloresBlankTap';

/// Tells the app about taps that end on text or empty space: a `click`
/// (the browser sends none for a scroll or a long press) that the page did
/// not take for itself (no link, control or handler-marked element under
/// it, not cancelled) and that selected no text. Bubbling, so the page's
/// own handlers run first. The same for every site.
const String wikiBlankTapScript = '''
(function () {
  if (window.__arkloresBlankTap) return;
  window.__arkloresBlankTap = true;
  var live = 'a[href],button,input,select,textarea,label,summary,video,audio,'
    + '[onclick],[role="button"],[role="link"],[role="tab"],[role="menuitem"],'
    + '[contenteditable=""],[contenteditable="true"],[tabindex]:not([tabindex="-1"])';
  document.addEventListener('click', function (e) {
    if (e.defaultPrevented) return;
    var t = e.target;
    if (t && t.closest && t.closest(live)) return;
    var s = window.getSelection && window.getSelection();
    if (s && !s.isCollapsed) return;
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('$wikiBlankTapHandler');
    }
  }, false);
})();
''';

/// Generic fixed/sticky dock adaptation; page padding stays stable while bars move.
@visibleForTesting
String wikiDockInsetsScript({
  required double top,
  required double bottom,
  required double visibleTop,
  required double visibleBottom,
  required Duration duration,
}) {
  String transition(String edge) => duration == Duration.zero
      ? ''
      : 'transition:$edge ${duration.inMilliseconds}ms cubic-bezier(0.7,0,0.2,1) !important;';
  final topTransition = transition('top');
  final bottomTransition = transition('bottom');
  return '''
(function(t, b) {
  var root = document.documentElement;
  root.style.setProperty('--arklores-dock-top', '${visibleTop}px');
  root.style.setProperty('--arklores-dock-bottom', '${visibleBottom}px');
  var id = 'arklores-dock-insets';
  var style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = 'html{padding-top:' + t + 'px !important;' +
      'padding-bottom:' + b + 'px !important;' +
      'scroll-padding-top:var(--arklores-dock-top);}' +
      '[data-arklores-dock=top]{top:var(--arklores-dock-top) !important;$topTransition}' +
      '[data-arklores-dock=bottom]{bottom:var(--arklores-dock-bottom) !important;$bottomTransition}';
  function shift() {
    if (!document.body) return;
    var all = document.body.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var e = all[i];
      var cs = window.getComputedStyle(e);
      if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
      if (e.dataset.arkloresDock === undefined) {
        if (parseFloat(cs.top) === 0) e.dataset.arkloresDock = 'top';
        else if (cs.position === 'fixed' && parseFloat(cs.bottom) === 0)
          e.dataset.arkloresDock = 'bottom';
        else e.dataset.arkloresDock = '';
      }
      if (e.dataset.arkloresDock === 'top')
        e.style.setProperty('top', 'var(--arklores-dock-top)', 'important');
      if (e.dataset.arkloresDock === 'bottom')
        e.style.setProperty('bottom', 'var(--arklores-dock-bottom)', 'important');
    }
  }
  shift();
  window.setTimeout(shift, 600);
  window.setTimeout(shift, 1600);
})($top, $bottom);
''';
}
