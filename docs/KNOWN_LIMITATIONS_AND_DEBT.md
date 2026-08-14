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

### 4.4 schema v2 把语义压在 FTS / LIKE 上（Open）

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

**当前缓解**：`story_scopes` 表、scoped evidence 检索路径、proximity ranking、
固定 QA（`act21mini + 米格鲁 + 死亡` 命中固定行）。

**修复方向与触发条件**：检索质量量化显示 FTS 召回不足（见 §5.1）时，规划
schema v3：实体级剧情倒排、关系索引、组织/概念实体、质量标记，详见
`GAMEDATA_BUILD_PIPELINE.md` 的 schema v3 候选方向。

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

### 5.3 歧义候选展示依赖 Agent 调用（Mitigated）

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

**当前缓解**：Fact-check prompt 明确要求歧义时输出存疑并要求用户消歧；
`agent_test.dart` 覆盖实体歧义场景；live QA 验证过真实 provider 下的歧义处理。

**修复方向与触发条件**：Agent 质量迭代（共享 story evidence layer、结构化
步骤协议、deterministic post-check）时将"歧义必须展示候选"升级为可执行的
结构化协议字段，而不是 prompt 期望。

## 6. 代码结构与维护性

### 6.1 大文件与职责集中（Open）

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

**修复方向与触发条件**：按 implementation plan 的代码质量清单分批拆解，
每批以固定 Agent / retrieval QA 回归为门槛；优先拆 `agent_provider.dart`
（抽共享 Notifier 基类）与 knowledge store（抽 scoped evidence 检索层）。

### 6.2 重复路由实现（Open）

**现象与影响**：`lib/app.dart` 尾部的 `KnowledgeBaseRoute` 与 `generateAppRoute()`
未被根 `MaterialApp` 使用；实际路由由 `main.dart` 的 `onGenerateRoute` +
`smoothPageRoute` 承担。

**根因分析**：早期路由实现遗留——先写了 generateAppRoute 包装，后来路由策略
改为 onGenerateRoute 统一注册；旧包装没有被删除，因为它在文件末尾不影响
编译与行为，属于"顺手可做、无人立项"的低风险清理债务。

**修复方向**：删除重复实现，统一到 `onGenerateRoute`；无行为变化，
由 `flutter analyze` 与既有 Widget 测试守护。

### 6.3 analyzer 规则未收紧（Open）

**现象与影响**：`analysis_options.yaml` 只继承 `flutter_lints` 默认规则集，
v0.9 计划中"收紧 analyzer / lint 规则"的交付未完成（当前为 No issues found，
但默认规则较宽松）。

**根因分析**：收紧规则（如 strict 模式、额外 lint）会立即暴露存量告警，
需要配套逐项修复与确认；v0.9 的实际工作量集中在视觉系统与设置页迁移，
规则收紧作为"代码质量交付内容"被推迟，且没有单独立项。

**修复方向与触发条件**：分批启用规则并修复告警，保持 analyze 全绿；
与 6.1 的重构批次合并执行，避免重复改动同一批文件。

### 6.4 硬编码中文未完全进入 ARB（Open）

**现象与影响**：Materials、知识库页与 Wiki 错误覆盖层等仍存在硬编码中文
（技术报告 22.2 确认），英文用户在这些界面会看到中文；新文案也可能
绕过本地化。

**根因分析**：v0.9 重构聚焦设置页与导航主表面，错误覆盖层与低活跃页面
（Materials 是暂停态）不在迁移范围；逐个字符串提取需要双语补译与
对应 Widget 测试更新，对低活跃页面的投入产出低。

**当前缓解**：ARB 已有约 176 条中英条目；新增主要页面文案已走本地化。

**修复方向与触发条件**：页面级迁移到 ARB，补齐中英翻译，并在 CONTRIBUTING
中禁止新增硬编码文案；优先处理知识库页（用户高频路径）。

### 6.5 主题/语言不持久化（Open）

**现象与影响**：用户切换的 Endfield 主题与英文语言在重启后回到默认值
（Ark 深色 + 中文），主题/语言选择是进程内状态。

**根因分析**：`ThemeNotifier` / `LocaleNotifier` 设计为进程内状态，
"默认 Ark 主题"起初是产品选择而非疏漏；持久化需要启动时异步读取 +
provider override 注入——`main.dart` 已为 onboarding 状态、主标签页
索引实现过同款模式（`initialMainTabIndexProvider` 等），接入成本低，
属于"已知怎么做、未排期"的小债。

**当前缓解**：启动时应用保存的主标签页（同类模式已存在）；主题/语言
默认值稳定，不产生数据风险。

**修复方向**：把主题与语言写入 Secure Storage / 偏好存储，启动时注入
provider；同时保留默认值兜底。

### 6.6 非流式输出（Mitigated）

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

**修复方向与触发条件**：长回答延迟成为体验瓶颈时，在最终回答阶段切换
`chatStream`，保留取消与代次语义。

### 6.7 debug Agent 日志敏感且无清理机制（Open）

**现象与影响**：`AgentLogger`（仅 `kDebugMode` 启用）记录完整用户 query、
每轮模型原始输出、工具参数与数据库原文；release 构建 no-op，但 debug
构建会留下敏感文件，且 App 内没有日志清理入口或用户告知。

**根因分析**：日志的设计目标明确——开发与测试时需要能定位"工具调用、
检索覆盖、provider 错误"（技术报告 22.1 列为已建立的保护），
因此记录完整上下文是刻意的；但"日志脱敏、清理入口、隐私说明"属于
隐私工程，没有随日志功能一起立项。日志写入 app external files /
Documents，用户卸载即清除，但没有主动管理机制。

**当前缓解**：release 构建 no-op；`logs/` 不参与编译与产品数据链；
测试环境下回退到系统临时目录。

**修复方向与触发条件**：正式分发前实现脱敏（截断 query、不记录 API key
与请求头）、应用内日志清理入口与隐私说明；v0.9 代码质量清单中
"审计 print / 临时日志"项的部分目标。

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
| 4.4 | schema v2 语义压在 FTS/LIKE | Open | 检索架构 | 质量量化证明不足 |
| 5.1 | 组织/概念汇总实体缺失 | Open | 数据构建 | schema v3 立项 |
| 5.2 | 同义词归一化为规则表 | Open | 数据维护 | 俗称召回缺口量化 |
| 5.3 | 歧义展示依赖 Agent 行为 | Mitigated | LLM 编排不确定性 | 结构化步骤协议 |
| 6.1 | 大文件职责集中 | Open | 重构未立项 | 代码质量清单分批执行 |
| 6.2 | 重复路由实现 | Open | 清理未立项 | 顺手清理（低风险） |
| 6.3 | analyzer 规则未收紧 | Open | 规则配套重构 | 与 6.1 合并执行 |
| 6.4 | 硬编码中文未入 ARB | Open | 本地化迁移 | 页面级迁移 |
| 6.5 | 主题/语言不持久化 | Open | 产品选择遗留 | 体验反馈（低成本） |
| 6.6 | 非流式输出 | Mitigated | ReAct 架构取舍 | 感知延迟成为瓶颈 |
| 6.7 | debug 日志敏感无清理 | Open | 隐私工程 | 正式分发前 |
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
