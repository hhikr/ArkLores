# ArkLores GameData Build Pipeline

> 本文档定义 v0.4.5 GameData DB 的构建、向量化和 GitHub Release 分发规范。

## 目标产物

每个 ArkLores Release 至少包含：

- `ArkLores-<version>.apk`
- `arklores_gamedata_zh.db.gz`
- `gamedata_manifest.json`
- `gamedata_build_report.json`

`arklores_gamedata_zh.db.gz` 是 App 下载和安装的主知识库资产，必须包含原文和向量。

## 输入源

### 明日方舟

- Community repo: `Kengxxiao/ArknightsGameData`
- Branch: `master`
- Language path: `zh_CN`
- Source kind: community unpack repository

首批导入路径：

- `zh_CN/gamedata/excel/character_table.json`
- `zh_CN/gamedata/excel/handbook_info_table.json`
- `zh_CN/gamedata/excel/charword_table.json`
- `zh_CN/gamedata/excel/item_table.json`
- `zh_CN/gamedata/excel/story_table.json`
- `zh_CN/gamedata/story/**/*.txt`

### 终末地

v0.4.5 不阻塞。后续候选：

- `3aKHP/EndFieldGameData` release asset `endfield-tables.zip`
- `wuyilingwei/EndfieldGameData` raw `TableCfg/*.json`

## SQLite Schema

### `gamedata_manifest`

```sql
CREATE TABLE gamedata_manifest (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

### `entities`

```sql
CREATE TABLE entities (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  aliases      TEXT,
  entity_type  TEXT NOT NULL,
  source_type  TEXT NOT NULL,
  game         TEXT NOT NULL,
  source_path  TEXT,
  game_version TEXT,
  updated_at   INTEGER
);
```

### `story_lines`

```sql
CREATE TABLE story_lines (
  id          TEXT PRIMARY KEY,
  game        TEXT NOT NULL,
  story_id    TEXT NOT NULL,
  episode_id  TEXT,
  event_id    TEXT,
  speaker     TEXT,
  content     TEXT NOT NULL,
  line_index  INTEGER,
  language    TEXT NOT NULL DEFAULT 'zh',
  source_path TEXT
);
```

### `lore_chunks`

```sql
CREATE TABLE lore_chunks (
  id             TEXT PRIMARY KEY,
  game           TEXT NOT NULL,
  source_type    TEXT NOT NULL,
  entity_id      TEXT,
  story_id       TEXT,
  page_title     TEXT,
  section        TEXT,
  content        TEXT NOT NULL,
  source_path    TEXT,
  source_url     TEXT,
  line_start     INTEGER,
  line_end       INTEGER,
  speaker        TEXT,
  language       TEXT NOT NULL DEFAULT 'zh',
  game_version   TEXT,
  updated_at     INTEGER,
  retrieval_hint TEXT
);
```

### `chunk_embeddings`

```sql
CREATE TABLE chunk_embeddings (
  chunk_id   TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  dimension  INTEGER NOT NULL,
  embedding  BLOB NOT NULL,
  PRIMARY KEY (chunk_id, profile_id)
);
```

### FTS

```sql
CREATE VIRTUAL TABLE lore_chunks_fts USING fts5(
  page_title,
  section,
  speaker,
  content,
  content='lore_chunks',
  content_rowid='rowid'
);
```

## Embedding

默认 profile:

- `profile_id`: `builtin:builtin-embedding`
- `dimension`: `512`
- runner: `tool/embed_seed_database.py` 的同款 TFLite runner 或后续替换的中文检索模型

构建要求：

- release DB 不允许只带 `pending_embedding`。
- `lore_chunks` 中可检索 chunk 必须有对应 `chunk_embeddings`。
- 如果 Linux 构建机缺少 TFLite runtime，构建应失败并记录，不发布缺向量 DB。

## 构建命令草案

```bash
dart run tool/build_gamedata_database.dart \
  --arknights-source=/path/to/ArknightsGameData \
  --output=build/gamedata \
  --language=zh \
  --force

python3 tool/embed_gamedata_database.py \
  --db=build/gamedata/arklores_gamedata_zh.db

gzip -c build/gamedata/arklores_gamedata_zh.db \
  > build/gamedata/arklores_gamedata_zh.db.gz
```

## Manifest

`gamedata_manifest.json` 必须包含：

- schema version
- build time
- language
- source repo URL
- source branch
- source commit SHA
- row counts
- chunk counts by source type
- embedding profile id
- embedding dimension
- compressed DB SHA-256
- compressed / uncompressed byte sizes

## 首批验收查询

- `阿米娅`
- `凯尔希`
- `罗德岛`
- `龙门`
- `莱茵生命`
- `第二次卡兹戴尔战争`
- `缪尔赛思`

最低标准：

- 实体查询 top 5 命中正确实体或档案 chunk。
- 剧情查询 top 10 命中原文或结构化剧情行。
- GameData 结果优先级高于 Wiki / Book。
- 引用能回到 `source_path` 和行号。

