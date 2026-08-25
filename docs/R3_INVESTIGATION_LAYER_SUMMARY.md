# R3 开发总结：AI 检索优化阶段 P1 —— 跨章节推理层

> 完成日期：2026-08-24
> 范围：`docs/AI_RETRIEVAL_OPTIMIZATION.md` 阶段 P1 的实现（跨章节细节定位 +
> 多候选对比 + 调查协议 + UI 接线），依据 `docs/R3_DESIGN_DECISIONS.md` 四项决策。
> 状态：**核心与 UI 接线均已完成并通过全部验证**；剩余：2–3 个真实剧情谜题固定
> 用例与单次调查成本量化（R3b 收尾）。

---

## 1. 背景与目标

P1 解决 P0 覆盖层之上的推理问题：答案需要跨章节对齐细节（凶器、行为模式、措辞）
才能推出，且大量中间章节可能误导。工程目标：相关原文可达、结论必须附证据链与已读
范围、覆盖缺口透明。R3 交付：speaker 覆盖扩展、两个调查工具、调查 Agent（S0–S8）、
代码级结论校验、ReActLoop 上下文裁剪。

## 2. 工程变更

### 2.1 speaker 名扩展（`story_coverage_builder.dart`）

- `_expandSpeakerEntities()`：统计 `story_lines.speaker` 出现行数 ≥ 3 的说话人，
  若名字不在 `entities` 或 `entity_aliases` 中，创建轻量实体
  （`id='speaker:<name>'`、`entity_type='speaker'`、`source_type='story_speaker'`、
  canonical alias），并入 trie——有台词 NPC 的出场现在可被确定性枚举与消歧；
  正式实体优先，不覆盖已有名字。

### 2.2 DATA 块契约（`tools/observation_data.dart`）

决策 1 落地：`appendDataBlock` / `parseDataBlocks`——工具在观察尾部输出
`DATA: <json>`；transform 优先解析 JSON，失败回退文本标记。JSON 由工具生成，
可靠性由代码保证。

### 2.3 新工具（`lib/core/agent/tools/`）

| 工具 | 行为 | DATA 块 |
| --- | --- | --- |
| `find_detail_echoes` | 从已知段落（source_text 或 story_id+行区间）提取稀有特征词（`rare_terms` IDF 白名单，排除实体名/别名子串），**按"命中不同章节数"排序选词**（直接优化跨章节呼应定位），`content LIKE` 检索全库（排除源章节），返回 term/story_id/行号/snippet | `{"type":"find_detail_echoes","terms":[...],"matches":[...],"total":N}` |
| `collect_suspect_evidence` | 经 `entity_story_mentions` 返回某嫌疑实体全部出场行（按 scope 过滤、claim_terms 标记、run 级分页） | `{"type":"collect_suspect_evidence","entity_id":...,"evidence_rows":N,"scopes":[...],"total_runs":N,"next_page_token":...}` |

### 2.4 调查 Agent（`investigation_agent.dart` + prompt）

`StoryInvestigationAgent` 注册全部 6 个工具（search_local_lore + 3 个覆盖层工具 +
2 个调查工具），无步数上限（决策 4 修订版）：`safetyMaxIterations=1000` 仅作防失控
安全网、`stepMaxTokens=4096`、`minimumToolCalls=4`、`maxObservationHistory=8`。prompt 实现 S0–S8 阶段协议 +
结论信封格式 + 预算规则（精读 ≤3 章、每章 ≤3 页）。

### 2.5 结论校验（`investigation_verdict.dart`）

`validateInvestigationVerdict` 三道代码级门槛：

1. **S6 门槛**：culprit 结论仅在 ≥2 个候选有非空证据集（解析 collect_suspect_evidence
   的 DATA 块）或模型显式声明 single-suspect-exhausted 时允许；否则降级
   `culprit=unresolved | basis=insufficient_evidence` 并附警告。
2. **行级 provenance**：答案中每个 `story_id:line` 引用必须能在 observations 中
   找到对应行（`Story:` 头 + `N |` 行解析）；缺失引用附 Source warning（applySourceGuard
   的行级扩展）。
3. **已读范围**：复用 `validateCoverageReport` 规范化 Coverage 行。

### 2.6 ReActLoop 分层记忆（`react_loop.dart` + `loop_memory.dart`）

决策 2 最初落地为 `maxObservationHistory`（占位消息替换最旧观察）；M1（R6）升级为
**分层记忆**：请求 = base（system+历史+query）+ `LoopMemory` 记忆块 + 近程窗口
（最近 2 轮原文）。记忆块由代码维护（已读章节索引、已查地图、已收集证据）并保留
每轮模型 Thought 摘要——旧观察离开窗口后其结论仍可见，消除重复读取。
transform 侧的 `observations` 快照始终完整——分层只影响模型可见上下文，
不影响代码级校验。`maxObservationHistory` 参数保留但不再生效。

### 2.7 UI 接线（R3b 第 1 项，决策：新增"剧情调查"tab）

- 入口形态决策：新增第四个 tab「剧情调查」（Fact-check / Summary / Investigation /
  Roleplay 并列）。理由：调查是独立 Agent（6 工具、S0–S8 协议、独立结论信封），与
  Summary/Fact-check 工作流差异大；独立 tab 与 Role-play 的结构一致，且不触碰
  Summary 既有行为与回归。
- `InvestigationChatNotifier`（继承 `ChatNotifierBase`）：ReAct 历史重建抽取为共享
  顶层函数 `buildReactHistory`（Summary 与 Investigation 共用，行为不变）；
  取消/错误标记 `[INVESTIGATION_CANCELED]` / `[INVESTIGATION_ERROR]`。
- AI 页：`DefaultTabController` 3→4，新增调查 tab（来源栏、空态建议、输入区复用
  现有组件）。
- 调查气泡渲染（§5.4 证据卡扩展）：`chat_bubble.dart` 对含结论信封的助手消息渲染
  调查区块——**结论条**（culprit + 置信度 + 依据，unresolved 用警示色）、**证据链
  引用 chips**（回答中的 `story_id:line` 提取）、**已读范围条**（read/mapped/skipped）；
  markdown 正文剥离信封与 Coverage 行避免重复。解析辅助在
  `features/ai/investigation_ui.dart`（纯函数，可单测）。
- 新增 ARB 键 16 个（中英），`flutter gen-l10n` 重新生成。

## 3. 验证结果

| 验证项 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` 全量 | **111 passed / 3 opt-in skipped / 0 failed**（R3 105 → +6 UI 测试） |
| 新增 `test/investigation_test.dart` | 10 项全过（R3 核心） |
| 新增 `test/investigation_ui_test.dart` | 6 项全过（解析辅助 + 气泡渲染 + 四 tab 页面） |
| 回归 | story_coverage（16）/ gamedata_build（9）/ agent（45）/ fact_check_widget / settings 全部保持通过 |

UI 测试覆盖：信封/Coverage 行/行引用解析、`stripInvestigationMarkers`、
气泡渲染（结论条、证据链 chips、已读范围条、marker 从正文剥离）、unresolved 警示色、
AI 页四 tab 与调查空态。

新增测试覆盖：

1. speaker 扩展：无实体行的 ≥3 行说话人 → `speaker:<名>` 实体 + coverage 命中；
   真实实体不被 shadow；
2. `find_detail_echoes`：稀有词跨章节命中（含源章节排除）、实体名 bigram 被过滤、
   DATA 块结构；
3. `collect_suspect_evidence`：证据行 + DATA counts + scope 聚合；
4. verdict transform：S6 满足保留 culprit / 不满足降级 unresolved + 警告 /
   single-suspect-exhausted 放行 / 伪造行引用附 Source warning；
5. ReActLoop 裁剪：12 轮工具调用后，模型收到的完整 Observation ≤ 8 且出现裁剪占位。

## 4. 用户端影响

1. **跨章节谜题的推理能力**（能力已就绪，UI 接线见 §6）：调查 Agent 能枚举出场、
   精读原文、用凶器等细节词跨章节找伏笔、逐嫌疑人收集证据集再对比，且结论受
   S6 门槛与行级 provenance 双重代码约束——**模型不能凭印象或多数章节指向就断言
   凶手**。
2. **覆盖更全**：有台词 NPC（如路人、次要角色）现在可被搜索与枚举，不再只覆盖
   干员/敌人/物品表实体。
3. **上下文可控**：长调查不再无限撑爆模型窗口；历史裁剪对用户无感（校验仍基于
   完整证据快照）。
4. **可审计**：结论信封、证据链行引用、已读范围、反方证据、置信度、替代解读
   六要素齐备，且伪造引用会被显式警告。

## 5. 实际效益

- **P1 核心能力闭环**：S0–S8 协议从"prompt 期望"升级为"代码门槛 + DATA 契约"
  （决策 1/2/4），延续项目"用代码而非 prompt 保证行为"的架构原则；三个门槛
  （S6/行级 provenance/已读范围）均有确定性单测。
- **覆盖层复用**：`rare_terms` 成为 IDF 白名单、`entity_story_mentions` 成为证据集
  数据源、`story_lines` LIKE 检索成为伏笔定位通道——R1 的构建产物被 P1 直接消费，
  无重复建设。
- **成本可预测**：固定 12 轮预算 + 精读上限 + 历史裁剪，单次调查的 LLM 调用与
  token 量级有确定性边界（真实用例量化列入 R3b QA）。
- **零回归**：ReActLoop 裁剪默认值对既有 Agent 无行为影响（既有测试观察数 < 8），
  全部既有测试保持通过。

## 6. 遗留与下一步（R3b 收尾）

- **UI 接线（§5.4）：已完成（2026-08-24）**——新增"剧情调查"tab + 结论条/证据链
  引用/已读范围条渲染（见 §2.7）。
- **真实剧情谜题固定用例未做**：2–3 个真实谜题（按实际剧情选定）的固定 QA 与
  单次调查成本量化（调用次数/token 量级）列入 R3b 收尾，`RETRIEVAL_QA.md` 相应更新。
- **已知边界**：艺术化指称（"那个女人"、代词回指）确定性方案无法覆盖，已按
  决策 3 写入文档；`find_detail_echoes` 的 `content LIKE` 全表扫描在 40 万行上的
  真机延迟待量化（候选选词阶段最多 12 次扫描，真机测试时评估是否收窄）。
