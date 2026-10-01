# ArkLores 已知限制与技术债根因分析

> 基准：v0.10.0（R12）与 `feature/r12-info-flow`，2026-10-02<br>
> 维护：本文档随代码与验收状态更新；"已关闭"条目保留记录，不再反复分析<br>
> 关联文档：`AI_ARCHITECTURE.md`（Agent 与检索架构）、`implementation_plan.md`（路线）、
> `ARKLORES_V0.9_TECHNICAL_REPORT.md`（v0.9 审计快照）、`GAMEDATA_BUILD_PIPELINE.md`（数据契约）、
> `RETRIEVAL_QA.md`（验收缺口）

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

### 3.1 Android release 使用 debug certificate 签名（Closed，v0.10.0）

**修复（2026-10）**：生成项目专用 release keystore（RSA 4096，有效期约 27 年，证书
SHA-256 `b1b09ebf…e364`），以加密 secrets 存入仓库，由 `android-release.yml` 在
GitHub Actions 中签名，并校验证书指纹。v0.9 及更早版本到 v0.10.0 需要卸载重装一次，
之后同一把钥匙签名的版本可以直接覆盖升级。keystore 与密码的唯一备份由维护者保管
（`tools/arklores-release.jks`、`tools/android_signing.properties`，均被 git 忽略），
丢失后将无法再发布可升级的版本。商店上架仍需另行处理。以下为历史分析。

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

### 3.2 无正式 CI workflow（Mitigated，v0.10.0）

**修复（2026-10）**：`.github/workflows/ci.yml` 在 PR 以及 dev/main 的推送上运行
analyze 与 test；`android-release.yml` 构建签名 APK。尚未覆盖：固定检索 QA（需要完整
DB）、secrets 扫描。以下为历史分析。

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

### 4.4 schema v2 把语义压在 FTS / LIKE 上（Mitigated：覆盖层 R1 + 可选向量召回 R12）

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

**当前缓解**：schema v3 起有确定性覆盖层（R1，构建规则见 `AI_ARCHITECTURE.md` §3.1）：
- `entity_story_mentions`：实体（canonical name + 全部 alias）出场倒排，台词说话人
  与正文一并扫描，连续命中合并为行区间 run；
- `story_chapter_profiles`：每 story 的行范围、speaker 集合、实体密度、抽取式摘要、
- `rare_terms`：跨文件 doc_freq ≤ 20 的中文双字词，作为 P1 跨章节细节匹配的 IDF 依据；
- `story_lines_fts`：40 万行剧情原文的行级全文索引，`read_story_lines` 工具可
  按行区间/分页直接读取原文。
- App 安装器已把四张新表纳入必需清单并升级校验 `schema_version == '4'`
  （v4：importer 跳过上游 `[uc]info/` 一行摘要桩树，`obt/<group>` 归入 `obt:<group>`）。

- R12 实测 `story_lines_fts` / `lore_chunks_fts` 为 unicode61 分词，对中文基本无效；
  原文检索改为 `search_story_lines`（LIKE，按命中行数排序）+ 可选向量召回
  （`story_chunk_vectors`，RRF 融合，见 `AI_ARCHITECTURE.md` §3.3）。没有向量 key 时
  仍只能依赖字面匹配。

**仍开放**：实体级关系索引（归属、敌对等）、组织/概念汇总实体；中文分词 FTS
（trigram 或分词器）未做，LIKE 在 41 万行上是全表扫描。

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

### 5.3 歧义候选展示依赖 Agent 调用（Closed，R11 + R12）

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

**修复**：消歧从"prompt 期望"升级为代码协议。R11：`EntityDisambiguator`
（一次轻量 LLM 调用）按问题语义选候选，失败回退候选 #1；候选清单与已尝试集合
进入状态，`RESELECT` 切换未尝试候选；已消歧名字再次 SEARCH 自动注入 entity_id。
R12：消歧器拿到候选的真实 type/source（此前是硬编码）；同名实体出场完全相同时
直接合并、不再要求消歧（实测 97% 的同名实体属于这种情况）。R11 为 SEARCH 单独写的
重复计数与 coverage 兜底已被 R12 的通用进展控制取代，R13 删除。

### 5.4 概括/事实核查仍走旧 ReActLoop（Closed，R13）

**现象与影响**：只有调查模式用 PlannerLoop（证据笔记、引用校验、进展控制、机械角色
关推理）。概括与事实核查仍是 ReAct：观察全文进上下文、截断容忍度低、没有行级引用
校验；来源守卫按答案中出现的“Wiki”“GameData”字样判断，会误报（R12 负例复测中出现）。
auto 路由把多数叙事问题分到概括，所以 R12 的改进对 auto 用户覆盖不足。

**根因**：R8 迁移时为控制回归风险只迁了调查；三种模式的差异其实只在输出格式。

**修复（R13）**：三者统一到 `StoryQaAgent` → PlannerLoop，`AnswerStyle {answer, summary,
factCheck}` 只决定 writer 的输出格式；`SummaryAgent` / `FactCheckAgent` 对外 API 不变。
真机验收结果见 `AI_ARCHITECTURE.md` §4。

### 5.5 调查结论信封与门槛是"凶手类"特判（Closed，R13）

**现象与影响**：`[INVESTIGATION_VERDICT: culprit=…]` 信封、“≥2 个嫌疑人有证据才允许
给出 culprit”的门槛、prompt 的 S5–S7 嫌疑人步骤、`collect_suspect_evidence` 命名，
都只对“谁干的”这类问题有意义。其他问题被迫套进 culprit 字段，模型也被锚定向找凶手。

**根因**：R3 以剧情谜题为设计样例，把样例的问题形态写进了协议。这与 CLAUDE.md
检索原则 1 和 anti-fixture 规则相冲突。

**修复（R13）**：换成与问题类型无关的 `[STORY_ANSWER: status=answered|partial|not_covered
| confidence=x]`，status 由代码按实际状态判定；删除门槛、S5–S7、basis 枚举；工具改名为
`collect_entity_evidence`。新规则：禁止任何只对某类问题或桥段生效的代码分支、阈值、
提示词步骤或输出字段，`test/no_special_case_test.dart` 守卫。

### 5.6 宽问题在 24 步预算内读不全（Open）

**现象**：R13 真机验收中，“谁导致……”与人物梗概两题都用满 24 步、以 `partial` 收尾；
梗概把预算花在早期经历，结局写成“资料未覆盖”。答案诚实，但覆盖不完整，单题约 80–100k
输入 token。

**根因**：决策器按发现顺序逐章精读，没有“先看全貌再分配阅读”的规划；预算是固定步数，
与问题需要读多少章无关。

**修复方向（待量化后立项）**：在 COVER/MAP 结果上先选章（例如按提及数与时间线均匀取样）
再 READ；或按已发现的相关章节数动态调整预算。必须是对任何问题都成立的通用规则。

### 5.7 档案类事实无法被引用（Open）

**现象**：引用校验只认 `story_id:行号`。SEARCH 返回的干员档案、敌人图鉴等结构化记录不进入
writer 的“已读原文”，所以只靠档案就能核查的说法会被判为 `uncertain`/`unavailable`。

**修复方向**：把 SEARCH 命中的记录（`source_path` + `raw_id`）作为第二类可引用证据交给
writer，并扩展引用校验。

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

（R6/R7 的 ReAct 截断与格式漂移修复与本条无关，已移至 `AI_ARCHITECTURE.md` §5。）

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
| 4.4 | schema v2 语义压在 FTS/LIKE | Mitigated（覆盖层 + 可选向量；中文 FTS 仍无效） | 检索架构 | 中文分词 FTS 立项 |
| 5.1 | 组织/概念汇总实体缺失 | Open | 数据构建 | 数据产品化立项 |
| 5.2 | 同义词归一化为规则表 | Open | 数据维护 | 俗称召回缺口量化 |
| 5.3 | 歧义展示依赖 Agent 行为 | Closed（R11 + R12） | LLM 编排不确定性 | – |
| 5.4 | 概括/核查仍走旧 ReActLoop | Closed（R13） | Agent 架构 | – |
| 5.5 | 结论信封与门槛是凶手类特判 | Closed（R13） | 协议设计 | – |
| 5.6 | 宽问题在 24 步预算内读不全 | Open | Agent 规划 | 量化后立项 |
| 5.7 | 档案类事实无法被引用 | Open | 引用协议 | 核查质量缺口量化 |
| R12 | 调查链路信息流断裂 | Closed（R12，见 `R12_BOTTLENECK_ANALYSIS.md`） | Agent 架构 | – |
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
- Agent 层的轮次演进记录写在 `AI_ARCHITECTURE.md` §5，不在本文档末尾追加流水账。
