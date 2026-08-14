import 'wiki_appearance_palette.dart';

/// Reader-mode constants shared between the CSS builder and the injected
/// scripts.
const String readerStyleId = 'arklores-reader-mode';
const String readerBodyClass = 'arklores-reader-mode';
const String readerFontFamily = 'LXGW WenKai';

/// Builds the full reader-mode stylesheet for a given palette and scale.
///
/// The result is injected into the page as a single `<style>` element with
/// id [readerStyleId]. Every selector is scoped under `body.$readerBodyClass`
/// so leaving reader mode restores the site's original look.
String buildReaderCss({
  required String fontFaces,
  required WikiAppearancePalette palette,
  required bool dark,
  required double fontScale,
  required String baseFontSize,
  required String lineHeight,
}) {
  final background = palette.pageBackground;
  final storySurface = palette.storySurface;
  final storyHeader = palette.storyHeader;
  final componentSurface = palette.componentSurface;
  final componentHeader = palette.componentHeader;
  final text = palette.text;
  final muted = palette.muted;
  final border = palette.border;
  final link = palette.link;
  final controlSurface = palette.controlSurface;
  final controlText = palette.controlText;
  final tableHeader = palette.tableHeader;
  final selection = palette.selection;

  return '''

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
body.$readerBodyClass {
  width: 100% !important;
  max-width: 100% !important;
  min-height: 100% !important;
  margin: 0 !important;
  background: $background !important;
  color: $text !important;
  overflow-x: hidden !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile),
body.$readerBodyClass:not(.arklores-reader-operator-profile) p,
body.$readerBodyClass:not(.arklores-reader-operator-profile) li,
body.$readerBodyClass:not(.arklores-reader-operator-profile) td,
body.$readerBodyClass:not(.arklores-reader-operator-profile) th,
body.$readerBodyClass:not(.arklores-reader-operator-profile) blockquote,
body.$readerBodyClass:not(.arklores-reader-operator-profile) dd,
body.$readerBodyClass:not(.arklores-reader-operator-profile) dt,
body.$readerBodyClass:not(.arklores-reader-operator-profile) div,
body.$readerBodyClass:not(.arklores-reader-operator-profile) span,
body.$readerBodyClass.arklores-reader-operator-profile {
  font-family: "$readerFontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  font-size: ${baseFontSize}px !important;
  line-height: $lineHeight !important;
  letter-spacing: 0 !important;
  font-variant-ligatures: common-ligatures !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) *,
body.$readerBodyClass:not(.arklores-reader-operator-profile) *::before,
body.$readerBodyClass:not(.arklores-reader-operator-profile) *::after {
  box-sizing: border-box !important;
  text-shadow: none !important;
  box-shadow: none !important;
  filter: none !important;
}

body.$readerBodyClass ::selection {
  background: $selection !important;
}

body.$readerBodyClass header,
body.$readerBodyClass footer,
body.$readerBodyClass nav,
body.$readerBodyClass aside,
body.$readerBodyClass .navbar,
body.$readerBodyClass .sidebar,
body.$readerBodyClass .side-bar,
body.$readerBodyClass .toc,
body.$readerBodyClass .table-of-contents,
body.$readerBodyClass #toc,
body.$readerBodyClass #footer,
body.$readerBodyClass #mw-head,
body.$readerBodyClass #mw-panel,
body.$readerBodyClass #p-logo,
body.$readerBodyClass #siteNotice,
body.$readerBodyClass #catlinks,
body.$readerBodyClass .mw-jump-link,
body.$readerBodyClass .mw-editsection,
body.$readerBodyClass .printfooter,
body.$readerBodyClass .vector-header-container,
body.$readerBodyClass .vector-page-toolbar,
body.$readerBodyClass .vector-column-start,
body.$readerBodyClass .vector-column-end,
body.$readerBodyClass .mw-indicators,
body.$readerBodyClass .page-actions,
body.$readerBodyClass .page-header,
body.$readerBodyClass .bread,
body.$readerBodyClass .breadcrumb,
body.$readerBodyClass .advertisement,
body.$readerBodyClass .noprint,
body.$readerBodyClass [role="banner"],
body.$readerBodyClass [role="navigation"],
body.$readerBodyClass [aria-label="Advertisement"] {
  display: none !important;
}

body.$readerBodyClass main,
body.$readerBodyClass article,
body.$readerBodyClass #content,
body.$readerBodyClass .mw-body,
body.$readerBodyClass #mw-content-text,
body.$readerBodyClass .mw-parser-output,
body.$readerBodyClass .content,
body.$readerBodyClass .page,
body.$readerBodyClass .prose,
body.$readerBodyClass .arklores-reader-content-root {
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

body.$readerBodyClass #content,
body.$readerBodyClass .mw-body,
body.$readerBodyClass main,
body.$readerBodyClass article,
body.$readerBodyClass .arklores-reader-content-root {
  padding: 24px 18px 56px !important;
}

/* fz.wiki is a Next.js application with card-based layouts rather than
   MediaWiki article markup. Keep the article column fluid in reader mode. */
body.$readerBodyClass.arklores-reader-fz main,
body.$readerBodyClass.arklores-reader-fz article,
body.$readerBodyClass.arklores-reader-fz .arklores-reader-content-root {
  width: 100% !important;
  max-width: none !important;
  min-width: 0 !important;
  padding: 24px 12px 56px !important;
  overflow: visible !important;
}

body.$readerBodyClass.arklores-reader-fz .arklores-reader-content-root,
body.$readerBodyClass.arklores-reader-fz .arklores-reader-content-root > * {
  min-width: 0 !important;
  max-width: 100% !important;
}

body.$readerBodyClass.arklores-reader-fz .arklores-fz-visual {
  max-width: 100% !important;
  min-width: 0 !important;
}

body.$readerBodyClass.arklores-reader-fz .arklores-fz-media {
  visibility: visible !important;
  opacity: 1 !important;
  filter: none !important;
}

body.$readerBodyClass.arklores-reader-fz img.arklores-fz-media,
body.$readerBodyClass.arklores-reader-fz picture.arklores-fz-media img {
  display: block !important;
  width: auto !important;
  max-width: 100% !important;
  height: auto !important;
  object-fit: contain !important;
}

body.$readerBodyClass.arklores-reader-fz .arklores-fz-overflow-repair {
  width: 100% !important;
  max-width: 100% !important;
  min-width: 0 !important;
  margin-left: 0 !important;
  margin-right: 0 !important;
  overflow: visible !important;
}

body.$readerBodyClass.arklores-reader-fz .arklores-fz-overflow-repair > img,
body.$readerBodyClass.arklores-reader-fz .arklores-fz-overflow-repair > picture,
body.$readerBodyClass.arklores-reader-fz .arklores-fz-overflow-repair
  > picture
  img,
body.$readerBodyClass.arklores-reader-fz .arklores-fz-overflow-repair > canvas,
body.$readerBodyClass.arklores-reader-fz .arklores-fz-overflow-repair > svg {
  width: auto !important;
  max-width: 100% !important;
  height: auto !important;
}

body.$readerBodyClass.arklores-reader-fz.arklores-reader-fz-operator
  .arklores-reader-content-root
  :where(.flex, .grid, [class*="flex-"], [class*="grid-"]) {
  min-width: 0 !important;
}

body.$readerBodyClass .mw-parser-output,
body.$readerBodyClass .prose,
body.$readerBodyClass .arklores-reader-content-root {
  background: transparent !important;
  border: 0 !important;
  border-radius: 0 !important;
  padding: 0 !important;
  box-sizing: border-box !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-parser-output,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where(p, li, dd, dt, div, span, small, b, strong, em, label, caption),
body.$readerBodyClass:not(.arklores-reader-operator-profile) #mw-content-text,
body.$readerBodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where(p, li, dd, dt, div, span, small, b, strong, em, label, caption) {
  color: $text !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where(div, section, article, center, ul, ol, dl),
body.$readerBodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where(div, section, article, center, ul, ol, dl) {
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

body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where([style*="background"], [style*="background-color"], [style*="background-image"], [style*="background: url"], [style*="background:url"]):not(button):not(input):not(select):not(textarea):not(pre):not(code):not(.mw-collapsible-toggle),
body.$readerBodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where([style*="background"], [style*="background-color"], [style*="background-image"], [style*="background: url"], [style*="background:url"]):not(button):not(input):not(select):not(textarea):not(pre):not(code):not(.mw-collapsible-toggle) {
  background: transparent !important;
  background-color: transparent !important;
  background-image: none !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where([style*="color"]),
body.$readerBodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where([style*="color"]) {
  color: $text !important;
}

/* Keep the character canvas and voice application native, but restore
   reader typography for the surrounding operator article. */
body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text :where(
  p, li, dd, dt, td, th, caption, blockquote, small, b, strong, em, label,
  .mw-collapsible-content, .mw-collapsible-content *
):not(.charinfo-container *):not(#voice-table-root *) {
  font-family: "$readerFontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  font-size: ${baseFontSize}px !important;
  line-height: $lineHeight !important;
  letter-spacing: 0 !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text :where(h1, h2, h3, h4, h5, h6, .mw-headline):not(.charinfo-container *):not(#voice-table-root *) {
  font-family: "$readerFontFamily", -apple-system, BlinkMacSystemFont, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif !important;
  color: $text !important;
  letter-spacing: 0 !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text h2:not(.charinfo-container *):not(#voice-table-root *) {
  font-size: ${(22 * fontScale).clamp(15, 31).toStringAsFixed(1)}px !important;
  line-height: 1.28 !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text h3:not(.charinfo-container *):not(#voice-table-root *) {
  font-size: ${(19 * fontScale).clamp(13, 27).toStringAsFixed(1)}px !important;
  line-height: 1.32 !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text #basictemplate,
body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text .equiptemplate {
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

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text #basictemplate > div,
body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text .equiptemplate > div {
  background-color: transparent !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text :where(
  .equip-base-title, .equip-name-box, .equip-level-desc, .equip-task-content,
  .equip-material-content, .equip-level-stats
) {
  color: $text !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text .equip-full-btn {
  background: $controlSurface !important;
  color: $controlText !important;
  border: 1px solid $border !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text .equip-nofull-btn {
  background: ${dark ? '#7A2E2E' : '#C93A3A'} !important;
  color: #ffffff !important;
  border: 1px solid ${dark ? '#A65A5A' : '#A51F1F'} !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text .mw-collapsible-toggle,
body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text .mw-collapsible-toggle a {
  background: $controlSurface !important;
  color: $controlText !important;
  border-color: $border !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root {
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

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root :where(
  .bg-wikitable, .table, table, tbody, tr, td
) {
  background: transparent !important;
  color: $text !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root :where(
  [class~="!bg-table"], .filter-title, thead, th, input, .n-base-selection,
  .n-base-selection-label, .n-base-selection-tags, .n-base-selection-input,
  .n-base-selection-input__content
) {
  background: $componentHeader !important;
  color: $text !important;
  border-color: $border !important;
}

body.$readerBodyClass.arklores-reader-operator-profile #mw-content-text #voice-table-root :where(
  .border, .border-divider, td, th
) {
  border-color: $border !important;
}

body.$readerBodyClass.arklores-reader-operator-profile
  #mw-content-text
  .arklores-prts-paradox-table {
  display: table !important;
  width: 100% !important;
  max-width: 100% !important;
  min-width: 0 !important;
  table-layout: fixed !important;
  overflow: visible !important;
}

body.$readerBodyClass.arklores-reader-operator-profile
  #mw-content-text
  .arklores-prts-paradox-table
  :where(tbody, tr, td, th) {
  max-width: 100% !important;
  min-width: 0 !important;
  overflow-wrap: anywhere !important;
  word-break: break-word !important;
}

body.$readerBodyClass.arklores-reader-operator-profile
  #mw-content-text
  .arklores-prts-paradox-table
  img {
  max-width: 100% !important;
  height: auto !important;
}

body.$readerBodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .arklores-prts-paradox-table
  .nomobile {
  display: none !important;
}

body.$readerBodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .arklores-prts-paradox-table
  .nodesktop {
  display: table !important;
}

body.$readerBodyClass.arklores-reader-operator-profile.arklores-prts-paradox-desktop
  #mw-content-text
  .arklores-prts-paradox-table
  .nodesktop {
  display: none !important;
}

body.$readerBodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
  #mw-content-text
  .arklores-prts-paradox-table
  .nodesktop {
  width: min(100%, 15rem) !important;
  max-width: 100% !important;
  margin: 0.55em auto !important;
  table-layout: auto !important;
}

body.$readerBodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
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

body.$readerBodyClass.arklores-reader-operator-profile.arklores-prts-paradox-mobile
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

body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-parser-output :where([style*="width"], [style*="margin"]):not(img):not(video):not(canvas):not(svg):not(table):not(.thumb):not(.gallery),
body.$readerBodyClass:not(.arklores-reader-operator-profile) #mw-content-text :where([style*="width"], [style*="margin"]):not(img):not(video):not(canvas):not(svg):not(table):not(.thumb):not(.gallery) {
  width: auto !important;
  max-width: none !important;
  min-width: 0 !important;
  margin-left: 0 !important;
  margin-right: 0 !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .arklores-reader-story-block {
  width: 100% !important;
  max-width: none !important;
  margin: 0.9em 0 !important;
  padding: 0.85em 0.95em !important;
  background: $storySurface !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .arklores-reader-story-heading {
  width: 100% !important;
  max-width: none !important;
  margin: 0.6em 0 !important;
  padding: 0.55em 0.7em !important;
  background: $storyHeader !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$readerBodyClass .arklores-reader-story-block *,
body.$readerBodyClass .arklores-reader-story-heading * {
  color: inherit !important;
  background-color: transparent !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) h1,
body.$readerBodyClass:not(.arklores-reader-operator-profile) h2,
body.$readerBodyClass:not(.arklores-reader-operator-profile) h3,
body.$readerBodyClass:not(.arklores-reader-operator-profile) h4 {
  color: $text !important;
  line-height: 1.28 !important;
  margin: 1.4em 0 0.65em !important;
  padding: 0 !important;
  border-color: $border !important;
  font-weight: 700 !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) h1 {
  font-size: ${(26 * fontScale).clamp(17, 35).toStringAsFixed(1)}px !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) h2 {
  font-size: ${(22 * fontScale).clamp(15, 31).toStringAsFixed(1)}px !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) h3 {
  font-size: ${(19 * fontScale).clamp(13, 27).toStringAsFixed(1)}px !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) p {
  margin: 0.75em 0 !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) a,
body.$readerBodyClass:not(.arklores-reader-operator-profile) a * {
  color: $link !important;
  text-decoration-thickness: 1px !important;
  text-underline-offset: 0.18em !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) img,
body.$readerBodyClass:not(.arklores-reader-operator-profile) video,
body.$readerBodyClass:not(.arklores-reader-operator-profile) canvas,
body.$readerBodyClass:not(.arklores-reader-operator-profile) svg {
  max-width: 100% !important;
  height: auto !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) figure,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .thumb,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .gallery,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .floatnone,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .image {
  max-width: 100% !important;
  margin: 1em auto !important;
  text-align: center !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .thumbinner,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .gallerybox,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .gallerytext {
  background: transparent !important;
  border: 0 !important;
  color: $muted !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) table,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .wikitable {
  display: block !important;
  width: 100% !important;
  max-width: 100% !important;
  overflow-x: auto !important;
  border-collapse: collapse !important;
  background: transparent !important;
  color: $text !important;
  border-color: $border !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) table tr,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .wikitable tr,
body.$readerBodyClass:not(.arklores-reader-operator-profile) table tbody,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .wikitable tbody {
  background: transparent !important;
  color: $text !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) th,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .wikitable th {
  background: $tableHeader !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) td,
body.$readerBodyClass:not(.arklores-reader-operator-profile) th,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .wikitable td,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .wikitable th {
  border: 1px solid $border !important;
  padding: 0.5em 0.65em !important;
  color: $text !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) td[style],
body.$readerBodyClass:not(.arklores-reader-operator-profile) th[style],
body.$readerBodyClass:not(.arklores-reader-operator-profile) td[bgcolor],
body.$readerBodyClass:not(.arklores-reader-operator-profile) th[bgcolor] {
  background: transparent !important;
  color: $text !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .arklores-reader-table-accent {
  background: $storyHeader !important;
  color: $text !important;
  border-color: $border !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .arklores-reader-table-accent * {
  background-color: transparent !important;
  background-image: none !important;
  color: inherit !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) blockquote,
body.$readerBodyClass:not(.arklores-reader-operator-profile) pre,
body.$readerBodyClass:not(.arklores-reader-operator-profile) code {
  background: ${dark ? '#151E29' : '#EFE8DA'} !important;
  color: $text !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) button,
body.$readerBodyClass:not(.arklores-reader-operator-profile) input,
body.$readerBodyClass:not(.arklores-reader-operator-profile) select,
body.$readerBodyClass:not(.arklores-reader-operator-profile) textarea,
body.$readerBodyClass:not(.arklores-reader-operator-profile) [role="button"],
body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-collapsible-toggle,
body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-collapsible-toggle a {
  color: $controlText !important;
  background: $controlSurface !important;
  border: 1px solid $border !important;
  border-radius: 2px !important;
  text-decoration: none !important;
}

body.$readerBodyClass:not(.arklores-reader-operator-profile) .mw-collapsible-toggle {
  display: inline-flex !important;
  align-items: center !important;
  min-height: 2em !important;
  padding: 0.12em 0.45em !important;
  vertical-align: baseline !important;
}

body.$readerBodyClass .reference,
body.$readerBodyClass .mw-references-wrap,
body.$readerBodyClass .metadata,
body.$readerBodyClass .ambox,
body.$readerBodyClass .navbox,
body.$readerBodyClass .vertical-navbox,
body.$readerBodyClass .succession-box {
  color: $muted !important;
}

body.$readerBodyClass #sys_fullscreen.arklores-prts-scenario-shell-hidden {
  display: none !important;
}

body.$readerBodyClass #arklores-prts-scenario-reader {
  width: 100% !important;
  max-width: 760px !important;
  margin: 1.2em auto 1.6em !important;
  padding: 0 !important;
  background: transparent !important;
  color: $text !important;
}

body.$readerBodyClass #arklores-prts-log-all-button {
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

body.$readerBodyClass #sys_playback_all.arklores-prts-log-panel {
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

body.$readerBodyClass #sys_playback_all.arklores-prts-log-visible {
  display: block !important;
}

body.$readerBodyClass #playback_all_result.arklores-prts-log-list,
body.$readerBodyClass #playback_all_result.arklores-prts-log-list .log_style {
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

body.$readerBodyClass #playback_all_result.arklores-prts-log-list li {
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

body.$readerBodyClass #playback_all_result.arklores-prts-log-list li.arklores-prts-log-narration {
  grid-template-columns: minmax(0, 1fr) !important;
}

body.$readerBodyClass #playback_all_result.arklores-prts-log-list li.arklores-prts-log-narration > em {
  display: none !important;
}

body.$readerBodyClass #playback_all_result.arklores-prts-log-list li.arklores-prts-log-narration > span {
  color: $text !important;
  padding-left: 0 !important;
  left: auto !important;
}

body.$readerBodyClass #playback_all_result.arklores-prts-log-list li > em,
body.$readerBodyClass #playback_all_result.arklores-prts-log-list li > span {
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

body.$readerBodyClass #playback_all_result.arklores-prts-log-list li > em {
  color: $muted !important;
  font-style: normal !important;
  font-weight: 700 !important;
}

body.$readerBodyClass #playback_all_result.arklores-prts-log-list div.decision,
body.$readerBodyClass #playback_all_result.arklores-prts-log-list div.predicate {
  display: block !important;
  margin: 0.6em 0 !important;
  padding: 0.65em 0.8em !important;
  border: 1px solid $border !important;
  background: $storySurface !important;
  color: $text !important;
}
''';
}
