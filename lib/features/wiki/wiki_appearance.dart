import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'wiki_appearance_palette.dart';
import 'wiki_site_adapter.dart';

/// Applies ArkLores appearance overrides to wiki pages.
///
/// The old implementation inverted the whole document and then tried to
/// re-invert images and background images. That cannot be made reliable for
/// canvas, SVG, iframes, game simulators, or nested compositing. This
/// implementation only changes semantic page surfaces and text, while
/// explicitly leaving rendered media and interactive widgets untouched.
class WikiAppearance {
  WikiAppearance._();

  @visibleForTesting
  static String cssForTesting() => _css();

  static String _css() => '''
:root[data-arklores-appearance="dark"] {
  color-scheme: dark !important;
  --arklores-page-bg: ${WikiAppearancePalette.dark.pageBackground};
  --arklores-surface: ${WikiAppearancePalette.dark.surface};
  --arklores-surface-elevated: ${WikiAppearancePalette.dark.surfaceElevated};
  --arklores-border: ${WikiAppearancePalette.dark.border};
  --arklores-text: ${WikiAppearancePalette.dark.text};
  --arklores-muted: ${WikiAppearancePalette.dark.muted};
  --arklores-link: ${WikiAppearancePalette.dark.link};
  --arklores-control-bg: ${WikiAppearancePalette.dark.controlSurface};
  --arklores-control-text: ${WikiAppearancePalette.dark.controlText};
}

:root[data-arklores-appearance="light"] {
  color-scheme: light !important;
  --arklores-page-bg: ${WikiAppearancePalette.light.pageBackground};
  --arklores-surface: ${WikiAppearancePalette.light.surface};
  --arklores-surface-elevated: ${WikiAppearancePalette.light.surfaceElevated};
  --arklores-border: ${WikiAppearancePalette.light.border};
  --arklores-text: ${WikiAppearancePalette.light.text};
  --arklores-muted: ${WikiAppearancePalette.light.muted};
  --arklores-link: ${WikiAppearancePalette.light.link};
  --arklores-control-bg: ${WikiAppearancePalette.light.controlSurface};
  --arklores-control-text: ${WikiAppearancePalette.light.controlText};
}

html[data-arklores-appearance].arklores-prts-site,
html[data-arklores-appearance].arklores-prts-site body,
html[data-arklores-appearance].arklores-generic-site,
html[data-arklores-appearance].arklores-generic-site body {
  background-color: var(--arklores-page-bg) !important;
}

html[data-arklores-appearance].arklores-generic-site body {
  color: var(--arklores-text) !important;
}

html[data-arklores-appearance="dark"].arklores-prts-site :where(
  #content,
  #bodyContent,
  #mw-content-text,
  .mw-body,
  .vector-body
) {
  background-color: var(--arklores-page-bg) !important;
}

html[data-arklores-appearance="dark"].arklores-prts-site :where(
  h1.firstHeading,
  .mw-first-heading,
  .firstHeading .mw-page-title-main
) {
  color: var(--arklores-text) !important;
}

html[data-arklores-appearance="dark"].arklores-prts-site :where(
  #siteSub,
  .mw-editsection,
  .mw-indicator,
  .catlinks
) {
  color: var(--arklores-muted) !important;
}

html[data-arklores-appearance="dark"].arklores-prts-site :where(
  #content,
  .mw-body,
  table.wikitable,
  .infobox,
  .cbox2,
  #app
) {
  border-color: var(--arklores-border) !important;
}

html[data-arklores-appearance].arklores-generic-site :where(
  #mw-content-text,
  .mw-parser-output,
  main,
  article,
  .content,
  .page-content
) {
  color: var(--arklores-text);
}

html[data-arklores-appearance="dark"]:not(.arklores-prts-site) :where(
  .mw-parser-output,
  .mw-parser-output > table,
  .mw-parser-output .wikitable,
  .infobox,
  table.wikitable,
  .prts-widget,
  .prts-widget-card,
  .prts-widget-panel,
  .prts-widget-surface
) {
  background-color: var(--arklores-surface) !important;
  color: var(--arklores-text) !important;
  border-color: var(--arklores-border) !important;
}

html[data-arklores-appearance].arklores-generic-site :where(
  .mw-parser-output p,
  .mw-parser-output li,
  .mw-parser-output dd,
  .mw-parser-output dt,
  .mw-parser-output td,
  .mw-parser-output th,
  .infobox td,
  .infobox th
) {
  color: var(--arklores-text);
}

html[data-arklores-appearance] :where(
  a,
  a:visited,
  .mw-parser-output a
) {
  color: var(--arklores-link);
}

html[data-arklores-appearance].arklores-generic-site :where(
  button,
  input,
  select,
  textarea,
  [role="button"],
  .mw-collapsible-toggle
) {
  color: var(--arklores-control-text);
  background-color: var(--arklores-control-bg);
  border-color: var(--arklores-border);
}

html[data-arklores-appearance] :where(
  img,
  picture,
  video,
  canvas,
  svg,
  iframe,
  [role="img"],
  #sys_fullscreen,
  #sys_offset,
  #sys_main,
  #sys_playback_all,
  #spine-root,
  #voice-table-root
) {
  filter: none !important;
}

html[data-arklores-appearance] .arklores-reader-mode,
html[data-arklores-appearance] #arklores-prts-scenario-reader {
  filter: none !important;
}

''';

  static const _applyScript = r'''
(function() {
  var html = document.documentElement;
  if (!html) return;
  var body = document.body;
  var isPrts = /(^|\.)prts\.wiki$/i.test(location.hostname);
  var isFz = /(^|\.)fz\.wiki$/i.test(location.hostname);
  var isWarfarin = /(^|\.)warfarin\.wiki$/i.test(location.hostname);

  var style = document.getElementById('arklores-wiki-appearance');
  if (!style) {
    style = document.createElement('style');
    style.id = 'arklores-wiki-appearance';
    (document.head || html).appendChild(style);
  }
  style.textContent = __ARKLORES_CSS__;

  var mode = __ARKLORES_MODE__;
  html.classList.toggle('arklores-prts-site', isPrts);
  html.classList.toggle('arklores-fz-site', isFz);
  html.classList.toggle('arklores-warfarin-site', isWarfarin);
  html.classList.toggle('arklores-generic-site', !isPrts && !isFz && !isWarfarin);
  html.setAttribute('data-arklores-appearance', mode);
  html.setAttribute('data-arklores-appearance-version', '2');

  if (isPrts) {
    if (mode === 'dark') {
      html.classList.remove('skin-theme-clientpref-day');
      html.classList.remove('skin-theme-clientpref-os');
      html.classList.add('skin-theme-clientpref-night');
      if (body) {
        body.classList.remove('skin-theme-clientpref-day');
        body.classList.remove('skin-theme-clientpref-os');
        body.classList.add('skin-theme-clientpref-night');
      }
    } else {
      html.classList.remove('skin-theme-clientpref-night');
      html.classList.remove('skin-theme-clientpref-os');
      html.classList.add('skin-theme-clientpref-day');
      if (body) {
        body.classList.remove('skin-theme-clientpref-night');
        body.classList.remove('skin-theme-clientpref-os');
        body.classList.add('skin-theme-clientpref-day');
      }
    }
  }

  if (!isPrts) {
    try {
      var adapterScript = __ARKLORES_ADAPTER_SCRIPT__;
      (0, eval)(adapterScript);
    } catch (e) {}
  }
})();
''';

  static const _removeScript = r'''
(function() {
  var html = document.documentElement;
  if (html) {
    html.removeAttribute('data-arklores-appearance');
    html.removeAttribute('data-arklores-appearance-version');
    html.classList.remove('arklores-prts-site');
    html.classList.remove(
      'arklores-fz-site',
      'arklores-warfarin-site',
      'arklores-generic-site',
    );
  }
  var style = document.getElementById('arklores-wiki-appearance');
  if (style) style.remove();
  try {
    (0, eval)(__ARKLORES_REMOVE_ADAPTER_SCRIPT__);
  } catch (e) {}
})();
''';

  static Future<void> inject(
    InAppWebViewController controller, {
    required bool dark,
  }) async {
    final script = _applyScript
        .replaceFirst('__ARKLORES_CSS__', _jsStringLiteral(_css()))
        .replaceFirst(
          '__ARKLORES_MODE__',
          _jsStringLiteral(dark ? 'dark' : 'light'),
        );
    final withAdapter = script.replaceFirst(
      '__ARKLORES_ADAPTER_SCRIPT__',
      _jsStringLiteral(WikiSiteAdapter.applyThemeScript(dark: dark)),
    );
    try {
      await controller.evaluateJavascript(source: withAdapter);
    } catch (_) {
      // Appearance is best effort while a page is navigating.
    }
  }

  static Future<void> remove(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(
        source: _removeScript.replaceFirst(
          '__ARKLORES_REMOVE_ADAPTER_SCRIPT__',
          _jsStringLiteral(WikiSiteAdapter.removeThemeScript()),
        ),
      );
    } catch (_) {
      // The WebView may already have been disposed during navigation.
    }
  }

  static Future<void> setEnabled(
    InAppWebViewController controller,
    bool enabled, {
    bool dark = false,
  }) async {
    if (enabled) {
      await inject(controller, dark: dark);
    } else {
      await remove(controller);
    }
  }

  static String _jsStringLiteral(String value) {
    return jsonString(value);
  }
}

String jsonString(String value) {
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('`', '\\`')
      .replaceAll(r'$', r'\$')
      .replaceAll('\r', '\\r')
      .replaceAll('\n', '\\n');
  return '`$escaped`';
}

/// Compatibility facade for older feature code.
@Deprecated('Use WikiAppearance instead.')
class WikiDarkMode {
  WikiDarkMode._();

  static String cssForTesting() => WikiAppearance.cssForTesting();

  static Future<void> inject(
    InAppWebViewController controller, {
    required bool dark,
  }) =>
      WikiAppearance.inject(controller, dark: dark);

  static Future<void> remove(InAppWebViewController controller) =>
      WikiAppearance.remove(controller);

  static Future<void> setEnabled(
    InAppWebViewController controller,
    bool enabled, {
    bool dark = false,
  }) =>
      WikiAppearance.setEnabled(controller, enabled, dark: dark);
}
