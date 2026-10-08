import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/providers/wiki_navigation_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../shared/widgets/smooth_page_route.dart';
import '../ai/ai_chat_page.dart';
import '../ai/wiki_ai_context.dart';
import '../settings/settings_service.dart';
import 'bookmark_page.dart';
import 'bookmark_service.dart' show Bookmark;
import 'wiki_appearance.dart';
import 'wiki_browser_controls.dart';
import 'wiki_reader_mode.dart';
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

  /// Dark mode toggle state for Wiki WebView pages.
  bool _isDarkMode = false;
  bool _isReaderMode = false;
  double _readerFontScale = 1.0;
  double _pageScale = 1.0;
  bool _trayExpanded = false;
  bool _readerControlsVisible = true;
  bool _restoredState = false;
  bool _hasStoredDarkMode = false;
  Timer? _readerControlsTimer;
  late final SettingsService _settings;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(settingsServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    _isDarkMode =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
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
    _readerControlsTimer?.cancel();
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

  @override
  void didChangePlatformBrightness() {
    if (_hasStoredDarkMode) return;
    final prefersDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    if (prefersDark == _isDarkMode) return;
    setState(() => _isDarkMode = prefersDark);
  }

  Future<void> _restoreBrowsingState() async {
    var tabIndex = 0;
    var readerMode = false;
    var readerFontScale = 1.0;
    bool? storedDarkMode;
    var sites = SettingsService.defaultWikiSites;
    var urls = <String>[];
    var appliedUrls = <String>[];
    try {
      final service = _settings;
      sites = await service.loadWikiSites();
      final loadedSites = sites;
      // Each read is a secure-storage platform call: run them together.
      (urls, appliedUrls, tabIndex, readerMode, readerFontScale, storedDarkMode) =
          await (
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
        service.loadWikiReaderMode(),
        service.loadWikiReaderFontScale(),
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
      _isReaderMode = readerMode;
      _readerFontScale = readerFontScale;
      if (storedDarkMode != null) {
        _isDarkMode = storedDarkMode;
        _hasStoredDarkMode = true;
      }
      _restoredState = true;
    });
    ref.read(wikiReaderFullscreenProvider.notifier).state = readerMode;
  }

  /// Saves the tabs, URLs and reader settings. Called from [dispose] too,
  /// where `ref` can no longer be used: the service was taken in
  /// [initState] and the state is copied before the first await.
  Future<void> _persistBrowsingState() async {
    final service = _settings;
    final tabIndex = _tabController.index;
    final readerMode = _isReaderMode;
    final fontScale = _readerFontScale;
    final darkMode = _hasStoredDarkMode ? _isDarkMode : null;
    final urls = List.of(_currentUrls);
    final appliedUrls = List.of(_appliedSourceUrls);
    try {
      await service.saveWikiTabIndex(tabIndex);
      await service.saveWikiReaderMode(readerMode);
      await service.saveWikiReaderFontScale(fontScale);
      if (darkMode != null) {
        await service.saveWikiDarkMode(darkMode);
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
    setState(() => _isDarkMode = newValue);
    _hasStoredDarkMode = true;
    ref.read(settingsServiceProvider).saveWikiDarkMode(newValue).catchError(
          (Object error) => debugPrint(
            '[WikiBrowser] Error saving wiki appearance: $error',
          ),
        );
  }

  void _toggleReaderMode() {
    final enabled = !_isReaderMode;
    _setReaderMode(enabled);
  }

  void _setReaderMode(bool enabled) {
    _readerControlsTimer?.cancel();
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
    if (enabled) _scheduleReaderControlsHide();
  }

  void _toggleReaderControls() {
    if (!_isReaderMode) return;
    if (_readerControlsVisible) {
      _readerControlsTimer?.cancel();
      setState(() => _readerControlsVisible = false);
      return;
    }
    setState(() => _readerControlsVisible = true);
    _scheduleReaderControlsHide();
  }

  void _scheduleReaderControlsHide() {
    _readerControlsTimer?.cancel();
    if (!_isReaderMode || !_readerControlsVisible) return;
    _readerControlsTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_isReaderMode) return;
      setState(() => _readerControlsVisible = false);
    });
  }

  void _runReaderToolbarAction(VoidCallback action) {
    _scheduleReaderControlsHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isReaderMode) return;
      action();
    });
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
  }

  /// Room the floating docks take over the web page (logical px = CSS px):
  /// the site pill at the top, the navigation at the bottom. Set in
  /// [build]; 0 in reader mode, where both docks are hidden.
  double _dockTop = 0;
  double _dockBottom = 0;

  /// Records the docks' room and, when it changed, pads every open page.
  void _syncDockInsets(double top, double bottom) {
    if (top == _dockTop && bottom == _dockBottom) return;
    _dockTop = top;
    _dockBottom = bottom;
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
    final js = '''
(function(t, b) {
  var id = 'arklores-dock-insets';
  var style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = 'html{padding-top:' + t + 'px !important;' +
      'padding-bottom:' + b + 'px !important;' +
      'scroll-padding-top:' + t + 'px;}';
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
        e.style.setProperty('top', t + 'px', 'important');
      if (e.dataset.arkloresDock === 'bottom')
        e.style.setProperty('bottom', b + 'px', 'important');
    }
  }
  shift();
  window.setTimeout(shift, 600);
  window.setTimeout(shift, 1600);
})($_dockTop, $_dockBottom);
''';
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

  Future<void> _sendSelectionToAi() async {
    final idx = _tabController.index;
    final controller = _controllers[idx];
    if (controller == null) return;
    final selectedText = await _readSelectedText(controller);
    if (!mounted) return;

    final target = await showModalBottomSheet<WikiAiTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => WikiAiTargetSheet(theme: ref.read(themeProvider)),
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

    await Navigator.of(context).push<void>(
      smoothPageRoute<void>(
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

  /// The site switch: the sites in a floating pill on the left (as wide as
  /// they need), bookmarks in a round pill on the right. The web page starts
  /// below them (a page cannot be told to leave room under a dock).
  Widget _buildSiteBar(AppThemeTokens theme) {
    return Padding(
      key: const ValueKey('wiki-site-bar'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: FloatingSplitBar(
        theme: theme,
        leading: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _wikiSites.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _siteSegment(theme, i),
                ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.bookmarks_outlined, size: 20),
          color: theme.textPrimary,
          tooltip: context.t.bookmarksTitle,
          onPressed: _openBookmarks,
        ),
      ),
    );
  }
  Widget _siteSegment(AppThemeTokens theme, int index) => FloatingSegment(
        key: ValueKey('wiki-site-$index'),
        theme: theme,
        label: _wikiSites[index].label,
        selected: _tabController.index == index,
        onTap: () => _tabController.index = index,
      );
  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final bookmarkAsync = ref.watch(bookmarkProvider);
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

    _syncDockInsets(
      _isReaderMode ? 0 : floatingTopInset,
      _isReaderMode ? 0 : MediaQuery.paddingOf(context).bottom,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: !_isReaderMode,
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
                        siteKind: WikiSiteAdapter.kindForUrl(_currentUrls[i]),
                        onReaderTapped: _toggleReaderControls,
                        onNormalAppearance: _applyNormalWebViewEnhancements,
                        onControllerCreated: _onControllerCreated,
                        onTitleChanged: _onTitleChanged,
                        onUrlChanged: _onUrlChanged,
                        onHistoryChanged: _onHistoryChanged,
                      );
                    }),
                  ),
                ),
            if (!_isReaderMode)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildSiteBar(theme),
              ),

            if (_isReaderMode)
              ReaderToolbar(
                visible: _readerControlsVisible,
                isDarkMode: _isDarkMode,
                onToggleDarkMode: () =>
                    _runReaderToolbarAction(_toggleDarkMode),
                onDecreaseReaderFont: () =>
                    _runReaderToolbarAction(_decreaseReaderFont),
                onIncreaseReaderFont: () =>
                    _runReaderToolbarAction(_increaseReaderFont),
                onHide: () {
                  _readerControlsTimer?.cancel();
                  setState(() => _readerControlsVisible = false);
                },
                onExitReader: () => _setReaderMode(false),
              )
            else
              ExpandableTray(
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

  const _WikiTabView({
    super.key,
    required this.index,
    required this.initialUrl,
    required this.theme,
    required this.isDarkMode,
    required this.isReaderMode,
    required this.readerDark,
    required this.readerFontScale,
    required this.siteKind,
    required this.onReaderTapped,
    required this.onNormalAppearance,
    required this.onControllerCreated,
    required this.onTitleChanged,
    required this.onUrlChanged,
    required this.onHistoryChanged,
  });
  final int index;
  final String initialUrl;
  final AppThemeTokens theme;
  final bool isDarkMode;
  final bool isReaderMode;
  final bool readerDark;
  final double readerFontScale;
  final WikiSiteKind siteKind;
  final VoidCallback onReaderTapped;
  final Future<void> Function(InAppWebViewController) onNormalAppearance;
  final void Function(int, InAppWebViewController) onControllerCreated;
  final void Function(int, String?) onTitleChanged;
  final void Function(int, String) onUrlChanged;
  final Future<void> Function(int, bool, bool) onHistoryChanged;

  @override
  State<_WikiTabView> createState() => _WikiTabViewState();
}

class _WikiTabViewState extends State<_WikiTabView> {
  InAppWebViewController? _controller;
  String? _loadError;
  double? _edgeDragStartX;
  bool _isPreparingWebView = true;
  bool _hasLoadedPage = false;
  int _appearanceRequest = 0;

  @override
  void didUpdateWidget(covariant _WikiTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;
    if (oldWidget.isReaderMode != widget.isReaderMode ||
        oldWidget.readerDark != widget.readerDark ||
        oldWidget.readerFontScale != widget.readerFontScale ||
        oldWidget.isDarkMode != widget.isDarkMode) {
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

    if (widget.isReaderMode) {
      await WikiAppearance.remove(controller);
      await _resetPageScale(controller);
      await WikiReaderMode.inject(
        controller,
        dark: widget.readerDark,
        fontScale: widget.readerFontScale,
        siteKind: widget.siteKind,
      );
      return;
    }

    await WikiReaderMode.remove(controller);
    await WikiAppearance.inject(
      controller,
      dark: widget.isDarkMode,
    );
    await widget.onNormalAppearance(controller);
  }

  Future<void> _resetPageScale(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(
        source: '''
(function() {
  var html = document.documentElement;
  if (!html) return;
  html.style.removeProperty('zoom');
  html.style.removeProperty('transform-origin');
})();
''',
      );
    } catch (_) {
      // Reader mode always uses the document's natural scale.
    }
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
          ]),
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
            _hasLoadedPage = false;
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
        if (!widget.isReaderMode) _buildEdgeGestureLayer(),
        if (_isPreparingWebView) _buildLoadingOverlay(),
        if (_loadError != null) _buildErrorOverlay(context),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return AbsorbPointer(
      child: ColoredBox(
        color: widget.isReaderMode
            ? (widget.readerDark
                ? const Color(0xFF0B0F14)
                : const Color(0xFFF6F3EA))
            : widget.theme.bgPrimary,
        child: Center(
          child: SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              color: widget.theme.accentPrimary,
              strokeWidth: 2.5,
            ),
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
                      context.t.wikiLoadFailed,
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
                          context.t.wikiRetry,
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
