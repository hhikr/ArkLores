/// Identifies the rendering contract of a Wiki host.
enum WikiSiteKind {
  prts,
  fz,
  warfarin,
  generic,
}

/// Small site-specific bridge for non-MediaWiki Wiki implementations.
///
/// The WebView still owns page navigation and interaction. This adapter only
/// changes the host's documented theme state and exposes stable content roots
/// for reader mode.
class WikiSiteAdapter {
  WikiSiteAdapter._();

  static WikiSiteKind kindForUrl(String? rawUrl) {
    final host = Uri.tryParse(rawUrl ?? '')?.host.toLowerCase() ?? '';
    if (host == 'prts.wiki' || host.endsWith('.prts.wiki')) {
      return WikiSiteKind.prts;
    }
    if (host == 'fz.wiki' ||
        host == 'www.fz.wiki' ||
        host.endsWith('.fz.wiki')) {
      return WikiSiteKind.fz;
    }
    if (host == 'warfarin.wiki' ||
        host == 'www.warfarin.wiki' ||
        host.endsWith('.warfarin.wiki')) {
      return WikiSiteKind.warfarin;
    }
    return WikiSiteKind.generic;
  }

  static String documentStartThemeScript({required bool dark}) {
    final mode = dark ? 'dark' : 'light';
    return '''
(function() {
  var mode = '$mode';
  try {
    var saved = sessionStorage.getItem('arklores-wiki-theme');
    if (saved === 'light' || saved === 'dark') mode = saved;
  } catch (e) {}
  var host = String(location.hostname || '').toLowerCase();
  var root = document.documentElement;
  if (!root) return;

  if (host === 'fz.wiki' || host === 'www.fz.wiki' ||
      host.endsWith('.fz.wiki')) {
    root.setAttribute('data-theme', mode);
    root.setAttribute('data-arklores-fz-theme', mode);
    return;
  }

  if (host === 'warfarin.wiki' || host === 'www.warfarin.wiki' ||
      host.endsWith('.warfarin.wiki')) {
    root.classList.toggle('dark', mode === 'dark');
    root.setAttribute('data-arklores-warfarin-theme', mode);
  }
})();
''';
  }

  static String applyThemeScript({required bool dark}) {
    final mode = dark ? 'dark' : 'light';
    return '''
(function() {
  var mode = '$mode';
  var root = document.documentElement;
  if (!root) return;
  var host = String(location.hostname || '').toLowerCase();
  try {
    sessionStorage.setItem('arklores-wiki-theme', mode);
  } catch (e) {}

  function setThemeColor(value) {
    var meta = document.querySelector('meta[name="theme-color"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'theme-color';
      (document.head || root).appendChild(meta);
    }
    meta.setAttribute('content', value);
  }

  if (host === 'fz.wiki' || host === 'www.fz.wiki' ||
      host.endsWith('.fz.wiki')) {
    root.setAttribute('data-theme', mode);
    root.setAttribute('data-arklores-fz-theme', mode);
    try {
      var raw = localStorage.getItem('endfield-wiki-theme');
      var parsed = raw ? JSON.parse(raw) : {};
      if (!parsed || typeof parsed !== 'object') parsed = {};
      if (!parsed.state || typeof parsed.state !== 'object') {
        parsed.state = {};
      }
      parsed.state.mode = mode;
      localStorage.setItem('endfield-wiki-theme', JSON.stringify(parsed));
    } catch (e) {}
    setThemeColor(mode === 'dark' ? '#0a0d13' : '#f7f8fa');
    return;
  }

  if (host === 'warfarin.wiki' || host === 'www.warfarin.wiki' ||
      host.endsWith('.warfarin.wiki')) {
    root.classList.toggle('dark', mode === 'dark');
    root.setAttribute('data-arklores-warfarin-theme', mode);
    root.style.setProperty('color-scheme', mode);
    setThemeColor(mode === 'dark' ? '#252525' : '#ffffff');
  }
})();
''';
  }

  static String removeThemeScript() => '''
(function() {
  var root = document.documentElement;
  if (!root) return;
  var host = String(location.hostname || '').toLowerCase();
  if (host === 'fz.wiki' || host === 'www.fz.wiki' ||
      host.endsWith('.fz.wiki')) {
    root.removeAttribute('data-arklores-fz-theme');
  }
  if (host === 'warfarin.wiki' || host === 'www.warfarin.wiki' ||
      host.endsWith('.warfarin.wiki')) {
    root.removeAttribute('data-arklores-warfarin-theme');
    root.style.removeProperty('color-scheme');
  }
})();
''';

  static const fzReaderRoots = <String>[
    'main > div.grid > div:first-child',
    '[data-page-content]',
    '[data-content]',
    'article',
  ];

  static const warfarinReaderRoots = <String>[
    'main > div.max-w-\\\\[1536px\\\\] > div.flex-1',
    'main > div > div.flex-1',
    'main',
  ];

  static String readerRootSelector(WikiSiteKind kind) {
    switch (kind) {
      case WikiSiteKind.fz:
        return fzReaderRoots.join(', ');
      case WikiSiteKind.warfarin:
        return warfarinReaderRoots.join(', ');
      case WikiSiteKind.prts:
        return '#mw-content-text, .mw-parser-output, main, article';
      case WikiSiteKind.generic:
        return 'article, main, [role="main"], .content, .page-content';
    }
  }
}
