# ArkLores AI 检索优化：现状与计划

> 本文档记录 AI 检索与 Agent 问答链路的现状、已识别缺陷，以及完整的优化计划。
> 本文档不修改、不删除现有文档；阶段落地后按项目约定更新 `RETRIEVAL_QA.md` 与
> `KNOWN_LIMITATIONS_AND_DEBT.md`，并在本文档标注完成情况。

> 阶段状态：
> - **阶段 P0（确定性覆盖层）：已完成（2026-08-24，对应开发轮次 R1）**。
>   schema v3 四张新表（`entity_story_mentions` / `story_chapter_profiles` /
>   `rare_terms`）与 `story_lines_fts`、构建第 5 阶段（`StoryCoverageBuilder`）、
>   三个新工具（`search_story_coverage` / `read_story_lines` / `get_story_map`）、
>   Summary 叙事工作流与已读范围报告校验均已实现并通过 QA（16 项新增测试 +
>   全量 86 项回归 + 合成 5 章 fixture + 固定检索 QA 全绿）。落地细节见
>   `R1_STORY_COVERAGE_LAYER_SUMMARY.md`。
> - **阶段 P1（跨章节细节定位与多候选对比）：核心与 UI 接线已完成（2026-08-24，开发轮次 R3/R3b）**。
>   speaker 覆盖扩展、`find_detail_echoes` / `collect_suspect_evidence` 两个工具、
>   StoryInvestigationAgent（S0–S8）、`validateInvestigationVerdict` 三道代码门槛
>   （S6 / 行级 provenance / 已读范围）、ReActLoop 观察历史裁剪、以及"剧情调查"tab
>   （结论条 + 证据链引用 + 已读范围条渲染，§5.4）均已实现并通过 QA（16 项新增
>   测试 + 全量 111 项回归）。设计决策见 `R3_DESIGN_DECISIONS.md`，落地细节见
>   `R3_INVESTIGATION_LAYER_SUMMARY.md`。
>   **剩余（R3b 收尾）**：2–3 个真实剧情谜题固定用例与单次调查成本量化。
> - **阶段 P2（可选增强）：未开始。**

## 1. 现状

### 1.1 知识库结构（schema 2）

当前主知识源为中文 GameData SQLite 数据库（schema 2），由 `tools/build_gamedata_database.dart`
从 Kengxxiao/ArknightsGameData（`zh_CN`）构建，gzip 后作为 GitHub Release asset 分发，
App 端下载、校验 SHA-256、验证 schema 后替换安装。

与剧情检索相关的表：

| 表 | 内容 | 规模（v0.9.0 manifest） |
| --- | --- | --- |
| `entities` | 实体（干员、敌人、物品等）与别名 | 17,680 |
| `entity_aliases` | 别名到实体映射 | - |
| `entity_documents` | 按实体聚合的档案文档 | 833 |
| `story_lines` | 剧情逐行原文（speaker、line_index、source_path） | 406,279 行 |
| `story_scopes` | story 到 scope（activity/main 等）的映射 | - |
| `normalized_records` | 结构化文本记录 | 95,362 |
| `entity_relations` | 实体关系（当前 App 查询利用有限） | 17,861 |
| `lore_chunks` | 统一检索片段（含 provenance） | 99,857 |
| `entity_documents_fts` / `lore_chunks_fts` | FTS5 外部内容索引 | - |

`story_lines` 目前仅由构建工具写入、安装器校验必需表清单与固定 QA 使用；
Agent 检索链路（`GameDataKnowledgeStore`）不直接读取该表。

### 1.2 检索链路

Agent 唯一检索工具为 `search_local_lore`（`lib/core/agent/tools/search_local_lore.dart`），
参数包括 `query`、`top_k`（默认 5、上限 10）、`content_type`、`entity_id`、`scope_id`、
`search_mode`（general / summary / roleplay / evidence）。观察结果受预算限制：
总字符上限 4800，单条 excerpt 上限 700 字符。

`GameDataKnowledgeStore`（`lib/core/gamedata/gamedata_knowledge_store.dart`）按以下顺序
多阶段检索并以 ID 去重：实体与别名结构化查询 → 实体聚合文档 → 剧情上下文（summary /
roleplay 模式）→ 实体绑定 chunk 与 record → entity document FTS 与 LIKE →
normalized record 多词 AND LIKE → story intent chunk → lore chunk FTS 与 LIKE →
指定 content type 宽回退。检索前由 `GameDataQueryPlan` 做空白规范化、content type
推断、意图词移除（剧情/梗概/档案）与同义词扩展（肉鸽→集成战略、语音→
operator_voice、秘录→operator record 等）。

`search_mode=evidence` 且同时提供 `scope_id` 与 `entity_id` 时进入 scoped story evidence
路径：限定 `source_type='game_story'` 且 scope 相等的 chunk，要求正文包含实体名与
全部关系词，取最多 200 个候选后在 Dart 内按实体名与关系词的最短字符距离排序。

### 1.3 Agent 编排

`ReActLoop`（`lib/core/agent/react_loop.dart`）默认 5 轮迭代、单步 2048 tokens、
`minimumToolCalls=0`；Fact-check 使用 7 轮、4096 tokens、最少 1 次工具调用。最终回答
以 120 字符分块输出。三个 Agent（Summary / Fact-check / Role-play）都只注册
`search_local_lore`，工具注册表不提供其他来源工具。

已有代码级约束：

- Fact-check 的 supported/refuted 结论必须能在 observations 中找到 GameData 记录，
  否则降级为 uncertain/unavailable（`lib/core/agent/fact_check_agent.dart` 的
  `validateFactCheckVerdict`）。
- 最终回答的来源声明与 observations 交叉校验（`evidence_summary.dart` 的
  `applySourceGuard`）。
- Role-play 解析到稳定 `entity_id` 后才创建角色绑定检索工具。
- `AgentLogger` 仅 debug 构建启用，已做内容截断与日志轮转清理。

### 1.4 证据展示

`evidence_observation.dart` 将 observation 中的 GameData result block 解析为证据卡
（title、section、content type、source path、raw id、retrieval type、ranking reason、
trust、excerpt），非 GameData 或字段不完整的 block 不会显示为证据卡。覆盖度标签仅
表达检索类型，不表达事实置信度。

### 1.5 已识别缺陷

1. **词面匹配局限**：检索依赖字面匹配（FTS/LIKE），剧情文本中的艺术化表达与检索词
   不一致时召回失败。
2. **检索量限制**：top-K 上限 10、excerpt 700 字符、observation 4800 字符，Agent 无法
   获取完整剧情原文（`story_lines` 未暴露给 Agent）。
3. **查询由模型自行决定**：模型可能使用狭窄复合查询（如"实体名+死亡"）而非先枚举
   实体全部出场；复合查询无结果时还可能被误读为反证（现有 prompt 与 evidence 模式
   已部分约束，但依赖模型行为）。
4. **误导性内容占比高**：当答案依赖少量早期伏笔、而大量中间章节指向错误方向时，
   基于相似度排序的检索会把误导内容排在前面，伏笔得不到召回。
5. **跨章节多跳推理**：答案需要跨章节对齐细节（凶器、行为模式、措辞）才能推出，
   现有检索返回独立片段，无法支撑该推理。
6. **锚定偏差**：模型读到的多数内容指向同一错误结论时，倾向于接受该结论，缺少
   显式的反方证据对比机制。

## 2. 问题定义

目标问题形态：跨章节多跳的因果/凶手类提问（例如"某角色死亡的罪魁祸首是谁"）。
该形态具有四个特征：

1. 相关原文总量远超任何模型上下文（`story_lines` 约 40 万行，估算千万 token 级）。
2. 关键伏笔可能只有一句，且不含受害者姓名或"死亡"字样；大量中间章节为误导内容。
3. 答案需要跨章节、跨时间线的细节对齐才能推出，属于推理而非抽取。
4. 模型存在接受多数内容的倾向，需要反方证据对比。

长篇叙事多跳推理的失败模式是已知研究问题（NovelHopQA、SagaQA 等 benchmark 均在
量化该失败模式）。本计划的工程目标是：保证相关原文与跨章节细节可达、结论必须附
证据链与已读范围、覆盖缺口透明；不承诺艺术性谜底的完全可靠。

## 3. 优化计划总览

检索模型从"相似度 top-K 检索驱动"调整为"出场覆盖 + 跨章节细节匹配 + 多候选对比"：

- **出场覆盖**：以实体出场倒排表保证"某实体出现在哪些章节哪些行"可被确定性枚举，
  与检索词怎么写无关。
- **跨章节细节匹配**：从已知段落提取少见特征词，在全库检索其他出现位置，用于定位
  跨章节呼应的细节（如凶器、特殊行为描述）。
- **多候选对比**：对每个候选分别收集证据集，再比较完整性与矛盾，避免单一来源
  （含误导章节）主导结论。

向量化召回不作为主检索路径；仅在后续阶段作为跨章节细节匹配的语义补充，且按
`RETRIEVAL_QA.md` 的 Hybrid 基准执行门禁。

计划分三个阶段：P0 确定性覆盖层、P1 跨章节细节定位与多候选对比、P2 可选增强
（向量化召回、LLM 章节摘要、时间线注册表，全部走门禁）。

## 4. 阶段 P0：确定性覆盖层

### 4.1 schema 新增（additive，不修改现有表）

```sql
-- 实体出场倒排：实体在哪些 story/scope 的哪些行区间出现
CREATE TABLE entity_story_mentions (
  entity_id     TEXT NOT NULL,
  story_id      TEXT NOT NULL,
  scope_id      TEXT NOT NULL,
  line_start    INTEGER NOT NULL,
  line_end      INTEGER NOT NULL,   -- 连续命中合并为 run
  mention_count INTEGER NOT NULL,
  matched_alias TEXT,
  PRIMARY KEY (entity_id, story_id, line_start)
);
CREATE INDEX idx_mentions_scope ON entity_story_mentions(scope_id, story_id);

-- 章节画像：每 story 文件的元数据（用于定位精读范围，不作为证据）
CREATE TABLE story_chapter_profiles (
  story_id       TEXT PRIMARY KEY,
  scope_id       TEXT NOT NULL,
  title          TEXT,
  line_start     INTEGER NOT NULL,
  line_end       INTEGER NOT NULL,
  speaker_set    TEXT,   -- JSON
  entity_density TEXT,   -- JSON: entity_id -> mention_count（top N）
  summary        TEXT,   -- 默认 extractive 摘要
  keyword_hits   TEXT    -- JSON: 死亡/凶案类词典命中（仅 triage 提示）
);
CREATE INDEX idx_profiles_scope ON story_chapter_profiles(scope_id);

-- story_lines 行级全文索引（外部内容表，tokenizer 与现有 FTS 一致）
CREATE VIRTUAL TABLE story_lines_fts USING fts5(
  content, content='story_lines', content_rowid='rowid'
);

-- 稀有特征词：跨章节细节匹配的 IDF 依据（仅保留低频词）
CREATE TABLE rare_terms (
  term     TEXT PRIMARY KEY,
  doc_freq INTEGER NOT NULL   -- 出现该词的 story 文件数，阈值 <= 20
);
```

实现注意：`story_lines` 当前为 TEXT 主键，SQLite 默认保留隐式 rowid，外部内容 FTS
可用；构建时需确认。若不可用，改为显式整数主键并同步更新引用。

### 4.2 构建工具变更（`tools/build_gamedata_database.dart`）

现有四阶段导入（角色档案、语音、结构化表、剧情）之后新增第五阶段：

1. 用实体 canonical name 与全部 alias 构建 trie，单遍扫描 `story_lines.content`，
   连续命中合并为行区间写入 `entity_story_mentions`（估计 20–50 万行，对 DB 体积
   影响可忽略）。
2. 每个 story 文件统计 speaker 集合、实体密度、死亡/凶案类词典命中，生成章节画像
   写入 `story_chapter_profiles`；`summary` 默认取实体密度与稀有词密度最高的句子
   （确定性、可复现）。
3. 重建 `story_lines_fts`。
4. 对 story 文件内容取字符 bigram（不做分词），统计跨文件 doc_freq，仅保留
   `doc_freq <= 20` 的条目写入 `rare_terms`。
5. 更新 manifest 与 `finalize_gamedata_assets.dart`：新增表计数与 hashes。

### 4.3 新工具（注册进 ToolRegistry）

| 工具 | 参数 | 返回 |
| --- | --- | --- |
| `search_story_coverage` | `entity_id` 或 `query`（走现有消歧）；可选 `scope_filter` | 实体全部出场：scope_id、story_id、title、行区间、mention_count |
| `read_story_lines` | `story_id`、`start_line`、`end_line` 或 `max_lines`；`page_token` | 原文行（line_index、speaker、content）与 `next_page_token`；受预算约束 |
| `get_story_map` | `story_ids` 列表或 `scope_id` | 各章节画像字段 |

三个工具均为纯 SQL，无模型调用；observation 复用现有预算与"未安装/无结果"区分。
分页通过 observation 返回的 `next_page_token` 由模型在下一轮调用时回传，不引入
服务端状态。

### 4.4 Agent 工作流与已读范围报告

对叙事类问题（由 query plan 的 story intent 或问题类型判定触发），Agent 流程改为：
先 `search_story_coverage` 枚举出场 → `get_story_map` 选择精读范围 →
`read_story_lines` 通读关键章节。回答末尾必须输出已读范围报告：

```text
Coverage: read=<实际精读 scope 数> | mapped=<仅浏览画像的 scope 数> | skipped=<未读+原因>
```

`finalAnswerTransform` 将报告字段与实际工具调用结果比对，不允许模型虚构已读范围。

### 4.5 QA 与验收

- **合成 fixture**：5 章小故事，第 1 章一句不含受害者姓名与"死亡"字样的伏笔，
  第 2–3 章误导指向角色 A，第 5 章过去时间线揭示角色 B。断言：coverage 返回全部
  出场章节；`read_story_lines` 可拉任意行区间并分页；Agent 回答包含真实行引用，
  已读范围报告与实际调用一致。
- **单元测试**：倒排表 run 合并、章节画像统计、rare_terms 提取过滤。
- **回归**：现有 `test/agent_test.dart`、widget 测试、固定检索 QA（含
  act21mini+米格鲁+死亡 scoped evidence）全部通过；`flutter analyze` 无问题。
- **验收标准**：任意实体 query 可枚举全部出场；`read_story_lines` 支持任意行区间
  与分页；合成 fixture 通过；旧功能不回归。

## 5. 阶段 P1：跨章节细节定位与多候选对比

### 5.1 新工具

| 工具 | 参数 | 返回 |
| --- | --- | --- |
| `find_detail_echoes` | `source_text`（或 `story_id`+行区间）、`max_terms`、`max_results` | 提取少见特征词，检索 `story_lines_fts`（长度不足 3 字符的词用 `content` LIKE 回退），返回 term、story_id、行号、snippet |
| `collect_suspect_evidence` | `entity_id`、可选 `scope_ids`、可选 `claim_terms` | 经 `entity_story_mentions` 返回该实体全部出场行，按 scope 分组、分页 |

### 5.2 跨章节推理工作流（StoryInvestigationAgent）

基于现有 ReActLoop，定义阶段协议；每阶段前置条件由工具返回计数校验（代码级，
不依赖 prompt）：

```text
S0 解析问题，消歧受害者实体；非叙事类问题回落到现有 Fact-check 路径
S1 search_story_coverage：gate 要求至少 1 个 scope，否则 unavailable
S2 get_story_map：gate 要求先取地图再精读
S3 read_story_lines 定位死亡情节所在行区间
S4 find_detail_echoes(死亡情节原文)：gate 要求必须调用，匹配位置进入观察
S5 从死亡情节与匹配位置共现实体生成候选集合
S6 collect_suspect_evidence(每个候选, 全部 scope)：
   gate 要求至少 2 个候选有非空证据集，或显式声明 single-suspect-exhausted
S7 逐候选比较证据链完整性与矛盾（协议：先各集齐再比较，误导章节只是一份证据）
S8 输出结论信封 + 证据链 + 反方证据 + 已读范围报告 + 置信度 + 替代解读
```

预算：`maxIterations` 12–15、`stepMaxTokens` 4096+、`minimumToolCalls` >= 4。

### 5.3 结论格式与校验

```text
[INVESTIGATION_VERDICT: culprit=<entity_id> | confidence=<0-1> | basis=<multi_hypothesis_contrast|single_suspect_exhausted>]
```

校验规则（`finalAnswerTransform` 内实现）：

1. `culprit` 结论仅在 S6 门槛满足时允许；
2. 证据链每条引用必须在 observations 中找到对应 provenance（扩展 `applySourceGuard`
   到行级）；
3. 已读范围报告与实际调用比对。

### 5.4 UI 变更

证据卡扩展两类条目：证据链条目（声明 + 引用）与已读范围条；双语 ARB 新增文案。

### 5.5 QA 与验收

- fixture 断言：`find_detail_echoes` 命中第 1 章伏笔行；误导章节不构成唯一证据；
  verdict=角色 B；已读范围报告与实际一致。
- 单元测试：特征词提取过滤（停用字符、标点、数字）、doc_freq 阈值、FTS 与 LIKE
  回退、分页连续性。
- 门槛测试：transform 拒绝"声明读取未实际读取章节"与"未满足 S6 门槛的 culprit
  结论"的输出。
- 真实 DB：新增 2–3 个剧情谜题固定用例（按实际剧情选定）；既有固定 QA 全绿。

## 6. 阶段 P2：可选增强（全部走门禁）

### 6.1 向量化召回

作为跨章节细节匹配的语义补充（查找字面不同但语义相近的细节）。按 `RETRIEVAL_QA.md`
的 Hybrid 基准执行：与现有 SQLite 路径并排 benchmark，通过标准为固定 QA 有效证据
召回提升且误证据率不上升；无索引或不兼容时回退现有路径。不作为主检索路径。

### 6.2 LLM 章节摘要

章节画像的 `summary` 可选用模型生成（`--with-summaries`），manifest 记录
`summary_model` 与 `summary_prompt_version`；核心 DB 构建保持可复现（默认 extractive）。

### 6.3 时间线注册表

轻量"事件-章节"注册表（人工维护或抽取辅助），仅在固定 QA 显示具体的时间线对齐
缺口时立项。

## 7. 成本与风险

- **工程成本**：P0、P1 均为确定性实现（全量扫描、FTS 重建、新表、新工具），无模型
  调用成本；P2 才涉及模型/向量成本。
- **正确性边界**：艺术化伏笔的推理无法保证完全可靠（该失败模式为开放研究问题）；
  以置信度、替代解读与已读范围报告兜底。
- **兼容性**：schema 新增为 additive，旧 App 版本不受影响；已安装 DB 需要新的
  schema v3 release asset，安装器必需表清单同步更新。
- **行为保持**：不改变信任模型（GameData 唯一证据）、不恢复 Wiki/Book 索引、不引入
  隐藏索引路径；Agent 默认检索仍只注册本地工具。

## 8. 与现有文档的关系

- `implementation_plan.md` 的 schema v3 候选（实体级剧情倒排）→ 本计划 P0 落地其
  第一部分。
- `implementation_plan.md` 的共享 StoryEvidenceRetriever、结构化步骤协议、
  deterministic post-check → 本计划 P1 对应。
- `GAMEDATA_BUILD_PIPELINE.md` 的向量索引资产契约 → 本计划 P2 遵循。
- `RETRIEVAL_QA.md` 的 Hybrid 基准 → 本计划 P2 门禁。
- 阶段落地后更新 `RETRIEVAL_QA.md` 验收记录与 `KNOWN_LIMITATIONS_AND_DEBT.md` 状态，
  并在本文档标注完成情况；不删除现有文档。
