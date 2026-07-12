import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Manages Wiki dark mode via CSS injection into [InAppWebView].
///
/// The strategy uses a style tag with id `arklores-dark-mode` containing
/// an invert filter on the root element, plus selective re-inversion of
/// images and media to avoid double-inversion artifacts.
///
/// After CSS injection, a DOM walk re-inverts elements whose computed
/// `background-image` is set via CSS classes (not inline styles), since
/// those cannot be targeted by CSS attribute selectors alone.
class WikiDarkMode {
  WikiDarkMode._();

  static const String _styleId = 'arklores-dark-mode';

  /// CSS rules for dark mode.
  ///
  /// - Base invert + hue rotation on `<html>` transforms light backgrounds
  ///   into dark ones while preserving hue relationships.
  /// - Images, videos, canvases and elements with background images are
  ///   re-inverted so they appear naturally, covering both longhand
  ///   (`background-image`) and shorthand (`background: url(...)`) inline styles.
  /// - A subtle background colour prevents intermediate white flashes.
  static const String _darkModeCSS = '''
html {
  filter: invert(1) hue-rotate(180deg) !important;
  background-color: #0b0d10 !important;
}
img, video, iframe, canvas, svg,
[style*="background-image"],
[style*="background:url"],
[style*="background: url"],
picture,
[role="img"] {
  filter: invert(1) hue-rotate(180deg) !important;
}
/* PRTS Wiki table & infobox adjustments */
.wikitable, .infobox, table.wikitable, .mw-parser-output table {
  border-color: #1e2d40 !important;
}
''';

  /// JS that walks the DOM to re-invert elements whose computed
  /// `background-image` is set via CSS classes (not inline styles) so they
  /// render correctly under the html-level invert.
  static const String _reInvertBackgroundsJS = '''
(function() {
  var reInvert = "invert(1) hue-rotate(180deg)";
  var skip = {SCRIPT:1, STYLE:1, META:1, LINK:1, HEAD:1};
  var all = document.querySelectorAll("*");
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    if (skip[el.tagName]) continue;
    try {
      if (window.getComputedStyle(el).backgroundImage !== "none") {
        if (el.dataset.arkloresInverted !== "1") {
          el.style.filter = reInvert;
          el.dataset.arkloresInverted = "1";
        }
      }
    } catch(e) {}
  }
})();
''';

  /// JS that cleans up inline filters set by [_reInvertBackgroundsJS].
  static const String _cleanupInvertedJS = '''
(function() {
  var el = document.getElementById("$_styleId");
  if (el) el.remove();

  var items = document.querySelectorAll("[data-arklores-inverted]");
  for (var i = 0; i < items.length; i++) {
    items[i].style.filter = "";
    items[i].removeAttribute("data-arklores-inverted");
  }
})();
''';

  /// Injects (or updates) the dark mode style tag into the page, then
  /// re-inverts elements with class-based background images.
  static Future<void> inject(InAppWebViewController controller) async {
    final js = '''
(function() {
  var css = ${_jsStringLiteral(_darkModeCSS)};
  var el = document.getElementById('$_styleId');
  if (el) {
    el.textContent = css;
  } else {
    var style = document.createElement('style');
    style.id = '$_styleId';
    style.textContent = css;
    document.head.appendChild(style);
  }
})();
$_reInvertBackgroundsJS
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Silently ignore — may fail on unsupported pages or early load.
    }
  }

  /// Removes the dark mode style tag and cleans up inline filters.
  static Future<void> remove(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: _cleanupInvertedJS);
    } catch (_) {
      // Silently ignore.
    }
  }

  /// Convenience: calls [inject] or [remove] based on [enabled].
  static Future<void> setEnabled(
    InAppWebViewController controller,
    bool enabled,
  ) async {
    if (enabled) {
      await inject(controller);
    } else {
      await remove(controller);
    }
  }

  /// Builds a safe JavaScript string literal from a multi-line Dart string.
  ///
  /// Escapes backticks, dollar signs, backslashes, and newlines so the CSS
  /// can be embedded inside a template literal without breaking the JS AST.
  static String _jsStringLiteral(String value) {
    return '`${value
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll(r'$', r'\$')
        .trim()}`';
  }
}
