# 一个剧情问题的完整流程（R16）

> 本文按时间顺序讲一个问题从输入到答案落盘的每一步，以及每一步的参数。总体架构、设计取舍和
> 演进历史见 `AI_ARCHITECTURE.md`；已知缺口见 `KNOWN_LIMITATIONS_AND_DEBT.md`。
> 文中的常量都对应代码里的同名常量，改动时两边一起改。

---

## 0. 一张图

```
输入框 ─► AskChatNotifier.sendMessage
           │ ① 历史（最近 3 轮问答 + 各轮已读章节列表）、上一轮已读原文页
           │ ② auto 模式：QuestionRouter 分类（不思考）
           │ ③ “深度思考”开关 → 本问的 writer client（off / low）
           ▼
         StoryQaAgent.run ─► PlannerLoop.run
           │ ④ 问题上下文：人名、点名的故事集（确定性，无 LLM）
           │ ⑤ 人物出场总览进状态；判断是否追问、是否继承上一轮原文
           │ ⑥ 阅读计划（一次 LLM 调用，不思考）
           │ ⑦ 检索循环：决策器一行意图 → 执行器 → 状态
           │      READ 后：提取器写摘要 + 证据笔记（不思考）
           │      ANSWER 时：充分性检查（不思考）→ 足够就收尾，不足就复核一次
           │ ⑧ writer 流式写答案 → 引用校验（必要时重写）→ 状态合成 → 替换为最终答案
           ▼
         UI（流式渲染、状态行、证据树） + ChatSessionStore（会话 JSON）
```

所有剧情问答（回答 / 梗概 / 核查）都走这一条路；模式只改变 writer 的输出格式和给决策器的一行
任务说明（CLAUDE.md“禁止特判”）。角色扮演走 `ReActLoop`，见 §9。

## 1. LLM 调用一览

| 调用 | 位置 | 思考档位 | 温度 | `max_tokens` | 每问次数 |
| --- | --- | --- | --- | --- | --- |
| 模式分类 router | `question_router.dart` | off | 0 | 256 | auto 模式 1 次 |
| 阅读计划 | `PlannerLoop._draftPlan` | off | 0.2 | 4096 | 1 次 |
| 决策器（一行意图） | `PlannerLoop.run` | off | 0.1 | 4096 | 每步 1 次 |
| 提取器（摘要 + 笔记） | `digestReadPage` | off | 0 | 2048 | 每次 READ 1 次（失败重试 1 次） |
| 消歧器 | `EntityDisambiguator` | off | 0 | 1024 | SEARCH 遇到同名时 |
| 充分性检查 | `PlannerLoop._sufficiencyGap` | off | 0 | 512 | 至多 1 次（ANSWER 时、且有未读项） |
| 写作者 writer（流式） | `PlannerLoop._streamAnswer` | off；“深度思考”时 low | 0.2 | 8192（空答截断时 16384） | 1 次；引用不合法再 1 次 |

- 档位由 `llmClientProvider(ReasoningLevel)` 提供（`llm_provider.dart`），映射到各 provider 的开关
  （deepseek `thinking` + `reasoning_effort`，百炼 `enable_thinking` + `thinking_budget`，未知 provider
  不发参数）。deepseek 不传参数时默认思考且为 high，所以每个角色都显式指定档位；任何剧情角色都不用 high。
- 非流式调用经 `completeWithHeadroom`：回答因 `max_tokens` 截断且内容为空时，上限 ×4 重试一次
  （最多 16384）。
- HTTP：单次请求超时 180 s；网络错误、TLS 握手失败重试 1 次。决策器步骤的网络错误最多再重试 2 次。

## 2. 发送之前（`AskChatNotifier.sendMessage`，`agent_provider.dart`）

1. 正在生成时忽略新输入；记下本问的 generation（取消、过期回调按它判断）。
2. **历史**：`buildStoryQaHistory`，只保留最近 3 轮，每轮 = 问题 + 答案（去掉状态信封）+
   “这一轮已读原文: story:区间…”。不回放工具观察。
3. **上一轮已读原文页**：`lastTurnReadPages`，从上一轮步骤里的 READ 观察解析出来，交给 PlannerLoop，
   是否使用由 ⑤ 决定。
4. **auto 模式**：`QuestionRouter.route`（附上一个问题）→ `verify` / `investigate` / `summarize`；
   失败或空回答回退到 summarize，并在步骤区显示原因。
5. **writer client**：`writerClientReader` 每问读一次 `deepThinkingProvider`——开着就给 low 档 client，
   关着用默认（off）。开关不会重建 notifier，对话不丢。
6. 进入事件循环（§8）。

## 3. 开局（`PlannerLoop.run` 进入循环之前）

1. 新建 `InvestigationState`，步数预算 24（`maxToolSteps`）。
2. **问题上下文**（`namesInText` / `namedStoryTargets`，确定性）：
   - 人名：干员/敌人名与台词 ≥5 行的说话人；更长的已知字符串先占位（“伊比利亚”里的“比利”不算）。
   - 点名的故事：故事集名 ≥2 字；章名、密录名 ≥3 字；写在《》里的不限长度。
   - 人名记入 `questionNames`（writer 原文优先级用，§7.2）。
3. **话题判断**：本问的人名、故事名都在上一轮问答里出现过 → 追问；有新名字 → 换话题，
   状态写“本问提到上一轮没有涉及的…——按本问重新定位”。
4. **出场总览**：最多前 2 个人名，各跑一次 COVER，取“出场总览”部分进状态；超过 15 行时保留
   提及最多的 15 个故事集（仍按故事顺序），并注明其余条数。
5. **继承**：只有追问才把上一轮已读页记为已读（可直接引用、不必重读，也送给 writer）；
   提取器的问题文本附“（承接上一问：…）”。
6. 给已入状态的 story_id 查目录标签（“故事集 关卡号 标签《章名》”）。
7. **阅读计划**（有 plan client 时，App 里总有）：状态行显示“正在制定阅读计划”。
   - 输入：问题 + 当前状态（出场总览、点名的故事）。
   - 要求：第一行“范围：…”；逐个核对总览里提及较多的故事集（活动的上线时间不代表剧情时间），
     落在范围内的都列出；最多 10 项，每项 `- 故事集名（id）：要找什么`。
   - `PlanItem.parse` 只取列表行，括号里的 id 用来打勾。计划作为一条“阅读计划”步骤显示。

## 4. 检索循环（每一步）

### 4.1 决策器请求

```
system : 知识库规则 + 剧情规划说明 + 本模式任务说明 + 意图格式（intentFormat）
history: §2 的历史
user   : 目标: <问题>\n\n当前状态:\n<state.serialize()>
recent : 最近 2 条观察
         - 最新一条原样；
         - 较早的一条若是 READ 页 → 换成“已读 X a-b（n 行）。摘要和笔记在状态里，不必重读”；
           其他超过 600 字的 → 截到 600 字并标“（已截断）”。
```

状态序列化的顺序（`InvestigationState._serialize`）：

1. `步数: 已用 n / 预算`（剩 ≤3 步时追加“先 READ 目录里最关键的未读章节，然后 ANSWER”）
2. 阅读计划（`✓` = 已读过其中章节；只看过梗概不算；`·` = 未完成）
3. 当前计划（决策器上一步 `# …` 的内容）
4. 重点原文（被固定的短段落，§4.5）
5. 问题提到的故事、各人物出场总览（每行附“已读 n/m 章”）、库中没有的写法、换话题提示、
   目标实体与已消歧名字
6. 已看梗概：最近 2 个故事集给完整目录（已读章节 `✓ 区间` 且去掉梗概，未读章节附梗概 ≤120 字）；
   更早的折叠为“已读章节 + 其余 N 章已折叠；需要时再 OUTLINE <id>，不占步数”
7. 已读章节：每章“story［标签］:区间”、摘要、证据笔记；决策器视图最多显示 40 条笔记
   （最新的章节优先，较早章节写“另有 k 条已折叠”），没有相关笔记的章节写“没有与问题直接相关的行”
8. 证据（COLLECT）、已查地图、已检索（FIND/COVER → 前 5 个 story）
9. 已读章节所属故事集还没看梗概时的一行提示

### 4.2 解析

- 回复按 `#` 拆成“意图 + 计划注记”（`splitPlanNote`），注记存为“当前计划”，只为连续，不参与判定。
- `parseIntent`：一行只能一个意图；`OUTLINE` 的目标去掉《》，`名（id）` 取括号里的 id。
- 空回复：提示重来，连续 3 次 → 收尾（`emptyReplies`）。乱码意图：连续 3 次 → 报错结束。
- 迭代安全上限 100 次（`safetyCap`）。

### 4.3 ANSWER / DONE

1. 至少完成过 1 次工具调用（否则要求先检索）。
2. **复核（每问一次）**——条件：剩余步数 > 3，且有未读项：
   - 阅读计划里未完成的项；
   - 出场总览里提及 ≥5、读了不到一半章节的故事集（按“提及 × 未读比例”取前 4，已作为未完成计划项
     列出的不重复）。
3. 有未读项时先做**充分性检查**：问题 + 状态 →“足够”或“不足：缺什么”。
   - 足够（或检查失败）→ 直接收尾（`answer`）。
   - 不足 → 观察里列出“回答还缺：…”、未读计划项、未读故事集，预算一次性 +8，继续检索；
     再次 ANSWER 即收尾。
4. 收尾进入 §6。

### 4.4 执行一个工具意图

1. 意图映射到工具（READ/SUMMARIZE → `read_story_lines`，FIND → `search_story_lines`，
   COVER → `search_story_coverage`，OUTLINE → `get_story_outline`，MAP、SEARCH、COLLECT 同名工具）；
   RESELECT 只切换消歧候选。
2. SEARCH 一个已消歧过的名字时自动带上 entity_id。
3. **进展控制**：步数 +1；状态指纹（已读行数、笔记数、有字面命中的新章节、证据行、已查地图、
   梗概、目标实体）没变则“停滞”+1。步数超预算 → 收尾（`budget`）；停滞 4 步提醒，8 步收尾（`stalled`）。
4. READ 的 story_id 没有 `.txt` 时补上；起点落在已读区间里时推到第一行未读行。
5. **去重**（SEARCH / FIND / COVER / MAP / OUTLINE / COLLECT / READ / SUMMARIZE，按规范化参数）：
   - 重复的 OUTLINE：从缓存回复，不占步数；目录仍完整在状态里就只回一句指引，被折叠的就再给全文
     并重新放到“最近 2 个”里。
   - 重读已读原文：见 §4.5。
   - 只由“库中没有的写法”组成的 FIND/COVER：直接拦下。
   - 其他完全相同的命令：拦下，不占步数；连续 3 条被拦下 → 收尾（全是重读 → `onlyRereads`，
     有重复检索 → `repeatedSearches`）。
6. 发 `status` 事件（“第 n 步 · 阅读 …/搜索原文“…”/看梗概 …”）和 `toolCall` 事件，执行工具。
7. 续读推过章末、工具返回 “No lines…” 时，改写为“X 已经读到结尾（已读 a-b），没有更多行”。
8. SEARCH 遇到同名多实体 → 消歧器按问题选一个（失败选第 1 个），记入状态，可 RESELECT。
9. 更新状态：READ 记录实际返回的行段；OUTLINE 存紧凑目录并缓存全文；FIND/COVER 记录
   “库中没有的写法”和检索结果；查新 story 的目录标签。
10. 观察进入近程窗口（保留 2 条），发 `toolObservation` 事件。
11. **READ 之后**：页面存入 `readPages`；提取器对本页输出一行摘要和至多 `行数/15`（10–25）条
    `L<行号>: 事实`；行号必须在本页内，引文由代码从原行复制；调用失败重试一次。

### 4.5 重读已读原文

决策器要已读原文，说明它想再看一眼（它手里只有摘要和笔记）。处理顺序：

1. 前 2 次（每问）：从手头的页面把那段原文再给它看一次，占一步。
2. 之后，如果这段 ≤60 行、且固定段落合计 ≤80 行：把它固定进状态的“重点原文”，每一步都可见，
   不占步数。
3. 否则，若本问还没有过“重读复核”：列出未读计划项和读得少的故事集（不做充分性检查），
   预算 +8（与 §4.3 共用这一次加预算），不占步数。
4. 再往后：拒绝（附上未完成的计划项），不占步数；连续 3 次 → 收尾。

## 5. 工具要点

| 工具 | 关键参数 |
| --- | --- |
| `read_story_lines` | 不写行号读整章：默认 450 行，存储层上限 500，观察上限 2 万字；不存在的 id 按关卡号（去前导零）列出真实 story_id |
| `search_story_lines`（FIND） | 关键词各词 OR、按 IDF 加权排序 + 可选向量召回，RRF（k=60）融合；默认 6 个故事、最多 10；单个章节文件不能当范围（提示改用 READ）；`activities/<id>` 视为活动范围；主线、密录的故事集 id（`main_9`）作范围时搜全库再按该故事集过滤；全库 0 命中给近似名，范围内 0 命中报“范围外命中” |
| `search_story_coverage`（COVER） | 先“出场总览”（全部故事集，按上线时间，主线按章号），再按故事集轮流分配明细；观察上限 4800 字；故事集 id 作范围同上 |
| `get_story_outline`（OUTLINE） | 认故事集名、`主线·名`/`干员密录·名`、id、scope、story_id；观察上限 6000 字 |
| `search_local_lore`（SEARCH） | 只查实体档案，不查剧情原文 |

## 6. 收尾（`PlannerLoop._finish`）

1. 发 `status`“正在撰写答案”。
2. **送给 writer 的原文**（`buildWriterSource`，≤60000 字）：
   1. 每条证据笔记所在行的前后 5 行（最新的笔记优先）；
   2. 问题人物名字出现的行的前后 1 行，各章轮流（每轮每章 20 行）；
   3. 其余行，各章轮流（每轮每章 20 行）；
   4. 输出按章节、行号排序，跳过的段落标 `…`，有目录标签的章节先写一行〔story = 标签〕。
3. **writer 请求**：
   - system：只依据证据笔记和已读原文、引用格式 `story_id:行号`、正文用章节名、梗概不能当证据、
     考虑前因后果、未覆盖写“资料未覆盖”、近似名规则（问题里的名字库中没有、而原文对得上相近名字时
     按那个名字作答并在第一句说明）、本模式的输出格式、末尾单独一行 `[COVERAGE: full|gaps]`
     （宽泛问题主要阶段都有原文就算 full）、停止原因说明（预算/停滞时一句中性的话；什么都没读到时
     要求如实说明知识库未找到）。
   - user：问题 + `serializeForWriter()`（全部笔记，不含步数和计划）+ 已读原文。
4. **流式**：思考内容（如有）→ `reasoningToken`；正文 → `finalAnswerToken`。`length` 截断且没有正文
   → 上限 16384 重来；有正文 → 末尾加“答案达到长度上限，可能不完整”。
5. **引用校验** `unreadCitations`：有引用落在未读行 → `finalAnswerReset`（步骤里显示“正在修正引用：
   n 处…”）→ 带着不合法引用列表流式重写一次；仍不合法 → 末尾加“来源警告”。
6. 剥掉 `[COVERAGE: …]`；核查模式规范化结论行（没读到原文 → `unavailable`；有定论但没有合法引用
   → `uncertain`）。
7. **状态合成** `answerStatus`：什么都没读到 → `not_covered`；否则 `full` → `answered`、`gaps` →
   `partial`；writer 没写这一行时按停止原因（ANSWER/DONE/只剩重读 → answered，其余 → partial）。
8. 发 `finalAnswerReplace`：`[STORY_ANSWER: status=… | confidence=…]` + 正文，然后 `complete`。

## 7. 事件与界面

### 7.1 事件类型（`react_event.dart`）

| 事件 | 来源 | notifier 的处理 |
| --- | --- | --- |
| `status` | 每个工具步、计划、撰写开始 | 更新消息的 `liveStatus`（状态行） |
| `toolCall` / `toolObservation` / `thought` | 检索步骤 | 追加到步骤列表；录制时写入会话记录 |
| `finalAnswerToken` | writer 流式正文 | 追加到答案缓冲，合并刷新 |
| `reasoningToken` | 开了思考的 writer | 追加到 `reasoning`（只显示，不保存） |
| `finalAnswerReset` | 引用重写前 | 清空答案缓冲，步骤里加一条原因 |
| `finalAnswerReplace` | 收尾 | 用最终答案（含信封）整段替换 |
| `error` / `complete` | — | 出错标记 / 结束流式、清空状态行与思考内容 |

答案文本由 `applyAnswerEvent` 计算（token 追加、reset 清空、replace 覆盖）；测试用 `finalAnswerOf(events)`。

### 7.2 渲染（`chat_bubble.dart`、`ai_chat_page.dart`）

- `StreamCoalescer`：正文与思考内容的刷新合并到每 60 ms 最多一次；reset/replace/complete 立即刷新。
- 生成中：状态行显示 `liveStatus`（可点开步骤）；有思考内容时显示可折叠的“思考过程”（最后 800 字）；
  正文实时把 `story:行` 渲染成可读出处，并隐藏正在生成的 `[COVERAGE…`。
- 完成后：状态行改为“已作答 / 部分作答 / 知识库未覆盖 · 置信度 · 推理 n 步”；证据默认折叠为
  “证据 N 处 · 来自 M 个故事”，展开为 故事集 → 章节 → 行号。
- 滚动：新问题自动滚到底；生成中只有停在底部时才跟随；用户上滑后停止跟随并出现“↓”。

## 8. 落盘

录制开启时（设置里“保存 AI 对话记录”），每轮写入 `chat_sessions/` 的会话 JSON：用户模式、生效模式、
router 原始输出、模型、每步决策器原始回复（含 `# 计划`）、工具与参数、观察、最终答案（含信封）、
状态、耗时、最终的状态序列化（`memory`）。思考内容不保存。真机问题都应能用这份 JSON 回放；
电脑端用同一链路复现见 CLAUDE.md“电脑端调查复现”。

## 9. 角色扮演（不在统一流程里）

`RoleplayAgent` → `ReActLoop`（Thought / Action / Final Answer 格式，单个检索工具锁定该角色的
entity_id），client 为 off 档。每步流式请求；出现 `Final Answer:` 之后的文字实时显示，这一步若
不被采纳（工具调用不足等）会在下一步开始前清掉；最终经来源守卫后整段替换。
