# ArkLores Implementation Plan

## 2026-07 Architecture Decision

ArkLores v0.4.5 主线使用中文 GameData release asset 作为主知识源。

可信度策略：

1. GameData / 游戏原始文本
2. 指定 Wiki
3. 用户导入 Book

当前代码主线只实现 GameData 本地结构化检索。Wiki 保留为浏览与人工补充入口；Book 路线暂停，后续重新设计。

## v0.4.5 Goals

- 稳定 ReAct Loop。
- 稳定 Summary Agent MVP。
- 构建中文 GameData 结构化 DB。
- App 内下载并安装 GameData DB。
- Agent observation 带来源、内容类型、source path、raw id、可信度提示。
- 空库、无结果、低覆盖给出清晰提示。

## Knowledge Source

GameData DB 由 `tools/build_gamedata_database.dart` 从社区解包仓库构建。

Release asset：

```text
arklores_gamedata_zh.db.gz
```

开发期可用：

```text
--dart-define=ARKLORES_GAMEDATA_DB_URL=<url>
--dart-define=ARKLORES_GAMEDATA_DB_SHA256=<sha256>
```

## Database Schema

- `gamedata_manifest`
- `entities`
- `entity_aliases`
- `entity_documents`
- `normalized_records`
- `story_lines`
- `lore_chunks`
- `entity_documents_fts`
- `lore_chunks_fts`

## Retrieval Order

1. Structured entity lookup.
2. Alias lookup.
3. Entity document exact / LIKE.
4. Entity document FTS.
5. Lore chunk FTS.
6. Normalized record / lore chunk LIKE fallback.

## Agent Infrastructure

Main tool:

```text
search_local_lore
```

ReAct Loop requirements:

- tolerate loose Action Input maps;
- reject empty final answer;
- surface truncated model output;
- protect against unsupported source claims.

## App Behavior

- Settings: Chat API only.
- Knowledge Base: GameData DB download/status only.
- Materials: paused state until user material source strategy is redesigned.
- AI Summary: GameData structured local search.

## Verification

Required for relevant changes:

```bash
/home/hhikr/flutter/bin/flutter test test/agent_test.dart
/home/hhikr/flutter/bin/dart analyze <changed files>
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
```

GameData smoke build:

```bash
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart \
  --arknights-source=/tmp/ArkLores-ArknightsGameData \
  --output=/tmp/arklores_gamedata_smoke \
  --force \
  --story-limit=1
```
