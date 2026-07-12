# Changelog

All notable changes to ArkLores will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
