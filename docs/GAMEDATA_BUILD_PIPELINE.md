# ArkLores GameData Build Pipeline

> 本文档定义当前 schema 2 中文 GameData DB 的构建、FTS 索引、验收和 GitHub Release
> 分发规范。v0.4.5 是 GameData-first 架构起点，不是本规范的版本上限。

内容分类、普查和 importer 覆盖范围由本文统一定义。

## 内容分类与普查原则

解包数据进入 importer 前必须先遍历文件树、识别中文剧情/档案/描述/语音来源、建立层级
分类，再转换成 normalized records；不能直接从原始 JSON/TXT 生成无 provenance 的 chunk。

分类同时保存层级 `content_category/content_subtype` 和便于 SQLite 过滤的扁平
`content_type`。当前主要枚举如下：

| Category | 主要 content type | 典型来源 |
| --- | --- | --- |
| `operator` | basic/profile/voice/record/module/skin | character、handbook、charword、uniequip、memory |
| `story` | main/activity/side/mini/tutorial/review/record | story TXT、story/review tables |
| `roguelike` | topic/ending/monthly/collectible/stage/event/mechanic | roguelike tables、rogue story/levels |
| `world_item` | item/material/collectible/medal/skin/module description | item、medal、skin、uniequip tables |
| `enemy` | profile/race/level data | enemy handbook、enemydata |
| `stage` | stage/zone/campaign/activity-zone/tutorial description | stage、zone、campaign、levels |
| `activity` | basic/mission/rule/reward/archive | activity、retro、mission、activity story |
| `sandbox` | story/ending/stage/item/event/mechanic | sandbox tables、story、levels |
| `system_text` | worldview/loading/UI/building/base-skill text | tip、main/init text、building data |

基准源快照普查为 10634 个文件、5999 个含中文文本文件，其中 story 5606、Excel JSON 57、
levels JSON 3743、bakemuzzledata JSON 702；`story_table.json` 的 2368 个条目与 TXT 在大小写
归一后无缺失。`levels/`、`bakemuzzledata/`、`building/` 和 `[uc]lua/` 不得仅按目录整体
导入或排除，应使用 `tools/audit_arknights_gamedata_files.py` 的目录分布、review packets 和
CSV 明细人工复核，并标记 `core/candidate/low/exclude`。

需要表达的主要层级关系包括 activity 到 stage/story/item、operator 到 voice/profile/
record story、roguelike topic 到 monthly squad/ending/collectible/stage、sandbox activity 到
stage/story、enemy race 到 enemy，以及 zone 到 stage。关系写入 `entity_relations`，不可只靠
路径字符串推断。

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

终末地数据不属于当前 active knowledge source，也不阻塞当前版本。以下仅为历史候选，
在来源协议、授权和 importer 另行立项前不得接入默认 Agent 检索：

- `3aKHP/EndFieldGameData` release asset `endfield-tables.zip`
- `wuyilingwei/EndfieldGameData` raw `TableCfg/*.json`

## SQLite Schema

当前 schema version 为 `2`。v2 为剧情 chunk 增加通用 `scope_type/scope_id`，并新增
`story_scopes`；旧 schema DB 不包含可靠剧情范围，App 安装器会拒绝替换。

### `story_scopes`

```sql
CREATE TABLE story_scopes (
  story_id    TEXT PRIMARY KEY,
  scope_type  TEXT NOT NULL,
  scope_id    TEXT NOT NULL,
  source_path TEXT NOT NULL
);
```

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
  scope_type     TEXT,
  scope_id       TEXT,
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

当前 GameData DB 的检索质量由以下结构保证：

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

## 构建与 finalization 命令

```bash
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart \
  --arknights-source=/path/to/ArknightsGameData \
  --output=build/gamedata_mobile \
  --force

gzip -c build/gamedata_mobile/arklores_gamedata_zh.db \
  > build/gamedata_mobile/arklores_gamedata_zh.db.gz

HOME=/tmp /home/hhikr/flutter/bin/dart run tools/finalize_gamedata_assets.dart \
  --output=build/gamedata_mobile

HOME=/tmp /home/hhikr/flutter/bin/dart run tools/check_gamedata_retrieval.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

builder 当前只接受 `--arknights-source`、`--output`、`--force` 和 smoke 专用的
`--story-limit=N`；语言固定为中文，不存在 `--language` 参数。`--story-limit` 产物不能用于
finalized 完整 DB retrieval QA。

`tools/finalize_gamedata_assets.dart` 在 gzip 后更新
`gamedata_manifest.json` 与 `gamedata_build_report.json`，写入：

- compressed / uncompressed byte sizes
- compressed / uncompressed SHA-256
- release asset file names
- finalization timestamp

## 未发布版本的真机测试

未发布开发版本不能假设同版本 GitHub Release asset 已存在。开发测试使用同一安装链路，
但通过构建参数注入临时下载地址：

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

## 固定验收查询

- `阿米娅`
- `阿米娅 语音`
- `阿米娅 主线`
- `莱茵生命`
- `萨卡兹王庭`
- `特蕾西娅`
- `源石技艺`
- `肉鸽`
- `集成战略 收藏品`
- `敌人介绍`
- `干员秘录`

最低标准：

- 实体查询 top 5 命中正确实体或档案 chunk。
- 剧情查询 top 10 命中原文或结构化剧情行。
- `normalized_records` 能按 `content_type` 区分 `operator_voice`、`enemy_profile`、`roguelike_topic`、`sandbox_item` 等来源。
- 默认 Agent evidence 只能来自 GameData；Wiki、Book 和用户文本不是候补官方证据源。
- 引用能回到 `source_path` 和行号。
- `特蕾西娅` 至少返回两个 alias candidates。
- `act21mini + 米格鲁 + 死亡` scoped evidence 命中固定剧情原文。

固定查询及预期的唯一维护入口是 [RETRIEVAL_QA.md](RETRIEVAL_QA.md) 和
`tools/check_gamedata_retrieval.dart`；本节只概述 release gate，二者冲突时必须先修正文档或
工具再验收，不能静默选择更宽松的一方。
