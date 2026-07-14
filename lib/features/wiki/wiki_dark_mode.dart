import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Manages Wiki dark mode via CSS injection into [InAppWebView].
///
/// Strategy selection:
/// - For sites with a native dark mode (`<html class="dark">`, e.g. Warfarin
///   Wiki / Tailwind CSS), "dark mode ON" toggles the `dark` class off so the
///   site's own light-mode styles take effect — no filter inversion needed.
/// - For light-native sites (e.g. PRTS Wiki), "dark mode ON" injects a CSS
///   `filter: invert(1)` on `<html>` and re-inverts images/media so they
///   appear at their original colours.
class WikiDarkMode {
  WikiDarkMode._();

  static const String _styleId = 'arklores-dark-mode';

  /// CSS rules for the dark-mode inversion strategy (light-native sites).
  ///
  /// Unused when the site has `<html class="dark">` (native dark mode site).
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

  /// JS injected for light-native sites to re-invert elements whose computed
  /// `background-image` is set via CSS classes (beyond what CSS selectors reach).
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

  /// JS that cleans up when turning dark mode OFF.
  static const String _cleanupJS = '''
(function() {
  var html = document.documentElement;

  if (html.dataset.arkloresNativeDark === "removed") {
    // ── Dark-native site cleanup ──
    // Restore the dark class we removed during inject().
    html.classList.add("dark");
    delete html.dataset.arkloresNativeDark;
  } else {
    // ── Light-native site cleanup ──
    // Remove the CSS inversion style tag and inline filters.
    var style = document.getElementById("$_styleId");
    if (style) style.remove();
    var items = document.querySelectorAll("[data-arklores-inverted]");
    for (var i = 0; i < items.length; i++) {
      items[i].style.filter = "";
      items[i].removeAttribute("data-arklores-inverted");
    }
  }
})();
''';

  /// Injects dark mode (or "day mode" for dark-native sites).
  ///
  /// For sites with `<html class="dark">`: removes the `dark` class so the
  /// site's own light-mode styles render natively, no CSS inversion needed.
  ///
  /// For light-native sites: injects the inversion CSS and re-inverts media.
  static Future<void> inject(InAppWebViewController controller) async {
    final js = '''
(function() {
  var html = document.documentElement;

  if (html.classList.contains("dark")) {
    // ── Dark-native site (e.g. Warfarin Wiki) ──
    // Remove the class so the site's own light-mode styles take over.
    html.classList.remove("dark");
    html.dataset.arkloresNativeDark = "removed";
  } else {
    // ── Light-native site (e.g. PRTS Wiki) ──
    // Inject CSS inversion dark mode and re-invert media.
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
    $_reInvertBackgroundsJS
  }
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Silently ignore — may fail on unsupported pages or early load.
    }
  }

  /// Removes dark mode, restoring the site's original appearance.
  static Future<void> remove(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: _cleanupJS);
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
  static String _jsStringLiteral(String value) {
    return '`${value.replaceAll('\\', '\\\\').replaceAll('`', '\\`').replaceAll(r'$', r'\$').trim()}`';
  }
}
