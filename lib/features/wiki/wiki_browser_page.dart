import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/l10n.dart';
import '../../shared/providers/bookmark_provider.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../ai/ai_chat_page.dart';
import '../ai/wiki_ai_context.dart';
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
  final List<String> _titles = List.filled(_wikiSites.length, '');

  /// Current page URL per tab.
  final List<String> _currentUrls = List.filled(_wikiSites.length, '');

  /// Navigation state per tab.
  final List<bool> _canGoBack = List.filled(_wikiSites.length, false);
  final List<bool> _canGoForward = List.filled(_wikiSites.length, false);

  /// Dark mode toggle state for Wiki WebView pages.
  bool _isDarkMode = false;
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

  void _toggleBookmark() {
    final idx = _tabController.index;
    final url = _currentUrls[idx];
    if (url.isEmpty) return;
    final title =
        _titles[idx].isNotEmpty ? _titles[idx] : _wikiSites[idx].label;
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
          : _wikiSites[idx].initialUrl,
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
                    unselectedLabelStyle: theme.bodyFont.copyWith(fontSize: 14),
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
                        theme: theme,
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
  final void Function(int, InAppWebViewController) onControllerCreated;
  final void Function(int, String?) onTitleChanged;
  final void Function(int, String) onUrlChanged;
  final Future<void> Function(int, bool, bool) onHistoryChanged;

  const _WikiTabView({
    required this.index,
    required this.initialUrl,
    required this.theme,
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
  InAppWebViewController? _controller;
  String? _loadError;

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
            widget.onControllerCreated(widget.index, controller);
          },
          onLoadStart: (controller, url) {
            if (_loadError != null) {
              setState(() => _loadError = null);
            }
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
            final isMainFrame = request.isForMainFrame ?? true;
            if (!isMainFrame) return;
            setState(() {
              _loadError = _friendlyWebViewError(error.description);
            });
          },
        ),
        if (_loadError != null) _buildErrorOverlay(context),
      ],
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
    required this.onSendToAi,
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
  final VoidCallback onSendToAi;

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
                    onSendToAi: onSendToAi,
                    sendToAiTooltip: context.t.wikiSendToAi,
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
