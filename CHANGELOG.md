# Changelog

All notable changes to ArkLores will be documented in this file.

## [Unreleased]

### Added

- Added shared industrial UI primitives for angular surfaces, section markers, responsive page headers, and layered perspective grid backdrops across app routes.
- Added narrow-screen and enlarged-text Widget coverage for the redesigned bilingual settings page.

### Changed

- Rebuilt the Night theme around neutral tactical black/gray and `#0BA0D0` wayfinding, and the Day theme around soft white/gray surfaces with `#F8D439` emphasis.
- Redesigned settings and bottom navigation with a shared information architecture, equal centered card widths, responsive section labels, and higher-contrast light-theme icons.
- Expanded the application-wide Material theme for consistent app bars, inputs, buttons, tabs, progress states, and feedback surfaces.
- Bumped the development version to `0.9.0+9`.

## [0.8.0] - 2026-07-15

### Added

- Added structured expandable GameData evidence cards for Summary and Fact-check, including title, section, content type, source path, raw ID, retrieval type, ranking reason, trust note, excerpt, and a neutral coverage label.
- Added Summary cancellation, stale-response protection, retry, and localized empty/error/canceled states to match Fact-check behavior.

### Changed

- Unified Summary and Fact-check source bars and send/stop interactions.
- Localized Agent loading and reasoning status text and improved evidence metadata wrapping for narrow screens and large text.
- Bumped the app version to `0.8.0+8` and built the release APK with the v0.8.0 GameData asset URL and SHA256.
- Audited tracked documentation for current version, architecture, verification ownership, local links, and deferred scope;
  corrected the GameData build/finalization example to match the current helper CLI.

### Verification

- Verified focused evidence parser and Widget tests, `test/agent_test.dart`, the full offline test suite
  (58 passed; 3 opt-in external Chat tests skipped), and `flutter analyze` on 2026-07-15.

### Known Limitations

- Android real-device screenshots, TalkBack navigation, landscape layouts, and extreme text scaling remain deferred.
- Evidence source navigation is not implemented because GameData `source_path` values are release-asset provenance paths, not app-openable documents.
- The GitHub APK is release-mode but signed with the Android Debug certificate, not a store production certificate.

## [0.7.0] - 2026-07-15

### Added

- Added explicit Wiki reading-context handoff from WebView to Summary and Fact-check.
- Added transfer of selected Wiki text, page title, URL, and site label as user context.
- Added bilingual UI strings for the Wiki-to-AI handoff sheet and toolbar action.

### Changed

- Updated Summary and Fact-check prompts so Wiki reading context must be independently verified with `search_local_lore`.
- Kept Wiki text and URLs visually and semantically separate from GameData evidence; no Wiki embedding, vector indexing, Book indexing, hidden indexing path, or GameData DB writes were introduced.
- Bumped the app version to `0.7.0+7` and built the release APK with the v0.7.0 GameData asset URL and SHA256.

### Verification

- Verified `test/agent_test.dart`, `test/fact_check_widget_test.dart`, `flutter analyze`,
  full GameData retrieval QA, setup release dry-run, release-mode APK build, and APK v1/v2 signature verification on 2026-07-15.

### Known Limitations

- Android real-device validation for WebView selection, the handoff bottom sheet, return-to-browse flow, TalkBack, and large text remains deferred.
- Real external Chat QA and a finalized-DB Wiki-context retrieval matrix remain deferred.
- The GitHub APK remains a release-mode debug-certificate acceptance build, not a store-signed production package.

## [0.6.0] - 2026-07-15

### Added

- Added GameData-resolved role-play with entity disambiguation and character-bound lore retrieval.
- Added multi-turn local role-play sessions with continue, restart, cancel, retry, and JSON session persistence.
- Added roleplay UI states that show the canonical character, stable entity id, GameData range, and generated-dialogue disclaimer.
- Added English and Chinese roleplay UI strings.

### Changed

- Kept roleplay on the GameData-only `search_local_lore` path; Wiki, Book, and user scene text remain context only.
- Hardened debug Agent logging in Flutter test environments where `path_provider` plugins are unavailable.

### Verification

- Verified `test/agent_test.dart`, `test/fact_check_widget_test.dart`,
  `ARKLORES_RUN_LIVE_CHAT=true test/live_fact_check_test.dart`, full GameData retrieval QA,
  schema smoke build, setup release dry-run, and `flutter analyze` on 2026-07-15.

### Known Limitations

- Android real-device validation for local save restore, bilingual UI, TalkBack, cancellation, and long-session performance remains deferred.
- Roleplay UI still needs real screenshots/device-rendering review beyond automated Widget coverage.
- Broader multi-character roleplay retrieval matrices and low-coverage quantification remain deferred.

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
  `docs/RETRIEVAL_QA.md` and `docs/RELEASE_HISTORY.md`.
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
