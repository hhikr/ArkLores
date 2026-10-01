# ArkLores 已知限制与技术债根因分析

> 基准：v0.9.0 发布线与 dev 分支 2026-08-07 状态<br>
> 维护：本文档随代码与验收状态更新；"已关闭"条目保留记录，不再反复分析<br>
> 关联文档：`implementation_plan.md`（路线）、`ARKLORES_V0.9_TECHNICAL_REPORT.md`（架构审计）、
> `GAMEDATA_BUILD_PIPELINE.md`（数据契约）、`RETRIEVAL_QA.md`（验收缺口）

## 1. 目的与阅读方式

ArkLores 的文档体系已经回答了"系统如何工作"（技术报告）、"按什么路线演进"
（implementation plan）与"哪些验收还没做"（retrieval QA）。本文档回答另一个问题：
**这些限制和技术债为什么存在，以及修复它们的真实成本与触发条件**。

每个条目按以下结构展开：

- **现象与影响**：现状描述、谁受影响、影响程度。
- **根因分析**：按"历史成因 → 设计权衡 → 未修复原因"展开，不满足于
  "没时间做"的结论，尽量追溯到具体的架构决策与成本结构。
- **当前缓解**：已有保护措施，说明该弱点并非完全没有防线。
- **修复方向与触发条件**：怎么做、什么情况下值得做、由谁（哪类变更）触发。

状态图例：**Closed**（已关闭）/ **Open**（开放）/ **Mitigated**（部分缓解）。

## 2. 已关闭项

### 2.1 Android 真机端到端验收（Closed）

**现象与影响**：v0.5–v0.9 的 QA 记录反复出现 "Android 真机…待验收 / Not verified"，
涉及 Role-play 存档恢复、WebView 原生选区、TalkBack、横屏、软键盘、长会话与双主题渲染。
这些是桌面自动化测试无法覆盖的交互面，长期悬空意味着"功能可用"只被证明到
Widget 测试层级。

**根因分析**：

- 历史成因：项目从 2026-07-12 初始化到 v0.9.0 封盘（2026-07-15）只有约 4 天密集开发，
  每个版本都先保证"自动化测试 + 固定 QA + release 资产"闭环，真机验证依赖人工操作，
  与发布节奏不匹配，因此被统一记为 deferred。
- 测试策略的取舍本身是合理的：协议、解析、检索、布局用临时 SQLite + Widget 测试
  自动化覆盖；WebView 原生行为、系统辅助功能、真实键盘只能真机验证。问题只在于
  真机环节始终排在最后，且没有任何机制强制它在发布前完成。
- 项目是个人开发，真机验证依赖开发者手头设备的可用时间；在桌面验证全部通过后，
  发布压力会自然把真机环节推到"之后补"。

**状态**：2026-08 已由开发者个人在代表性 Android 真机上完成，覆盖知识库下载/安装/替换、
检索、Summary / Fact-check / Role-play 对话、Wiki 双站浏览与阅读器、双主题/双语、
TalkBack 与横屏，结果符合预期。历史文档中的 "Not verified: Android 真机…" 条目
视为已被该轮验收关闭，不再逐条修订。

**残留**：真机**功能**验收已关闭；真机**性能指标**（查询延迟、内存峰值、安装耗时）
仍无量化记录，见 §7.1。

## 3. 发布工程

### 3.1 Android release 使用 debug certificate 签名（Open）

**现象与影响**：GitHub Release 中的 APK 是 release-mode（优化构建）但使用 Android
Debug 证书签名。它不是商店正式包；用户未来从 debug 证书版升级到正式签名版时，
签名不一致会导致覆盖安装失败，需要卸载重装并丢失数据。

**根因分析**：

- 历史成因：Flutter 工程模板默认使用 debug signing config，v0.1.0 初始化后从未更换；
  项目的发布目标从一开始就是"可安装的验收包"，让测试者能装上体验，而不是上架。
- 成本结构：正式 keystore 需要长期安全保管（丢失即永久无法向老用户升级），
  CI 集成需要加密存储与解密流程，签名切换本身会造成覆盖安装断裂——这三个成本
  在没有商店分发需求时全部是纯投入。
- 未修复原因：正式发布工程（keystore、升级策略、隐私说明、release checklist）
  一直排在功能与数据质量之后；在 debug 证书已能满足"个人 + 测试者分发"的前提下，
  没有触发修复的外部压力。

**当前缓解**：README、CHANGELOG 与 release notes 明确标注 "debug-certificate 验收包"，
不冒充正式签名；资产 SHA-256 全部记录在 CHANGELOG，可校验来源。

**修复方向与触发条件**：决定正式分发（商店上架或公开 beta）时，建立 keystore 生成与
保管流程、签名切换的升级路径（提前发布正式签名版过渡包）与可重复 release checklist；
若引入 CI，keystore 以加密方式存入 CI secrets。

### 3.2 无正式 CI workflow（Open）

**现象与影响**：`.github/` 只有工具 hooks，没有自动执行 test / analyze / 固定 QA /
release 资产校验的 workflow。所有验证依赖开发者本地手动执行，存在漏跑或
环境差异导致"本地通过、发布后不一致"的风险。

**根因分析**：

- 历史成因：项目是单人开发，本地验证命令已在 `CLAUDE.md` / `CONTRIBUTING.md`
  中固化为硬性要求，且每个版本的 CHANGELOG 都记录实际验证结果——手动流程
  已经形成纪律。
- 成本结构：GitHub Actions 需要为 Flutter + Android SDK + sqflite FFI 搭 runner 环境，
  构建缓存策略，以及（若要做签名发布）keystore 的加密管理；对发布频率约
  每周一次的项目，CI 的边际收益主要是"防漏跑"与"发布可复现"，两者在
  手动纪律下已被部分覆盖。
- 权衡：项目选择先把有限精力投入数据质量与检索 QA（这些是产品正确性的核心），
  工程化自动化排在后面。

**当前缓解**：验证命令文档化并作为提交前要求；每次发布记录验证结果与资产 hash。

**修复方向与触发条件**：v1.0 前按路线要求建立 CI（test、analyze、asset 元数据校验、
release packaging），并加入 secrets 扫描防止 API key 进入提交。

## 4. 数据产品化

### 4.1 知识库是一次性 release 快照，无 update manifest（Open）

**现象与影响**：App 只能下载编译期注入的固定 URL + SHA-256 的 `.db.gz`；DB 内部
`gamedata_manifest` 表和外部 manifest JSON 记录了来源 commit 与计数，但 App 没有
"检查新版本、展示变更摘要、提示更新"的能力。知识库刷新 = 发布一个新 release。

**根因分析**：

- 历史成因：v0.4.5 架构转向的目标是打通"固定 source commit → 可复现 DB →
  发布资产 → App 下载校验替换"这条闭环；update manifest 是闭环之后的
  "数据产品层"，属于第二个问题，当时没有触发需求。
- 设计约束：App 侧 `GameDataInstaller` 的契约是"注入 URL+SHA → 校验 → 原子替换"，
  是单资产协议。升级到 manifest 协议需要定义 game、language、schema version、
  source commit、最低 App 版本、迁移说明等字段（字段清单已在
  `GAMEDATA_BUILD_PIPELINE.md` 完整列出），还要设计兼容窗口与不兼容升级策略，
  是一次协议扩展而非小改动。
- 未修复原因：没有真实用户规模驱动数据刷新频率；对测试阶段而言，
  全量快照 + 手动发布已经可用。

**当前缓解**：manifest 已携带完整来源元数据；安装器校验必需表、schema version、
关键计数与哈希，坏库验证失败时保留旧库，不会用坏数据覆盖好数据。

**修复方向与触发条件**：数据需要按游戏版本节奏刷新（新活动、新干员上线）时，
实现远程 update manifest 与 App 内"当前已安装 vs 最新"展示、下载前体积提示、
失败保留旧库的更新流程。

### 4.2 无增量包与差异报告（Open）

**现象与影响**：更新只能全量下载约 115 MB gz；每次数据刷新没有自动差异报告
（实体增删、alias 变化、story scope 变化、记录计数、固定 QA 回归），
无法快速判断"这次刷新改变了什么"。

**根因分析**：

- 全量包是正确起点：record 主键是内容字段拼接后的 SHA-1（重复构建主键稳定），
  这为增量打了基础；但增量包还缺三样东西——基线版本跟踪、差异生成工具、
  增量损坏时回退全量的恢复策略，三者构成一条新工具链。
- 差异报告需要"旧快照 vs 新快照"对比工具与人工审查流程；在刷新频率为
  "版本发布时"的前提下，对比工作可以靠固定 QA 人工完成，自动化投入不划算。
- 成本权衡：全量包实现简单、失败恢复直观（删临时文件保留旧库）；
  115 MB 在 Wi-Fi 场景可接受，在测试阶段没有用户抱怨下载成本。

**当前缓解**：manifest 记录各类计数；`check_gamedata_retrieval.dart` 固定 QA
可人工对比新旧快照的命中差异。

**修复方向与触发条件**：source 更新频率提高或用户反馈下载成本后，先实现差异
报告（每次刷新自动生成），再根据真实体积与失败恢复成本决策是否做增量包。

### 4.3 《终末地》无 active 数据源（Open，Mitigated）

**现象与影响**：App 有终末地主题与 Endfield Wiki 浏览入口，但 AI 没有 Endfield
GameData 证据；DB 的 `game` 字段存在，但 importer 与 release asset 只覆盖
Arknights `zh_CN`。

**根因分析**：

- 历史成因：终末地从"主题 + Wiki 浏览"立项，数据接入被明确推迟；
  `GAMEDATA_BUILD_PIPELINE.md` 记录了候选仓库（`3aKHP/EndFieldGameData`、
  `wuyilingwei/EndfieldGameData`），但都标注了未决条件。
- 关键未决条件：数据来源授权与许可、稳定 ID 规则、语言策略、importer adapter
  设计、证据标签与跨游戏检索范围。这些契约不确定时接入，会引入"跨游戏混搜
  错证据"的真实风险——把终末地文本当成方舟证据，比没有数据更糟。
- 权衡：这是一个"宁可 UI 明示无数据支持，也不做半成品混搜"的决策，
  与项目整体"证据来源可信度优先"的原则一致。

**当前缓解**：UI 与文档明确"终末地主题 / Wiki 浏览 ≠ AI 终末地数据支持"；
schema 已预留 `game` 字段，未来接入不需要改表。

**修复方向与触发条件**：完成来源协议与授权确认后，按独立 importer adapter 立项，
并配套 Endfield 专属 content category、story scope 与固定 QA。

### 4.4 schema v2 把语义压在 FTS / LIKE 上（Mitigated，2026-08 已落地覆盖层）

**现象与影响**：Story chunks 检索以 FTS / LIKE 为主，没有实体级剧情倒排；
`entity_relations` 表存在（17,861 行）但 App 查询利用有限。

**根因分析**：

- 历史成因：schema v2 的设计目标（2026-07 架构决策）是"provenance 完整 +
  结构化基础检索"——优先保证每条记录可追溯到 `source_path` / `raw_id` /
  `content_type`，检索质量是第二步。
- 实体级倒排的成本：要从 40 万行 `story_lines` 中解析"哪个实体在哪些行被提及"，
  需要实体识别（别名膨胀、变体名）、speaker 对齐、行范围与提及强度统计，
  是 NLP 级工程量；关系索引（死亡/存活、归属、敌对）还需要关系抽取或
  人工规则，质量难以自动保证。
- 现有折中：scoped evidence 路径用"scope + entity + 关系词 SQL 交集 + Dart
  最短文本距离排序"在查询层模拟了倒排效果，先以确定性规则覆盖最高频的
  事实核查场景，把 schema 演进推迟到质量量化证明需要时。

**当前缓解（2026-08-24 更新）**：schema v3 已落地确定性覆盖层（对应
`AI_RETRIEVAL_OPTIMIZATION.md` 阶段 P0，见 `R1_STORY_COVERAGE_LAYER_SUMMARY.md`）：
- `entity_story_mentions`：实体（canonical name + 全部 alias）出场倒排，台词说话人
  与正文一并扫描，连续命中合并为行区间 run；
- `story_chapter_profiles`：每 story 的行范围、speaker 集合、实体密度、抽取式摘要、
- `rare_terms`：跨文件 doc_freq ≤ 20 的中文双字词，作为 P1 跨章节细节匹配的 IDF 依据；
- `story_lines_fts`：40 万行剧情原文的行级全文索引，`read_story_lines` 工具可
  按行区间/分页直接读取原文。
- App 安装器已把四张新表纳入必需清单并升级校验 `schema_version == '4'`
  （v4：importer 跳过上游 `[uc]info/` 一行摘要桩树，`obt/<group>` 归入 `obt:<group>`）。

**仍开放**：实体级关系索引（死亡/存活、归属、敌对）、组织/概念汇总实体、
以及基于覆盖层的跨章节推理（P1），见 `AI_RETRIEVAL_OPTIMIZATION.md`。

## 5. 检索质量

### 5.1 组织/概念级汇总实体缺失（Open）

**现象与影响**："莱茵生命"、"萨卡兹王庭"等组织 query 当前命中相关干员档案
（如深海色、凛视的档案），但没有组织实体本身的汇总文档；"组织是什么、
成员有哪些"这类问题无法得到直接答案。

**根因分析**：

- 历史成因：importer 的实体主要来自表驱动枚举——`character_table.json`、
  `enemy_handbook_table.json` 等表格可以逐行生成实体；组织/概念是
  "文本中涌现"的实体，没有枚举表可遍历，天然不在首批 importer 范围内。
- 构建组织实体的两条路都有成本：词典挖掘（从档案/剧情统计高频共现，
  需要人工复核防幻觉）或人工 curated 表（需要维护机制）；且组织实体
  的价值依赖与成员实体的关系写入 `entity_relations`，这又回到 §4.4 的
  schema v3 依赖。
- 影响评估：宽泛组织 query 目前仍能通过 LIKE/FTS 召回相关档案，用户
  至少能看到"哪些干员属于该组织"的间接证据，属于"可用但不直接"。

**当前缓解**：LIKE/FTS 召回 + 固定 QA 中保留 `莱茵生命`、`萨卡兹王庭` 查询；
文档明确这是已知覆盖缺口，Agent 必须如实说明低覆盖。

**修复方向与触发条件**：数据产品化立项时加入组织/概念实体构建、与成员实体的
关系写入及对应固定 QA；在此之前不得让模型用记忆编造组织资料。

### 5.2 同义词归一化是规则表（Open）

**现象与影响**："肉鸽→集成战略"、"秘录→operator record / story review"、
"语音→charword"等扩展是 query plan 中的手写映射；未覆盖的俗称会直接
落入 FTS / LIKE，可能召回不足。

**根因分析**：

- 规则表是"成本最低、可解释、可测试"的方案：`agent_test.dart` 直接覆盖
  归一化行为，映射表变化可回归验证；而完整同义词知识库需要词典资源
  （社区俗语、缩写、错别字变体）与持续维护机制，是数据工程投入。
- 在测试阶段，已知高频俗语的规则表已经覆盖了绝大多数用户提问；
  规则表之外的低频俗称召回不足，影响面小且 Agent 会如实报告低覆盖。

**当前缓解**：高频映射已覆盖并有测试；固定 QA 保证已有映射不回归。

**修复方向与触发条件**：检索质量量化显示"俗称召回"缺口后，把规则表升级为
可维护的同义词表（带来源与置信度），并接入 alias 构建流程。

### 5.3 歧义候选展示依赖 Agent 调用（Closed，R11）

**现象与影响**："特蕾西娅"有 3 个 alias 候选（两个 enemy 实体 + 一个 trap），
工具层会返回带 entity_id、类型、来源与 confidence 的候选块；但用户是否
真的看到候选并完成消歧，取决于 Agent 是否走了 disambiguation 分支。

**根因分析**：

- 消歧逻辑本身在工具层是确定性的（候选查询分级、候选块结构化返回），
  这部分没有问题；不确定的是"模型是否遵守 prompt 的消歧指令"。
- 这是 LLM 编排层的固有不确定性：prompt 约束不能 100% 保证 provider 行为，
  项目在 v0.5 就遇到过同类问题（模型绕过 scoped evidence 直接断言），
  当时的结论是"用代码门槛而非 prompt 保证"，但"何时展示候选"是对话行为，
  无法完全代码化。
- 项目已把 Fact-check 的 supported/refuted 结论用 observation 二次校验
  代码化（verdict transform），但候选展示仍是行为层。

**当前缓解（R11 前）**：Fact-check prompt 明确要求歧义时输出存疑并要求用户消歧；
`agent_test.dart` 覆盖实体歧义场景；live QA 验证过真实 provider 下的歧义处理。

**R11 修复（2026-08-26）**：消歧从"prompt 期望"升级为**代码协议**：
调查 Agent 的歧义分支由执行器自动处理——`EntityDisambiguator`（辅助 Agent，
一次轻量 LLM 调用）按用户问题语义 + 候选列表选择实体（失败回退最高置信度
候选#1），选择写入 `InvestigationState.targetEntity`；候选清单与已尝试集合
进入状态，`RESELECT <entity_id>` 可切换未尝试候选且拒绝重复选择；`SEARCH`
对已消歧名字自动注入 entity_id、支持 `id=` 语法与实体 id 字面量检索；
重复 SEARCH 无进展时执行器自动转 `search_story_coverage`，仍无覆盖则以
`unresolved` 收场（循环在代码层面终结，不再依赖模型自觉）。详见
`docs/AI_REFACTOR_SUMMARY.md` R11 小节。

## 6. 代码结构与维护性

### 6.1 大文件与职责集中（In Progress）

**现象与影响**：以下文件显著超长且职责集中：

| 文件 | 行数 | 承载职责 |
| --- | --- | --- |
| `lib/core/gamedata/gamedata_knowledge_store.dart` | 1,347 | 9 阶段检索管线、消歧、scoped evidence 排序 |
| `lib/features/wiki/wiki_reader_mode.dart` | 1,722 | CSS/JS 注入、字体加载、DOM 观察与布局保护 |
| `lib/features/wiki/wiki_browser_page.dart` | 1,652 | 双 WebView 状态机、工具托盘、书签/转交联动 |
| `lib/core/agent/agent_provider.dart` | 747 | 三个工作流 UI 状态、会话协调、取消/代次/重试 |
| `lib/core/agent/react_loop.dart` | 636 | ReAct 状态机、解析容错、来源与结论约束 |

**根因分析（逐文件）**：

- `agent_provider.dart`：仓库没有独立 domain package，Riverpod 装配集中在 core，
  三个 Notifier（Summary / Fact-check / Role-play）共享取消、请求代次、重试模式，
  抽离需要引入共享基类或 service 抽象。这是行为保持型重构，必须由固定 QA
  保护，风险高于收益时自然被推迟。
- `gamedata_knowledge_store.dart`：检索管线按"结构化 → 别名 → 文档 → FTS →
  LIKE 回退"的顺序自然生长，每个新检索阶段都追加私有方法；抽离需要中间层
  抽象（如共享 StoryEvidenceRetriever），implementation plan 的 v0.5 后续候选
  已提出但未立项，因为现有单文件实现没有功能缺陷。
- `wiki_browser_page.dart`：双 WebView 的 controller/标题/URL/前进后退状态、
  工具托盘、书签联动、转交 AI 天然是页面级状态，拆分会引入跨组件状态
  传递成本，Flutter 页面级 State 集中是可接受的折中。
- `wiki_reader_mode.dart`：v0.9 之后快速迭代期的产物（46 个提交中的大部分），
  注入脚本、观察器、布局保护逻辑在修 bug 的过程中增长；拆分前需要先固化
  注入脚本的测试契约，否则拆分会破坏站点适配行为。

**当前缓解**：技术报告附录 A 提供逐文件职责索引；`agent_test.dart` 与 Widget 测试
覆盖关键行为；CLAUDE.md 约束代理"相关 tests / analyze 后再汇报"防止盲目重构。

**修复记录（agent 模块）**：
- `react_loop.dart`（645 → 368 行）：解析器提取为 `react_parser.dart`
  （`parseReActKey` / `parseActionInput` 等纯函数），证据汇总与回答约束
  提取为 `evidence_summary.dart`（`EvidenceSummary`、`buildFallbackPrompt`、
  `applySourceGuard`）；`react_loop.dart` 只保留状态机与事件编排。
- `agent_provider.dart`（747 → 588 行）：`ReActStep` / `ChatMessage` 提取为
  `chat_message.dart`（经 `export` 保持引用兼容）；三个 chat Notifier 的
  代次、消息更新、cancel/retry/clear 与 history 构建提取为
  `chat_notifier_base.dart` 抽象基类，Summary / Fact-check 继承后只保留
  各自工作流差异（verdict、steps 重建、取消文案）。
- `wiki_reader_mode.dart`（1722 → 93 行门面）：CSS 构建提取为
  `wiki_reader_css.dart`（`buildReaderCss`，795 行），注入/清理脚本提取为
  `wiki_reader_scripts.dart`（`buildReaderScript` / `buildRemoveReaderScript`，
  877 行）；`wiki_reader_mode.dart` 只保留字体加载与注入门面。
- `wiki_browser_page.dart`（1652 → 1278 行）：`_WikiAiTargetSheet`、
  `_ReaderToolbar`、`_ReaderToolButton`、`_ExpandableTray` 等独立 UI 组件
  提取为 `wiki_browser_controls.dart`（公开类，370 行）；页面保留双 WebView
  状态机与回调编排。
- `gamedata_knowledge_store.dart`（1347 → 1041 行）：结果模型提取为
  `gamedata_models.dart`（`GameDataSearchResult` / `GameDataEntityCandidate`，
  经 `export` 保持引用兼容）；query plan 与评分辅助提取为
  `gamedata_query_plan.dart`（`GameDataQueryPlan`、意图归一化、FTS 构建、
  proximity 评分等纯函数，255 行）。

拆分后全部通过 `flutter analyze`（No issues）、完整测试套件（68 passed）
与固定 GameData retrieval QA。

**剩余**：`gamedata_knowledge_store.dart`（1,041 行）与 `wiki_browser_page.dart`
（1,278 行）仍是最大的单文件，剩余职责（检索编排 / WebView 状态机）属于
"页面级/存储级状态集中是合理折中"的范畴；如后续引入共享 StoryEvidenceRetriever
或 WebView controller 管理器，可继续拆解。

### 6.2 重复路由实现（Closed）

**现象与影响**：`lib/app.dart` 尾部的 `KnowledgeBaseRoute` 与 `generateAppRoute()`
未被根 `MaterialApp` 使用；实际路由由 `main.dart` 的 `onGenerateRoute` +
`smoothPageRoute` 承担。

**根因分析**：早期路由实现遗留——先写了 generateAppRoute 包装，后来路由策略
改为 onGenerateRoute 统一注册；旧包装没有被删除，因为它在文件末尾不影响
编译与行为，属于"顺手可做、无人立项"的低风险清理债务。

**修复记录**：已删除 `KnowledgeBaseRoute` 与 `generateAppRoute` 及其不再使用的
import；路由统一由 `main.dart` 的 `onGenerateRoute` 注册。`flutter analyze`
与既有 Widget 测试守护该行为。

### 6.3 analyzer 规则未收紧（Closed）

**现象与影响**：`analysis_options.yaml` 只继承 `flutter_lints` 默认规则集，
v0.9 计划中"收紧 analyzer / lint 规则"的交付未完成（当时为 No issues found，
但默认规则较宽松）。

**根因分析**：收紧规则（如 strict 模式、额外 lint）会立即暴露存量告警，
需要配套逐项修复与确认；v0.9 的实际工作量集中在视觉系统与设置页迁移，
规则收紧作为"代码质量交付内容"被推迟，且没有单独立项。

**修复记录**：已启用 analyzer strict 模式（`strict-casts` / `strict-inference` /
`strict-raw-types`）与 10 条补充 lint（`directives_ordering`、
`prefer_single_quotes`、`require_trailing_commas`、`sort_constructors_first`、
`use_super_parameters`、`prefer_final_fields`、`prefer_final_locals`、
`avoid_dynamic_calls`、`unawaited_futures`）。`dart fix` 自动修复 204 处，
手动修复 28 处，其中 strict 模式暴露了 1 个真实类型错误
（`warfarin_crawler.dart` 中 `dynamic` 键传给 `int.parse`）与多处缺失的
泛型参数（`Future<void>.delayed`、`showDialog<void>`、`smoothPageRoute<void>`
等）。当前 `flutter analyze` 为 No issues found。

### 6.4 硬编码中文未完全进入 ARB（Closed）

**现象与影响**：Materials、知识库页与 Wiki 错误覆盖层等仍存在硬编码中文
（技术报告 22.2 确认），英文用户在这些界面会看到中文；新文案也可能
绕过本地化。

**根因分析**：v0.9 重构聚焦设置页与导航主表面，错误覆盖层与低活跃页面
（Materials 是暂停态）不在迁移范围；逐个字符串提取需要双语补译与
对应 Widget 测试更新，对低活跃页面的投入产出低。

**修复记录**：为 `app_en.arb` / `app_zh.arb` 新增 45 个条目（含 2 个带
placeholder 的错误消息），迁移了设置页（Wiki 来源管理、应用图标、对话框）、
知识库页（标题、错误消息、统计标签、下载按钮）、Wiki 错误覆盖层与
Materials 暂停说明的全部硬编码 UI 文案；引导页语言按钮改用
`SupportedLocale.displayName`。遗留硬编码仅剩专名（GameData、Warfarin）、
数据值（entityId）与注入网页的 DOM 选择器/脚本字符串（站点适配逻辑，
不属于 App 本地化范围）。

### 6.5 主题/语言不持久化（Closed）

**现象与影响**：用户切换的 Endfield 主题与英文语言在重启后回到默认值
（Ark 深色 + 中文），主题/语言选择是进程内状态。

**根因分析**：`ThemeNotifier` / `LocaleNotifier` 设计为进程内状态，
"默认 Ark 主题"起初是产品选择而非疏漏；持久化需要启动时异步读取 +
provider override 注入——`main.dart` 已为 onboarding 状态、主标签页
索引实现过同款模式（`initialMainTabIndexProvider` 等），接入成本低，
属于"已知怎么做、未排期"的小债。

**修复记录**：`SettingsService` 新增 `loadTheme` / `saveTheme` /
`loadLocale` / `saveLocale`；`main.dart` 启动时读取并注入
`initialThemeProvider` / `initialLocaleProvider`；设置页与引导页切换时
同步保存。两个 initial provider 默认保留历史值（ark / zh），测试与
未 override 环境无需改动。

### 6.6 非流式输出（Mitigated，已改进）

**现象与影响**：`OpenAICompatibleClient` 实现了 SSE `chatStream`，但 ReAct
主循环使用非流式 `chatCompletion`，最终回答整段返回后一次性渲染，
长回答的感知延迟较高。

**根因分析**：工具循环的每一步都需要完整步骤文本才能解析
Thought/Action/Action Input，流式只对"最终回答阶段"有意义；流式化需要
处理"流式输出 + 取消 + 请求代次"的组合语义与 stop 序列，改动位于
ReAct 核心与 Notifier 消费端，属于中等风险重构。项目选择先保证
协议稳定性，把感知体验优化排在功能正确性之后。

**当前缓解**：UI 有加载/思考步骤展示，用户能感知进度；
`wasTruncated` 截断检测保证不把半截回答当完整答案。

**修复记录**：最终回答改为分块事件（`_emitFinalAnswer`，120 字符/块），
UI 已具备的 `finalAnswerBuffer` 追加逻辑使其渐进渲染，长回答不再整段
闪现；相关测试断言同步更新为拼接校验。

**仍开放的权衡**：真正的 provider 级 SSE 流式（请求阶段边收边显示）未实施。
原因是 ReAct 步骤解析需要完整响应文本（Action Input 可能跨 chunk），且
Fact-check 的 verdict transform 与来源守卫必须在完整文本上执行后才能
发出——把流式接入请求阶段会破坏这两条约束。若未来引入结构化步骤协议
（v0.13 方向），可以重新评估。

### 6.7 debug Agent 日志敏感且无清理机制（Mitigated，R4 起由用户开关控制）

**现象与影响**：`AgentLogger`（原仅 `kDebugMode` 启用）记录用户 query、
每轮模型原始输出、工具参数与数据库原文；release 构建 no-op，但 debug
构建会留下敏感文件，且 App 内没有日志清理入口或用户告知。

**根因分析**：日志的设计目标明确——开发与测试时需要能定位"工具调用、
检索覆盖、provider 错误"（技术报告 22.1 列为已建立的保护），
因此记录完整上下文是刻意的；但"日志脱敏、清理入口、隐私说明"属于
隐私工程，没有随日志功能一起立项。日志写入 app external files /
Documents，用户卸载即清除，但没有主动管理机制。

**当前缓解（R4 更新）**：`AgentLogger` 改为 debug 与 release 均可用，但
**默认关闭，由用户在设置中自行开启**（"保存 AI 会话日志"开关，持久化到
安全存储，启动时恢复并应用）。开启后每次 AI 会话的日志写入与 GameData
数据库同级的用户可见目录（Android external storage → `agent_logs/`），
可用于真机排查；两级防护保留：query 截断 200 字符、模型输出/observation/
最终回答/错误截断 2000 字符，自动保留最近 20 个会话（`_pruneOldLogs`），
`AgentLogger.clearLogs()` 可清空。权衡：开启后用户对话会写入自身设备文件
——数据留在用户设备、可手动删除、默认关闭，隐私边界在代码注释与
设置说明中明确。

**R5 更新（会话持久化）**：Ask 页的会话记录迁移到新机制
`ChatSessionStore`（`chat_sessions/` 目录，JSON，每对话一个文件），
由同一开关控制，但**记录完整、无截断**（完整思维链、原始 LLM 响应、
检索原文），因为该文件同时是"对话记录"功能的恢复源——恢复需要完整
数据，截断会使恢复后上下文缺失。隐私保护改为：默认开启（功能定位，
用户可关）、仅存本机用户可见目录、app 内可查看/删除、文件管理器可删。
`AgentLogger`（旧 `agent_logs/` .log 格式）仅保留给角色扮演 tab 使用；
Ask 页不再产生旧格式日志。

**R6 更新（分层记忆，三实验复盘修复）**：真机三实验暴露的截断问题按
"分层而非扩窗"根治：(1) ReActLoop 改为分层记忆——请求只含记忆块 +
最近 2 轮原文，旧观察不再以占位符驱逐（`loop_memory.dart`），消除
重复读取；(2) `QuestionRouter` 分类失败显式化（reasoning 模型下
maxTokens 16 会产出空 content 并静默降级为概括），现提高 token 预算、
空/截断响应记为 error 并在 UI 步骤区提示；(3) `SummaryAgent`
stepMaxTokens 升至 4096（2048 导致长答案截断整轮报错）；(4)
`get_story_map` scope 模式改为按章节号自然排序的紧凑列表（全章节
可见，原字典序 + 4800 字符预算会把核心章节如 act33side_09_beg 截掉）；
(5) `collect_suspect_evidence` 的 claim 术语全局优先排序（高频实体
537 runs 时首屏不再是无关日常对话）；(6) `find_detail_echoes`
从调查工具集移除并**评估后废弃**（不再立项修复）：三次真机实验中共
5 次调用零贡献——提取词全为双字碎词（"讲到/无防/娅与/势必"），
echo 全库无关，模型从未采用；其"提取特征词 + 全库检索"能力已被
模型自主选词 + `search_local_lore` FTS 完全覆盖，且伏笔呼应类问题
占比未量化（检索设计原则 2），故不修复。代码与工具测试保留备用。

**R7 更新（真机三实验复盘：格式漂移与截断容错）**：R6 后三次自动档
实验（2 失败 1 离谱）暴露：① 98% 迭代丢失 `Thought:` 前缀——记忆块
作为独立 user 消息诱导模型"续写要点"而非按格式输出，连带记忆块
"调查要点"退化、且裸思考被 `action.isEmpty` 分支误当最终答案；
② 单步隐藏推理吃满 4096 token、可见输出 0 → 截断被设计成整轮失败；
③ 恢复历史看不到错误文本（`turn.error` 未进消息内容）。
修复：(1) 记忆块并入 system prompt 并标注"系统维护记录，请勿续写"；
(2) 无 Action 无 Final Answer 键的响应不再当答案——注入格式错误重试，
连续 3 次 malformed 才终止；(3) `wasTruncated` 改为精简重试 ≤2 次后
才报错；(4) `stepMaxTokens` 4096→8192、默认请求超时 120s→180s（配套）；
(5) 恢复/详情视图显示 `turn.error` 文本。已知边界：8192 仍可能被
极端长推理吃满（届时按 (3) 重试），超长答案分段生成仍列后续。

**修复记录**：`AgentLogger` 增加两级防护——(1) 脱敏：query 截断到 200
字符、模型输出 / observation / 最终回答 / 错误正文截断到 2000 字符，
不再落盘完整用户问题、完整推理或完整数据库原文；
(2) 清理：flush 后自动保留最近 20 个会话日志（`_pruneOldLogs`），并新增
`AgentLogger.clearLogs()` 静态方法供设置/隐私 UI 调用。
R4：去除 `kDebugMode` 门控，改为 `AgentLogger.setEnabled()` 运行时开关，
设置页新增"保存 AI 会话日志"开关（默认关），日志目录与 GameData DB 同级。
R5：Ask 页改用 `ChatSessionStore` JSON 会话（无截断），新增「对话记录」
页面（列表/只读详情/继续对话/删除），`QuestionRouter` 输出原始分类
决策，`ReActLoop` 暴露每迭代原始响应（`onRawLlmResponse`）。
R6：`LoopMemory` 分层记忆（已读索引 + Thought 摘要 + 近程窗口），
`onMemoryChanged` 把记忆块快照写入会话记录（`turn.memory`）。

## 7. 工程化与量化

### 7.1 真机性能指标未量化（Open）

**现象与影响**：真机功能验收已关闭（§2.1），但查询 p50/p95 延迟、内存峰值、
DB 安装耗时、冷启动时间等没有量化记录，无法回答"在代表性设备上是否
够快"。

**根因分析**：量化需要固定设备、固定 DB 快照与重复采样脚本，是测试工程
投入；在功能正确性优先的开发节奏里，性能数字属于"知道大概没问题"，
缺少数据支撑。单机采样还有设备差异问题，需要记录设备型号与 Android
版本才能有意义。

**当前缓解**：implementation plan 已列出性能预算条目（冷启动、检索延迟、
DB 安装、内存峰值、长会话帧率）；无自动化测量。

**修复方向与触发条件**：正式发布前在代表性设备上采样记录，形成性能
基线；性能回归由固定 QA 扩展（查询超时上限）守护。

### 7.2 无自动截图回读管线（Open）

**现象与影响**：v0.9 双主题/双语/文字缩放的视觉验收依赖人工检查
（真机人工验收已覆盖主要路径），没有自动化截图对比，未来 UI 改动
可能引入无意的视觉回归而不被发现。

**根因分析**：自动化截图需要 integration_test + 设备/视口矩阵 +
golden 对比基线，首次搭建成本高，且 golden 对字体渲染、平台差异敏感，
容易产生噪音；个人开发流程中人工检查成本可接受，因此未立项。

**当前缓解**：`settings_redesign_test.dart` 等 Widget 测试覆盖关键尺寸/
字号下的 RenderFlex overflow 断言；真机人工验收已覆盖主要页面。

**修复方向与触发条件**：v1.0 前建立自动化截图管线，或明确放弃并记录
理由（以 Widget 约束测试替代）。

## 8. 死代码与历史链

### 8.1 Wiki crawler / provider 运行时不可达（Open）

**现象与影响**：`core/wiki/wiki_crawler.dart`（MediaWiki crawler）、
`wiki_provider.dart`（CrawlNotifier）、`warfarin_crawler.dart` 不被任何
feature 页面或 Agent 引用；测试仍覆盖 decoder/formatter 契约。

**根因分析**：v0.4.5 转向 GameData-first 后，Agent 检索链不再使用爬虫，
但代码作为"可复用解析工具"保留（Warfarin 的 Remix 数据流解析、
PRTS template 清洗对未来站点数据研究仍有参考价值，技术报告 16 章
明确说明了这一点）。删除需要同步删除测试与文档引用，属于低风险清理
但未被立项；保留的成本是维护与理解成本。

**当前缓解**：技术报告明确标注"历史能力 / 运行时不可达"；测试继续
守护 parser 契约，防止其腐烂。

**修复方向与触发条件**：清理立项时归档到 `docs/` 说明或删除；
保留则继续标注历史链身份，禁止新代码依赖它。

### 8.2 `citation_card.dart` 的 "View in Wiki" TODO 悬空（Open）

**现象与影响**：`shared/widgets/citation_card.dart` 是旧 Wiki/Book 引用卡，
含未实现的来源跳转 TODO；当前 AI 证据展示已改用 `chat_bubble.dart` 内
专用 evidence UI，该组件没有使用方。

**根因分析**：组件从旧 Wiki/Book 引用链继承，GameData 转向后失去使用方；
TODO 悬空说明组件已无维护者，但删除动作被"先留着"的惯性推迟。
另有客观约束：GameData 的 `source_path` 是 release asset 内的来源路径，
不是 App 可打开的文档，来源导航本身需要重新设计（技术报告 8.1 记录）。

**修复方向**：删除或标注废弃；来源导航作为独立功能另行设计。

### 8.3 `wiki_toolbar.dart` 未实例化（Open）

**现象与影响**：横向 `WikiToolbar` 组件保留在代码中，但浏览页实际使用
`_ExpandableTray` 工具托盘。

**根因分析**：Wiki 工具 UI 在 v0.2 双站 WebView 时设计为横向工具栏，
v0.7 之后演进为右下角可展开托盘，旧组件未随演进删除。

**修复方向**：删除旧工具栏或将其统一到托盘组件，避免两套工具 UI 并存。

## 9. 汇总表

| # | 弱点 | 状态 | 根因类别 | 修复触发条件 |
| --- | --- | --- | --- | --- |
| 2.1 | Android 真机端到端验收 | Closed | 测试策略优先级 | 已关闭（个人验收完成） |
| 3.1 | release 使用 debug certificate | Open | 发布工程 | 决定正式分发 |
| 3.2 | 无 CI workflow | Open | 工程化 | 正式发布前 |
| 4.1 | 无 update manifest | Open | 数据产品化 | 数据需按游戏节奏刷新 |
| 4.2 | 无增量包/差异报告 | Open | 数据产品化 | 刷新频率或下载成本反馈 |
| 4.3 | 终末地无 active 数据源 | Open/Mitigated | 授权与契约 | 来源协议确认 |
| 4.4 | schema v2 语义压在 FTS/LIKE | Open（R12 补充：story_lines/lore_chunks FTS 为 unicode61，中文无效） | 检索架构 | R12 P1 向量召回 |
| 5.1 | 组织/概念汇总实体缺失 | Open | 数据构建 | schema v3 立项 |
| 5.2 | 同义词归一化为规则表 | Open | 数据维护 | 俗称召回缺口量化 |
| 5.3 | 歧义展示依赖 Agent 行为 | Reopened（R12：消歧器收到硬编码 type；同名出场可能相同） | LLM 编排不确定性 | R12 P0 消歧修正 |
| R12 | 调查链路信息流断裂（原文不进答案、缺剧情检索意图、CLI 不等价、无评测） | Open | Agent 架构 | 见 `R12_BOTTLENECK_ANALYSIS.md` |
| 6.1 | 大文件职责集中 | Closed | 重构未立项 | 五个大文件全部拆出独立模块 |
| 6.2 | 重复路由实现 | Closed | 清理未立项 | 已删除重复实现 |
| 6.3 | analyzer 规则未收紧 | Closed | 规则配套重构 | 已启用 strict + 10 条 lint，0 issues |
| 6.4 | 硬编码中文未入 ARB | Closed | 本地化迁移 | 45 个新 ARB key 迁移完成 |
| 6.5 | 主题/语言不持久化 | Closed | 产品选择遗留 | 已持久化并启动注入 |
| 6.6 | 非流式输出 | Mitigated（已改进） | ReAct 架构取舍 | 分块渲染已上线；真流式受 transform 约束 |
| 6.7 | debug 日志敏感无清理 | Closed | 隐私工程 | 已脱敏 + 自动清理 + clearLogs |
| 7.1 | 真机性能未量化 | Open | 测试工程 | 正式发布前 |
| 7.2 | 无自动截图回读 | Open | 测试工程 | 正式发布前或明确放弃 |
| 8.1 | Wiki crawler 死代码 | Open | 历史链 | 清理立项 |
| 8.2 | citation_card TODO | Open | 历史链 | 清理立项 |
| 8.3 | wiki_toolbar 未实例化 | Open | 历史链 | 清理立项 |

## 10. 维护约定

- 本文档不重复 `RETRIEVAL_QA.md` 的验收记录；验收状态变化时先更新
  `RETRIEVAL_QA.md`，再回来改本文档的状态与"已关闭"说明。
- 新增限制或技术债时，按上述条目结构补充，并更新汇总表。
- 修复某一项时，在对应条目记录修复 commit 与验证结果后，将状态改为 Closed。

**R8 更新（三角色分工，根治重复消耗与质量缺失）**：真机四问题（103 迭代重复、
答案缺巴别塔、切后台断连、余额耗尽）根因：A 模型 Thought 前缀丢失→记忆要点空转→
重做 S1；B 记忆无内容回显→重读原文回忆；C 阶段进度无记录→反复从头执行；
D 紧凑列表 40 字摘要切掉"屠戮魔王"信号→巴别塔刺杀章从未精读；F 进后台断连无重试；
G 重复调用烧光余额。修复：引入**PlannerLoop（三角色分工）**——
决策 Agent 每轮只输出一行意图（READ/SEARCH/MAP/COLLECT/VERDICT/DONE），上下文
恒定不随调查增长（截断需求消失）；代码执行器解析意图、调工具、用 DATA 块更新
[InvestigationState]（阶段/已读要点/证据）；提取 Agent 把读到的章节压成 ≤150 字要点
存入状态（模型不再重读回忆）。配套：git 摘要 80 字、网络异常自动重试、402 余额提示。
investigation 切到 PlannerLoop；summary/factcheck/roleplay 保留旧 ReActLoop。

**R11 更新（SEARCH 死路消除 + 问题语义消歧 + 防重选记忆）**：R10 后真机复现
（`logs/conversation_0beaa9fd*.json`）显示调查仍在 SEARCH 上无限自我重复
（13 步里 8 步重复 `SEARCH 特蕾西娅`、4 步 `SEARCH enemy:...` 永远 No matching）。
根因三条死路：① 消歧结果不进下一次检索（已消歧名再 SEARCH 仍重新歧义）；
② 意图协议无 entity_id、按 id 检索无路可走；③ 自动选#1 选错不可纠、状态无
重复计数 → 循环无代码终点。修复：**EntityDisambiguator** 辅助 Agent 按问题
语义选候选（失败回退#1）；消歧结果进状态（候选清单/已尝试集合/名字→id 映射/
重复与无结果计数/覆盖兜底标记）；SEARCH 支持 `id=` 与 id 字面量、已消歧名
自动注入 id、显式 entity_id 跳过歧义；新意图 **RESELECT** 切换未尝试候选且
拒绝重复；同一搜索键第 3 次重复自动转 search_story_coverage，已兜底仍重复
或空覆盖则直接 `unresolved` 收场；多意图行拒绝、引号短语保留。测试 200 全绿。

**R11.1 更新（重复终结误判修正）**：R11 后真机复现
（`logs/conversation_284c0267-*.json`）显示重复终结**生效但误杀**——模型已精读
4 个章节（含"巴别塔意外"关键线索）、调查仍有实质进展时被 `unresolved` 抢先终止。
四个代码缺陷：① 有结果的重复也被判死循环（计数在工具执行前无条件递增）；
② key 注入后不一致（原名/id 分散计数、覆盖兜底重复注入）；③ 终止不看整体进展
（无视已读章节/证据）；④ RESELECT 换候选不隔离计数（新候选继承旧候选的计数，
"看第 2/3 个候选"会被误杀）。修复：**无进展计数**（有结果重置计数，只有无结果
才递增）；**key 归一化**（计数/兜底标记统一用规范 id）；**进展门控**（有已读章节
或证据时注入"请 COLLECT/VERDICT"引导而非终止，仅既无 SEARCH 进展又无任何
已读/证据时才 unresolved）；**RESELECT 重置计数**（`resetSearchTrackingFor(id)`，
换候选后各自独立基线）。测试 200 → 205 全绿。

**R12 复盘（2026-10-01，信息流瓶颈）**：R8→R11.2 四轮修复集中在终止控制，
计数规则三次改向，真机失败形态每轮都变，但从未产出基于原文的有效答案。
根因不在循环控制：① App 未接入提取器，Writer 只拿到 story_id + 行号，
R3 引用校验在 R8 后失联——原文进不了答案；② 意图协议无 coverage / 行级原文检索，
SEARCH 只能拿实体档案——这是重复 SEARCH 的结构根源；③ 消歧器收到硬编码
type，且同名候选出场可能相同；④ `consecutiveNoResult` 全局连坐；⑤ CLI 数据层
是简化重写；⑥ 无评测集；另发现 `story_lines_fts` / `lore_chunks_fts` 为
unicode61 分词，中文无效。详见 `docs/R12_BOTTLENECK_ANALYSIS.md`，修复按
P0（证据笔记本、COVER/FIND 意图、消歧与计数修正）→ P1（CLI 用真 store、
行级向量召回、评测集、循环控制简化）推进。
