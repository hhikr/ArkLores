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

---

## 当前已知边界（未做）

- **实体别名 RAG**：玩家错字（"隐德莱希"→"隐德来希"）无别名映射，靠模型猜——数据层问题，暂缓
- **single 答案超长**：`stepMaxTokens` 8192 是单步硬上限，超过报错；分段生成未做
- **qwen3.7-flash 格式遵从**：真机两次卡意图格式/循环比 deepseek 明显；调查类问题或应固定更稳模型
- **summary/factcheck/roleplay** 仍走旧 `ReActLoop`（未迁移 Planner），截断容忍度低于 investigation

---

## 测试与质量

- 全量测试：157（R5）→ 185（R8）→ 188（R10），`flutter analyze` 干净
- 关键回归用例：请求有界（<8 条消息）、歧义自动消歧、HandshakeException 重试、裸思考不当答案、截断重试、database_closed 共享连接、摘要全保留（屠戮魔王可见）
- 所有真机问题均有对应会话 JSON 证据（`logs/conversation_*.json`），可回放验证