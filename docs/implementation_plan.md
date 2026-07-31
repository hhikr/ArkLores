# ArkLores Implementation Plan

## 2026-07 Architecture Decision

ArkLores 自 v0.4.5 起使用中文 GameData release asset 作为主知识源；当前 release 为
v0.9.0，兼容 GameData schema 2。

可信度策略：

1. GameData / 游戏原始文本
2. 指定 Wiki
3. 用户导入 Book

当前代码主线只实现 GameData 本地结构化检索。Wiki 保留为浏览与人工补充入口；Book 路线暂停，后续重新设计。

## v0.4.5 Goals

- 稳定 ReAct Loop。
- 稳定 Summary Agent MVP。
- 构建中文 GameData 结构化 DB。
- App 内下载并安装 GameData DB。
- Agent observation 带来源、内容类型、source path、raw id、可信度提示。
- 空库、无结果、低覆盖给出清晰提示。

## Knowledge Source

GameData DB 由 `tools/build_gamedata_database.dart` 从社区解包仓库构建。

Release asset：

```text
arklores_gamedata_zh.db.gz
```

开发期可用：

```text
--dart-define=ARKLORES_GAMEDATA_DB_URL=<url>
--dart-define=ARKLORES_GAMEDATA_DB_SHA256=<sha256>
```

## Database Schema

- `gamedata_manifest`
- `entities`
- `entity_aliases`
- `entity_documents`
- `normalized_records`
- `story_lines`
- `lore_chunks`
- `entity_documents_fts`
- `lore_chunks_fts`

## Retrieval Order

1. Structured entity lookup.
2. Alias lookup.
3. Entity document exact / LIKE.
4. Entity document FTS.
5. Lore chunk FTS.
6. Normalized record / lore chunk LIKE fallback.

## Agent Infrastructure

Main tool:

```text
search_local_lore
```

ReAct Loop requirements:

- tolerate loose Action Input maps;
- tolerate provider keys placed after sentence punctuation or followed by provider metadata;
- reject empty final answer;
- surface truncated model output;
- allow an Agent to require completed tool calls before accepting a final answer;
- protect against unsupported source claims.

## App Behavior

- Settings: Chat API only.
- Knowledge Base: GameData DB download/status only.
- Materials: paused state until user material source strategy is redesigned.
- AI Summary: GameData structured local search.

## GameData 转向后的 v0.5-v1.0 路线

旧路线的产品演进顺序仍有价值，但其中 Wiki seed、Book indexing、embedding、
向量检索与 TFLite 的实现前提已被 v0.4.5 架构决策废止。后续版本必须建立在
中文 GameData release DB 和结构化检索契约上。

跨版本约束：

- `search_local_lore` 是默认且唯一的 Agent 检索工具。
- 除非后续版本重新立项并设计新的来源协议，否则 GameData / 游戏原始文本是
  唯一 active evidence source。
- Wiki 浏览内容和用户提供文本可以作为问题上下文，但不是 GameData 证据，不能
  被表述为官方游戏原文。
- Agent 不得用模型记忆补齐证据缺口；证据不足时必须明确说明无法确认或覆盖不足。
- 带证据的输出应保留 `source_path`、`raw_id`、`content_type`、retrieval type
  和 trust information。
- 新增检索行为必须提供基于 finalized GameData DB 的固定 QA 与回归测试。

### v0.5 - 事实核查 Agent

实现状态（2026-07-15）：代码、deterministic 自动化测试和 scoped 剧情命题的真实 Chat
QA 已完成。事实核查仅注册 `search_local_lore`，结论经过实际 GameData observation 二次
校验；四态 UI、证据展开、追问历史、话题切换指令、取消和重试已接入。其余固定真实 API
命题和 Android 真机渲染仍待执行，详见 `RETRIEVAL_QA.md`。

目标：仅依据本地 GameData 证据，把用户的设定或剧情说法判断为“支持”“反驳”
“存疑”或“无法确认”。

交付内容：

- 基于现有 ReAct Loop 增加事实核查模式。
- 实现“拆解主张与实体 → 多次定向调用 `search_local_lore` → 对照支持与反驳
  证据 → 形成结论”的 workflow。
- 剧情命题先分别解析 canonical `scope_id` 和 `entity_id`，再用单一关系、状态或动作词
  执行 evidence mode；普通复合关键词无结果不能被解释为反证。
- Fact-check 最终回答前至少完成一次工具调用；其 ReAct 预算为 7 轮、单步 4096 tokens，
  以容纳实体/范围解析和 reasoning provider 的输出，其他 Agent 保持默认预算。
- scoped evidence 在候选交集内按实体名与关系词的最短文本距离排序，优先返回同句或
  邻近句的直接陈述，而不是按剧情文件名排序。
- 在回答中区分直接证据、间接证据和证据缺失，不把 retrieval confidence 等同于
  事实确定性。
- 支持带对话上下文的追问，并检测话题切换；不得静默丢弃当前对话。
- 增加四种结论 UI 状态和可展开的 GameData 证据引用。
- 固定 QA 至少覆盖：支持、反驳、存疑、无覆盖各一个命题，以及一个上下文追问。

验收标准：

- “支持”或“反驳”结论必须引用实际检索到的 GameData 记录。
- 证据冲突或不完整时必须输出“存疑”或“无法确认”，不得依赖模型记忆作答。
- 追问能保留相关主张和证据上下文。
- 单元测试覆盖 tool 限制、来源声明、空结果、实体歧义和结论解析。

#### 后续候选：跨 Agent 共享剧情取证工具

v0.5 已验证的 scoped evidence 能力目前分布在 `search_local_lore`、
`GameDataKnowledgeStore`、Fact-check prompt 和 ReAct 配置中。后续迭代可将其抽取为独立
`StoryEvidenceRetriever` 和 `search_story_evidence` Agent tool，供 Fact-check、Summary
及后续 Role-play 复用；这项抽取不是 v0.5 已交付功能。

候选边界：

- 共享层负责 scope/entity 结构化解析、歧义状态、claim term 检索、proximity ranking、
  coverage 分类、稳定引用和 observation 截断。
- Agent 只负责各自任务：Fact-check 形成 verdict，Summary 按剧情顺序生成梗概，
  Role-play 只把证据作为角色背景而不冒充官方对白。
- 保留 `search_local_lore(search_mode=evidence)` 兼容入口，迁移完成且固定 QA 通过后再考虑
  弃用，避免复制 prompt 或一次性破坏既有 Agent。
- 首轮抽取不需要改变 schema v2；只有引入实体级剧情倒排表或行级关系索引时才规划
  schema v3 和新 release asset。
- 验收至少覆盖普通人物梗概回归、指定剧情中的人物经历、范围/实体双歧义、无覆盖、
  大量弱相关候选、输出截断和真实 Chat opt-in QA。

### v0.6 - 证据约束的角色扮演 Agent

实现状态（2026-07-15）：稳定 GameData entity/alias 解析、消歧、GameData-only ReAct、
角色绑定检索、多轮本地存档、继续/重开、取消/重试及双语 UI 已实现。自动 Agent 测试已
覆盖解析、歧义、工具门槛、角色记忆约束和存档容错；`test/live_fact_check_test.dart`、
`test/fact_check_widget_test.dart` 与完整 DB retrieval QA 已通过。更广的多角色矩阵和 Android
真机仍待验收，详见 `RETRIEVAL_QA.md`。

目标：提供角色扮演能力，同时明确区分官方设定事实与模型创作内容。

交付内容：

- 使用 GameData entity / alias 完成角色选择，并在开始会话前处理实体消歧。
- 通过 `search_local_lore` 检索干员档案、语音、秘录、模组和相关剧情片段，
  构建角色上下文。
- 允许用户提供可选场景设定，但必须标记为会话上下文而非 GameData 证据。
- 对超出角色认知、无证据时间线、用户设定与 GameData 冲突等情况定义约束。
- 支持多轮对话、本地存档、继续会话和重新开始。
- 展示选中的 canonical character 及会话所依据的 GameData 范围；生成对白不得
  冒充游戏官方台词。

验收标准：

- 生成前必须把角色解析到稳定 `entity_id`。
- 对话中的设定事实可追溯到 GameData；创作对白被明确视为生成内容。
- 测试覆盖重名、角色资料缺失、场景冲突、继续会话和重新开始。

### v0.7 - Wiki 阅读上下文转交

实现状态（2026-07-15）：v0.7.0 已封盘。已实现 WebView 当前选中文字、页面标题、URL 和站点信息显式转交到
Summary / Fact-check；转交文本会被包装为用户阅读上下文，Agent prompt 明确要求独立调用
`search_local_lore` 核验，且不得把 Wiki 文本或 URL 写成 GameData 证据。自动测试覆盖
Wiki context prompt 的有选区/空选区边界，以及 AI 页面接收 Summary 转交后的窄路径渲染；
release-mode APK build、完整 DB retrieval QA、setup dry-run 和 APK 签名校验已通过。
WebView 原生选区读取、底部面板交互、真实外部 Chat QA 和 Android 真机仍待验收，详见
`RETRIEVAL_QA.md` 与 `ARKLORES_V0.9_TECHNICAL_REPORT.md`。

目标：连接 Wiki 人工阅读与 AI workflow，但不恢复 Wiki seed RAG，也不把 Wiki
内容当作 GameData 证据。

交付内容：

- 支持把 WebView 选中文字和当前页面信息转交给 Summary / Fact-check 模式。
- Wiki 选中文字只作为用户提供的主张或提问上下文。
- 从选中文字解析实体，并独立调用 `search_local_lore` 核验后再作事实声明。
- 保留 Wiki URL 用于返回浏览和来源说明，但与 GameData evidence 分开展示。
- 书签或保存上下文的联动不得引入隐藏 indexing 路径。

验收标准：

- 不对 Wiki 页面做 embedding、vector indexing 或写入 GameData DB。
- Wiki 上下文和 GameData 证据在语义与视觉上明确区分。
- GameData 无法核实时，Agent 必须说明限制，不能直接认可 Wiki 选中文字。

### v0.8 - 证据与交互体验

实现状态（2026-07-15）：v0.8.0 已封盘。Summary / Fact-check 已统一来源栏、加载、取消、重试、错误和空状态；
`search_local_lore` observation 已通过独立 parser 转为可展开 GameData 证据卡，展示计划字段、
原文片段和不暗示事实确定性的覆盖度标签。自动测试覆盖窄屏、大字、双语资源、取消与 parser
边界；release-mode APK、完整 DB QA、release dry-run 和签名校验已通过。Android 真机截图、
TalkBack、横屏和来源路径导航仍 deferred，详见
`RETRIEVAL_QA.md` 与 `ARKLORES_V0.9_TECHNICAL_REPORT.md`。

目标：让移动端 Agent 结果便于检查，并能清楚理解结论的证据基础。

交付内容：

- 统一 Summary / Fact-check 的模式切换、加载、取消、重试、截断和空结果状态。
- 提供可展开证据视图，展示 title、section、content type、source path、raw id、
  retrieval type、ranking reason 和 trust note。
- 增加紧凑的结论与覆盖度标识，但不能暗示证据未支持的确定性。
- 改善实体消歧、来源导航、长回答阅读、无障碍、本地化和响应式布局。
- 视觉改进延续现有主题，优先保证证据检查与高频操作，不以装饰动画为主目标。

验收标准：

- 证据在支持的移动端尺寸下可读且不重叠。
- 来源标签不得把 Wiki、Book、用户上下文或生成文本描述为官方 GameData。
- Summary / Fact-check 核心流程支持无障碍文字缩放及现有双语环境。

### v0.9 - 视觉重设计与代码质量重构

实现状态（2026-07-15）：v0.9.0 已完成开发、自动验证、release-mode APK 构建、分支合并、
tag、推送与 GitHub Release。完整实现审计见 `ARKLORES_V0.9_TECHNICAL_REPORT.md`，持续验收
缺口统一维护在 `RETRIEVAL_QA.md`。

目标：在核心功能和证据交互稳定后，以《明日方舟》和《明日方舟：终末地》的
真实 UI 图片为视觉研究依据，系统重做 App 界面，并同步偿还影响 v1.0 维护性的
代码质量债务。

视觉设计交付内容：

- 收集并整理来自游戏实机、官方演示或官方宣传材料的 UI 参考图，记录图片来源、
  对应界面、可借鉴的布局规律和不应直接复制的品牌资产。
- 分别研究《明日方舟》的战术档案、工业信息层级与高对比导视，以及《终末地》的
  空间界面、信息密度、材质和动效语言；不得只凭印象使用通用科幻风模板。
- 先产出关键页面的 reference board、界面审计、线框图和高保真方案，经确认后再
  修改 Flutter UI。
- 重建可复用 design tokens，包括颜色、排版、间距、边框、图标、动效、状态和
  响应式约束；两套主题应有共同的信息架构，但保持清晰的视觉差异。
- 重做 Wiki、AI 对话、证据详情、知识库、设置和错误/空/加载状态，优先保证信息
  扫描、来源识别和高频操作效率。
- 对使用到的参考图片和最终 App 资产进行版权与授权检查；参考游戏 UI 不代表可以
  直接打包游戏截图、商标、角色立绘或其他受保护资产。
- 使用真机截图或自动化截图对比检查常见手机尺寸、横竖屏、双主题、双语和无障碍
  文字缩放，避免文字溢出、控件位移和内容遮挡。

代码质量交付内容：

- 审计 `print`、临时日志和可能泄露 API key、请求正文或用户对话的输出；开发诊断
  统一使用受 `kDebugMode`、assert 或项目日志抽象约束的机制，release 构建不输出
  调试信息。
- 把面向用户的字符串统一迁移到 ARB 本地化资源，补齐中英文翻译，并禁止在 Widget、
  Agent 错误提示和设置页面继续新增硬编码文案。
- 按职责拆分过长文件和过大的 Widget / service / Agent 类，优先处理同时承担 UI、
  状态、存储、网络或检索职责的模块；不以任意行数阈值制造无意义的小文件。
- 清理重复样式、重复 Widget、过深 build 嵌套、无效代码和过期兼容分支，统一命名、
  import、错误处理、异步生命周期和 Riverpod 使用方式。
- 收紧 analyzer / lint 规则，并为重构涉及的共享组件、状态流和关键业务行为补充测试，
  保证重构不改变检索、来源声明与 Agent 行为。
- 分阶段提交视觉改动与行为保持型重构，避免把全项目格式化、UI 重写和功能修改混在
  一个不可审查的变更中。

验收标准：

- 设计文档能把关键视觉决策追溯到具体的官方或实机 UI 参考，而不是只写“方舟风”
  或“终末地风”。
- 关键页面在目标尺寸、双主题、双语和文字缩放下通过截图审查，无明显溢出或遮挡。
- release 构建不存在无约束的 `print` 或敏感调试输出；用户可见字符串进入本地化资源。
- 选定的超长、高耦合文件完成职责拆分，公共组件和状态边界有清晰所有权。
- `flutter analyze`、相关单元/Widget 测试和既有 GameData retrieval QA 全部通过。
- 重构前后的固定 Agent / retrieval QA 结果没有非预期行为变化。

### v0.10 - 真机验证、检索质量与发布工程

目标：补齐 v0.9 以后最基础的端到端验收，使当前 GameData-first 版本不再只依赖
桌面自动测试和人工假设。

交付内容：

- 完成真机 asset 下载、checksum 校验、安装、替换、失败保留、检索和 Agent 对话。
- 覆盖下载中断、坏资产、空间不足、离线启动、schema 不兼容及旧有效 DB 保留。
- 扩充角色、组织、概念、剧情、歧义别名和意图归一化的固定 retrieval / Agent QA。
- 根据量化 QA 缺口增强剧情实体关系、组织/概念汇总和同义词归一化。
- 固定 GameData 源元数据，记录可复现的 builder、finalization、manifest、checksum
  和 release asset 流程。
- 在代表性 Android 设备上测量安装时间、DB 体积、查询延迟、内存和长对话表现。
- 进行小规模 beta，按严重级别处理正确性、检索、安装和 UI 问题。

验收标准：

- 自动测试、Flutter analyze、完整 DB 固定 QA、schema smoke build 和 release
  dry-run 能在文档化的干净环境中通过。
- 至少一台受支持 Android 真机完成从 release asset 到 Agent 回答的完整流程。
- 发布资产可由固定 GameData commit 重建，hash 与 finalized metadata 一致。
- 不存在未解决的发布阻断级正确性、数据丢失或来源归属问题。

### v0.11 - GameData 更新模式、多游戏数据与 schema 演进

目标：把知识库从一次性 release asset 扩展为可维护的数据产品。当前 DB 实际只覆盖
《明日方舟》中文 GameData；《终末地》只存在主题和 Wiki 浏览入口，不是 active
knowledge source。v1.0 前必须明确数据更新、版本兼容和多游戏边界，否则 App 会停留在
一次性测试包状态。

交付内容：

- 设计 GameData update manifest：包含 game、language、schema version、source commit、
  build tool version、asset URL、compressed/uncompressed hash、大小、发布时间、最低 App
  版本和迁移说明。
- 支持 App 内检查新知识库版本、展示当前已安装数据版本、下载前显示体积和变更摘要，
  并允许用户跳过或稍后更新。
- 定义全量包与增量包策略。若先不做增量更新，文档必须明确原因、下载体积上限、
  失败恢复和旧 DB 保留策略。
- 规划 schema v3：补足组织/概念实体、实体级剧情倒排、关系索引、时间线/活动范围索引、
  data quality flags 和多游戏字段，避免继续把复杂语义压在 FTS / LIKE 上。
- 将《终末地》作为独立数据源立项：确认来源、授权、语言、表结构、ID 稳定性、
  importer adapter、manifest 字段和 QA query。未完成前 UI 不得暗示 AI 已能依据
  Endfield GameData 回答。
- 为数据源刷新建立差异报告：新增/删除实体、改名 alias、story scope 变化、记录计数、
  top query 回归、hash 和构建日志。
- 定义旧 DB 兼容窗口和不兼容升级策略；schema 不兼容时必须保留设置和会话，并向用户
  明确说明需要更新知识库。

验收标准：

- 用户能在 App 内看懂“当前知识库覆盖哪款游戏、哪种语言、哪个源 commit、是否需要更新”。
- 替换 DB 失败不会丢失旧有效 DB。
- Arknights 与 Endfield 的数据来源、证据标签和检索范围不会混淆。
- 每次数据刷新都有固定 retrieval QA、差异报告和可追溯 manifest。

### v0.12 - 向量化与混合检索

目标：在保持 GameData provenance 的前提下引入语义检索，提升长剧情、模糊提问、
跨事件关系和角色经历召回。向量化不是恢复旧 Wiki seed RAG；它必须建立在
normalized GameData records、稳定 chunk id 和 source metadata 上。

交付内容：

- 先完成离线 benchmark，再决定是否进入 App 端：对比 SQLite structured/FTS、BM25-like
  排序、embedding 向量检索和 hybrid reranking 在固定 QA 上的召回、准确率、延迟和体积。
- 明确 embedding 生成位置：开发者离线生成、服务端生成、或设备端生成。默认不在手机上
  生成全量 embedding，除非证明电量、时间、模型体积和隐私成本可接受。
- 设计向量索引资产：包含 embedding model id/version、维度、量化方式、chunk id 映射、
  hash、schema compatibility 和 rebuild command。
- 选择部署形态：SQLite extension、独立 ANN 文件、平台原生库或纯 Dart fallback。选择前
  必须验证 Android ABI、包体、冷启动、查询延迟和崩溃恢复。
- 引入 hybrid retrieval contract：结构化实体/scope 解析仍优先；向量结果只能补充召回，
  不能覆盖 GameData provenance，最终 observation 仍必须引用 source_path/raw_id/content_type。
- 增加 reranker 或规则后处理，减少“语义相近但事实无关”的高分误召回；Fact-check 的
  supported/refuted 结论仍需直接证据。
- 为向量索引提供降级路径：索引缺失、版本不兼容、内存不足或设备不支持时自动回退到
  现有 SQLite 检索，并在 UI/日志中可诊断。

验收标准：

- hybrid 检索在固定剧情/角色/组织/概念 QA 上相对当前 FTS/LIKE 有可量化提升，且没有
  引入不可接受的误证据。
- 冷启动、单次检索延迟、内存峰值、安装包或下载体积满足目标 Android 设备预算。
- 所有向量结果都能追溯到 GameData chunk/record，不出现“只有 embedding 命中但无来源”的证据。

### v0.13 - Agent 质量、可控性与 provider 差异收敛

目标：减少输出质量对单一 Chat API/provider 行为的依赖，让 App 的工作流质量更多来自
可测试的编排、检索、约束和后处理，而不是靠 prompt 运气。

交付内容：

- 把 Summary、Fact-check、Role-play 的共同取证能力抽取为共享 story evidence layer，
  由代码负责 scope/entity/claim term 解析、候选聚合、排序、覆盖判断和 observation 截断。
- 将 Agent 工作流从自由文本 ReAct 逐步收敛为更结构化的步骤协议：计划、工具调用、
  证据表、结论草案、来源校验、最终回答。模型输出格式错误时可以局部重试，而不是
  整轮失败。
- 增加 deterministic post-check：检查引用是否真实出现在 observation、结论是否越过覆盖度、
  是否把 Wiki/用户上下文写成 GameData 证据、是否遗漏歧义。
- 建立 provider compatibility matrix：至少覆盖一个 OpenAI-compatible 主流 provider、
  一个 reasoning provider 和一个低成本模型，记录格式遵循、截断、中文质量、工具调用稳定性
  和延迟。
- 引入 answer quality fixtures：固定输入、固定本地 DB、mock LLM 或录制响应，验证
  Agent 在支持、反驳、存疑、无覆盖、长剧情梗概、角色设定冲突等场景下的行为。
- Role-play 需要单独质量边界：角色事实卡、会话记忆压缩、用户场景隔离、创作对白声明、
  低覆盖时的拒答/弱化策略，以及多轮漂移检测。
- 设计可观测性：本地 debug 日志可定位工具调用、检索覆盖和 provider 错误，但 release
  不记录 API key、完整请求正文或敏感用户对话。

验收标准：

- 换 provider 后，关键事实核查和梗概 fixtures 的结论类型、来源约束和错误处理保持稳定。
- Agent 可以在模型格式轻微偏离时恢复，无法恢复时给出可理解错误。
- 角色扮演不会把模型创作内容误标为官方原文。

### v0.14 - 性能、离线可用性与正式应用体验

目标：把 App 从“可测试的功能集合”打磨成日常可用的移动应用，重点处理体积、
速度、失败恢复、长会话和低端设备表现。

交付内容：

- 建立性能预算：冷启动时间、首次进入 AI 页时间、知识库状态读取时间、常见检索 p50/p95、
  DB 安装耗时、内存峰值、长回答渲染帧率和 WebView 标签切换成本。
- 优化 GameData DB 访问：连接生命周期、索引、分页、结果截断、并发请求取消、长查询超时、
  FTS/LIKE fallback 的上限和后台 isolate 可行性。
- 优化 AI UI：长对话虚拟化、Markdown 渲染成本、证据卡展开性能、取消/重试一致性、
  键盘避让、横屏、低内存恢复和页面状态保存。
- 完善离线体验：无 API、无 DB、旧 DB、下载失败、断网、provider 超时和 token 截断都要有
  明确状态、恢复动作和不会误导用户的文案。
- 增加正式发布能力：release keystore、版本升级策略、隐私说明、崩溃/日志策略、
  最小 Android 版本声明、权限说明和可重复 release checklist。
- 进行 beta 回收：记录真实设备型号、Android 版本、DB 安装方式、失败日志、慢查询和
  用户误解点，按阻断/高/中/低分级处理。

验收标准：

- 代表性中低端 Android 设备完成知识库安装、查询、Summary、Fact-check、Role-play 和
  Wiki 浏览，不出现不可接受卡顿或数据损坏。
- 所有关键错误都有用户可执行的恢复路径。
- release 构建使用正式签名流程，文档不再把 debug-certificate APK 当作正式发布包。

### v1.0 - 稳定 GameData-first 发布

目标：发布行为、文档、数据资产、性能和 AI 工作流质量均达到可日常使用的稳定版本。
v1.0 不应只因为 UI 完成或测试通过而发布；必须证明数据更新、检索质量、Agent 稳定性、
真机性能和发布工程已经闭环。

交付内容：

- 稳定交付 Summary 和 Fact-check；Role-play 与 Wiki 联动只有在满足对应证据和
  稳定性验收标准后才进入 v1.0。
- 发布签名应用、finalized 中文 GameData DB、manifest、build report、checksums
  和 release notes。
- 完善安装、API 配置、GameData 下载、存储需求、来源信任、隐私、限制与排障文档。
- 完善 tests、analyze、asset metadata 校验和 release packaging 的 CI，禁止提交
  secrets。
- 定义 GameData schema 升级、数据源刷新和不兼容已安装 DB 的支持策略。
- 明确哪些功能进入 v1.0 正式支持，哪些仍是 beta 或实验功能；未达到稳定标准的能力
  必须在 UI 和文档中标注限制。

验收标准：

- 全新安装和从最近受支持的 pre-1.0 版本升级均不会丢失有效设置或会话。
- 发布 hash、manifest、tag 和 release assets 相互一致。
- 产品文案与 Agent 行为始终区分 GameData 证据、Wiki 上下文、用户上下文和
  生成文本。
- 固定 QA、真实 Chat QA、真机性能矩阵和 release checklist 均有可复现记录。

## 旧路线映射

| 版本 | 保留的产品方向 | 已废止的实现前提 |
| --- | --- | --- |
| v0.5 | 事实核查、追问、话题切换、结论 UI | `search_wiki`、向量检索、Wiki 默认取证 |
| v0.6 | 角色选择与多轮角色扮演 | Wiki 角色卡和 Wiki / vector RAG 上下文 |
| v0.7 | Wiki 阅读到 AI 的联动 | 把 Wiki 文本送入隐藏索引证据源 |
| v0.8 | 交互和视觉完善 | 缺少 evidence UX 要求的动画优先范围 |
| v0.9 | UI 精修与工程质量提升 | 仅凭抽象主题描述进行动画优先的视觉修改 |
| v0.10 | 测试、性能、beta、错误处理 | 依赖桌面自动测试替代真机端到端验收 |
| v0.11 | 数据更新、多游戏 schema 和终末地数据接入 | 把视觉主题或 Wiki 浏览误认为 Endfield GameData 支持 |
| v0.12 | GameData provenance 约束下的 hybrid/vector retrieval | 旧 Wiki seed 向量库、无来源 embedding 命中 |
| v0.13 | Agent 编排、后处理和 provider 兼容 | 单纯依赖 prompt 或单一模型表现 |
| v0.14 | 正式应用性能、离线恢复和发布工程 | debug-certificate APK 和玩具级错误处理 |
| v1.0 | 稳定正式发布 | 依赖已废止 seed DB 的打包假设 |

## Verification

Required for relevant changes:

```bash
/home/hhikr/flutter/bin/flutter test test/agent_test.dart
/home/hhikr/flutter/bin/dart analyze <changed files>
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
```

GameData smoke build:

```bash
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart \
  --arknights-source=/tmp/ArkLores-ArknightsGameData \
  --output=/tmp/arklores_gamedata_smoke \
  --force \
  --story-limit=1
```
