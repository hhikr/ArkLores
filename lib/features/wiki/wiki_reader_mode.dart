import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WikiReaderMode {
  WikiReaderMode._();

  static const _styleId = 'arklores-reader-mode';
  static const _bodyClass = 'arklores-reader-mode';
  static const _fontFamily = 'LXGW WenKai';
  static const fontScheme = 'arklores-reader-font';
  static const _regularFontUrl = '$fontScheme://lxgw-wenkai/regular.woff2';
  static const _mediumFontUrl = '$fontScheme://lxgw-wenkai/medium.woff2';
  static const _regularFontAsset =
      'assets/fonts/lxgw-wenkai/LXGWWenKai-Regular.woff2';
  static const _mediumFontAsset =
      'assets/fonts/lxgw-wenkai/LXGWWenKai-Medium.woff2';

  static const _fontFaces = '''
@font-face {
  font-family: "$_fontFamily";
  src: url("$_regularFontUrl") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}

@font-face {
  font-family: "$_fontFamily";
  src: url("$_mediumFontUrl") format("woff2");
  font-weight: 700;
  font-style: normal;
  font-display: swap;
}
''';

  static Future<CustomSchemeResponse?> loadFontResource(
    WebResourceRequest request,
  ) async {
    final url = request.url;
    if (url.scheme != fontScheme) return null;

    final assetPath = switch (url.path) {
      '/regular.woff2' => _regularFontAsset,
      '/medium.woff2' => _mediumFontAsset,
      _ => null,
    };
    if (assetPath == null) return null;

    try {
      final data = await rootBundle.load(assetPath);
      return CustomSchemeResponse(
        data: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        contentType: 'font/woff2',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> setEnabled(
    InAppWebViewController controller, {
    required bool enabled,
    required bool dark,
    required double fontScale,
  }) async {
    if (!enabled) {
      await remove(controller);
      return;
    }
    await inject(controller, dark: dark, fontScale: fontScale);
  }

  static Future<void> inject(
    InAppWebViewController controller, {
    required bool dark,
    required double fontScale,
  }) async {
    final background = dark ? '#0B0F14' : '#F6F3EA';
    final storySurface = dark ? '#111A24' : '#FFFDF7';
    final storyHeader = dark ? '#172230' : '#EFE8DA';
    final text = dark ? '#E8EDF2' : '#24211C';
    final muted = dark ? '#A7B1BA' : '#686157';
    final border = dark ? '#263241' : '#DED6C8';
    final link = dark ? '#7AC7DD' : '#236A80';
    final controlSurface = dark ? '#172230' : '#ECE5D8';
    final controlText = dark ? '#DCE8F0' : '#17202A';
    final tableHeader = dark ? '#151E29' : '#EFE8DA';
    final selection =
        dark ? 'rgba(122, 199, 221, 0.28)' : 'rgba(35, 106, 128, 0.18)';
    final baseFontSize = (18 * fontScale).clamp(15, 24).toStringAsFixed(1);
    final lineHeight =
        (1.72 - ((fontScale - 1) * 0.08)).clamp(1.56, 1.78).toStringAsFixed(2);

    final css = '''
$_fontFaces

:root {
  color-scheme: ${dark ? 'dark' : 'light'} !important;
  --color-base: $text !important;
  --color-emphasized: $text !important;
  --color-subtle: $muted !important;
  --color-placeholder: $muted !important;
  --color-link: $link !important;
  --color-link--visited: $link !important;
  --background-color-base: $background !important;
  --background-color-neutral: $background !important;
  --background-color-interactive: $controlSurface !important;
  --border-color-base: $border !important;
}

html {
  background: $background !important;
  filter: none !important;
}

html,
body.$_bodyClass {
  min-height: 100% !important;
  margin: 0 !important;
  background: $background !important;
  color: $text !important;
  overflow-x: hidden !important;
}

body.$_bodyClass,
body.$_bodyClass p,
body.$_bodyClass li,
body.$_bodyClass td,
body.$_bodyClass th,
body.$_bodyClass blockquote,
body.$_bodyClass dd,
body.$_bodyClass dt,
body.$_bodyClass div,
body.$_bodyClass span {
  font-family: "$_fontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  font-size: ${baseFontSize}px !important;
  line-height: $lineHeight !important;
  letter-spacing: 0 !important;
  font-variant-ligatures: common-ligatures !important;
}

body.$_bodyClass *,
body.$_bodyClass *::before,
body.$_bodyClass *::after {
  box-sizing: border-box !important;
  text-shadow: none !important;
  box-shadow: none !important;
  filter: none !important;
}

body.$_bodyClass ::selection {
  background: $selection !important;
}

body.$_bodyClass header,
body.$_bodyClass footer,
body.$_bodyClass nav,
body.$_bodyClass aside,
body.$_bodyClass .navbar,
body.$_bodyClass .sidebar,
body.$_bodyClass .side-bar,
body.$_bodyClass .toc,
body.$_bodyClass .table-of-contents,
body.$_bodyClass #toc,
body.$_bodyClass #footer,
body.$_bodyClass #mw-head,
body.$_bodyClass #mw-panel,
body.$_bodyClass #p-logo,
body.$_bodyClass #siteNotice,
body.$_bodyClass #catlinks,
body.$_bodyClass .mw-jump-link,
body.$_bodyClass .mw-editsection,
body.$_bodyClass .printfooter,
body.$_bodyClass .vector-header-container,
body.$_bodyClass .vector-page-toolbar,
body.$_bodyClass .vector-column-start,
body.$_bodyClass .vector-column-end,
body.$_bodyClass .mw-indicators,
body.$_bodyClass .page-actions,
body.$_bodyClass .page-header,
body.$_bodyClass .bread,
body.$_bodyClass .breadcrumb,
body.$_bodyClass .advertisement,
body.$_bodyClass .noprint,
body.$_bodyClass [role="banner"],
body.$_bodyClass [role="navigation"],
body.$_bodyClass [aria-label="Advertisement"] {
  display: none !important;
}

body.$_bodyClass main,
body.$_bodyClass article,
body.$_bodyClass #content,
body.$_bodyClass .mw-body,
body.$_bodyClass #mw-content-text,
body.$_bodyClass .mw-parser-output,
body.$_bodyClass .content,
body.$_bodyClass .page,
body.$_bodyClass .prose {
  display: block !important;
  visibility: visible !important;
  opacity: 1 !important;
  float: none !important;
  position: static !important;
  inset: auto !important;
  width: auto !important;
  max-width: 760px !important;
  min-height: 0 !important;
  margin: 0 auto !important;
  padding: 0 !important;
  transform: none !important;
  background: transparent !important;
  color: $text !important;
  border: 0 !important;
  box-shadow: none !important;
}

body.$_bodyClass #content,
body.$_bodyClass .mw-body,
body.$_bodyClass main,
body.$_bodyClass article {
  padding: 24px 18px 56px !important;
}

body.$_bodyClass .mw-parser-output,
body.$_bodyClass .prose {
  background: transparent !important;
  border: 0 !important;
  border-radius: 0 !important;
  padding: 0 !important;
  box-sizing: border-box !important;
}

body.$_bodyClass .mw-parser-output,
body.$_bodyClass .mw-parser-output :where(p, li, dd, dt, div, span, small, b, strong, em, label, caption),
body.$_bodyClass #mw-content-text,
body.$_bodyClass #mw-content-text :where(p, li, dd, dt, div, span, small, b, strong, em, label, caption) {
  color: $text !important;
}

body.$_bodyClass .mw-parser-output :where(div, section, article, center, ul, ol, dl),
body.$_bodyClass #mw-content-text :where(div, section, article, center, ul, ol, dl) {
  width: auto !important;
  max-width: none !important;
  min-width: 0 !important;
  min-height: 0 !important;
  float: none !important;
  margin-left: 0 !important;
  margin-right: 0 !important;
  padding-left: 0 !important;
  padding-right: 0 !important;
  background-color: transparent !important;
  background-image: none !important;
  border-color: transparent !important;
  border-radius: 0 !important;
}

body.$_bodyClass .mw-parser-output :where([style*="background"], [style*="background-color"], [style*="background-image"], [style*="background: url"], [style*="background:url"]):not(button):not(input):not(select):not(textarea):not(pre):not(code):not(.mw-collapsible-toggle),
body.$_bodyClass #mw-content-text :where([style*="background"], [style*="background-color"], [style*="background-image"], [style*="background: url"], [style*="background:url"]):not(button):not(input):not(select):not(textarea):not(pre):not(code):not(.mw-collapsible-toggle) {
  background: transparent !important;
  background-color: transparent !important;
  background-image: none !important;
}

body.$_bodyClass .mw-parser-output :where([style*="color"]),
body.$_bodyClass #mw-content-text :where([style*="color"]) {
  color: $text !important;
}

body.$_bodyClass .mw-parser-output :where([style*="width"], [style*="margin"]):not(img):not(video):not(canvas):not(svg):not(table):not(.thumb):not(.gallery),
body.$_bodyClass #mw-content-text :where([style*="width"], [style*="margin"]):not(img):not(video):not(canvas):not(svg):not(table):not(.thumb):not(.gallery) {
  width: auto !important;
  max-width: none !important;
  min-width: 0 !important;
  margin-left: 0 !important;
  margin-right: 0 !important;
}

body.$_bodyClass .arklores-reader-story-block {
  width: 100% !important;
  max-width: none !important;
  margin: 0.9em 0 !important;
  padding: 0.85em 0.95em !important;
  background: $storySurface !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$_bodyClass .arklores-reader-story-heading {
  width: 100% !important;
  max-width: none !important;
  margin: 0.6em 0 !important;
  padding: 0.55em 0.7em !important;
  background: $storyHeader !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$_bodyClass .arklores-reader-story-block *,
body.$_bodyClass .arklores-reader-story-heading * {
  color: inherit !important;
  background-color: transparent !important;
}

body.$_bodyClass h1,
body.$_bodyClass h2,
body.$_bodyClass h3,
body.$_bodyClass h4 {
  color: $text !important;
  line-height: 1.28 !important;
  margin: 1.4em 0 0.65em !important;
  padding: 0 !important;
  border-color: $border !important;
  font-weight: 700 !important;
}

body.$_bodyClass h1 {
  font-size: ${(26 * fontScale).clamp(22, 34).toStringAsFixed(1)}px !important;
}

body.$_bodyClass h2 {
  font-size: ${(22 * fontScale).clamp(19, 30).toStringAsFixed(1)}px !important;
}

body.$_bodyClass h3 {
  font-size: ${(19 * fontScale).clamp(17, 26).toStringAsFixed(1)}px !important;
}

body.$_bodyClass p {
  margin: 0.75em 0 !important;
}

body.$_bodyClass a,
body.$_bodyClass a * {
  color: $link !important;
  text-decoration-thickness: 1px !important;
  text-underline-offset: 0.18em !important;
}

body.$_bodyClass img,
body.$_bodyClass video,
body.$_bodyClass canvas,
body.$_bodyClass svg {
  max-width: 100% !important;
  height: auto !important;
}

body.$_bodyClass figure,
body.$_bodyClass .thumb,
body.$_bodyClass .gallery,
body.$_bodyClass .floatnone,
body.$_bodyClass .image {
  max-width: 100% !important;
  margin: 1em auto !important;
  text-align: center !important;
}

body.$_bodyClass .thumbinner,
body.$_bodyClass .gallerybox,
body.$_bodyClass .gallerytext {
  background: transparent !important;
  border: 0 !important;
  color: $muted !important;
}

body.$_bodyClass table,
body.$_bodyClass .wikitable {
  display: block !important;
  width: 100% !important;
  max-width: 100% !important;
  overflow-x: auto !important;
  border-collapse: collapse !important;
  background: transparent !important;
  color: $text !important;
  border-color: $border !important;
}

body.$_bodyClass th,
body.$_bodyClass .wikitable th {
  background: $tableHeader !important;
}

body.$_bodyClass td,
body.$_bodyClass th,
body.$_bodyClass .wikitable td,
body.$_bodyClass .wikitable th {
  border: 1px solid $border !important;
  padding: 0.5em 0.65em !important;
  color: $text !important;
}

body.$_bodyClass td[style],
body.$_bodyClass th[style] {
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass blockquote,
body.$_bodyClass pre,
body.$_bodyClass code {
  background: ${dark ? '#151E29' : '#EFE8DA'} !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$_bodyClass button,
body.$_bodyClass input,
body.$_bodyClass select,
body.$_bodyClass textarea,
body.$_bodyClass [role="button"],
body.$_bodyClass .mw-collapsible-toggle,
body.$_bodyClass .mw-collapsible-toggle a {
  color: $controlText !important;
  background: $controlSurface !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
  text-decoration: none !important;
}

body.$_bodyClass .mw-collapsible-toggle {
  display: inline-flex !important;
  align-items: center !important;
  min-height: 2em !important;
  padding: 0.12em 0.45em !important;
  vertical-align: baseline !important;
}

body.$_bodyClass .reference,
body.$_bodyClass .mw-references-wrap,
body.$_bodyClass .metadata,
body.$_bodyClass .ambox,
body.$_bodyClass .navbox,
body.$_bodyClass .vertical-navbox,
body.$_bodyClass .succession-box {
  color: $muted !important;
}
''';

    final js = '''
(function() {
  var body = document.body;
  if (!body || !document.head) return;
  body.classList.add('$_bodyClass');
  var style = document.getElementById('$_styleId');
  if (!style) {
    style = document.createElement('style');
    style.id = '$_styleId';
    document.head.appendChild(style);
  }
  style.textContent = ${_jsStringLiteral(css)};

  var keepVisualStyle = 'button,input,select,textarea,pre,code,img,video,canvas,svg,.thumb,.gallery,.mw-collapsible-toggle,.mw-collapsible-toggle *';
  var keepSizing = 'img,video,canvas,svg,table,.wikitable,.thumb,.gallery,.mw-collapsible-toggle,.mw-collapsible-toggle *';
  var roots = document.querySelectorAll('#mw-content-text, .mw-parser-output, main, article');
  var touched = [];
  for (var r = 0; r < roots.length; r++) {
    touched.push(roots[r]);
    var nodes = roots[r].querySelectorAll('*');
    for (var n = 0; n < nodes.length; n++) touched.push(nodes[n]);
  }
  for (var i = 0; i < touched.length; i++) {
    var el = touched[i];
    if (!el || !el.style) continue;
    if (!el.matches(keepVisualStyle)) {
      el.style.removeProperty('color');
      el.style.removeProperty('background');
      el.style.removeProperty('background-color');
      el.style.removeProperty('background-image');
      el.style.removeProperty('text-shadow');
      el.style.removeProperty('box-shadow');
      el.style.removeProperty('filter');
      el.style.removeProperty('border-left-color');
      el.style.removeProperty('border-right-color');
      el.style.removeProperty('border-top-color');
      el.style.removeProperty('border-bottom-color');
    }
    if (!el.matches(keepSizing)) {
      el.style.removeProperty('margin');
      el.style.removeProperty('padding');
      el.style.removeProperty('width');
      el.style.removeProperty('max-width');
      el.style.removeProperty('min-width');
      el.style.removeProperty('margin-left');
      el.style.removeProperty('margin-right');
      el.style.removeProperty('padding-left');
      el.style.removeProperty('padding-right');
      el.style.removeProperty('float');
    }
  }

  function cleanText(el) {
    return (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
  }

  function hasTextBlockChild(el) {
    var children = el.children || [];
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (!child || child.matches('script,style,button,input,select,textarea,pre,code,table,.wikitable,.thumb,.gallery,.mw-collapsible-toggle')) {
        continue;
      }
      if (!child.matches('div,section,article,center,blockquote,ul,ol,dl')) {
        continue;
      }
      if (cleanText(child).length >= 18) return true;
    }
    return false;
  }

  for (var j = 0; j < touched.length; j++) {
    var block = touched[j];
    if (!block || !block.classList || !block.matches('div,section,article,center,blockquote')) {
      continue;
    }
    if (block.matches('button,input,select,textarea,pre,code,table,.wikitable,.thumb,.gallery,.mw-collapsible-toggle,.mw-collapsible-toggle *')) {
      continue;
    }
    var text = cleanText(block);
    if (!text) continue;
    if (/^(PART\\s*\\d+|PART\\s*\\d*|.*(展开|折叠|解锁|需要触发).*)/i.test(text) && text.length <= 120) {
      block.classList.add('arklores-reader-story-heading');
      continue;
    }
    if (text.length >= 40 && !hasTextBlockChild(block)) {
      block.classList.add('arklores-reader-story-block');
    }
  }
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Reader mode is best-effort for third-party pages.
    }
  }

  static Future<void> remove(InAppWebViewController controller) async {
    const js = '''
(function() {
  if (document.body) document.body.classList.remove('$_bodyClass');
  var style = document.getElementById('$_styleId');
  if (style) style.remove();
})();
''';
    try {
      await controller.evaluateJavascript(source: js);
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  static String _jsStringLiteral(String value) {
    return '`${value.replaceAll('\\', '\\\\').replaceAll('`', '\\`').replaceAll(r'$', r'\$').trim()}`';
  }
}
