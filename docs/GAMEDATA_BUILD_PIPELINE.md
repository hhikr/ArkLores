# ArkLores GameData Build Pipeline

> 本文档定义 v0.4.5 GameData DB 的构建、FTS 索引和 GitHub Release 分发规范。

内容分类和 importer 覆盖范围必须遵循
[ARKNIGHTS_GAMEDATA_CONTENT_TAXONOMY.md](ARKNIGHTS_GAMEDATA_CONTENT_TAXONOMY.md)。

## 目标产物

每个 ArkLores Release 至少包含：

- `ArkLores-<version>.apk`
- `arklores_gamedata_zh.db.gz`
- `gamedata_manifest.json`
- `gamedata_build_report.json`

`arklores_gamedata_zh.db.gz` 是 App 下载和安装的主知识库资产，必须包含原文、
结构化表、检索元数据和 FTS 索引。

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
- `zh_CN/gamedata/excel/skin_table.json`
- `zh_CN/gamedata/excel/medal_table.json`
- `zh_CN/gamedata/excel/uniequip_table.json`
- `zh_CN/gamedata/excel/enemy_handbook_table.json`
- `zh_CN/gamedata/excel/stage_table.json`
- `zh_CN/gamedata/excel/zone_table.json`
- `zh_CN/gamedata/excel/campaign_table.json`
- `zh_CN/gamedata/excel/activity_table.json`
- `zh_CN/gamedata/excel/retro_table.json`
- `zh_CN/gamedata/excel/mission_table.json`
- `zh_CN/gamedata/excel/roguelike_table.json`
- `zh_CN/gamedata/excel/roguelike_topic_table.json`
- `zh_CN/gamedata/excel/sandbox_table.json`
- `zh_CN/gamedata/excel/sandbox_perm_table.json`
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

### `normalized_records`

`normalized_records` 是 importer adapter 的 canonical 输出层。原始 JSON / txt
先归一化到 record，再派生 `lore_chunks`。

```sql
CREATE TABLE normalized_records (
  id             TEXT PRIMARY KEY,
  game           TEXT NOT NULL,
  language       TEXT NOT NULL DEFAULT 'zh',
  category       TEXT NOT NULL,
  subtype        TEXT NOT NULL,
  content_type   TEXT NOT NULL,
  entity_id      TEXT,
  entity_name    TEXT,
  parent_id      TEXT,
  parent_type    TEXT,
  title          TEXT,
  section        TEXT,
  speaker        TEXT,
  content        TEXT NOT NULL,
  source_path    TEXT NOT NULL,
  raw_id         TEXT,
  line_start     INTEGER,
  line_end       INTEGER,
  source_repo    TEXT,
  source_commit  TEXT,
  game_version   TEXT,
  updated_at     INTEGER
);
```

### `entity_relations`

```sql
CREATE TABLE entity_relations (
  id               TEXT PRIMARY KEY,
  source_entity_id TEXT NOT NULL,
  target_entity_id TEXT NOT NULL,
  relation_type    TEXT NOT NULL,
  source_path      TEXT,
  raw_id           TEXT
);
```

### `lore_chunks`

```sql
CREATE TABLE lore_chunks (
  id             TEXT PRIMARY KEY,
  game           TEXT NOT NULL,
  source_type    TEXT NOT NULL,
  content_category TEXT,
  content_subtype  TEXT,
  content_type     TEXT,
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
  raw_id         TEXT,
  retrieval_hint TEXT
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

## Retrieval Contract

v0.4.5 GameData DB 的检索质量由以下结构保证：

- `entities` / `entity_aliases` 支持 canonical entity lookup。
- `entity_documents` 提供面向 Agent 的聚合主文档。
- `entity_documents_fts` 负责实体摘要类关键词检索。
- `lore_chunks_fts` 负责剧情原文和片段检索。
- `normalized_records` 保留 importer 输出和引用元数据。
- LIKE fallback 覆盖 Android SQLite FTS tokenizer 差异。

构建失败条件：

- `entity_documents` 为空。
- `entity_documents_fts` 或 `lore_chunks_fts` 缺失。
- 固定验收查询不能命中预期实体或原文。
- manifest 缺少源仓库、commit、row counts、DB hash 或 schema version。

## 构建命令草案

```bash
dart run tools/build_gamedata_database.dart \
  --arknights-source=/path/to/ArknightsGameData \
  --output=build/gamedata \
  --language=zh \
  --force

gzip -c build/gamedata/arklores_gamedata_zh.db \
  > build/gamedata/arklores_gamedata_zh.db.gz

HOME=/tmp /home/hhikr/flutter/bin/dart run tools/finalize_gamedata_assets.dart \
  --output=build/gamedata
```

`tools/finalize_gamedata_assets.dart` 在 gzip 后更新
`gamedata_manifest.json` 与 `gamedata_build_report.json`，写入：

- compressed / uncompressed byte sizes
- compressed / uncompressed SHA-256
- release asset file names
- finalization timestamp

## 未发布版本的真机测试

正式 v0.4.5 发布前，App 不能依赖“当前版本已有 GitHub Release
asset”。开发测试使用同一安装链路，但通过构建参数注入临时下载地址：

```bash
/home/hhikr/flutter/bin/flutter run \
  --dart-define=ARKLORES_GAMEDATA_DB_URL=http://<LAN-IP>:8000/arklores_gamedata_zh.db.gz \
  --dart-define=ARKLORES_GAMEDATA_DB_SHA256=<compressed-db-sha256>
```

可选临时分发方式：

- 本机启动局域网 HTTP 服务，手机与电脑在同一网络。
- 上传到 GitHub pre-release asset，使用公开下载 URL。
- 不建议使用 draft release asset，因为 App 侧没有 GitHub token，不应在客户端内置 token。

未提供 `ARKLORES_GAMEDATA_DB_URL` 时，知识库页面会显示 GameData
未安装，并提示当前构建未配置下载地址；这不是业务失败，而是未发布版本的预期状态。

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
- normalized record counts
- FTS table names and indexed row counts
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
- `normalized_records` 能按 `content_type` 区分 `operator_voice`、`enemy_profile`、`roguelike_topic`、`sandbox_item` 等来源。
- GameData 结果优先级高于 Wiki / Book。
- 引用能回到 `source_path` 和行号。
