import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WikiReaderMode {
  WikiReaderMode._();

  static const _styleId = 'arklores-reader-mode';
  static const _bodyClass = 'arklores-reader-mode';
  static const _fontFamily = 'LXGW WenKai';
  static const _regularFontAsset =
      'assets/fonts/lxgw-wenkai/LXGWWenKai-Regular.woff2';

  static Future<String>? _fontFacesFuture;

  static Future<String> _fontFaces() {
    return _fontFacesFuture ??= _buildFontFaces();
  }

  static Future<String> _buildFontFaces() async {
    final data = await rootBundle.load(_regularFontAsset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final uri = 'data:font/woff2;base64,${base64Encode(bytes)}';
    return '''
@font-face {
  font-family: "$_fontFamily";
  src: url("$uri") format("woff2");
  font-weight: 400 700;
  font-style: normal;
  font-display: swap;
}
''';
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
    final fontFaces = await _fontFaces();
    final background = dark ? '#0B0F14' : '#F6F3EA';
    final storySurface = dark ? '#111A24' : '#FFFDF7';
    final storyHeader = dark ? '#172230' : '#EFE8DA';
    final componentSurface =
        dark ? 'rgba(23, 38, 56, 0.84)' : 'rgba(231, 239, 239, 0.86)';
    final componentHeader =
        dark ? 'rgba(34, 57, 80, 0.78)' : 'rgba(213, 227, 228, 0.9)';
    final text = dark ? '#E8EDF2' : '#24211C';
    final muted = dark ? '#A7B1BA' : '#686157';
    final border = dark ? '#263241' : '#DED6C8';
    final link = dark ? '#7AC7DD' : '#236A80';
    final controlSurface = dark ? '#172230' : '#ECE5D8';
    final controlText = dark ? '#DCE8F0' : '#17202A';
    final tableHeader = dark ? '#151E29' : '#EFE8DA';
    final selection =
        dark ? 'rgba(122, 199, 221, 0.28)' : 'rgba(35, 106, 128, 0.18)';
    final baseFontSize = (18 * fontScale).clamp(11, 25).toStringAsFixed(1);
    final lineHeight =
        (1.72 - ((fontScale - 1) * 0.08)).clamp(1.56, 1.78).toStringAsFixed(2);

    final css = '''
$fontFaces

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
  --background-color-neutral-subtle: $storyHeader !important;
  --background-color-interactive: $controlSurface !important;
  --border-color-base: $border !important;
}

html {
  width: 100% !important;
  max-width: 100% !important;
  background: $background !important;
  filter: none !important;
}

html,
body.$_bodyClass {
  width: 100% !important;
  max-width: 100% !important;
  min-height: 100% !important;
  margin: 0 !important;
  background: $background !important;
  color: $text !important;
  overflow-x: hidden !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile),
body.$_bodyClass:not(.arklores-reader-operator-profile) p,
body.$_bodyClass:not(.arklores-reader-operator-profile) li,
body.$_bodyClass:not(.arklores-reader-operator-profile) td,
body.$_bodyClass:not(.arklores-reader-operator-profile) th,
body.$_bodyClass:not(.arklores-reader-operator-profile) blockquote,
body.$_bodyClass:not(.arklores-reader-operator-profile) dd,
body.$_bodyClass:not(.arklores-reader-operator-profile) dt,
body.$_bodyClass:not(.arklores-reader-operator-profile) div,
body.$_bodyClass:not(.arklores-reader-operator-profile) span,
body.$_bodyClass.arklores-reader-operator-profile {
  font-family: "$_fontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  font-size: ${baseFontSize}px !important;
  line-height: $lineHeight !important;
  letter-spacing: 0 !important;
  font-variant-ligatures: common-ligatures !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) *,
body.$_bodyClass:not(.arklores-reader-operator-profile) *::before,
body.$_bodyClass:not(.arklores-reader-operator-profile) *::after {
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

body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-parser-output,
body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where(p, li, dd, dt, div, span, small, b, strong, em, label, caption),
body.$_bodyClass:not(.arklores-reader-operator-profile) #mw-content-text,
body.$_bodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where(p, li, dd, dt, div, span, small, b, strong, em, label, caption) {
  color: $text !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where(div, section, article, center, ul, ol, dl),
body.$_bodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where(div, section, article, center, ul, ol, dl) {
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

body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where([style*="background"], [style*="background-color"], [style*="background-image"], [style*="background: url"], [style*="background:url"]):not(button):not(input):not(select):not(textarea):not(pre):not(code):not(.mw-collapsible-toggle),
body.$_bodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where([style*="background"], [style*="background-color"], [style*="background-image"], [style*="background: url"], [style*="background:url"]):not(button):not(input):not(select):not(textarea):not(pre):not(code):not(.mw-collapsible-toggle) {
  background: transparent !important;
  background-color: transparent !important;
  background-image: none !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where([style*="color"]),
body.$_bodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where([style*="color"]) {
  color: $text !important;
}

/* Keep the character canvas and voice application native, but restore
   reader typography for the surrounding operator article. */
body.$_bodyClass.arklores-reader-operator-profile #mw-content-text :where(
  p, li, dd, dt, td, th, caption, blockquote, small, b, strong, em, label,
  .mw-collapsible-content, .mw-collapsible-content *
):not(.charinfo-container *):not(#voice-table-root *) {
  font-family: "$_fontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  font-size: ${baseFontSize}px !important;
  line-height: $lineHeight !important;
  letter-spacing: 0 !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text :where(h1, h2, h3, h4, h5, h6, .mw-headline):not(.charinfo-container *):not(#voice-table-root *) {
  font-family: "$_fontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  color: $text !important;
  letter-spacing: 0 !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text h2:not(.charinfo-container *):not(#voice-table-root *) {
  font-size: ${(22 * fontScale).clamp(15, 31).toStringAsFixed(1)}px !important;
  line-height: 1.28 !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text h3:not(.charinfo-container *):not(#voice-table-root *) {
  font-size: ${(19 * fontScale).clamp(13, 27).toStringAsFixed(1)}px !important;
  line-height: 1.32 !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text #basictemplate,
body.$_bodyClass.arklores-reader-operator-profile #mw-content-text .equiptemplate {
  width: 100% !important;
  max-width: 100% !important;
  margin: 1.15em 0 !important;
  overflow: visible !important;
  background: $componentSurface !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 6px !important;
  box-shadow: 0 8px 24px ${dark ? 'rgba(0, 0, 0, 0.16)' : 'rgba(58, 76, 78, 0.10)'} !important;
  backdrop-filter: blur(14px) saturate(116%) !important;
  -webkit-backdrop-filter: blur(14px) saturate(116%) !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text #basictemplate > div,
body.$_bodyClass.arklores-reader-operator-profile #mw-content-text .equiptemplate > div {
  background-color: transparent !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text :where(
  .equip-base-title, .equip-name-box, .equip-level-desc, .equip-task-content,
  .equip-material-content, .equip-level-stats
) {
  color: $text !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text .equip-full-btn {
  background: $controlSurface !important;
  color: $controlText !important;
  border: 1px solid $border !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text .equip-nofull-btn {
  background: ${dark ? '#7A2E2E' : '#C93A3A'} !important;
  color: #ffffff !important;
  border: 1px solid ${dark ? '#A65A5A' : '#A51F1F'} !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text .mw-collapsible-toggle,
body.$_bodyClass.arklores-reader-operator-profile #mw-content-text .mw-collapsible-toggle a {
  background: $controlSurface !important;
  color: $controlText !important;
  border-color: $border !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root {
  margin: 1.15em 0 !important;
  padding: 0.7em !important;
  background: $componentSurface !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 6px !important;
  box-shadow: 0 8px 24px ${dark ? 'rgba(0, 0, 0, 0.16)' : 'rgba(58, 76, 78, 0.10)'} !important;
  backdrop-filter: blur(14px) saturate(116%) !important;
  -webkit-backdrop-filter: blur(14px) saturate(116%) !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root :where(
  .bg-wikitable, .table, table, tbody, tr, td
) {
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root :where(
  [class~="!bg-table"], .filter-title, thead, th, input, .n-base-selection,
  .n-base-selection-label, .n-base-selection-tags, .n-base-selection-input,
  .n-base-selection-input__content
) {
  background: $componentHeader !important;
  color: $text !important;
  border-color: $border !important;
}

body.$_bodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root :where(
  .border, .border-divider, td, th
) {
  border-color: $border !important;
}

body.$_bodyClass.arklores-reader-operator-profile
  #mw-content-text
  .arklores-prts-paradox-table {
  display: table !important;
  width: 100% !important;
  max-width: 100% !important;
  min-width: 0 !important;
  table-layout: fixed !important;
  overflow: visible !important;
}

body.$_bodyClass.arklores-reader-operator-profile
  #mw-content-text
  .arklores-prts-paradox-table
  :where(tbody, tr, td, th) {
  max-width: 100% !important;
  min-width: 0 !important;
  overflow-wrap: anywhere !important;
  word-break: break-word !important;
}

body.$_bodyClass.arklores-reader-operator-profile
  #mw-content-text
  .arklores-prts-paradox-table
  img {
  max-width: 100% !important;
  height: auto !important;
}

body.$_bodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .nomobile {
  display: none !important;
}

body.$_bodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .nodesktop {
  display: table !important;
}

body.$_bodyClass.arklores-reader-operator-profile.arklores-prts-paradox-desktop
  #mw-content-text
  .nodesktop {
  display: none !important;
}

body.$_bodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .arklores-prts-paradox-table
  .nodesktop {
  width: min(100%, 15rem) !important;
  max-width: 100% !important;
  margin: 0.55em auto !important;
  table-layout: auto !important;
}

body.$_bodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .arklores-prts-paradox-table
  .nodesktop
  > tbody
  > tr
  > td
  > a
  > div {
  width: 100% !important;
  max-width: 100% !important;
  margin-left: 0 !important;
}

body.$_bodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .arklores-prts-paradox-table
  .nodesktop
  > tbody
  > tr
  > td
  > span {
  width: auto !important;
  max-width: 100% !important;
  margin: 0.7em auto 0 !important;
  padding: 0.4em 0.5em !important;
  height: auto !important;
  flex-wrap: wrap !important;
  justify-content: center !important;
  gap: 0.35em !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where([style*="width"], [style*="margin"]):not(img):not(video):not(canvas):not(svg):not(table):not(.thumb):not(.gallery),
body.$_bodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where([style*="width"], [style*="margin"]):not(img):not(video):not(canvas):not(svg):not(table):not(.thumb):not(.gallery) {
  width: auto !important;
  max-width: none !important;
  min-width: 0 !important;
  margin-left: 0 !important;
  margin-right: 0 !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .arklores-reader-story-block {
  width: 100% !important;
  max-width: none !important;
  margin: 0.9em 0 !important;
  padding: 0.85em 0.95em !important;
  background: $storySurface !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .arklores-reader-story-heading {
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

body.$_bodyClass:not(.arklores-reader-operator-profile) h1,
body.$_bodyClass:not(.arklores-reader-operator-profile) h2,
body.$_bodyClass:not(.arklores-reader-operator-profile) h3,
body.$_bodyClass:not(.arklores-reader-operator-profile) h4 {
  color: $text !important;
  line-height: 1.28 !important;
  margin: 1.4em 0 0.65em !important;
  padding: 0 !important;
  border-color: $border !important;
  font-weight: 700 !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) h1 {
  font-size: ${(26 * fontScale).clamp(17, 35).toStringAsFixed(1)}px !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) h2 {
  font-size: ${(22 * fontScale).clamp(15, 31).toStringAsFixed(1)}px !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) h3 {
  font-size: ${(19 * fontScale).clamp(13, 27).toStringAsFixed(1)}px !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) p {
  margin: 0.75em 0 !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) a,
body.$_bodyClass:not(.arklores-reader-operator-profile) a * {
  color: $link !important;
  text-decoration-thickness: 1px !important;
  text-underline-offset: 0.18em !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) img,
body.$_bodyClass:not(.arklores-reader-operator-profile) video,
body.$_bodyClass:not(.arklores-reader-operator-profile) canvas,
body.$_bodyClass:not(.arklores-reader-operator-profile) svg {
  max-width: 100% !important;
  height: auto !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) figure,
body.$_bodyClass:not(.arklores-reader-operator-profile) .thumb,
body.$_bodyClass:not(.arklores-reader-operator-profile) .gallery,
body.$_bodyClass:not(.arklores-reader-operator-profile) .floatnone,
body.$_bodyClass:not(.arklores-reader-operator-profile) .image {
  max-width: 100% !important;
  margin: 1em auto !important;
  text-align: center !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .thumbinner,
body.$_bodyClass:not(.arklores-reader-operator-profile) .gallerybox,
body.$_bodyClass:not(.arklores-reader-operator-profile) .gallerytext {
  background: transparent !important;
  border: 0 !important;
  color: $muted !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) table,
body.$_bodyClass:not(.arklores-reader-operator-profile) .wikitable {
  display: block !important;
  width: 100% !important;
  max-width: 100% !important;
  overflow-x: auto !important;
  border-collapse: collapse !important;
  background: transparent !important;
  color: $text !important;
  border-color: $border !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) table tr,
body.$_bodyClass:not(.arklores-reader-operator-profile) .wikitable tr,
body.$_bodyClass:not(.arklores-reader-operator-profile) table tbody,
body.$_bodyClass:not(.arklores-reader-operator-profile) .wikitable tbody {
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) th,
body.$_bodyClass:not(.arklores-reader-operator-profile) .wikitable th {
  background: $tableHeader !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) td,
body.$_bodyClass:not(.arklores-reader-operator-profile) th,
body.$_bodyClass:not(.arklores-reader-operator-profile) .wikitable td,
body.$_bodyClass:not(.arklores-reader-operator-profile) .wikitable th {
  border: 1px solid $border !important;
  padding: 0.5em 0.65em !important;
  color: $text !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) td[style],
body.$_bodyClass:not(.arklores-reader-operator-profile) th[style],
body.$_bodyClass:not(.arklores-reader-operator-profile) td[bgcolor],
body.$_bodyClass:not(.arklores-reader-operator-profile) th[bgcolor] {
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .arklores-reader-table-accent {
  background: $storyHeader !important;
  color: $text !important;
  border-color: $border !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .arklores-reader-table-accent * {
  background-color: transparent !important;
  background-image: none !important;
  color: inherit !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) blockquote,
body.$_bodyClass:not(.arklores-reader-operator-profile) pre,
body.$_bodyClass:not(.arklores-reader-operator-profile) code {
  background: ${dark ? '#151E29' : '#EFE8DA'} !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) button,
body.$_bodyClass:not(.arklores-reader-operator-profile) input,
body.$_bodyClass:not(.arklores-reader-operator-profile) select,
body.$_bodyClass:not(.arklores-reader-operator-profile) textarea,
body.$_bodyClass:not(.arklores-reader-operator-profile) [role="button"],
body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-collapsible-toggle,
body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-collapsible-toggle a {
  color: $controlText !important;
  background: $controlSurface !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
  text-decoration: none !important;
}

body.$_bodyClass:not(.arklores-reader-operator-profile) .mw-collapsible-toggle {
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

body.$_bodyClass #sys_fullscreen.arklores-prts-scenario-shell-hidden {
  display: none !important;
}

body.$_bodyClass #arklores-prts-scenario-reader {
  width: 100% !important;
  max-width: 760px !important;
  margin: 1.2em auto 1.6em !important;
  padding: 0 !important;
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass #arklores-prts-log-all-button {
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  min-height: 44px !important;
  padding: 0 1.05em !important;
  color: $controlText !important;
  background: $controlSurface !important;
  border: 1px solid $border !important;
  border-radius: 4px !important;
  font-weight: 700 !important;
  letter-spacing: 0 !important;
}

body.$_bodyClass #sys_playback_all.arklores-prts-log-panel {
  position: static !important;
  display: none !important;
  width: 100% !important;
  max-width: none !important;
  height: auto !important;
  min-height: 0 !important;
  margin: 1em 0 0 !important;
  padding: 0 !important;
  background: transparent !important;
  color: $text !important;
  overflow: visible !important;
  cursor: default !important;
  user-select: text !important;
}

body.$_bodyClass #sys_playback_all.arklores-prts-log-visible {
  display: block !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list,
body.$_bodyClass #playback_all_result.arklores-prts-log-list .log_style {
  position: static !important;
  display: block !important;
  left: auto !important;
  width: 100% !important;
  max-width: none !important;
  margin: 0 !important;
  padding: 0 !important;
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list li {
  display: grid !important;
  grid-template-columns: minmax(4.5em, 22%) minmax(0, 1fr) !important;
  column-gap: 0.8em !important;
  list-style: none !important;
  margin: 0 !important;
  padding: 0.65em 0 !important;
  border-bottom: 1px solid $border !important;
  background: transparent !important;
  color: $text !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list li.arklores-prts-log-narration {
  grid-template-columns: minmax(0, 1fr) !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list li.arklores-prts-log-narration > em {
  display: none !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list li.arklores-prts-log-narration > span {
  color: $text !important;
  padding-left: 0 !important;
  left: auto !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list li > em,
body.$_bodyClass #playback_all_result.arklores-prts-log-list li > span {
  position: static !important;
  display: block !important;
  left: auto !important;
  width: auto !important;
  max-width: none !important;
  padding: 0 !important;
  color: $text !important;
  background: transparent !important;
  text-align: left !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list li > em {
  color: $muted !important;
  font-style: normal !important;
  font-weight: 700 !important;
}

body.$_bodyClass #playback_all_result.arklores-prts-log-list div.decision,
body.$_bodyClass #playback_all_result.arklores-prts-log-list div.predicate {
  display: block !important;
  margin: 0.6em 0 !important;
  padding: 0.65em 0.8em !important;
  border: 1px solid $border !important;
  background: $storySurface !important;
  color: $text !important;
}

''';

    final js = '''
(function() {
  var body = document.body;
  if (!body || !document.head) return;
  var viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.name = 'viewport';
    viewport.dataset.arkloresReaderViewportCreated = '1';
    document.head.appendChild(viewport);
  } else if (viewport.dataset.arkloresReaderViewportOriginal === undefined) {
    viewport.dataset.arkloresReaderViewportOriginal =
        viewport.getAttribute('content') || '';
  }
  viewport.setAttribute(
    'content',
    'width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover',
  );
  body.classList.add('$_bodyClass');
  var style = document.getElementById('$_styleId');
  if (!style) {
    style = document.createElement('style');
    style.id = '$_styleId';
    document.head.appendChild(style);
  }
  style.textContent = ${_jsStringLiteral(css)};

  function setupPrtsScenarioReader() {
    var nativeButton = document.getElementById('button_playback_all');
    var panel = document.getElementById('sys_playback_all');
    var log = document.getElementById('playback_all_result');
    var data = document.getElementById('datas_txt');
    if (!nativeButton || !panel || !log || !data) return;

    var shell = document.getElementById('sys_fullscreen');
    var host = document.getElementById('arklores-prts-scenario-reader');
    if (!host) {
      host = document.createElement('div');
      host.id = 'arklores-prts-scenario-reader';
      var open = document.createElement('button');
      open.type = 'button';
      open.id = 'arklores-prts-log-all-button';
      open.textContent = 'LOG ALL';
      host.appendChild(open);
      if (shell && shell.parentElement) {
        shell.parentElement.insertBefore(host, shell);
      } else {
        body.insertBefore(host, body.firstChild);
      }
    }

    if (panel.parentElement !== host) {
      host.appendChild(panel);
    }
    if (shell) shell.classList.add('arklores-prts-scenario-shell-hidden');
    panel.classList.add('arklores-prts-log-panel');
    log.classList.add('arklores-prts-log-list');

    var button = document.getElementById('arklores-prts-log-all-button');
    if (!button || button.dataset.arkloresBound === '1') return;
    button.addEventListener('click', function(event) {
      event.preventDefault();
      event.stopPropagation();
      try {
        if (panel.classList.contains('hidden')) {
          if (typeof window.txt_playback === 'function') {
            window.txt_playback('sys_playback_all', 'button_playback_all', true);
          } else if (nativeButton.click) {
            nativeButton.click();
          }
        }
      } catch (e) {
        if (nativeButton.click) nativeButton.click();
      }
      panel.classList.remove('hidden');
      panel.classList.add('arklores-prts-log-visible');
      host.classList.add('arklores-prts-log-open');
      button.textContent = '全部剧情日志';
    }, true);
    button.dataset.arkloresBound = '1';
  }

  setupPrtsScenarioReader();

  function refreshPrtsLogNarrationStyles() {
    var logList = document.getElementById('playback_all_result');
    if (!logList) return;
    var items = logList.querySelectorAll('li');
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      var speaker = item.firstElementChild && item.firstElementChild.tagName === 'EM'
          ? (item.firstElementChild.textContent || '').trim()
          : '';
      var isNarration =
          !speaker ||
          speaker === '旁白' ||
          speaker === '剧情旁白' ||
          speaker === '叙述' ||
          speaker === 'Narration' ||
          speaker === 'narration';
      item.classList.toggle('arklores-prts-log-narration', isNarration);
    }
    if (logList.dataset.arkloresNarrationObserver !== '1') {
      var observer = new MutationObserver(function() {
        refreshPrtsLogNarrationStyles();
      });
      observer.observe(logList, { childList: true, subtree: true });
      logList.dataset.arkloresNarrationObserver = '1';
    }
  }

  refreshPrtsLogNarrationStyles();

  function isOperatorProfilePage() {
    var text = (document.body && document.body.innerText) ? document.body.innerText : '';
    return text.indexOf('干员信息') !== -1 &&
        text.indexOf('模组') !== -1 &&
        (text.indexOf('特性') !== -1 || text.indexOf('基础信息') !== -1);
  }

  if (isOperatorProfilePage()) {
    body.classList.add('arklores-reader-operator-profile');
  }

  function setupPrtsOperatorReader() {
    if (!body.classList.contains('arklores-reader-operator-profile')) return;
    var html = document.documentElement;
    if (!html) return;
    html.dataset.arkloresReaderDark = ${dark ? "'1'" : "'0'"};

    function setupPrtsParadoxLayout() {
      var marker = document.querySelector(
        '#mw-content-text h2 span#悖论模拟, .mw-parser-output h2 span#悖论模拟',
      );
      if (!marker || !marker.closest) return;
      var heading = marker.closest('h2');
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
      var mobile = window.innerWidth <= 600;
      body.classList.toggle('arklores-prts-paradox-mobile', mobile);
      body.classList.toggle('arklores-prts-paradox-desktop', !mobile);
    }

    function syncPrtsTheme() {
      var useDark = html.dataset.arkloresReaderDark === '1';
      if (useDark) {
        if (!html.classList.contains('skin-theme-clientpref-night')) {
          html.classList.add('skin-theme-clientpref-night');
          html.dataset.arkloresPrtsNight = '1';
        }
      } else if (html.dataset.arkloresPrtsNight === '1') {
        html.classList.remove('skin-theme-clientpref-night');
        delete html.dataset.arkloresPrtsNight;
      }

      var voiceRoot = document.getElementById('voice-table-root');
      if (voiceRoot && useDark) {
        if (!voiceRoot.classList.contains('prts-widget-dark')) {
          voiceRoot.classList.add('prts-widget-dark');
          voiceRoot.dataset.arkloresPrtsWidgetDark = '1';
        }
      } else if (
        voiceRoot &&
        voiceRoot.dataset.arkloresPrtsWidgetDark === '1'
      ) {
        voiceRoot.classList.remove('prts-widget-dark');
        delete voiceRoot.dataset.arkloresPrtsWidgetDark;
      }
      setupPrtsParadoxLayout();
    }

    syncPrtsTheme();
    if (!window.__arkloresPrtsOperatorObserver) {
      var observer = new MutationObserver(syncPrtsTheme);
      observer.observe(body, { childList: true, subtree: true });
      window.__arkloresPrtsOperatorObserver = observer;
    }
    if (!html.dataset.arkloresPrtsParadoxResize) {
      window.addEventListener('resize', setupPrtsParadoxLayout, { passive: true });
      html.dataset.arkloresPrtsParadoxResize = '1';
    }
    window.setTimeout(syncPrtsTheme, 350);
    window.setTimeout(syncPrtsTheme, 1200);
  }

  setupPrtsOperatorReader();

  // A document-level click cannot reliably distinguish empty space from a
  // custom wiki control: many PRTS widgets handle clicks on an ancestor or
  // on a plain div. Use a deliberate double tap instead.
  if (window.__arkloresReaderClickHandler) {
    document.removeEventListener(
      'click',
      window.__arkloresReaderClickHandler,
      true,
    );
    delete window.__arkloresReaderClickHandler;
  }
  if (window.__arkloresReaderGestureHandlers) {
    document.removeEventListener(
      'touchstart',
      window.__arkloresReaderGestureHandlers.start,
      true,
    );
    document.removeEventListener(
      'touchmove',
      window.__arkloresReaderGestureHandlers.move,
      true,
    );
    document.removeEventListener(
      'touchend',
      window.__arkloresReaderGestureHandlers.end,
      true,
    );
  }
  if (window.__arkloresReaderDoubleTapHandler) {
    document.removeEventListener(
      'touchend',
      window.__arkloresReaderDoubleTapHandler,
      true,
    );
    delete window.__arkloresReaderDoubleTapHandler;
  }

  var doubleTap = {
    lastAt: 0,
    lastX: 0,
    lastY: 0,
  };

  function onReaderGesture() {
    try {
      window.flutter_inappwebview.callHandler('arkloresReaderTap');
    } catch (e) {}
  }

  function onDoubleTap(event) {
    if (!event.changedTouches || event.changedTouches.length !== 1) return;
    var touch = event.changedTouches[0];
    var now = Date.now();
    var dx = touch.clientX - doubleTap.lastX;
    var dy = touch.clientY - doubleTap.lastY;
    var closeEnough = Math.sqrt(dx * dx + dy * dy) <= 36;
    var isDoubleTap = now - doubleTap.lastAt <= 360 && closeEnough;
    if (isDoubleTap) {
      doubleTap.lastAt = 0;
      onReaderGesture();
      return;
    }
    doubleTap.lastAt = now;
    doubleTap.lastX = touch.clientX;
    doubleTap.lastY = touch.clientY;
  }

  document.addEventListener('touchend', onDoubleTap, true);
  window.__arkloresReaderDoubleTapHandler = onDoubleTap;
  body.dataset.arkloresReaderGestureHandler = '1';

  // PRTS operator pages mount interactive applications, not article prose.
  // Their own styles and scripts control fixed canvases, controls and tables.
  if (body.classList.contains('arklores-reader-operator-profile')) return;

  var keepVisualStyle = 'button,input,select,textarea,pre,code,img,video,canvas,svg,.thumb,.gallery,.mw-collapsible-toggle,.mw-collapsible-toggle *,#arklores-prts-scenario-reader,#arklores-prts-scenario-reader *,#sys_playback_all,#sys_playback_all *';
  var keepSizing = 'img,video,canvas,svg,table,.wikitable,.thumb,.gallery,.mw-collapsible-toggle,.mw-collapsible-toggle *,#arklores-prts-scenario-reader,#arklores-prts-scenario-reader *,#sys_playback_all,#sys_playback_all *';
  var roots = document.querySelectorAll('#mw-content-text, .mw-parser-output, main, article');
  var touched = [];
  for (var r = 0; r < roots.length; r++) {
    touched.push(roots[r]);
    var nodes = roots[r].querySelectorAll('*');
    for (var n = 0; n < nodes.length; n++) touched.push(nodes[n]);
  }

  function colorParts(value) {
    var match = String(value || '').match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/i);
    if (!match) return null;
    var alpha = match[4] == null ? 1 : parseFloat(match[4]);
    if (!alpha) return null;
    return {
      r: parseInt(match[1], 10),
      g: parseInt(match[2], 10),
      b: parseInt(match[3], 10),
      a: alpha
    };
  }

  function luminance(parts) {
    return (0.2126 * parts.r + 0.7152 * parts.g + 0.0722 * parts.b) / 255;
  }

  function hasDecorativeBackground(el) {
    if (!el) return false;
    var inline = (el.getAttribute('style') || '').toLowerCase();
    var hasBgAttr = el.hasAttribute('bgcolor') || inline.indexOf('background') !== -1;
    var color = colorParts(window.getComputedStyle(el).backgroundColor);
    if (!color || color.a < 0.2) return false;
    var lum = luminance(color);
    return hasBgAttr || lum < 0.22 || lum > 0.90;
  }

  var cells = document.querySelectorAll('#mw-content-text td, #mw-content-text th, .mw-parser-output td, .mw-parser-output th');
  for (var c = 0; c < cells.length; c++) {
    var cell = cells[c];
    if (!cell || cell.matches('.mw-collapsible-toggle, .mw-collapsible-toggle *')) continue;
    var textInCell = cleanText(cell);
    if (!textInCell) continue;
    if (hasDecorativeBackground(cell)) {
      cell.classList.add('arklores-reader-table-accent');
      continue;
    }
    var decoratedChild = cell.querySelector('div[style*="background"], span[style*="background"], div[bgcolor], span[bgcolor]');
    if (decoratedChild && cleanText(decoratedChild)) {
      cell.classList.add('arklores-reader-table-accent');
    }
  }

  for (var i = 0; i < touched.length; i++) {
    var el = touched[i];
    if (!el || !el.style) continue;
    el.removeAttribute('bgcolor');
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
    if (!body.classList.contains('arklores-reader-operator-profile') &&
        !el.matches(keepSizing)) {
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
    if (body.classList.contains('arklores-reader-operator-profile')) {
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
  var host = document.getElementById('arklores-prts-scenario-reader');
  var panel = document.getElementById('sys_playback_all');
  var offset = document.getElementById('sys_offset');
  var shell = document.getElementById('sys_fullscreen');
  if (panel) {
    panel.classList.remove('arklores-prts-log-panel', 'arklores-prts-log-visible');
    if (host && offset) offset.appendChild(panel);
  }
  var log = document.getElementById('playback_all_result');
  if (log) log.classList.remove('arklores-prts-log-list');
  if (shell) shell.classList.remove('arklores-prts-scenario-shell-hidden');
  if (host) host.remove();
  var html = document.documentElement;
  if (html) {
    if (html.dataset.arkloresPrtsNight === '1') {
      html.classList.remove('skin-theme-clientpref-night');
      delete html.dataset.arkloresPrtsNight;
    }
    delete html.dataset.arkloresReaderDark;
  }
  var voiceRoot = document.getElementById('voice-table-root');
  if (voiceRoot && voiceRoot.dataset.arkloresPrtsWidgetDark === '1') {
    voiceRoot.classList.remove('prts-widget-dark');
    delete voiceRoot.dataset.arkloresPrtsWidgetDark;
  }
  if (window.__arkloresPrtsOperatorObserver) {
    window.__arkloresPrtsOperatorObserver.disconnect();
    delete window.__arkloresPrtsOperatorObserver;
  }
  if (window.__arkloresReaderClickHandler) {
    document.removeEventListener(
      'click',
      window.__arkloresReaderClickHandler,
      true,
    );
    delete window.__arkloresReaderClickHandler;
  }
  if (window.__arkloresReaderGestureHandlers) {
    document.removeEventListener(
      'touchstart',
      window.__arkloresReaderGestureHandlers.start,
      true,
    );
    document.removeEventListener(
      'touchmove',
      window.__arkloresReaderGestureHandlers.move,
      true,
    );
    document.removeEventListener(
      'touchend',
      window.__arkloresReaderGestureHandlers.end,
      true,
    );
    delete window.__arkloresReaderGestureHandlers;
  }
  if (window.__arkloresReaderDoubleTapHandler) {
    document.removeEventListener(
      'touchend',
      window.__arkloresReaderDoubleTapHandler,
      true,
    );
    delete window.__arkloresReaderDoubleTapHandler;
  }
  if (document.body) {
    document.body.classList.remove(
      '$_bodyClass',
      'arklores-reader-operator-profile',
      'arklores-prts-paradox-mobile',
      'arklores-prts-paradox-desktop',
    );
  }
  var viewport = document.querySelector('meta[name="viewport"]');
  if (viewport) {
    if (viewport.dataset.arkloresReaderViewportCreated === '1') {
      viewport.remove();
    } else if (
      viewport.dataset.arkloresReaderViewportOriginal !== undefined
    ) {
      viewport.setAttribute(
        'content',
        viewport.dataset.arkloresReaderViewportOriginal,
      );
      delete viewport.dataset.arkloresReaderViewportOriginal;
    }
  }
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
