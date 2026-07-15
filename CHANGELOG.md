# Changelog

All notable changes to ArkLores will be documented in this file.

## [0.5.0] - 2026-07-15

### Added

- Added a GameData-only Fact-Check Agent with claim decomposition, directed support/counter-evidence searches, and conversation-aware follow-ups.
- Added supported, refuted, uncertain, and cannot-confirm verdict states with expandable GameData evidence.
- Added verdict enforcement that prevents supported/refuted results without retrieved GameData records.
- Added fact-check cancellation, retry, empty/error handling, localized UI strings, and narrow-screen text-scale coverage.
- Added Fact-check session labels and validated-verdict output to the shared debug Agent log.
- Added schema v2 story scopes and scoped evidence retrieval for entity-and-relationship fact checks.

### Changed

- Updated shared Agent trust instructions so Wiki and user text are context only, never active GameData evidence.
- Hardened ReAct action parsing and source guards, and prevented unrelated GameData results from authorizing definitive verdicts.
- Added opt-in live Chat QA, evidence proximity ranking, and Fact-check retrieval enforcement for provider format and truncation variance.
- Replaced network-dependent Warfarin crawler output tests with deterministic offline parser and formatter contracts.
- Updated Android setup automation for API 36, data-preserving installs, verified GameData URLs, localhost adb reverse, and explicit debug-key release warnings.
- Added an Android setup option to serve an existing local GameData `.db.gz` with gzip/SHA256 validation, without rebuilding the database.

### Migration

- GameData schema v1 assets are incompatible with v0.5.0. Install the v0.5.0 schema v2 asset;
  the App validates the downloaded DB before replacing an existing valid installation.
- Existing App settings and conversations are preserved by normal update installs. Explicit uninstall/clean
  install still removes App data.

### Known Limitations

- The full external Chat matrix and Android accessibility/large-text/device coverage remain incomplete; see
  `docs/v0.5_task_breakdown.md`.
- Wiki and user text remain browsing/context only and are not official GameData evidence.

## [0.4.5] - 2026-07-15

### Changed

- Switched v0.4.5 architecture to Chinese GameData release assets as the primary knowledge source.
- Reduced AI provider settings to Chat API only.
- Reworked local lore search around structured GameData tables, aliases, LIKE, and FTS.
- Paused user-imported materials indexing until the low-trust Book source path is redesigned.
- Added GameData DB install validation before replacing the installed knowledge base.
- Added structured retrieval QA tooling for fixed full-DB smoke queries and alias candidate checks.
- Improved Chinese intent normalization for voice, archive, operator record, module, enemy profile, and roguelike queries.
- Added GameData asset finalization metadata for compressed/uncompressed SHA-256 and byte sizes.
- Fixed `tools/setup.sh` parameter mode so remote GameData URL builds do not report stale temporary HTTP service state.

### Removed

- Removed the old Wiki seed RAG runtime path from the app.
- Removed built-in model assets, seed assets, and old seed builder scripts.
- Removed local user-material indexing implementation tied to the old DB.
- Removed old citation-card lookup tied to the old chunk store.

## [0.3.0] - 2026-07-14

Superseded by the v0.4.5 GameData-first architecture.

## [0.2.0] - 2026-07-12

- Added dual-site Wiki WebView, bookmark management, theme refinements, and one-click setup script.

## [0.1.0] - 2026-07-12

- Initialized Flutter project, theme system, bottom navigation, placeholder pages, and Android build setup.
