import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Manages Wiki dark mode via CSS injection into [InAppWebView].
///
/// The strategy uses a style tag with id `arklores-dark-mode` containing
/// an invert filter on the root element, plus selective re-inversion of
/// images and media to avoid double-inversion artifacts.
///
/// Call [inject] after a page finishes loading (`onLoadStop`) and call
/// [remove] (or re-inject with empty state) to disable dark mode.
class WikiDarkMode {
  WikiDarkMode._();

  static const String _styleId = 'arklores-dark-mode';

  /// CSS rules for dark mode.
  ///
  /// - Base invert + hue rotation on `<html>` transforms light backgrounds
  ///   into dark ones while preserving hue relationships.
  /// - Images, videos, canvases and elements with background images are
  ///   re-inverted so they appear naturally.
  /// - A subtle background colour prevents intermediate white flashes.
  static const String _darkModeCSS = '''
html {
  filter: invert(1) hue-rotate(180deg) !important;
  background-color: #0b0d10 !important;
}
img, video, iframe, canvas, svg,
[style*="background-image"],
picture,
[role="img"] {
  filter: invert(1) hue-rotate(180deg) !important;
}
/* PRTS Wiki table & infobox adjustments */
.wikitable, .infobox, table.wikitable, .mw-parser-output table {
  border-color: #1e2d40 !important;
}
''';

  /// Injects (or updates) the dark mode style tag into the page.
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
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Silently ignore — may fail on unsupported pages or early load.
    }
  }

  /// Removes the dark mode style tag from the page, restoring original colours.
  static Future<void> remove(InAppWebViewController controller) async {
    final js = '''
(function() {
  var el = document.getElementById('$_styleId');
  if (el) el.remove();
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
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
