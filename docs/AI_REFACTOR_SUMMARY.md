# AI 检索与调查架构重构总结（R5–R10）

> 覆盖提交 `fbcede2..HEAD`（investigation tab 起）的 24 个提交，对应
> "AI 问答体验 + 调查能力"从 v0.9 基线到 Planner 三角色架构的完整演进。
> 每个阶段都以真机日志实证驱动（日志均在 `logs/`，会话 JSON 自 R5 起可完整回放）。

---

## 阶段总览

| 阶段 | 核心提交 | 一句话 |
|---|---|---|
| R5 | `6b429b6` | 会话持久化：Ask 对话记录 JSON 化，可恢复、可回放 |
| R6 | `5974cff` | 分层记忆取代"扩窗"：记忆块 + 近程窗口，上下文不再随迭代增长 |
| R7 | `0f65177` | 格式漂移修复：截断可恢复、裸思考不当答案、错误可见 |
| R8 | `5896e34` | **Planner 三角色架构**：决策/执行/提取分离，根治重复与截断 |
| R9 | `b0836ec` | 共享 DB 连接 + SEARCH 引号剥离（database_closed 修复） |
| R10 | `d563e82` | 歧义实体自动消歧，消灭 SEARCH 死循环 |

---

## R5：AI 会话持久化（`6b429b6`）

**背景**：Ask 对话纯内存，进程被杀即丢失；调试日志按单次 ReAct 分文件、有截断、无模式信息。

**改动**：
- 新 `ChatSessionStore`：每对话一个 JSON 文件（用户可见 `chat_sessions/` 目录，原子写、损坏容错、50 会话轮转、可导出纯文本）
- 每轮记录：用户模式 / 生效模式 / router 原始输出 / 模型与 base_url / **完整 ReAct 链（不截断 raw response、thought、tool、observation）** / 最终答案 / verdict / 状态(completed/error/canceled) / 耗时
- `QuestionRouter.route()` 返回 `RouteResult`（mode + raw + error）；`ReActLoop` 新增 `onRawLlmResponse` 原始响应回调
- 对话记录页：列表 / 只读详情（复用 ChatBubble）/ 继续对话（恢复后历史进 LLM 上下文）/ 删除
- Ask 页三个 agent 不再写旧 `.log`（`agentName` 可空），`AgentLogger` 仅保留给角色扮演

**驱动**：用户要求"sessionlog 作为持久化容器 + app 内对话记录"。

---

## R6：分层记忆（`5974cff`）

**背景**：真机三实验（`logs/` 为证）暴露截断导致的三种病——`get_story_map` 字典序 + 4800 字符预算把核心章节（act33side_09_beg 刺杀章）藏掉；观察历史裁剪占位符让模型"忘记读过的内容"而重复精读（08-14 读 15 次）；auto 路由静默降级（router `maxTokens:16` 被 reasoning 吃光 → 空内容 → 落 summarize）。

**改动**：
- 新 `LoopMemory`：已读章节索引（分页自动合并区间）/ 已查地图 / 已收集证据 / 每轮 **Thought 摘要**，作为记忆块注入请求
- 请求结构 = system + chatHistory + query + **记忆块** + **近程窗口（K=2）**；旧观察不再以占位符驱逐，其结论进记忆块
- 请求大小与迭代数解耦（64 轮也仅 ~64 行索引）→ **"任何窗口调整都只是推迟撞墙"的规避**
- 三个 agent 的 `stepMaxTokens` 关键修复：route 16→256、summary 2048→4096
- `get_story_map` scope 模式改**按章节号自然排序 + 紧凑列表**，分页兜底；`collect_suspect_evidence` claim 术语**全局优先**排序（537 runs 时首屏即核心证据）
- `find_detail_echoes`（2 字 bigram 噪声）从调查工具集移除并**评估后废弃**（3 次真机 5 次调用零贡献，能力被 `search_local_lore` FTS 覆盖）

**设计原则**（写入 CLAUDE.md）：先量化再立项；只做桥段无关的通用机制；不硬编码场景词典；不制造隐性证据。`find_detail_echoes` 因违反"先量化"被否决。

---

## R7：格式漂移修复（`0f65177`）

**背景**：R6 后三次自动档实验（2 失败 1 离谱）——记忆块作独立 user 消息使其"调查要点"诱导模型续写，**98% 迭代丢失 `Thought:` 前缀**；连锁：要点层空转、`action.isEmpty` 分支把裸思考当最终答案、截断被设计成整轮失败。

**改动**：
- 记忆块并入 **system 消息**并标注"系统维护记录，请勿续写"（消除续写诱导）
- **裸思考不再当答案**：无 Action 无 Final Answer 键 → 格式错误重试 ≤3 次
- **截断可恢复**：`wasTruncated` → "精简输出"重试 ≤2 次后才 error
- `stepMaxTokens` 4096→8192；默认请求超时 120s→180s
- 恢复历史显示 `turn.error` 文本（此前 error 不进消息内容）

---

## R8：Planner 三角色架构（`5896e34`，核心重构）

**背景**：真机 103 迭代 / 204 步 / 海量重复 / 余额耗尽 + 答案缺巴别塔。三个根本缺陷：模型 Thought 漂移→记忆要点空转→重做 S1（37 次枚举）；记忆无内容回显→重读原文回忆（08-14 15 次）；阶段无记录→反复从头执行。**设计缺陷总根源**：ReAct 把"记忆（随调查增长）+ 推理（需全部观察）+ 执行（工具+观察回传）"揉进同一模型上下文，上下文必然膨胀 → 必须截断 → 任何窗口调整都只是推迟撞墙。

**改动（三角色分工）**：
- **决策 Agent**（唯一常驻 LLM）：每轮输出**一行意图**（`READ/SEARCH/MAP/COLLECT/VERDICT/DONE`），上下文 = 固定 system + 状态序列化 + 最近观察，**不随调查增长 → 架构级无截断**；短输出 → 格式遵从率大幅提升（Thought 漂移问题不存在）
- **代码执行器**（无 LLM）：`parseIntent` → 调工具 → 解析 DATA 块更新 `InvestigationState`
- **提取 Agent**（按需）：READ 后把章节压成 ≤150 字要点存入状态 → 模型不再重读回忆
- **Writer**（VERDICT 时）：基于状态生成带引用的最终答案（一次有界调用）
- `InvestigationState`：阶段(stages) / 已读(reads+keyPoints) / 证据(evidence) / 已查地图，代码维护、序列化有界
- `maxObservationHistory` 旧占位机制退役；`get_story_map` 紧凑摘要全保留

---

## R9：共享 DB 连接 + SEARCH 引号（`b0836ec`）

**背景**：两次真机（auto 长问题 + 深挖短问题）反复 `DatabaseException: database_closed`，最终步数超限。根因：5 工具各自 `GameDataKnowledgeStore()`，sqflite `singleInstance` 返回同一底层连接，任一 store 的 stat-change `close()` 杀掉共享连接，其他 store 仍用已关闭句柄。

**改动**：
- `InvestigationAgent` 构建**一个共享 store** 传给全部工具（stat 重开只影响唯一连接）
- SEARCH 意图剥离首尾引号（`SEARCH "特蕾西娅" 10` → query `特蕾西娅`；此前引号被当字面量查，永远无结果 → 逼模型乱猜 `Tersia`）
- 无结果观察提示勿猜拼写、用 `search_story_coverage` 查精确名

---

## R10：歧义实体自动消歧（`d563e82`）

**背景**：真机日志（`93cdd507`）——模型 14 次迭代 13 次 `SEARCH 特蕾西娅`，每次都返回同一份 ~1.6KB 的"Ambiguous entity query"（3 候选完整档案），模型不知道用哪个 entity_id，原地死循环至用户取消。

**改动**：
- 歧义观察压缩为每候选一行（`1. enemy:enemy_1554_lrtsia | 特蕾西娅 | name_exact | 1.00`），不再占满近程窗口
- **执行器自动消歧**：SEARCH 返回 Ambiguous → 代码选候选 #1 写入 `InvestigationState.targetEntity`，观察替换为"目标实体已自动消解，直接用其 id"
- 状态序列化加"目标实体"行；意图提示加"不要重复 SEARCH 已消歧名字"

---

## 其他重要修复（贯穿各阶段）

| 提交 | 内容 |
|---|---|
| `994dfe4` | **移除步数限制**：ReAct 可一直推理到 Final Answer；`safetyMaxIterations`(1000) 仅防失控（真机 12 轮耗尽后模型把 Action 文本当答案的问题） |
| `2aaee19` | LLM 请求超时 30s→120s（调查上下文大时 30s 会断） |
| `03b6db3` | **GameData schema 3→4**：跳过上游 `[uc]info/` 一行摘要桩树（曾导致每故事重复导入 + 章节列表污染）；`obt/<group>` 归 `obt:<group>` scope |
| `7faf59e` | `collect_suspect_evidence` 未解析实体名时明确提示先 `search_story_coverage` |
| `e3d6bc6` | Ask 入口统一（Ask + Roleplay 两 tab，Ask 内 auto/summarize/verify/investigate 四模式） |
| `11b4aad` | AI 会话日志用户开关（默认关，release 可用） |
| `9d29e80` | `HandshakeException` 纳入可重试网络错误（TLS 握手中断不再整轮失败） |
| `15496b3` | 移除死亡/凶案 triage 关键词（防桥段优化，改由 Agent 在通用检索上自行推理） |

---

## 架构演进图（R6 → R8）

```
R6 分层记忆（ReAct 内优化）          R8 Planner 三角色（架构重构）
┌─────────────────────┐      ┌──────────────────────────────┐
│ ReActLoop           │      │ PlannerLoop                  │
│ 请求=system+记忆块+窗口│  →   │ 决策Agent→一行意图            │
│ 模型输出 Thought/Action│      │ 执行器→工具+DATA→状态           │
│ 观察全文进近程窗口     │      │ 提取Agent→要点→状态            │
│ 裁剪靠K窗口+记忆块     │      │ 观察全文永远不进上下文          │
└─────────────────────┘      └──────────────────────────────┘
```

关键差异：R6 仍在"模型读 Observation 再回忆"，R8 让**代码解析 Observation 成状态**，模型只看状态——截断从架构上消失。

## R11：SEARCH 死路消除 + 问题语义消歧 + 防重选记忆（`2026-08-26`）

**背景**：R10 后真机复现（`logs/conversation_0beaa9fd*.json`）显示**仍未根治**——
13 步里 8 步重复 `SEARCH 特蕾西娅`（每次都返回同一句"实体歧义已自动消解"）、
4 步 `SEARCH enemy:enemy_1554_lrtsia`（永远 "No matching"），直到用户手动取消。

**根因（三条死路，均可在代码里复现）**：

1. **消歧结果不可复用（路 A 死锁）**：`search_local_lore` 对任意无 entity_id/
   content_type 的 query 先查候选；`特蕾西娅` 命中 3 个 exact 候选（1 name_exact
   + 2 alias_exact），`>1` 永远返回歧义。R10 把候选#1 写进 state，但**下一次
   SEARCH 原名没有任何代码消费这个记录**——原样再调工具 → 重新歧义 → 重新
   选#1，无限循环。
2. **按 id 检索无路可走（路 B 死锁）**：意图协议只有 `query`+`top_k`，无 entity_id；
   `store.search(entityId:)` 需要显式参数，模型发 `SEARCH enemy:...` 永远被当
   全文 query → "No matching"。A、B 都不通 → A→B→A→B。
3. **选错不可纠 + 无代码终点**：自动选#1 时候选#2/#3 被丢弃、无重选意图；
   state 里 `目标实体:` 只是文字，没有任何"重复次数/连续无结果"计数 → 循环
   无代码级终结点。qwen 低遵从只是放大器。

**改动**：

- **`EntityDisambiguator`（新，辅助 Agent）**：歧义时一次轻量 LLM 调用（≤32
  token、temperature 0），输入 = 用户问题 + 紧凑候选列表 + 已尝试集合，输出 =
  最匹配候选；失败/乱输出回退候选#1。原"永远选#1"（SQL 排序隐含决策）改为
  "按问题语义选"——`导致特蕾西娅死亡的罪魁祸首` 会倾向魔王/干员而非普通敌人。
- **消歧结果进入状态协议**：`targetEntity` + 候选清单 + 已尝试集合 +
  `已消歧名字→id` 映射（`searchedNames`）+ 重复计数 + 连续无结果计数 +
  覆盖兜底标记，全部由执行器代码维护。
- **SEARCH 死路消除**：
  - 已消歧名字再次 SEARCH → 执行器自动注入 `entity_id`（不再重新歧义）；
  - 意图协议支持 `SEARCH <name> id=<id>` 与 `SEARCH id=<id>`；
  - `search_local_lore` 对**实体 id 字面量**（含 `:` 或 `char_`/`enemy_` 前缀）
    自动解析并按其检索（普通显示名仍走歧义/名称路径）；
  - 显式 `entity_id` 时跳过歧义分支（Roleplay 锁角色语义的通用化）。
- **RESELECT 重选**：新意图 `RESELECT <entity_id>` 切换候选；已尝试候选被拒绝
  （记忆机制，不会在候选间打转）；无候选清单时按 id 形态识别。
- **重复终结（不依赖模型自觉）**：同一搜索键第 3 次重复（或连续无结果 ≥2）
  → 执行器自动转 `search_story_coverage` 枚举出场；该键已兜底过仍重复 →
  直接 `culprit=unresolved` 收场并输出已收集内容，循环在代码层面终止。
- **多意图与引号修复**：一行多个意图前缀 → 拒绝（malformed ≤3 终止）；
  `SEARCH "特蕾西娅 死亡"` 保留完整短语（不再截成 `"特蕾西娅`）。

**测试**：planner_test 新增 10（id= 语法、引号短语、多意图拒绝、RESELECT、
消歧选#2/失败回退、已消歧名注入 entity_id、重复→coverage、空覆盖→unresolved）；
agent_test 新增 2（显式 entity_id 跳过歧义、id 字面量检索）。全量
157 → 185 → 188 → **200 passed / 3 opt-in skipped / 0 failed**，analyze 干净。

---

## R11.1：重复终结误判修正——无进展计数 + key 归一化 + 候选隔离 + 进展门控（`2026-08-26`）

**背景**：R11 后真机复现（`logs/conversation_284c0267-*.json`）显示重复终结
**生效但误杀**：模型已精读 4 个章节（含"巴别塔意外"关键线索）、调查仍有实质
进展时，被 `culprit=unresolved` 抢先终止。同时核查发现 RESELECT 换候选机制
存在但**计数不随候选切换隔离**——模型"没把握时继续查看第 2/3 个候选"不可靠。

**根因（四个代码缺陷）**：

1. **有结果的重复也被判死循环**：`noteSearchAttempt` 在工具执行前无条件计数，
   第 3 次同类 SEARCH 即触发兜底，无视前两次是否有结果（log 迭代 2/4 成功返回
   档案，迭代 5 仍触发"重复无进展"）。
2. **key 注入后不一致**：注入 `entity_id` 后 `key` 变 id，但计数/兜底标记用
   原名——同一实体分散计数、覆盖兜底重复注入（log 迭代 5/10/16 节奏混乱）。
3. **终止不看整体进展**：终止判定只数 SEARCH 重复，不检查已读章节/证据，
   有实质调查仍被掐死。
4. **候选切换不隔离计数**：RESELECT 换候选后不重置计数，新候选继承旧候选的
   "重复无进展"计数 → "看第 2/3 个候选"会被误杀。

**改动**：

- **无进展计数**：`noteSearchProgress(hadResult, contentChanged)` —— 有结果
  （无论内容是否重复）**重置**计数器；只有无结果才递增 `searchRepeatCount`/
  `consecutiveNoResult`。有结果的重复永不触发兜底。
- **key 归一化**：SEARCH 解析到规范实体 id 后，计数与兜底标记统一用 id
  （原名→id 仅用于注入，不参与计数）。
- **进展门控**：触发兜底/终止前检查 `hasReadOrEvidence`（已读章节或证据）。
  有进展 → 注入引导"请停止重复搜索，改为 COLLECT <嫌疑人> 或 VERDICT"，
  **不终止**；无进展 → `_coverageFallback`（有覆盖注入继续 / 空覆盖 unresolved）。
- **候选切换隔离计数**：RESELECT 成功后 `resetSearchTrackingFor(id)` 清除该
  候选的计数/兜底标记——每个候选独立基线，可依次查看 #1/#2/#3。
- `_terminateUnresolved` 辅助统一收场文案；`_coverageFallback` 三态返回。

**测试**：planner_test 调整为 25（新增 5 个 R11.1：有结果重复不终止、有进展
引导而非终止、无进展 unresolved、无目标引导不终止、RESELECT 重置计数；删除
2 个语义过时的旧用例）。全量 **200 → 205 passed / 3 opt-in skipped / 0 failed**，
analyze 干净。

---

## R11.2：重复终结再修正——同内容也算重复 + 空输出温和收场 + 多词查询（`2026-08-26`）

**背景**：R11.1 后的真机（`logs/conversation_d8819cb3-*.json`，deepseek）暴露两个
新问题：① R11.1 的"有结果即重置计数"过宽——模型反复 `SEARCH id=enemy:1554`，
每次都拿到**同一份敌人档案**（对"谁导致死亡"毫无进展），`consecutiveNoResult`
永不累积，"重复无进展"兜底永不触发 → 原地打转直到输出空串；② 模型连发空串被
`parseIntent("")` 判为"无效意图"，连续 3 次 → `模型连续输出无效意图，终止`。

**根因（R11.1 矫枉过正 + 空输出误判）**：

1. **"有结果但内容相同"被当真进展**：R11.1 把 `hadResult=true` 一律重置计数，
   `contentChanged` 未参与判定。同 id 反复返回同档案 → 假进展永不兜底（log
   迭代 2–6,9,11–14,16–18,20 全返回同一 enemy_profile）。
2. **空响应被判无效意图**：`planner_intent.parseIntent("")` 返回 null → 走
   malformed 分支，3 次硬 error 终止。模型"无话可说"（对重复观察）被当成垃圾输出。
3. **多词被截断**：`SEARCH 特蕾西娅 死亡` 只取第一 token，`死亡` 被丢。

**改动**：

- **同内容也算重复**：`noteSearchProgress` 改为——有结果**且内容变化**才重置；
  有结果**但内容与上次相同**（`hasSearchContentChanged` 判定）→ 与无结果一样
  递增 `searchRepeatCount`/`consecutiveNoResult`。同 id 反复拿同档案的原地循环
  现在会触发兜底（引导/coverage/unresolved）。
- **空输出温和收场**：PlannerLoop 区分"空响应"与"垃圾意图"。空响应不计
  malformed，单独计数 `emptyResponses`（上限 `_maxEmptyResponses=3`），达到后
  `_terminateUnresolved` 温和收场（unresolved），不再 `模型连续输出无效意图`。
  垃圾文本仍累计 malformed 并硬终止。
- **多词查询**：`parseIntent` SEARCH 支持把 `SEARCH 特蕾西娅 死亡 id=...` 中
  `id=`/`top_k=`/末尾数字之前的词合并为完整 query（复合查询）。
- **CLI 电脑测试链**：新增 `tools/run_investigation.dart`——纯 Dart（不依赖
  Flutter-bound store），用 `sqflite_common_ffi` 直开真实 DB 实现 5 个调查工具
  （真实 SQL），注入 `PlannerLoop` + `EntityDisambiguator` + 真实 LLM，在电脑上
  跑完整调查并落盘 `build/investigation_run.json`。配套抽出 `react_event.dart`
  （纯 Dart 事件类型），`react_loop.dart`/`planner_loop.dart` 改从其 import，使
  CLI 不拉入 Flutter SDK。

**测试**：planner_test 28（新增 3 个 R11.2：多词合并、空输出温和收场、内容变化
重置；改写 1 个 R11.1 旧用例为"同内容计重复"）。全量
**205 → 206 passed / 3 opt-in skipped / 0 failed**，analyze 干净。CLI 工具实测
可编译、可开 DB（59 万覆盖行/41 万剧情行）、可调 LLM、可落盘；因本沙箱无有效
API key 未跑通完整调查。

---

## R12：信息流瓶颈复盘（`2026-10-01`，P0 已落地）

R8→R11.2 的修复都集中在终止控制上，真机每轮都出现新的失败形态，但始终没有产出
基于原文的答案。复盘结论：瓶颈在信息流，不在循环。具体是：提取器未接线、Writer
看不到原文、引用校验失联；意图里没有 coverage 和行级原文检索；消歧器收到硬编码
type；计数全局连坐；CLI 数据层不等价；没有评测集。完整证据和修复路线见
`docs/R12_BOTTLENECK_ANALYSIS.md`。

**P0 改动（Phase 1）**：
- **证据笔记本**（`evidence_notebook.dart`）：READ 观察带 DATA 块记录**实际返回**的行区间；
  state 的已读改为多段区间，空洞不再算作已读；提取器结合用户问题挑出相关行，
  输出 `L<行号>: 事实`。行号不在本页内的条目会被丢弃，引用原文由代码从原行复制。
  `InvestigationAgent` 默认用主模型作为提取器（App 之前从未接入提取器）。
- **Writer 基于原文写答案**：输入改为证据笔记加已读原文（≤8000 字），并做行级引用校验
  （`unreadCitations`）。有非法引用时重写一次；仍非法就附加来源警告。
- **新意图**：`COVER <名字|id>` 对应 `search_story_coverage`；`FIND <短语>` 对应新工具
  `search_story_lines`（在剧情原文上做 LIKE，按命中行数排序，结果标注为定位线索）。
  SEARCH 在 prompt 里定位为查实体档案。
- **消歧修正**：同名实体的出场直接合并，不再要求消歧（实测 97% 的同名实体出场完全相同）；
  消歧器现在能拿到候选的真实 type 和 source。
- **计数修正**：无结果计数改为按 key 统计；兜底引导文案按实际状态区分两种。
- 测试：新增 `test/evidence_notebook_test.dart`（10 项）和 story_coverage 的 3 项 DB 级用例。
  Windows 下全量结果为 219 passed / 4 skipped。

---

## 当前已知边界（未做）

- **实体别名 RAG**：玩家错字（"隐德莱希"→"隐德来希"）无别名映射，靠模型猜——数据层问题，暂缓
- **single 答案超长**：`stepMaxTokens` 8192 是单步硬上限，超过报错；分段生成未做
- **qwen3.7-flash 格式遵从**：真机两次卡意图格式/循环比 deepseek 明显；调查类问题或应固定更稳模型
- **summary/factcheck/roleplay** 仍走旧 `ReActLoop`（未迁移 Planner），截断容忍度低于 investigation

---

## 测试与质量

- 全量测试：157（R5）→ 185（R8）→ 188（R10）→ 200（R11）→ 205（R11.1）
  → 206（R11.2），`flutter analyze` 干净
- 关键回归用例：请求有界（<8 条消息）、歧义自动消歧（含消歧辅助选#2/失败回退）、
  HandshakeException 重试、裸思考不当答案、截断重试、database_closed 共享连接、
  摘要全保留（屠戮魔王可见）、已消歧名自动注入 entity_id、重复 SEARCH→coverage→
  unresolved 终结、RESELECT 防重选
- 所有真机问题均有对应会话 JSON 证据（`logs/conversation_*.json`），可回放验证