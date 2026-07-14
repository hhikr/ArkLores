# ArkLores 中文 GameData 知识库重构方案

> 本文档定义 v0.4.5 的主知识库重构方向。ArkLores 后续以中文 GameData 解包数据作为主知识源，通过 GitHub release asset 在 App 内下载；Wiki 作为受限在线补充搜索，Book 作为用户导入辅助资料。

---

## 决策

| 问题 | 决策 |
|------|------|
| 知识库语言 | 只做中文 GameData |
| 分发方式 | 构建压缩 SQLite DB，作为 GitHub release asset 发布，App 内下载 |
| 主知识源 | GameData / 游戏原始文本 |
| 辅助知识源 | 指定 Wiki 在线搜索、用户导入 Book |
| 检索策略 | 结构化查询 + FTS + 标题/别名匹配优先，向量为补充 |
| 可信度优先级 | GameData > Wiki > Book |

---

## 范围

v0.4.5 优先覆盖中文数据：

- 角色基础档案
- 角色客观履历与档案资料
- 角色语音台词
- 干员密录 / 剧情文本
- 主线 / 活动剧情文本
- 组织、地点、事件可从文本和实体表逐步抽取
- 物品描述、信物、模组文本可作为后续扩展

不在 v0.4.5 首批范围：

- 多语言知识库
- 用户自定义 GameData 数据源
- 完整自动实体关系图谱
- 完全依赖向量检索的语义搜索

---

## 数据源分层

### GameData

GameData 是最高可信来源。Agent 在事实核查、剧情梗概和角色扮演中应优先引用 GameData。

常见 `source_type`：

- `game_story`
- `operator_profile`
- `operator_voice`
- `operator_record`
- `item_description`
- `faction_profile`
- `event_text`

### Wiki

Wiki 只作为补充搜索来源：

- 当 GameData 未覆盖某个别名、整理性说明或页面导航时调用。
- 当 Wiki 与 GameData 冲突时，以 GameData 为准。
- Wiki 引用必须明确标注站点。

### Book

Book 是用户导入资料：

- 可以作为补充参考。
- 无法被 GameData 或 Wiki 佐证时，必须提示“仅来自用户导入资料，建议自行核实”。

---

## SQLite Schema 草案

### `entities`

```sql
CREATE TABLE entities (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  aliases      TEXT,
  entity_type  TEXT NOT NULL,
  source_type  TEXT NOT NULL,
  game_version TEXT,
  updated_at   INTEGER
);
```

### `story_lines`

```sql
CREATE TABLE story_lines (
  id          TEXT PRIMARY KEY,
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
  id           TEXT PRIMARY KEY,
  source_type  TEXT NOT NULL,
  entity_id    TEXT,
  story_id     TEXT,
  page_title   TEXT,
  section      TEXT,
  content      TEXT NOT NULL,
  source_path  TEXT,
  line_start   INTEGER,
  line_end     INTEGER,
  speaker      TEXT,
  language     TEXT NOT NULL DEFAULT 'zh',
  game_version TEXT,
  updated_at   INTEGER
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

---

## 构建流程

```text
中文解包数据目录
  -> parse entities
  -> parse story lines
  -> parse operator profiles / voices / records
  -> normalize aliases and source paths
  -> write structured tables
  -> build lore_chunks
  -> build FTS index
  -> optional embedding generation
  -> validate fixed retrieval queries
  -> gzip DB
  -> write manifest
  -> publish release asset
```

建议输出：

- `arklores_gamedata_zh.db.gz`
- `gamedata_manifest.json`
- `gamedata_build_report.json`

Manifest 必须包含：

- schema version
- GameData source version / snapshot id
- language: `zh`
- row counts
- chunk counts by source type
- embedding profile metadata
- DB SHA256 and byte size

---

## App 安装流程

1. Knowledge Base 页面读取 bundled manifest。
2. 用户点击“下载中文 GameData 知识库”。
3. App 下载 release asset。
4. 校验 SHA256 和解压后大小。
5. 原子替换本地 DB。
6. 刷新知识库统计和 active source 状态。

旧 v0.3 Wiki DB 可以保留为临时/legacy profile，但 v0.4.5 之后不再作为默认主知识库。

---

## Agent 工具映射

| 工具 | 主数据源 | 说明 |
|------|----------|------|
| `search_local_lore` | GameData DB | FTS / 标题 / 结构化查询 / 向量扩展 |
| `get_entity_profile` | `entities` + profile chunks | 角色、组织、地点、事件的结构化资料 |
| `get_story_context` | `story_lines` + chunks | 按剧情、章节、speaker 获取上下文 |
| `search_wiki` | 指定 Wiki | 在线补充搜索，不作为默认主源 |
| `cite_source` | 所有来源 | 统一引用卡片数据 |

---

## 验收查询

发布 GameData DB 前必须验证：

- `阿米娅`
- `凯尔希`
- `罗德岛`
- `龙门`
- `莱茵生命`
- `第二次卡兹戴尔战争`
- `缪尔赛思`

最低标准：

- 实体查询 top 5 必须包含正确实体。
- 剧情查询 top 10 必须包含相关剧情原文或结构化事件。
- 低信息 chunk 不得主导 top-K。
- 引用必须能定位到 `source_path` 或剧情行号。

---

## 风险

- 解包数据格式可能随版本变化，需要 parser regression tests。
- DB 体积可能显著增加，需要 release asset 下载和断点/重试体验。
- GameData 版权和分发边界需要谨慎处理，README 中应避免官方授权暗示。
- 结构化 schema 需要支持迁移，避免每次更新都强制清空用户 Book 数据。
