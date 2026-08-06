import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'wiki_appearance_palette.dart';

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

html[data-arklores-appearance],
html[data-arklores-appearance] body {
  background-color: var(--arklores-page-bg) !important;
  color: var(--arklores-text) !important;
}

html[data-arklores-appearance] :where(
  #mw-content-text,
  .mw-parser-output,
  main,
  article,
  .content,
  .page-content
) {
  color: var(--arklores-text);
}

html[data-arklores-appearance="dark"] :where(
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

html[data-arklores-appearance] :where(
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

html[data-arklores-appearance] :where(
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

  var style = document.getElementById('arklores-wiki-appearance');
  if (!style) {
    style = document.createElement('style');
    style.id = 'arklores-wiki-appearance';
    (document.head || html).appendChild(style);
  }
  style.textContent = __ARKLORES_CSS__;

  html.setAttribute('data-arklores-appearance', __ARKLORES_MODE__);
  html.setAttribute('data-arklores-appearance-version', '2');
})();
''';

  static const _removeScript = r'''
(function() {
  var html = document.documentElement;
  if (html) {
    html.removeAttribute('data-arklores-appearance');
    html.removeAttribute('data-arklores-appearance-version');
  }
  var style = document.getElementById('arklores-wiki-appearance');
  if (style) style.remove();
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
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {
      // Appearance is best effort while a page is navigating.
    }
  }

  static Future<void> remove(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: _removeScript);
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
