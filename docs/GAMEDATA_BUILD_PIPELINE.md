# ArkLores GameData Build Pipeline

> 本文档定义中文 GameData DB（当前 schema 4，可选剧情向量表）的构建、索引、验收和
> GitHub Release 分发规范。v0.4.5 是 GameData-first 架构起点，不是本规范的版本上限。
> Agent 如何使用这些表见 `AI_ARCHITECTURE.md`。

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

## v1.0 前的数据产品缺口

当前 schema 2 DB 是可用的 Arknights 中文 GameData 快照，但还不是长期可维护的数据产品。
v1.0 前需要把以下问题独立立项，不能只靠重新上传一个 `.db.gz` 解决。

### 更新模式

后续 release asset 需要从“固定下载文件”升级为“可检查、可解释、可恢复”的更新模式：

- 远程 update manifest 必须描述 game、language、schema version、source commit、
  builder version、asset URL、压缩包 hash、解压后 hash、大小、发布时间、最低 App
  版本和迁移说明。
- App 应能展示当前安装 DB 的来源 commit、构建时间、schema 和覆盖游戏，并检查是否有
  新版本。
- 下载失败、hash mismatch、gzip 损坏、空间不足、schema 不兼容时必须保留旧有效 DB。
- 是否支持增量包需要基于真实体积和失败恢复成本决策。若 v1.0 仍只支持全量包，需记录
  下载体积、网络建议和用户可取消/重试行为。
- 每次数据刷新必须生成差异报告，至少包含实体增删、alias 改动、story scope 改动、
  记录计数变化、固定 QA 变化和 hash。

### App 内构建（R2，2026-08-24 落地）

除 release asset 外，App 提供第二条更新通道：直接从源仓库在设备上构建/增量更新
知识库（实现见 `lib/core/gamedata/build/`，编排见 `gamedata_build_provider.dart`）。
App 内构建不生成向量表（需要向量 API 与较长时间）；需要语义检索时使用 release 资产。

- 与桌面 release 管线共用同一份 importer / schema / coverage 构建代码（单一实现）；
- 首次：下载源仓库 zip（codeload），按 importer 白名单（18 个 excel +
  `zh_CN/gamedata/story/**/*.txt`，约 168 MB）选择性解压到 `gamedata_source/`；
- 增量：compare API 对比已装 commit 与最新 commit，逐文件 raw 下载/删除变更；
- DB 侧：全量构建或 per-file 删旧重导（按 `source_path`/`story_id`），随后全量重建
  coverage 与 FTS；产物经与 installer 相同的 `validateGameDataDatabase` 校验后原子替换；
- 构建在后台 isolate 运行（`sqflite_common_ffi` + `sqlite3_flutter_libs`），支持进度
  与取消；已安装库在替换前永不修改。

### 多游戏与终末地接入

当前 DB 的 `game` 字段已经存在，但 active importer 和 release asset 实际只覆盖
Arknights `zh_CN`。终末地接入不能只把文件塞进同一张表：

- 需要确认数据来源授权、稳定 ID、语言策略、版本号、source path 和 raw id 规则。
- 需要为 Endfield 单独建立 importer adapter、content category、entity type、story scope
  与固定 QA。
- App UI 和 Agent observation 必须明确区分 Arknights / Endfield 的证据来源；跨游戏查询
  需要显式范围，不能默认混搜导致错证据。
- 在 Endfield GameData 未完成前，终末地主题和 Wiki 浏览只代表阅读体验，不代表 AI
  已有终末地官方数据支持。

### 后续 schema 方向

schema 3 已落地实体级剧情倒排（`entity_story_mentions`）、章节画像与行级原文 FTS；
schema 4 跳过上游 `[uc]info/` 摘要桩树。仍待立项：

- 组织、阵营、概念和地点的汇总实体，而不只依赖干员档案里偶然出现的词。
- 关系索引，区分同场出现、称谓、身份、归属、敌对、时间线状态等可核查关系。
- 中文可用的 FTS（trigram 或分词器）；当前 unicode61 对中文基本无效。
- 更新质量标记，如 low coverage、ambiguous alias、generated aggregate、manual review needed。
- 多游戏、多语言和跨版本兼容字段，避免后续 Endfield 或其他语言接入时破坏现有 App。

### 剧情向量（可选表，R12）

向量是 GameData 的派生产物，与原文同库，不是第二知识库：

- 表 `story_chunk_vectors`：每块记录 `story_id`、起止行号、int8 量化向量与缩放系数；
  切块规则固定为 12 行一块、步长 8。schema 版本不变，没有该表的库照常可用。
- DB 内 `gamedata_manifest` 表写入 `embedding_model` / `embedding_dims` /
  `embedding_chunking`。App 只在设置中的向量配置与之一致时启用语义召回，否则回退关键词。
- 生成命令（可续跑，按内容哈希缓存到 `build/embedding_cache/`；API key 从
  gitignored 的 `tools/embedding-apiKey.csv` 读取）：

```bash
dart run tools/build_story_embeddings.dart --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

向量命中只是定位线索；最终证据仍必须回到 `story_id` 与行号对应的原文。

### 故事目录（可选表，R14）

`story_catalog` 给每个剧情文件补上人能读懂的位置和官方简介：

- 来源：`excel/story_review_table.json`（每个故事集的 `name` / `entryType`，每章的
  `storyCode`、`storyName`、`avgTag`、`storySort`、`storyTxt`、`storyInfo`）与
  `story/[uc]info/<storyInfo>.txt`（游戏剧情回顾里的一段官方简介）。`story_id = storyTxt + ".txt"`；
  同一文件出现在多个故事集时按 JSON 顺序取第一个，结果确定。
- 列：`story_id`、`collection_id`、`collection_name`、`collection_type`（ACTIVITY / MINI_ACTIVITY /
  MAINLINE / NONE=干员密录）、`story_code`、`story_name`、`avg_tag`、`story_sort`、`synopsis`、`synopsis_path`。
- 构建：全量与增量构建都在覆盖层之后整表重建（约 2000 行），并把章节名、梗概写进
  `story_chapter_profiles` 的 title / summary；manifest 记 `story_catalog_count`。
  `story_review_table.json` 已加入源白名单；`[uc]info` 变更只触发目录重建，绝不当剧情导入。
  源树里没有目录表（旧 App 内源码缓存）时保留库里现有目录。
- 给现有库补表（不重建、不动向量）：

```bash
git clone --depth 1 --filter=blob:none --sparse --no-checkout \
  https://github.com/Kengxxiao/ArknightsGameData.git agd
cd agd && git sparse-checkout set --no-cone \
  "/zh_CN/gamedata/excel/story_review_table.json" "/zh_CN/gamedata/story/[[]uc]info/" \
  && git checkout && cd ..
dart run tools/build_story_catalog.dart --db=build/gamedata_mobile/arklores_gamedata_zh.db --source=agd
```

目录与梗概只是浏览/定位线索，不参与事实判定。

## SQLite Schema

当前 schema version 为 `4`，App 安装器拒绝其他版本。下面列出 v2 起的基础表；
v3 新增的覆盖层表（`entity_story_mentions`、`story_chapter_profiles`、`rare_terms`、
`story_lines_fts`）与可选向量表的 DDL 以 `lib/core/gamedata/build/gamedata_schema.dart`
和 `lib/core/gamedata/story_vectors.dart` 为准。

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

# 全量构建已包含故事目录（R14）；给旧库补目录用 tools/build_story_catalog.dart
# 可选：剧情向量（v0.10.0 起 release 资产包含该表）
/home/hhikr/flutter/bin/dart run tools/build_story_embeddings.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db

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
- 库内含向量表时：`embedding` 段（model / dims / chunking / 向量行数）

Windows 上命令相同，把 `/home/hhikr/flutter/bin/` 换成 `C:\src\flutter\bin\`（已在 PATH 中，
可直接写 `dart` / `flutter`）；Windows 没有 gzip，用 PowerShell 的 .NET `GZipStream` 压缩。

### v0.10.0 发布步骤（R12）

1. 以 schema 4 库（2026-08-24 构建）为基础运行 `build_story_embeddings`，得到含 51,264 条
   向量的库；固定检索 QA 与 `flutter test` 通过。
2. gzip → `finalize_gamedata_assets.dart` 写入 SHA-256 与 `embedding` 段。
3. 用 API 创建 **draft** release，上传 `.db.gz` 与 `gamedata_manifest.json`。
4. 以资产 URL 和 SHA 构建 APK（`--dart-define=ARKLORES_GAMEDATA_DB_URL=… --dart-define=ARKLORES_GAMEDATA_DB_SHA256=…`），
   上传后由开发者发布。向量是可选功能：设置中配置百炼 key（`qwen3.7-text-embedding@512`）
   才启用语义召回，否则自动退回关键词检索。

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
