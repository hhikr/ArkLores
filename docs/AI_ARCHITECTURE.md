# AI 架构（Ask 问答 + GameData 检索）

> 当前状态：R12（v0.10.0）。本文档是 Agent 层与检索层的**唯一总括文档**，
> 取代旧的 `AI_REFACTOR_SUMMARY.md`、`R0`–`R3` 阶段总结、`AI_RETRIEVAL_OPTIMIZATION.md`、
> `FEASIBILITY_ANALYSIS.md`、`RETRIEVAL_INSTALL_CHAIN_ANALYSIS.md`（均已删除，原文在 git 历史中）。
> R12 的决策过程见 `R12_BOTTLENECK_ANALYSIS.md`；已知缺口见 `KNOWN_LIMITATIONS_AND_DEBT.md`。

---

## 1. 总体链路

```
用户问题 ──► AskChatNotifier.sendMessage（auto / summarize / verify / investigate）
              │
              ├─ auto：QuestionRouter（一次短 LLM 调用）选出模式
              │
              ├─ investigate ─► InvestigationAgent ─► PlannerLoop（本文 §2）
              ├─ summarize   ─► SummaryAgent      ─► ReActLoop（旧流程，R13 迁移）
              ├─ verify      ─► FactCheckAgent    ─► ReActLoop（旧流程，R13 迁移）
              └─ Roleplay tab ► RoleplayAgent     ─► ReActLoop（不在迁移范围）
                                         │
                       工具 ──► GameDataKnowledgeStore（共享只读 SQLite 连接）
                                         │
              ChatSessionStore（每对话一个 JSON，完整记录每步原始输出、工具、观察）
```

- **知识源**：只有 GameData（解包文本构建的 SQLite）。Wiki 与用户文本只作浏览/上下文，
  不能作为证据。
- **会话记录**：`chat_sessions/` 下每对话一个 JSON（原子写、损坏容错、50 会话轮转），
  记录用户模式 / 生效模式 / router 原始输出 / 模型 / 每步原始响应 / 工具与观察 / 最终答案 /
  状态与耗时。开发日志开关打开时额外写入 `logs/`。所有真机问题都应能用这些 JSON 回放。

## 2. PlannerLoop（调查流程）

ReAct 把“记忆 + 推理 + 执行”放在同一个上下文里，上下文必然膨胀，只能靠截断，
截断又导致重复与遗忘（R6–R7 的教训）。PlannerLoop 把职责拆开：

| 角色 | 实现 | 模型 | 职责 |
| --- | --- | --- | --- |
| 决策器 planner | `planner_loop.dart` | aux（不推理） | 每步只输出**一行意图**；上下文 = 固定 system + 状态序列化 + 最近观察，不随调查增长 |
| 执行器 | 代码（无 LLM） | – | `parseIntent` → 调工具 → 解析 DATA 块 → 更新 `InvestigationState` |
| 提取器 extractor | `evidence_notebook.dart` | aux | READ 之后从本页挑出与问题相关的行，输出 `L<行号>: 事实` |
| 消歧器 | `entity_disambiguator.dart` | aux | 同名多实体时按问题语义选一个候选，失败回退第 1 个 |
| 写作者 writer | `planner_loop.dart` | 主模型（保留推理） | 基于证据笔记 + 已读原文写最终答案，并经过引用校验 |

“aux” = `auxLlmClientProvider`：同一 API 配置，但关闭推理（deepseek
`thinking:{type:disabled}`，百炼 `enable_thinking:false`，未知 provider 不发参数）。
机械角色关推理后输出 token 下降约 88%，答案质量不变（R12 A/B）。

### 2.1 意图与工具

| 意图 | 工具 | 用途 |
| --- | --- | --- |
| `SEARCH <名字> [id=<id>] [top_k]` | `search_local_lore` | 查实体档案（FTS + LIKE） |
| `COVER <名字\|id> [scope=]` | `search_story_coverage` | 确定性枚举实体在哪些章节、哪些行出场 |
| `MAP <scope_id>` | `get_story_map` | 章节画像（行范围、speaker、高密度实体、抽取式摘要） |
| `READ <story_id> [start] [end]` | `read_story_lines` | 读剧情原文（行号、分页） |
| `FIND <短语> [scope=] [top_k]` | `search_story_lines` | 在原文里找线索：关键词 LIKE + 可选向量召回，RRF 融合 |
| `COLLECT <entity_id> [...]` | `collect_suspect_evidence`（R13 改名） | 列出某实体的全部出场行 |
| `RESELECT <entity_id>` | – | 切换消歧候选；已尝试的候选不会再选 |
| `SUMMARIZE` / `VERDICT` / `DONE` | – | 收尾，交给 writer |

- 一行只能有一个意图，多意图行整体拒绝；空输出单独计数，3 次后温和收尾。
- 工具观察 = 人类可读正文 + 末尾 `DATA: <json>`（由工具生成，代码解析，失败回退文本标记）。
  新工具必须同时提供两者。

### 2.2 状态与证据

`InvestigationState`（代码维护，序列化有界）：

- **已读**：按实际返回的行段记录（保留空洞），所以“读过 1–40 和 80–120”不会被当成读过 1–120。
- **证据笔记** `EvidenceNote`（最多 30 条）：行号必须落在本页内，引用原文由代码从原行复制，
  模型无法伪造引文。
- **检索记录** `searchLog`、**已发现章节** `discoveredStories`、目标实体与候选清单。

### 2.3 进展控制

- 完全相同的 FIND / COVER / MAP / COLLECT / READ / SUMMARIZE 不重复执行（直接返回“已执行过”）。
- “进展” = 状态指纹有变化（新读到的行、新证据、新发现的章节）；单纯换说法检索不算进展。
- 连续 4 步无进展 → 提醒；连续 8 步无进展或用满 24 步 → `_finishFromState`，由 writer
  基于已读内容收尾，不再“状态转储”。
- 近程窗口中，除最新一条观察外都截到 600 字。

### 2.4 Writer 与引用校验

- 输入：用户问题 + 证据笔记 + 已读原文（≤8000 字）。要求直接回答、行级引用
  `story_id.txt:行号`、反方证据、置信度；可以否定决策器选定的主体。
- `unreadCitations`：每条引用必须落在已读区间内。不合法 → 重写一次；仍不合法 →
  附加来源警告。
- `completeWithHeadroom`：reasoning 模型的隐藏推理也占 `max_tokens`；遇到截断时把上限
  放大 4 倍重试一次，而不是返回空串。

### 2.5 结论信封（R13 将替换）

当前 writer 前面附 `[INVESTIGATION_VERDICT: culprit=… | confidence=… | basis=…]`，
`investigation_verdict.dart` 对 culprit 做“≥2 个候选有证据”门槛。这是为“凶手类”问题
写的特判，R13 会换成与问题类型无关的 `[STORY_ANSWER: status=… | confidence=…]`。

## 3. 检索层（GameData SQLite，schema 4）

### 3.1 表与构建

构建代码在 `lib/core/gamedata/build/`，桌面 CLI（`tools/build_gamedata_database.dart`）与
App 内构建共用同一份实现：

1. 四阶段导入：角色档案 → 语音 → 15 张结构化表 → 剧情（`story_lines` 约 41 万行）。
   主键由内容派生（SHA-1），重复导入幂等。上游 `[uc]info/` 摘要桩树被跳过（schema 4）。
2. 第 5 阶段 **确定性覆盖层**（`StoryCoverageBuilder`）：
   - 实体 trie（名字 + 全部别名，最长匹配）扫描 **speaker + content**，连续命中合并为
     run 写入 `entity_story_mentions`；
   - 出现 ≥3 行但不在实体表里的说话人建为轻量实体 `speaker:<名>`，正式实体优先；
   - `story_chapter_profiles`：行范围、speaker 集合、实体密度、抽取式摘要（桥段无关）；
   - `rare_terms`：跨文件 doc_freq ≤ 20 的中文双字词；
   - `story_lines_fts`：行级 FTS（unicode61，配合 LIKE 回退）。
3. FTS 重建 → manifest（计数、源 commit）→ 共享验证器 `gamedata_db_validator.dart`
   （安装器与构建服务用同一套拒绝规则）。

覆盖层只提供**定位线索**，不参与事实判定（CLAUDE.md 检索原则 5）。

### 3.2 安装与替换

- 两条通道：官方 release asset 下载（`.db.gz` + SHA-256）与 App 内“从源仓库构建”
  （GitHub zip 首次拉取 / compare API 增量，白名单只落约 168MB 源子集，构建在后台 isolate）。
- 不变量：**已安装库永不原地修改**。新库写到临时路径 → 校验 → 删旧 + rename。
- 所有工具共享一个 `GameDataKnowledgeStore` 连接；store 每次查询前比对文件 stamp，
  库被替换后自动重开（避免读旧库，也避免多实例互相关闭连接）。

### 3.3 剧情向量（可选，R12）

- 表 `story_chunk_vectors`：12 行一块、步长 8，约 51k 块，512 维 int8 量化（约 25MB 内存），
  暴力 cosine。schema 版本不变，没有这张表的库照常可用。
- manifest：`embedding_model` / `embedding_dims` / `embedding_chunking`。App 只在设置中的
  向量配置（默认百炼 `qwen3.7-text-embedding`，512 维）与 manifest 一致时启用语义召回；
  否则 FIND 退回纯关键词，并在观察里写明原因。
- 关键词一条都没命中时，观察会标注“只是语义相近，可能无关”。向量命中必须 READ 原文后
  才能当证据。
- 构建：`dart run tools/build_story_embeddings.dart --db=...`（可续跑，按内容哈希缓存，全量约 11 分钟）。

## 4. 测试与成本

- 离线：`flutter test`（mock LLM 复现 Agent 行为，DB 级用例用 FFI 建临时库）。
- 真机同链路：`test/live/ask_pipeline_live_test.dart`（opt-in），驱动 App 的
  `askChatProvider`，只替换启动注入的 provider 和平台路径；用法见 CLAUDE.md。
  每题输出会话 JSON + `*.summary.json`（步数、工具、引用、召回、token 用量）。
- 成本规则：先离线；每个方面最多 2 个代表性用例，逐题串行；不整批跑评测。
- 评测集 `test/fixtures/investigation_eval.json`（30 题草稿，标准答案章节待人工审核），
  汇总工具 `tools/summarize_eval.dart`。

### R12 真机结果（向量 + 机械角色不推理，deepseek flash）

| 用例 | 步数 | 耗时 | 输入 / 输出 token | 结果 |
| --- | --- | --- | --- | --- |
| theresa_death（问“谁”） | 23 | 82 s | 107k / 11k | 正确，11 条引用全部合法，含反方证据 |
| frostnova_end（问“怎样”） | 8 | 31 s | 27k / 4k | 正确，读到标准答案章节 |
| neg_fictional（负例，auto 路由到概括） | 3 | 9 s | 7k / 0.8k | 诚实回答“未覆盖”（旧概括流程） |

中期评测（investigate 模式，样本不完整）：有引用答案 6% → 100%，无答案 88% → 0%，
标准答案章节召回 0 → 0.63。

## 5. 演进简史

| 轮次 | 做了什么 | 为什么 |
| --- | --- | --- |
| R0 | 构建代码从 tools/ 抽到 lib/；store 文件 stamp 失效重开；安装器补校验 | 桌面与 App 共用一套构建；换库后不再读旧库 |
| R1 | schema 3 确定性覆盖层 + coverage/map/read 三个工具 | “某角色在哪出场”不再依赖检索措辞；原文可逐行读 |
| R2 | App 内从源仓库构建/增量更新 | 不依赖 release 节奏；校验后原子替换 |
| R3 | speaker 实体扩展、DATA 块契约、调查 Agent 与 tab、结论门槛 | 跨章节问题；（结论门槛为凶手类特判，R13 删除） |
| R5 | 会话 JSON 持久化与回放 | 真机问题可复现 |
| R6 | 分层记忆；废弃 `find_detail_echoes` | 截断导致重读；该工具真机零贡献 |
| R7 | 记忆并入 system、截断可恢复、裸思考不当答案 | 98% 迭代丢 `Thought:` 前缀 |
| R8 | PlannerLoop 三角色 | 上下文膨胀是 ReAct 结构问题，只能拆角色 |
| R9 | 共享 DB 连接、SEARCH 去引号 | `database_closed`；引号被当字面量 |
| R10–R11.2 | 自动消歧、RESELECT、SEARCH 重复终结的多轮修正 | 同名实体导致 SEARCH 死循环（这些 SEARCH 专用补丁 R13 删除，由通用进展控制取代） |
| R12 | 证据笔记、writer 读原文 + 引用校验、COVER/FIND、向量召回、通用进展控制、机械角色关推理、同链路 live 测试 | R8–R11 只修终止，没修信息流：提取器未接线、writer 看不到原文 |
| R13（进行中） | 删除全部特判；概括/核查迁移到 PlannerLoop | 见 KNOWN_LIMITATIONS 与开发计划 |
