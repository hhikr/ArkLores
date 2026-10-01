# R12 调查链路瓶颈分析

> 基准：dev 分支 2026-10-01 状态（R11.2 之后）<br>
> 输入：`logs/session.jsonl`（上一轮 agent 会话，2026-08-25～26，18 轮）、
> `build/investigation_run.json`（R11.2 前最后一次 CLI 运行）、agent / 检索 / 构建层源码<br>
> 关联：修复计划见本文 §4；状态跟踪见 `KNOWN_LIMITATIONS_AND_DEBT.md` R12 条目

## 1. 结论

R8→R11.2 连续四轮修复都集中在调查循环的**终止控制**上：歧义自动消解、
RESELECT、重复计数、进展门控、空输出收场。其中计数规则先后改了三次：
R11 无条件计数，R11.1 有结果即重置，R11.2 改为同内容也计重复。每次修复后，
真机都会暴露新的失败形态。

这种反复说明修的是症状。复盘代码后的判断是：

> **主要瓶颈在信息流。** 模型拿不到“查剧情原文”的动作，读到的原文也进不了
> 最终答案。循环控制只是在给这两个缺口打补丁。

另一个结构性问题是只有一个验收样例。每次修改都只能靠“跑一次、看 log”来判断，
既证明不了改动通用，又容易对这个样例过拟合（与 anti-fixture 原则冲突）。

## 2. 瓶颈清单（按影响排序）

### B1 读到的原文进不了最终答案（最严重）

| 证据 | 位置 |
| --- | --- |
| App 构造 `InvestigationAgent` 时没有传 `extractorClient`，READ 之后的要点提取**从未运行** | `lib/core/agent/agent_provider.dart:667` / `planner_loop.dart:402` |
| 原文只在近程窗口里停留 2 条观察，之后丢弃 | `planner_loop.dart:392` |
| Writer 只拿到 `state.serialize()`，内容是 story_id + 行号区间，没有原文 | `planner_loop.dart:609-630` |
| R3 的行级引用校验 `validateInvestigationVerdict` 在 R8 迁移后不再被调用（只有 UI 解析信封） | `lib/core/agent/investigation_verdict.dart:54` |
| “已读”按**请求参数**推算（`start + max_lines(60)`），不是工具实际返回的行；工具受 4800 字预算截断时，状态会多记 | `planner_loop.dart:571-574` |
| `noteRead` 把同一章的多次读取合并成 min..max，中间没读的空洞也被算作已读 | `investigation_state.dart:236-255` |
| 提取器（即使接上）看不到用户问题，只取前 3000 字，压成 ≤150 字 | `planner_loop.dart:634-650` |

**影响**：就算模型读到了正确章节，最终答案也只能靠模型自身的记忆来写，
违反 CLAUDE.md 第 5 条（判定只能基于检索到的原文）。“答案缺关键章节”和
“答案离谱”两类失败都根源于此。

### B2 意图协议缺少剧情检索动作，这是 SEARCH 死循环的结构根源

| 证据 | 位置 |
| --- | --- |
| 系统 prompt 要求 S1 先用 `search_story_coverage` 枚举出场 | `agent_prompts.dart:118` |
| 意图到工具的映射里没有 coverage，也没有行级原文检索 | `planner_loop.dart:413-420`、`planner_intent.dart:31-39` |
| SEARCH 对应的 `search_local_lore` 只查实体档案 / records / lore_chunks，不查 `story_lines` | `gamedata_knowledge_store.dart:31-216` |

**影响**：模型想“找某人在剧情里的出场或某件事”时，只能发 SEARCH，
结果拿回同一份实体档案（例如敌人图鉴），于是重复。R11 系列的计数器、
覆盖兜底、进展门控，都是在这个缺口上打的补丁。

### B3 消歧可能在优化一个没用的杠杆

| 证据 | 位置 |
| --- | --- |
| 覆盖层 trie 命中一个别名时，会把这一行写给**所有**共享该别名的实体 | `lib/core/gamedata/build/story_coverage_builder.dart:238-244` |
| 消歧器收到的候选 `entityType` 被硬编码为 `'entity'`、`sourceType` 被硬编码为 `'game_data'`，真实类型和来源都被丢掉 | `planner_loop.dart:469-484` |

**推论（待在真实 DB 上验证，见计划 Phase 0）**：同名候选在 `entity_story_mentions`
中的出场很可能完全相同，选哪个实体只影响 SEARCH 返回哪份档案，不影响能读到哪些剧情。
另外，消歧器只能看到 id + 名字，所以常常选 #1 或判定失败回退。

### B4 循环控制本身的 bug

| 证据 | 位置 |
| --- | --- |
| `consecutiveNoResult` 是全局计数，新的 query 会被前面其他 query 的失败连带惩罚。`build/investigation_run.json` 中，`维多利亚` 第一次搜索就被强制转兜底 | `investigation_state.dart:165-180` |
| 已兜底（`alreadyFellBack`）但没有任何已读时，引导文案仍是“已有0 个已读章节……对已读章节中的嫌疑人 COLLECT”，自相矛盾 | `planner_loop.dart:349-355` |

### B5 CLI 复现链路并不等价

`tools/run_investigation.dart` 复用了 App 的 `InvestigationAgent`、工具类、
PlannerLoop 和消歧器，但数据层 `_FfiGameDataRetrieval` 是重写的：
`search()` 是几十行的简化版（`run_investigation.dart:179`），
而 App 是多阶段检索管线。偏偏 SEARCH 是出问题最多的路径。
上一轮会话里已经发现过一次行为差异（`findEntityCandidates` 漏掉别名候选）。

根因是 `GameDataKnowledgeStore` 直接依赖 `path_provider` 和 Flutter 版 `sqflite`，
纯 Dart CLI 无法 import。

### B6 没有评测集

只有“导致特蕾西娅死亡的罪魁祸首是谁”这一个验收样例。
`check_gamedata_retrieval.dart` 只覆盖单次检索，不覆盖多步调查。
修复效果没有任何量化指标，比如关键章节召回率、引用合法率、步数、成本、终止类型分布。

### B7 调查模式整体是围绕“凶手”设计的（产品层，本次只记录）

S0–S8 流程、`VERDICT culprit`、“至少 2 个嫌疑人有证据”门槛，都只适合凶手类问题。
这与 CLAUDE.md 检索原则第 1 条（只做桥段无关的通用机制）存在张力。
真实问题大多是经过、原因、关系和时间线。泛化列为 P2。

### 新发现：中文 FTS 基本无效

| 表 | 分词器 | 位置 |
| --- | --- | --- |
| `entity_documents_fts` | `trigram` ✅ | `gamedata_schema.dart:176-188` |
| `lore_chunks_fts` | 默认 `unicode61` ❌ | `gamedata_schema.dart:189-198` |
| `story_lines_fts` | 默认 `unicode61` ❌，且从未被查询 | `gamedata_schema.dart:237-243` |

`unicode61` 把连续的汉字视为同一个 token，所以“特蕾西娅”这类词无法匹配句中的子串。
`lore_chunks` 的实际召回靠后续的 LIKE 兜底。行级剧情原文目前没有任何可用的全文检索入口。

### Phase 0 实测（2026-10-01，真实 DB：schema 4，built 2026-08-24）

| 项目 | 结果 |
| --- | --- |
| 规模 | `story_lines` 409,476 行 / 2,816 个 story / 约 888 万字 |
| 中文 FTS | `story_lines_fts MATCH "做到"` = **0**；`LIKE '%做到%'` = **952**，证实 unicode61 对中文无效 |
| LIKE 延迟（桌面） | `LIMIT 50` 命中约 7ms；全表扫描未命中约 100ms |
| B3 | 共有 1,996 个别名被多个实体共享；有出场的里面 **499 个出场完全相同、16 个不同**（约 97% 相同），证实 B3 |
| 向量体积估算 | 按 12 行一块、步长 8 切块，共 51,264 块；int8 存储下 256 维 12.5MB / 512 维 25MB / 1024 维 50MB；待 embed 文本约 1,511 万字 |

附带发现：`sqflite_common_ffi` 会把**相对路径**解析到
`.dart_tool/sqflite_common_ffi/databases/` 下。本机这个目录里还残留着一个
schema 1 的旧库，临时脚本用相对路径打开时会静默打开这个错误的库。
`run_investigation.dart` 已经先把路径转成绝对路径，不受影响；新增的 FFI 工具也必须这样做。

### B8（P1 期间新发现）reasoning 模型的隐藏推理占用 `max_tokens`

用 app 同一条链路实测 deepseek flash：`max_tokens=64` 时 64 个 token 全部用于
隐藏推理，`finish_reason=length`，**content 为空**；512 以上才正常返回。
项目里有几处调用把上限设得很低：

| 调用 | 原上限 | 后果 |
| --- | --- | --- |
| 消歧器 `EntityDisambiguator` | 32 | 几乎总是空输出，解析失败后回退选 #1。这解释了历史日志里反复出现的“消歧失败回退最高置信度候选” |
| 提取器（R12 P0 新增） | 512 | 证据笔记为空 |
| Planner 每步 | 1024 | 上下文变长后出现空输出 |

R11.2 把这种空输出解读为“模型对重复观察无话可说”，加了“连续 3 次空输出就温和收场”
的逻辑。实际上这些是**截断**，不是模型没话说。

修复（`lib/core/llm/completion_budget.dart`）：`completeWithHeadroom` 在截断时把
上限放大 4 倍重试，四处调用的上限也都调高。`max_tokens` 只是上限，按实际生成的
token 计费，调高不会增加成本。修复后用同一个问题复跑：空输出从 3 次降到 0 次，
调查正常走完，答案的 8 条引用全部通过校验，原文没覆盖的地方明确写“资料未覆盖”。

## 3. 上一轮会话时间线（摘要）

| 轮次 | 用户诉求 | Agent 产出 |
| --- | --- | --- |
| 1 | 了解项目 | 状态报告（R0–R10，188 tests） |
| 2–8 | observation 自我重复 | R11：消歧辅助 Agent、`id=` 语法、RESELECT、重复→coverage→unresolved |
| 9 | 是否针对样例编程 | 自查通过，CLAUDE.md 新增 anti-fixture 章节 |
| 10–13 | 新 log：被 unresolved 误杀 | R11.1：有结果即重置、key 归一化、进展门控、RESELECT 重置计数 |
| 14 | 新 log：空输出终止；希望不依赖真机 | R11.2：同内容计重复、空输出温和收场、多词 query；新建 CLI |
| 15–18 | CLI 必须复用 App 代码 | 抽出 `GameDataRetrieval` 接口；工具和 Agent 改依赖接口；FFI 数据层仍为重写 |

真机失败形态的演变：
1. 无限重复 SEARCH 原名（R10）
2. 被 unresolved 误杀（R11）
3. 原地拿同一档案，最后输出空串终止（R11.1）
4. CLI 中因上游 503/524 中断（R11.2）

四次失败形态都不同，但全都发生在“找不到剧情原文入口”的阶段（B2），
也从来没有出现过基于原文的有效答案（B1）。

## 4. 修复方向（详细计划见 R12 开发计划）

| 优先级 | 修复项 | 对应瓶颈 |
| --- | --- | --- |
| P0 | 证据笔记本：READ 的实际行和结合问题的带行号笔记写入 state；接上提取器 | B1 |
| P0 | Writer 基于笔记本原文写答案，恢复行级引用校验 | B1 |
| P0 | 意图协议新增 `COVER`（出场枚举）和 `FIND`（行级原文检索）；SEARCH 定位为查档案 | B2 |
| P0 | 消歧传入真实 type/source；同名出场相同时合并，跳过消歧 | B3 |
| P0 | 无结果计数改为按 key；修正引导文案 | B4 |
| P1 | store 去掉 Flutter 依赖、改为注入式，CLI 使用 App 真 store | B5 |
| P1 | 行级向量召回（百炼 embedding，int8 存可选表，schema 5）与 LIKE 融合，结果只作定位线索 | B2 / 新发现 |
| P1 | 30 题多题型评测集，加批量评测与基线对比 | B6 |
| P1 | 循环控制简化为“state 增量 = 进展”加总预算（由评测数据驱动） | B4 |
| P2 | 调查模式泛化为通用剧情问答；Summary / Fact-check 迁移 | B7 |

设计约束：所有新机制都必须对任意剧情问题有意义（CLAUDE.md 检索原则 1、anti-fixture 2）。
向量命中只作为定位线索，必须 READ 原文后才能成为证据（检索原则 5）。
