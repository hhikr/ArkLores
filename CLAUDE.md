# ArkLores — CLAUDE.md

## Project Overview

ArkLores is an AI-enhanced reading companion for *Arknights* story enthusiasts. It's an open-source, serverless mobile app (Android + iOS) built with Flutter, where users bring their own API Key.

- **App Name**: ArkLores
- **Author**: hhikr
- **License**: GPL-3.0
- **Repository**: `github.com/hhikr/ArkLores`
- **Minimum OS**: Android 8.0 (API 26) / iOS 14
- **Target Platforms**: Android + iOS (Flutter)

## Tech Stack

| Category        | Choice                                      |
|-----------------|---------------------------------------------|
| Framework       | Flutter (Dart)                              |
| State Management| Riverpod (`flutter_riverpod`)               |
| WebView         | `flutter_inappwebview`                      |
| Database        | SQLite (`sqflite`) + sqlite-vec (vector)    |
| LLM Client      | OpenAI-compatible API (user's own key)      |
| Agent Runtime   | Pure Dart hand-written ReAct Loop           |
| Theme           | Dual theme switchable (Ark / Endfield)      |
| Fonts           | Rajdhani / Exo 2 / Noto Sans SC (Google Fonts) |

## Development Environment

- **Conda**: Must use the **base** conda environment for all development.
  - Conda path: `/opt/miniconda3`
  - Activation: `conda activate base` (or `source /opt/miniconda3/etc/profile.d/conda.sh && conda activate base`)
  - Flutter and Dart tools should be available via the conda base environment.
- **Flutter**: Ensure `flutter doctor` passes for both Android and iOS targets before starting development.

## Key Dependencies

```yaml
dependencies:
  flutter_inappwebview: ^6.x
  flutter_riverpod: ^2.x
  sqflite: ^2.x
  sqlite_vec: ^0.1.x
  http: ^1.x
  flutter_markdown: ^0.x
  flutter_secure_storage: ^9.x
  google_fonts: ^6.x
  file_picker: ^8.x
  syncfusion_flutter_pdf: ^26.x
  path_provider: ^2.x
  uuid: ^4.x
```

## Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Flutter UI Layer                      │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌───────────┐  │
│  │ Wiki 浏览  │ │  AI 对话  │ │   资料     │ │   设置    │  │
│  │ WebView    │ │ 三模式切换 │ │ 书籍导入   │ │ API Key   │  │
│  │ +书签/深色 │ │ +引用卡片  │ │ 多文件管理 │ │ 知识库管理│  │
│  └─────┬────┘ └─────┬────┘ └─────┬────┘ └────┬───┘  │
│       │  智能浮动按钮联动   │           │            │  │
└───────┼───────────────────────┼───────────┼────────────┘
         │                      │           │
┌────────▼───────────────────▼─────────▼──────────────────┐
│                 Application Layer (Dart)                │
│  │  │ 事实核查   │ │ 梗概生成   │ │  角色扮演    │  │  │
│  │  │  Agent    │ │  Agent    │ │   Agent     │  │  │
│  │  └────────────┘ └────────────┘ └──────────────┘  │  │
│  │           ↓ Tool Calls                            │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │              Tool Registry                  │  │  │
│  │  │  search_wiki | get_character | cite_source │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────┬───────────────────────────┘
                             │
         ┌───────────────────┼──────────────────┐
         ▼                   ▼                  ▼
┌──────────────┐   ┌──────────────────────────┐  ┌──────────────┐
│ sqlite-vec   │   │   内容摄取层               │  │  LLM Client  │
│ 向量索引      │   │  ┌──────────────────────┐  │  │  OpenAI 兼容 │
│ + SQLite     │   │  │ Wiki 爬取器           │  │  │  Embedding + │
│ 结构化缓存    │   │  │ MediaWiki API        │  │  │  Chat API    │
└──────────────┘   │  │ (prts + warfarin)    │  │  └──────────────┘
                   │  ├──────────────────────┤  │
                   │  │ 书籍导入器            │  │
                   │  │ PDF/TXT 文件导入      │  │
                   │  │ → 文本提取 → 分块     │  │
                   │  └──────────────────────┘  │
                   └──────────────────────────┘
```

## Directory Structure

```
arklores/
├── lib/
│   ├── main.dart
│   ├── app.dart                    # Routing & Theme
│   ├── core/
│   │   ├── llm/
│   │   │   ├── llm_client.dart     # Abstract interface
│   │   │   └── openai_client.dart  # OpenAI-compatible implementation
│   │   ├── rag/
│   │   │   ├── vector_store.dart   # sqlite-vec wrapper
│   │   │   ├── chunker.dart        # Text chunking
│   │   │   └── embedder.dart       # Embedding API calls
│   │   ├── wiki/
│   │   │   ├── wiki_crawler.dart   # MediaWiki API crawler
│   │   │   └── wiki_models.dart
│   │   └── agent/
│   │       ├── react_loop.dart     # Generic ReAct executor
│   │       ├── tools/
│   │       │   ├── search_wiki.dart
│   │       │   ├── get_character.dart
│   │       │   └── cite_source.dart
│   │       ├── fact_check_agent.dart
│   │       ├── summary_agent.dart
│   │       └── roleplay_agent.dart
│   ├── features/
│   │   ├── wiki/
│   │   │   ├── wiki_browser_page.dart
│   │   │   └── bookmark_page.dart
│   │   ├── ai/
│   │   │   ├── ai_chat_page.dart
│   │   │   ├── fact_check/
│   │   │   ├── summary/
│   │   │   └── roleplay/
│   │   │       ├── character_search.dart
│   │   │       ├── character_card.dart
│   │   │       └── roleplay_chat.dart
│   │   ├── materials/
│   │   │   ├── materials_page.dart
│   │   │   ├── book_import_sheet.dart
│   │   │   └── book_list_item.dart
│   │   └── settings/
│   │       ├── settings_page.dart
│   │       └── knowledge_base_page.dart
│   └── shared/
│       ├── theme/
│       │   ├── app_theme.dart           # Abstract AppThemeTokens
│       │   ├── ark_theme_tokens.dart    # Theme A: Tactical Archive
│       │   └── endfield_theme_tokens.dart # Theme B: Holographic Projection
│       ├── widgets/
│       │   ├── citation_card.dart
│       │   ├── floating_action.dart
│       │   └── theme_aware_card.dart
│       └── providers/
│           ├── settings_provider.dart
│           ├── theme_provider.dart
│           └── chat_provider.dart
├── android/
├── ios/
└── pubspec.yaml
```

## Commands

```bash
# Run
flutter run                          # Run on connected device
flutter run -d chrome                # Run as web (debugging only, not a target platform)

# Build
flutter build apk --debug            # Debug APK
flutter build apk --release          # Release APK
flutter build ios                    # iOS build (macOS only)

# Analyze
flutter analyze                     # Static analysis (must pass before commit)

# Test
flutter test                        # Run all tests

# Dependencies
flutter pub get                     # Get dependencies
flutter pub upgrade                 # Upgrade dependencies
```

## Git Conventions

### Branch Strategy

Simplified GitFlow:

```
main — stable releases only
dev  — daily integration (target branch for PRs)
feature/<scope>-<description>  — new features (branch from dev)
fix/<scope>-<description>      — bug fixes (branch from dev)
chore/<scope>-<description>    — maintenance (branch from dev)
release/v<X.Y>                 — release preparation
```

**Rules**:
- Never push directly to `main` or `dev` (PR merge only via @hhikr).
- Branch names: lowercase, kebab-case, format `<type>/<scope>-<short-description>`.

### Branch Scope Abbreviations

| Scope  | Module                    |
|--------|---------------------------|
| wiki   | Wiki browser module       |
| ai     | AI chat module            |
| materials | Materials tab          |
| rag    | Knowledge base / RAG      |
| agent  | Agent logic               |
| theme  | Theme system              |
| settings | Settings page           |
| llm    | LLM client layer          |
| db     | Database / sqlite-vec     |
| ci     | CI/CD                     |

### Commit Message Format

Conventional Commits 1.0.0:

```
<type>(<scope>): <subject>

[body: explain why, not what]

[footer: Closes #N / BREAKING CHANGE]
```

**Types**: `feat` | `fix` | `chore` | `docs` | `refactor` | `perf` | `test` | `style` | `revert`

**Rules**:
- Subject ≤ 72 chars, imperative mood, no trailing period.
- One commit = one clear change. If your subject has "and", split it.
- Body explains *why* (code itself shows *what*).
- Commit after each independent subtask — never batch at the end.

### Examples

```
feat(rag): add PDF text extraction via syncfusion_flutter_pdf
fix(wiki): prevent CSS injection from breaking PRTS table layout
chore(ci): add GitHub Actions APK build workflow
feat(theme): add dual theme token system with ArkTheme and EndfieldTheme
```

## Theme System

The app has two fully switchable themes with instant effect (no restart needed).

### Theme A — ArkTheme (Arknights Tactical Archive)
- Cyperpunk tactical/industrial aesthetic
- Cold blue-gray palette, chamfer-corner cards, geometric decoration lines
- Fonts: Rajdhani (English) + Noto Sans SC (Chinese)

### Theme B — EndfieldTheme (Endfield Holographic Projection)
- Futuristic sci-fi with spatial/diegetic UI
- Semi-transparent frosted glass cards, cyan holographic accents, grid drift animation
- Fonts: Exo 2 (English) + Noto Sans SC (Chinese)

### Implementation

```dart
// Abstract interface in lib/shared/theme/app_theme.dart
abstract class AppThemeTokens {
  Color get bgPrimary;
  Color get bgSecondary;
  Color get cardSurface;
  Color get accentPrimary;
  // ... more tokens
  TextStyle get titleFont;
  BorderRadius get cardRadius;
  List<BoxShadow> get cardShadow;
}

// Riverpod Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeTokens>(...);
```

**All UI components must read tokens via `ref.watch(themeProvider)` — no hardcoded colors or fonts.**

## AI Content Trust Strategy (RAG)

When the app retrieves content from the knowledge base, it distinguishes two source types:

- **[Wiki]** — from PRTS Wiki or Endfield Wiki (community-maintained, more reliable)
- **[Book]** — from user-imported book files (may contain non-official interpretations or translation errors)

**Agent Prompt rules** (injected into every Agent's system prompt):
1. When [Wiki] and [Book] conflict, prioritize [Wiki].
2. When citing [Book] content, explicitly mark it as "from book materials".
3. If [Book] content can't be corroborated by [Wiki], state "this information comes only from user-imported materials, verify independently."
4. Never present [Book]-sourced content as official setting with a definitive tone.

**Citation card visual distinction**:

| Source Type | Badge       | Color              |
|-------------|-------------|--------------------|
| PRTS Wiki   | 🌐 Wiki · PRTS    | Theme accent color |
| Endfield Wiki | 🌐 Wiki · Endfield | Theme accent color |
| Book        | 📚 Book · [name]  | Amber/brown        |

## Code Style Guidelines

1. **State Management**: Use Riverpod exclusively. All state reads via `ref.watch()`, writes via `ref.read(...notifier)`.
2. **No Hardcoded Theme Values**: All colors, fonts, spacing, radii must come from `AppThemeTokens` via `ref.watch(themeProvider)`.
3. **File Organization**: Place files under the exact paths specified in the directory structure above.
4. **Error Handling**: Handle API timeouts, network disconnects, and empty vector store states gracefully with user-friendly messages.
5. **Performance**: Heavy data operations (embedding, chunking) must run in an isolate to avoid blocking the main thread.
6. **Security**: Never commit API keys, tokens, or `.env` file contents. Store secrets via `flutter_secure_storage`.
7. **No Debug Residue**: Remove `print()` statements and debug code before committing.

## Iteration Roadmap

| Version | Focus                          | Est. |
|---------|--------------------------------|------|
| v0.1    | Skeleton + Dual Theme          | 1w   |
| v0.2    | Wiki Browser                   | 1.5w |
| v0.3    | LLM + Knowledge Base Infrastructure | 2w   |
| v0.4    | Summary Agent                  | 2w   |
| v0.5    | Fact-Check Agent               | 1.5w |
| v0.6    | Roleplay Agent                 | 2w   |
| v0.7    | Wiki Smart Linking             | 1w   |
| v0.8    | UI Polish + Animation          | 1.5w |
| v0.9    | Testing + Stability            | 1.5w |
| v1.0    | Official Release               | 1w   |

## Project Docs

- [Architecture Design & Implementation Plan](docs/implementation_plan.md) — full design doc
- [Git Guide](docs/GIT_GUIDE.md) — detailed branch/commit conventions
- [Agent Prompts](docs/AGENT_PROMPTS.md) — reusable prompts for AI-assisted development
- [v0.1 Task Breakdown](docs/v0.1_TASK_BREAKDOWN.md) — task plan for the first iteration
