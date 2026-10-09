# AI 架构（Ask 问答 + GameData 检索）

> 当前：v0.13.0 + 开发中的 0.14（问答重构，见 `R17_TOOL_AGENT.md` §5）。剧情问答由**工具型 Agent** `LoreAgentLoop` 完成：一个模型、通用工具、对话只追加、代码核对出处。
> 0.12 起有两个知识库（明日方舟、终末地），Agent 看到的是合并的检索面（§3）。
> 结构、工具、提示词约定与验收数据见 **`R17_TOOL_AGENT.md`**；服务商差异见 `LLM_PROVIDERS.md`；知识库表见 `GAMEDATA_BUILD_PIPELINE.md`。

## 1. 链路

```
用户问题 ──► AskChatNotifier.sendMessage（没有模式；Wiki/提要/复核/子助手四个可选项来自 AnswerOptions，后两个默认关）
              │   紧接上一条回答时带上一问的对话（LoreConversation，工具结果折叠），否则带最近 3 轮问答文本
              │   “深度思考”开关 → 本问使用 low 档思考的 client
              └─ StoryQaAgent ─► LoreAgentLoop
                                   预检索（0.14，有向量时）：问题原文先跑一次 search（两个游戏 + Wiki，按来源分组），附在问题下面
                                   system：库结构（含资料页说明 loreLibraryGuide）+ 工作方式 + 出处格式 + 输出格式
                                   每轮 streamTurn(tools) → 守门（拆分粘连、按 schema 校验）→ 工具并发执行 → 结果追加
                                   最终答案（JSON）→ 出处核对（SeenLines；少量未核实由代码删去，多了退回一次）→ [审稿] → 按阶段整理（只发条目）
                                   → [STORY_ANSWER: status=answered|partial|not_covered]
       工具：search / read_story / grep / sql（只读）/ outline / similar_names / [delegate]
             （0.13，“Wiki 资料”开着时）wiki_search / wiki_read → WikiLookup（PRTS / Warfarin，快照）
                                   │
              GameDataKnowledgeStore（共享只读连接；sql 另开只读 FFI 连接，超时 sqlite3_interrupt）
                                   │
              ChatSessionStore（chat_sessions/ 每对话一个 JSON：每次模型输出、工具、观察、答案、usage、timeline）
```

- **主要知识源是 GameData**。0.13 起 Agent 还可以查 PRTS / Warfarin Wiki 作为**二手**证据（第三种出处 `wiki:…`，同一套核对；
  原文优先，只有 Wiki 支持的说法要写明），见 `WIKI_EVIDENCE.md`。用户资料和 Wiki 页里选中的文字只作上下文（“用它提问”放进提问框草稿），不是证据。
- 界面把工具调用与输出配对成时间线（`features/ai/work_steps.dart`），不显示 Thought/Action/Observation 原文。
- 事件类型在 `react_event.dart`（名字沿用 ReAct，内容是原生工具调用）。角色扮演及其文本式 ReAct 已在 0.11 删除。

## 2. 设计原则

- **读原文的模型就是写答案的模型**：信息每多一次交接就丢一部分（R8–R16 分步流程的根本问题）。
- **工具要有表达力**：只读 SQL 一次看全语料；grep / read_story 整章读、章内搜；0 命中如实报告并附近名。
- **对话只追加**：前缀缓存命中 85–90%；超过上下文预算才把最早的工具结果折叠成指引。
- **不写进度规则**（预算提示、重读阶梯、阅读计划）：R13–R16 证明它们只对样例有效。
- **代码只做确定性的事**：出处是否被工具展示过、状态信封、核查结论降级、只读 SQL 边界。
- **没有问题类型分支**：同一流程、同一份提示词；提示词与工具说明里不放具体人物/章节/活动/剧情手法（守卫测试）。

## 3. 检索层（schema 5）

- 表与构建见 `GAMEDATA_BUILD_PIPELINE.md`。Agent 主要用：`story_lines`（逐行原文，`kind`）、`entries`/`collections`/`entry_links`（条目、归属、绑定）、
  `normalized_records`（档案等，出处 `record:<id>`）、`story_catalog`（章节名、顺序、梗概、上线时间）、`story_chunk_vectors`（可选语义召回）。
- `search`（0.14，取代 `find`）：有向量服务时按意思检索为主，问题里出现的库中名字做关键词，RRF 融合；所有已安装游戏和 Wiki 同时查、按来源分组；
  打印出的原文行算读过、可以引用。向量只在配置的模型/维度与 manifest 一致时启用；没有向量时退回关键词并提示“问答质量可能下降”。
- 覆盖层、目录、梗概、向量都只是**定位线索**，不参与事实判定。
- 资料页的检索（`library_search.dart`）与 Agent 无关：名字/代号 → 相近名字 → 正文提到；“按意思找剧情”是手动按钮。
- **两个游戏（0.12）**：每个游戏一个库文件，表结构相同；终末地的所有 id 以 `ef/` 开头（`game.dart` 的 `gameOfId`），所以出处、阅读历史、
  资料页路由拿到 id 就知道去哪个库。`MultiGameRetrieval` 把两个库合成一个检索面：按 id 的调用去对应的库，`search`/`grep` 默认两个库都查、按游戏分组
  （同一个嵌入模型，分数可比），`sql` 用 `game` 参数选库。出处标签带“终末地·”前缀。工具参数见 `R17_TOOL_AGENT.md`。

## 4. 测试与成本

- 离线：`flutter test`（mock LLM，FFI 临时库，生产 schema）。
- 真实同链路：`test/live/ask_pipeline_live_test.dart` 驱动 App 的 `askChatProvider`，只替换启动注入的 provider 与平台路径；每题输出会话 JSON 与 `*.summary.json`。
- 成本规则：先离线；每方面最多 2 个代表性用例，逐题串行；开发者同意后才花钱。

## 5. 演进简史

| 轮次 | 做了什么 | 为什么 |
| --- | --- | --- |
| R0–R2 | 构建代码进 `lib/`；store 换库自动重开；App 内构建/增量更新 | 桌面与 App 一套构建；不依赖发版节奏 |
| R1 | schema 3 确定性覆盖层 | “某角色在哪出场”不再依赖措辞 |
| R5–R7 | 会话 JSON 持久化与回放；分层记忆 | 真机问题可复现；截断导致重读 |
| R8–R11 | PlannerLoop 三角色、自动消歧 | 上下文膨胀；同名实体死循环（这些补丁后来都删了） |
| R12 | 证据笔记、引用校验、可选向量召回、同链路 live 测试 | 提取器未接线、writer 看不到原文 |
| R13 | 删除全部问题类型特判，代码判定 status，特判守卫 | 结论协议锚定“凶手类”问题 |
| R14–R15 | 故事目录与官方梗概、近似名、全库总览 | 只看得到文件名；错别字让检索打转 |
| R16 | 真流式、按角色设定思考档位 | 答案整段蹦出；所有角色都在 high 档思考 |
| **R17** | **工具型 Agent**：删除 PlannerLoop 及其状态/提取器/writer/消歧器 | 通用 agent 直接读库，全面优于 R16 |
| R18 | 审稿子 agent（读者视角）+ 按阶段整理 | 答案平铺、故事后段揭示的性质后知后觉 |
| v0.10.7 | 删除 自动/概括/核查/回答 模式与路由 | 模式只改输出格式，路由多一次调用 |
| 0.11 | 资料页说明进提示词（`loreLibraryGuide`）；复核/提要可选；服务商兼容；删除角色扮演；工作过程时间线 | 条目层上线；非 GLM 服务商空回复；界面可读 |
| 0.12 | 终末地知识库；`MultiGameRetrieval`，工具带 `game`；提示词加“两个游戏”一节；一个任务一篇剧情，提示词说明跨种类的先后不可推断 | 第二个游戏；终末地的对话种类各自编号 |
| 0.13 | Wiki 工具（`wiki_search`/`wiki_read`）与 Wiki 出处：段落编号、版本快照、同一套出处核对；“Wiki 资料”开关 | 库里没有的整理与资料；玩家常用的 Wiki 可以引证 |
| 0.14 | 统一检索 `search` + 预检索；工具调用守门；数据库连接独立；空回复只对一轮降级；出处少量问题由代码处理；整理只发条目；审稿/子助手默认关；工作过程可读 | 真机 10 个会话：17% 调用出错、数据库被关、一题 1.5–24 分钟、单题百万 token |

R12–R16 的逐轮真机数据已删（git 历史可查，`docs/AI_ARCHITECTURE.md` 2026-10-07 之前的版本）。
