# Changelog

All notable changes to ArkLores will be documented in this file.

## [Unreleased]

## [0.10.7] - 2026-10-04 (pre-release)

App-only update; the knowledge base is the v0.10.1 asset (unchanged, no new download).

### Changed

- **No more answer modes.** The 自动 / 概括 / 查证 / 回答 picker, the question router (one extra
  model call before every auto-mode question) and the three wrapper agents are gone: every
  question runs the one story agent with one prompt, and the model lays the answer out to fit
  the question. A claim check still shows its verdict chip (the model starts the answer with a
  verdict when asked to check a claim; the code still downgrades a verdict that has no cited,
  actually-read text). Saved sessions with the old mode fields still open.
- **The question box** is wider and grows with the text up to four lines; a button opens it to
  half of the screen and from there to the full screen (animated, rounded). The draft and the
  keyboard stay put while it changes size; sending collapses it. Enter sends when the box is
  closed up and writes a new line when it is open. The send button is a small round button with
  less margin.
- **Sources under an answer are compact and grouped.** One story collection gets one header; its
  chapters are indented under it, and the line chips of a chapter sit on the chapter's row
  (about half the height of before).
- **Cost under every answer**: a small grey line with input tokens (and the share served from the
  provider's cache), output tokens, number of model calls and the time, e.g. `in 382k · out 12k · cache 87% · 14 calls · 4m22s`. Also saved in the session file together with a
  per-call timeline (when each call and each tool run started and how long it took).

### Fixed

- **Reading a chapter was slow.** The knowledge base has no index on `story_lines(story_id,
  line_index)`, so every `read_story`, every context line of a `grep` and every citation check
  scanned all ~410,000 lines (~0.45 s each; one answer did dozens, 19 s in one citation check).
  The app now creates the index the first time it opens an older knowledge base (about a second,
  +20 MB) and new builds include it. No re-download.

### Measured (live, glm-5.3-flash)

- The key accepts at least 5 requests at once (no 429), so the parallel sub-agents are not
  throttled. A tool-using call has a floor of 4.5–6 s even for a 25-token reply; writing the
  answer (draft, rewrite after the review, reorganised version) is ~55% of a run.

## [0.10.6] - 2026-10-04 (pre-release)

App-only update; the knowledge base is the v0.10.1 asset (unchanged, no new download).

### Fixed

- **Evidence chains were missing** with GLM: the model wrote each citation flat
  (`"cite": ["<story>.txt", 97, 127]`) instead of as a list of lists, the app dropped them, and
  the answer ended up with no sources and the status "knowledge base not covered". The prompt now
  shows the exact nested shape, and the app reads the flat shape, `L97` / `"97-127"` line values,
  a story id without `.txt`, and a reversed range. An answer whose citations still cannot be read
  is sent back once with the correct shape, and the model's own answer is kept in the nested form
  (a rewrite or follow-up no longer copies the odd shape).
- Long operations are no longer cut when the app goes to the background: an Ask answer, a
  role-play reply, the knowledge-base download and the in-app build run under an Android
  foreground service (a small ongoing notification, a wake lock; Android 13+ asks for the
  notification permission once). A turn cut by a dropped connection is asked again (twice).
- The knowledge-base page offered "更新" and a full re-download even when the installed
  knowledge base was current. It now shows "已是最新" (greyed), with a confirmed "重新下载" for the
  rare case; the download is skipped when nothing is new. Rebuilding in the app drops the
  official-asset marker.
- Format tolerance elsewhere: `coverage` words (partial/incomplete = gaps), unknown fact-check
  verdict words, the stage `from` as "1-3", the plain-text tool protocol (`json` fence,
  `parameters`/`args`), an empty `{}` tool call, and a sub-agent's gaps and unchecked citations
  are reported to the main agent. A failed reviewer call is now written to the session log.
- Prompt and tool descriptions state the formats the code needs: the nested `cite`, one range
  per backtick for sub-agents, `read_story` has no `end`, a fact-check's `verdict` position.

## [0.10.5] - 2026-10-04 (pre-release)

App-only update; the knowledge base is the v0.10.1 asset (unchanged, no new download).

### Changed

- New installs default to Zhipu GLM-5.3-Flash (`glm-5.3-flash`,
  `https://api.z.ai/api/paas/v4`) instead of DeepSeek; saved settings are kept.
- Zhipu GLM (api.z.ai / open.bigmodel.cn, or a `glm*` model behind another endpoint) is a
  known provider. GLM-5.3-Flash cannot switch thinking off, so the effort is set with
  `reasoning_effort`: `low` by default (an 80-word answer: ~20 s → ~4 s), `high` with
  "深度思考". `tool_choice` is not sent (Zhipu accepts only `auto`); tool calls are streamed
  with `tool_stream`.
- The story reader: the text starts at the page gutter with small line numbers on the right,
  a speaker's name is shown once per run of lines, the cited lines are one rounded highlight,
  and a header shows the collection, chapter and cited range, with a button back to them.
- The sources under each point of an answer are a folded pill ("出处 N" and the story
  collections) that opens a card with the chapters and line chips, instead of an always-open
  list behind a grey bar.

### Fixed

- A request the provider rejects only for its reasoning fields (including a bare "invalid
  parameter") is sent once more without them, and later requests leave them out; a rejected
  `stream_options` is dropped before falling back to a non-streamed answer. Before, a GLM run
  could spend over 20 minutes in retries.
- A rate-limited request (HTTP 429) is retried up to three times, honouring `Retry-After`
  (otherwise 2 / 5 / 10 s); parallel sub-agents can exceed a provider's concurrency limit.
- A tool name repeated in every streamed chunk is no longer joined into one long name.

## [0.10.4] - 2026-10-03 (pre-release)

App-only update; the knowledge base is the v0.10.1 asset (unchanged, no new download).

### Changed

- Story answers get a reader's review: a second model call reads the question and the answer
  (without the source text) and asks up to three questions about the whole story — whether a
  later reveal changes what the answer tells as fact, whether other stories add or correct it,
  whether the question was answered. The agent checks them in the text and rewrites; once per
  question, and a failed review lets the answer through.
- Long answers are reorganised into a few paragraphs, one per stage, each followed by all the
  citations of the points it covers (merged by code, none lost). The detailed answer is folded
  below as "详细经过 · N 条", also while it streams.
- The prompt no longer names plot devices; a question about one story collection still looks at
  the corpus-wide distribution first.

### Fixed

- After an answer was sent back (citation check or review), a reply that only described the
  process could be taken as the answer and end as "not covered"; it is now asked for once more,
  and otherwise the earlier answer is kept.

## [0.10.3] - 2026-10-03 (pre-release)

App-only update; the knowledge base is the v0.10.1 asset (unchanged, no new download).

### Changed

- The Ask list no longer follows a streaming answer: thinking, steps and answer grow below
  while the view stays where the reader put it (before, each update jumped to the end and
  cut off the reader's drag). Only a new question scrolls to the end once; a ↓ button
  appears whenever the end is out of view.
- The thinking is a scrollable window of fixed height holding the whole text (not the last
  800 characters); it does not follow new thinking and stays after the answer is complete,
  so nothing above the answer changes height while it is read.
- While an answer streams, every finished point already shows its evidence chain; only the
  point being written waits. Chain labels are looked up per story, so they no longer change
  when the answer completes.
- Readability on the light (Endfield) theme: the signal yellow is kept for fills and thick
  lines; accent text, icons and thin borders use a deep amber of the same hue (new theme
  tokens `accentText` / `onAccent`, contrast ≥ 4.5 checked by a test) — status line,
  evidence chips, mode button, send icon, tab label. Other pages can follow the same rule.
- The mode picker is a rounded panel that slides up from the mode button instead of a popup
  menu; it takes no focus, so the keyboard stays up.

### Notes

- Answer quality issues from the same device test (no short top-level answer for broad
  questions; a story's framing, such as events later revealed to be a dream, is not stated
  up front or checked against other stories) are recorded with candidate fixes in
  `docs/KNOWN_LIMITATIONS_AND_DEBT.md` §5.9 and left for a later round.

## [0.10.2] - 2026-10-03 (pre-release)

App-only update; the knowledge base is the v0.10.1 asset (unchanged, no new download).

### Changed

- Answers are written for the reader, not about the knowledge base: no table names, file names,
  ids or "库中 …" in the text, events retold in the agent's own words instead of quoted dialogue,
  and a misspelled name noted once as "X（你写的是 Y）". The prompt states rules only — no
  concrete story, chapter or character (a test guards this). Gaps are one closing sentence in
  chapter names instead of a list of what was read.
- The agent writes its final answer as JSON — entries of text plus citation tuples
  (`["<story_id>", start, end]` / `["record", id]`) — which the app turns into the answer as it
  streams, so every citation lands under the point it supports. Quoted text that copies the
  cited lines is sent back once to be retold (shared with the citation check). On two test
  questions the quoted share of the text fell from 15% / 10.6% to 0.5% / 1.4%.
- Each paragraph or list item is followed by its evidence chain (`故事集 → 章 → 第 a–b 行`)
  instead of citations inside the sentence. Tapping a line range opens the whole chapter,
  scrolled to those lines, which flash twice and stay highlighted; a cited record opens in a
  sheet. The collapsed evidence summary under the answer opens the chapter the same way.
- A short opening paragraph about the search itself ("让我确认……grep 显示……") is dropped like
  the other process lead-ins.

## [0.10.1] - 2026-10-03 (pre-release)

Everything since v0.10.0 is one iteration of the story Q&A agent and ships as 0.10.1 (a v0.11.0
pre-release published on 2026-10-02 was withdrawn; its work is included here). Knowledge base:
same story text and vectors as v0.10.0 plus the optional `story_catalog` table
(`arklores_gamedata_zh.db.gz` 184,850,215 B, SHA-256
`f5f14283a42f9b678a598354e74033c2393da64e4e1b4bc470303f279c9aed53`). The APK installs over
v0.10.0 (same signing key); download the new knowledge base in the app to get story names.

### Changed

- New story agent for every Ask question (investigate, summarize, verify — the mode only changes
  the answer format): one model works the knowledge base with general tools in one append-only
  conversation — read-only SQL over the whole database, corpus-wide or scoped grep with context,
  whole-chapter reads, ranked keyword/vector search, collection outlines and near names. For
  questions that span many chapters it can hand parts of the reading to sub-agents that run in
  parallel. It replaces the step-by-step planner pipeline of v0.10.0 (planner, note extractor,
  separate answer writer). On the test question "塔露拉在切尔诺伯格事件之后做了哪些事情？" it read
  all four key chapters with 11 model calls in 35 s; the planner needed ~37 calls and 97 s and
  most of its input could not be served from the provider's prompt cache.
- Follow-up questions continue the previous answer's conversation, so text already read is
  still there.
- Misspelled names (e.g. 切尔诺贝利, 缪因) are searched under the knowledge base's spelling;
  the answer says "库中写作 …". Zero-hit searches list near names (pinyin-aware string
  similarity only — who a name refers to is settled from the lines read).
- Citations are checked by code against the lines and records the tools actually showed; an
  answer citing anything else is sent back once. Answers start with a code-decided
  `[STORY_ANSWER: status=answered|partial|not_covered]` line; fact-check verdicts need cited,
  checked lines. No question-type special cases (a test guards against new ones).
- Answers stream token by token; the status line shows what the agent is doing
  ("第 3 轮 · 阅读 …"); the list follows the answer only while it is at the bottom (↓ button
  otherwise). Roleplay replies stream too.
- "深度思考" switch next to the mode chip: the agent thinks at low effort for the next
  questions. By default nothing runs with hidden reasoning (deepseek otherwise thinks at high
  effort; it cost ~5× the output tokens and invited guesses beyond the text).
- Evidence: sources show as "巴别塔 BB-7 行动前《…》 第 N 行"; cited lines fold into
  "证据 N 处 · 来自 M 个故事" and open as collection → chapter → line chips; tapping a chip shows
  the original lines from the knowledge base. Non-story records (profiles, voice lines, item
  texts) are cited as "资料 n" and open the same way.
- Ask page: one top bar (Ask / Roleplay switch, history, new conversation, a menu with retry /
  clear); the mode picker is a chip in the input row; no avatars.
- Knowledge base: optional `story_catalog` (collection name, level code, chapter name,
  行动前/后, order, official synopsis, release time) built from `story_review_table.json` and the
  `[uc]info` synopses; `tools/build_story_catalog.dart` adds it to an existing DB in place. The
  download streams to disk, resumes after a dropped connection, and runs app-wide (one download
  at a time). The knowledge-base page offers an update when the installed asset differs from the
  one this APK points to.
- Providers without function calling fall back to a plain-text tool protocol.

### Fixed

- Roleplay replies longer than 120 characters showed only their last part.
- Non-streamed responses without a `charset` were decoded as latin1.
- `HandshakeException: Connection terminated during handshake` during the knowledge-base
  download (now retried and resumed).

## [0.10.0] - 2026-10-02

Covers development rounds R0–R12 since v0.9.0. Architecture: `docs/AI_ARCHITECTURE.md`.

### Added

- GameData schema 3/4: deterministic story coverage layer (entity appearance runs over
  speaker + content, chapter profiles, rare terms, line-level story FTS), speaker entities
  for NPCs with dialogue; schema 4 skips upstream `[uc]info/` stub trees.
- Story tools for the Agent: `search_story_coverage`, `get_story_map`, `read_story_lines`,
  `search_story_lines`, `collect_suspect_evidence`.
- In-app knowledge base build from the source repository (first download or incremental
  compare), in a background isolate, validated and atomically swapped.
- Ask entry with auto / summarize / verify / investigate modes; story investigation mode.
- Persistent chat sessions (`chat_sessions/` JSON) with history page, resume and delete;
  optional AI session log toggle.
- Optional story vector recall: `story_chunk_vectors` table (51,264 chunks, 512-dim int8),
  configurable embedding API in Settings (default Bailian `qwen3.7-text-embedding`).
  Without a key, or when the model does not match the DB, search falls back to keywords.
- Opt-in live test that drives the app's own Ask pipeline (`test/live/ask_pipeline_live_test.dart`)
  and records token usage per question.

### Changed

- Investigation runs on PlannerLoop (planner / executor / extractor / writer). R12: evidence
  notes with code-copied quotes, the writer reads the original lines, every line citation is
  checked against what was actually read, duplicate searches are not re-run, and stalls end
  in an answer built from what was read instead of a state dump.
- Mechanical roles (planner, extractor, disambiguator) run with reasoning disabled; the writer
  keeps reasoning. Output tokens per investigation dropped about 88% at equal answer quality.
- Shared DB connection for all tools; the store reopens after the DB file is replaced.
- Removed the death/murder keyword features and the `find_detail_echoes` tool.

### Verification

- Offline suite on Windows: 231 passed, 5 skipped (opt-in live / POSIX-only); `flutter analyze`
  has one known deprecation info.
- Fixed GameData retrieval QA passed on the release DB; installer validator accepts it.
- Live (deepseek flash, vectors on): "who" question 23 steps / 82 s / 11 valid citations;
  "how" question 8 steps / 31 s, read the gold chapter; fictional-entity negative answered
  "not covered".

### Release Assets

- `arklores_gamedata_zh.db.gz`: 184507479 bytes, schema 4 with optional vectors, SHA-256
  `aa1c3650e37f1ec53281dc5c35e7e909da82ad752c05b2cb64b80ea3717ff968`
  (uncompressed 622948352 bytes, SHA-256
  `6c331cda39f2756762e0b0ea927a58b0baaf559bc2080c2303b52d915a721c50`).
- `gamedata_manifest.json`: 1348 bytes, SHA-256
  `0e78c79c7fc0735eab926913bb4a283608cfeba770383e4dad6e8d8d696aecb4`.
- `ArkLores-0.10.0.apk`: 40349995 bytes, SHA-256
  `bc501b1962c6debc2de8788ce21e7cd0d0bd44c52d2f6498cb1281fe14e0f45a`; ARM 32/64-bit, built by
  GitHub Actions (`.github/workflows/android-release.yml`) from `2353d95` and signed with the
  new project release key (certificate SHA-256
  `b1b09ebfd22659b4b246ea87d67ff340a277e8031c14577caa5715519923e364`).
- Android build toolchain raised to Flutter 3.47's minimums: Gradle 8.14.3, AGP 8.11.1,
  Kotlin 2.2.20, Java 17.

### Upgrade note

- Earlier APKs were signed with a developer machine's debug key. Android refuses to install an
  APK signed with a different key over an existing install, so **uninstall the old app once
  before installing v0.10.0** (local chats and the downloaded knowledge base are removed).
  Later versions signed with the same project key upgrade in place.

### CI

- `.github/workflows/ci.yml` runs `flutter analyze` and `flutter test` on pull requests and on
  pushes to `dev`/`main`.

## [0.9.0] - 2026-07-15

### Added

- Added shared industrial UI primitives for angular surfaces, section markers, responsive page headers, and layered perspective grid backdrops across app routes.
- Added narrow-screen and enlarged-text Widget coverage for the redesigned bilingual settings page.

### Changed

- Rebuilt the Night theme around neutral tactical black/gray and `#0BA0D0` wayfinding, and the Day theme around soft white/gray surfaces with `#F8D439` emphasis.
- Redesigned settings and bottom navigation with a shared information architecture, equal centered card widths, responsive section labels, and higher-contrast light-theme icons.
- Expanded the application-wide Material theme for consistent app bars, inputs, buttons, tabs, progress states, and feedback surfaces.
- Released app version `0.9.0+9`.

### Verification

- Verified the full offline test suite (61 passed; 3 opt-in external Chat tests skipped),
  `flutter analyze`, finalized GameData retrieval QA, release-mode APK build, and APK signing.
- Published `v0.9.0` to GitHub after merging the completed `dev` line into `main`.

### Release Assets

- `ArkLores-0.9.0.apk`: 27167887 bytes, SHA-256
  `a261919380865efa1ed22f11f4eba09558adfeee1095ce4068d5a2cb8c5b686c`.
- `arklores_gamedata_zh.db.gz`: 115092521 bytes, schema 2, SHA-256
  `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5`.
- `gamedata_manifest.json`: 984 bytes, SHA-256
  `e8d45acb2d3cc5ff3a33a386f77de7caefda9193d07b106c9fc6d8bf1e4cc90d`.
- `gamedata_build_report.json`: 690 bytes, SHA-256
  `7116dc394db92173682e2560e0ea11ea115434816b227340f6869cdb908cb3db`.
- The APK is release-mode but signed with the Android Debug certificate, not a store production certificate.

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
  `docs/RETRIEVAL_QA.md`.
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

## Historical Release Metadata

Detailed task snapshots remain available in Git history. Durable asset records are consolidated here:

| Version | APK SHA-256 | GameData DB.gz SHA-256 | Notes |
| --- | --- | --- | --- |
| v0.4.5 | `a81d3c4ef849ca09319d8516226cbeaa1ea63d75b7654a299fa64acdc9c07977` | `cfd3bfaeeefdf7477ae0c9342cab61ab4feb3367bb11b820ba8075c35dc70675` | GameData-first/schema 1 transition |
| v0.5.0 | `58f4b42a5ac239af0a0e5d2f33a2dae786ea80ab87fb138395bd317d42e72b37` | `c96599a7291751ada06f8d9b52b90fe0193615beb8eac39488bb49bd03694b10` | schema 2 scoped evidence |
| v0.6.0 | `a6d5dcc55b775fa08dc0609ca5e6dd91f672ca44bc906abaf3005c029d898e91` | `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5` | Role-play; debug-certificate APK |
| v0.7.0 | `a656154d5cf0495fd70f12332b45da8ec29e2b7b9356e85bcb0e962c7ed96496` | `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5` | Wiki context handoff |
| v0.8.0 | `f246e55b53690f3139a29d82d4f8c2d1abfecb59068bf5d204b67785f752c5e3` | `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5` | Evidence UX; debug-certificate APK |
| v0.9.0 | `a261919380865efa1ed22f11f4eba09558adfeee1095ce4068d5a2cb8c5b686c` | `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5` | Visual system; debug-certificate APK |
