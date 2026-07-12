# Changelog

All notable changes to ArkLores will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] — 2026-07-12

### Added

- **Dual-site WebView** — PRTS Wiki and Endfield Wiki tabs with independent `InAppWebViewController`, tap-only switching via `TabBar` + `IndexedStack`
- **Expandable floating toolbar** — bottom-right tray morphs between a FAB and a vertical toolbar via `AnimatedContainer`, designed for one-handed operation
- **Wiki dark mode CSS injection** — `filter: invert(1) hue-rotate(180deg)` strategy with automatic re-inversion of images/media; adaptive strategy for dark-native sites (removes `class="dark"` to enable native light mode)
- **Bookmark SQLite service** — `BookmarkService` singleton with full CRUD, stored in `arklores_bookmarks.db`
- **Bookmark Riverpod provider** — `BookmarkNotifier` with async state loading, in-memory URL set for O(1) `isBookmarked` queries
- **Bookmark management page** — scrollable list with swipe-to-delete, confirmation dialog, tap-to-navigate back to WebView
- **One-click setup script** — `tools/setup.sh` automates Flutter/Java/Android SDK checking, APK building (debug/release), and device installation

### Changed

- **Wiki toolbar removed from top** — replaced by bottom-right expandable tray for ergonomic one-handed reach
- **Dark mode default** — changed from `true` (dark) to `false` (light) on first visit

### Fixed

- **Tab swipe vs vertical scroll conflict** — `TabBarView` replaced with `IndexedStack` to eliminate horizontal swipe gesture interference with WebView scrolling
- **Dark mode auto-reverting on rebuild** — removed build-time sync block that forcibly reset `_isDarkMode` on every `setState`
- **Image distortion from invert(0.88) compound filter** — changed to `invert(1)` for perfect double-invert cancellation
- **PRTS carousel images not re-inverted** — added `[style*="background:url"]` and `[style*="background: url"]` CSS selectors for shorthand background properties
- **Class-based background icons not re-inverted** — added JS DOM walk (`getComputedStyle().backgroundImage`) to catch elements with CSS class backgrounds
- **JS re-inversion running on dark-native sites** — moved background re-inversion into the light-site-only code path
- **Toolbar button labeling** — toolbar now shows text labels in expanded state for clarity

### Documentation

- `docs/v0.2_SUMMARY.md` — v0.2 development summary
- `docs/v0.2_QA_REPORT.md` — v0.2 code verification and bug fix report
- `docs/v0.2_TASK_BREAKDOWN.md` — v0.2 task breakdown plan
- `docs/ANDROID_SETUP_GUIDE.md` — added one-click script reference section
- `README.md` — updated version to v0.2.0, added v0.2 features

---

## [0.1.0] — 2026-07-12

### Added

- **Flutter project initialization** — Android + iOS dual-platform configuration, project directory structure per architecture design
- **Dual theme token system** — `AppThemeTokens` abstract interface with 17 tokens, `ArkThemeTokens` (Tactical Archive, cold blue-gray palette), and `EndfieldThemeTokens` (Holographic Projection, cyan palette)
- **Theme switching** — `ThemeNotifier` + Riverpod `StateNotifierProvider`, supports `switchTo()` / `toggle()` via Settings page switch
- **Bottom navigation** — `MainShell` with 4 tabs: Wiki / AI / Materials / Settings, `IndexedStack` page switching
- **Google Fonts integration** — Rajdhani (ArkTheme titles), Exo 2 (EndfieldTheme titles), Noto Sans SC (body text)
- **ThemeAwareCard** — reusable card widget reading all visual tokens from `themeProvider`
- **Theme switch animation** — 300ms cross-fade via `AnimatedSwitcher` + `FadeTransition`
- **Placeholder pages** — Wiki browser, AI Chat, Materials, Settings tabs with theme-aware placeholders
- **Smoke test** — widget test verifying 4-tab bottom navigation rendering
- **Android build tooling** — AGP upgraded to 8.2.2 for Java 21 compatibility

### Changed

- `MaterialApp.theme` parameter corrected from `ThemeData.dark()` to `ThemeData.light()` (no visible effect, as `themeMode` is fixed to `dark`)

### Fixed

- `AnimatedSwitcher` key in `MainShell` decoupled from tab index — tab switches no longer trigger fade animation
- Gradle build failure on Java 21 resolved by upgrading Android Gradle Plugin to 8.2.2

### Documentation

- `docs/ANDROID_SETUP_GUIDE.md` — Android SDK setup and APK build guide
- `docs/v0.1_SUMMARY.md` — v0.1 development summary
- `docs/v0.1_QA_REPORT.md` — v0.1 code verification report
