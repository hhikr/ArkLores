# ArkLores 可行性分析：AI 检索优化与 App 内构建剧情数据库

> 分析日期：2026-08-24
> 分析基准：dev 分支当前 HEAD（e2867cd），v0.9.0 / GameData schema 2
> 方法：代码级逐行核对（lib/core、tools、pubspec）+ 两份子代理事实报告
> （`docs/RETRIEVAL_INSTALL_CHAIN_ANALYSIS.md`、构建工具链分析）+ GitHub API 实测
> （仓库规模、树结构、提交节奏、compare API）。
> 本文档只做可行性评估，不改动现有文档；落地后按项目约定更新
> `AI_RETRIEVAL_OPTIMIZATION.md` / `RETRIEVAL_QA.md` / `KNOWN_LIMITATIONS_AND_DEBT.md`。

---

## 0. 结论摘要（TL;DR）

| 议题 | 结论 | 一句话理由 |
| --- | --- | --- |
| `docs/AI_RETRIEVAL_OPTIMIZATION.md`（超长文本剧情问答检索优化） | **总体可行，P0 可立即立项；P1 可行但有 3 个需补充的设计点** | 计划的技术断言与代码结构全部对得上（rowid、FTS、预算、ReActLoop 参数、transform、ToolRegistry、page_token 均已核验）；工程是确定性实现、无模型调用成本。P1 的"已读范围校验"依赖 observation 文本标记、"上下文预算策略"缺失、实体覆盖边界需要明示 |
| App 内直接构建剧情数据库（拉取仓库 → 增量更新 → 按结构规约更新 DB） | **架构上可行，但属于中等规模数据产品化工程，需先做 3 个技术决策** | importer 是纯 Dart（唯一硬阻塞是 `Process.run('git')` 与 `sqflite_common_ffi` 后端，均可替换）；源数据实际只需要 ~168 MB 子集（20 个 excel JSON 105 MB + 5,691 个剧情 TXT 63 MB），远小于全仓库 945 MB；仓库约 1–2 周更新一次，GitHub compare API 实测可用于增量 |

两项工作有一个共同的架构前置：**把 `_ArknightsImporter` 从 `tools/` 抽到 `lib/`**，并让
schema v3（AI 计划的 P0 新增表）的构建阶段一次实现、两条构建路径（桌面 release 管线与
App 内构建）共用。建议顺序：先做 AI 计划 P0（纯确定性工程、不依赖 App 内构建），再做
App 内构建，最后做 AI 计划 P1（依赖 P0 的倒排表）。

---

## 1. 项目理解摘要

ArkLores 是一款《明日方舟》剧情 AI 辅助阅读 App（Flutter / Riverpod / sqflite）。核心运行链：

```text
用户输入 → Riverpod Chat Notifier → Agent(Summary/Fact-check/Role-play)
  → ReActLoop → search_local_lore → GameDataKnowledgeStore → 本地 SQLite schema 2
  → 带 provenance 的 Observation → LLM 生成回答 → 来源守卫/verdict transform → 证据卡
```

关键约束（`CLAUDE.md` / `implementation_plan.md`）：

- GameData（游戏原始文本）是唯一主动证据源；Wiki/用户文本只能作为阅读上下文；
- Agent 默认只注册 `search_local_lore` 一个工具（ToolRegistry 无其他来源工具）；
- 知识库通过 GitHub Release asset（`arklores_gamedata_zh.db.gz`，115 MB）下载安装，
  由 `tools/build_gamedata_database.dart` 从 Kengxxiao/ArknightsGameData 的 `zh_CN` 目录构建；
- 结论必须有 observation 中可找到的 GameData 证据（verdict transform / applySourceGuard 代码级约束）。

数据规模（v0.9.0 manifest）：entities 17,680 / story_lines 406,279 / normalized_records 95,362 /
lore_chunks 99,857 / entity_documents 833 / entity_relations 17,861；DB 395 MB（gz 115 MB）。

---

## 2. AI 检索优化计划可行性

### 2.1 总体评价

计划把检索模型从"相似度 top-K"调整为"出场覆盖 + 跨章节细节匹配 + 多候选对比"，与
代码现状和项目"确定性优先、代码门槛而非 prompt"的哲学一致。P0/P1 均为确定性实现
（全量扫描、FTS 重建、新表、新工具），P2（向量/摘要/时间线）全部走门禁——成本结构合理。

### 2.2 计划技术断言核验（代码级）

| 计划断言 | 代码证据 | 结论 |
| --- | --- | --- |
| `story_lines` 为 TEXT 主键，SQLite 保留隐式 rowid，外部内容 FTS 可用 | `build_gamedata_database.dart` 211–223 行 `id TEXT PRIMARY KEY`；同类先例 `lore_chunks_fts` 已用 `content_rowid='rowid'`（326–334 行）且生产可用 | ✅ 成立 |
| `story_lines` 未暴露给 Agent | store/agent 全库 grep 无引用；仅 installer 必需表清单出现 | ✅ 成立 |
| 观察预算 4800 / excerpt 700 / top_k ≤ 10 的实现位置 | `search_local_lore.dart` 10–11、74、167–171、264–268 行 | ✅ 已定位，新工具需独立预算 |
| ReActLoop 支持 12–15 轮 / 4096+ / minToolCalls ≥ 4 | `react_loop.dart` 51–53 行构造参数；Fact-check 已用 7/4096/1 | ✅ 零改动可扩展 |
| `finalAnswerTransform` 可做已读范围校验 | `react_loop.dart` 11–14、339–349 行；先例 `validateFactCheckVerdict`（`fact_check_agent.dart` 49–85 行） | ✅ 机制存在，但见 §2.4 补充点 1 |
| 新工具接入 ToolRegistry | `agent_tool.dart` 14–36、`tool_registry.dart` 8–27 行；角色绑定包装先例（`roleplay_agent.dart` 100–124 行） | ✅ 机制清晰 |
| page_token 无服务端状态可行 | observation 是单字符串（`agent_tool.dart` 3–11 行）；`react_parser.dart` 83–97 行 loose map 支持回传 | ✅ 可行；需 prompt 强制原样回传 |
| FTS tokenizer 差异 | `entity_documents_fts` 用 trigram（需 SQLite ≥ 3.34，老设备报错被 try/catch 静默吞掉）；`lore_chunks_fts` 默认 unicode61（中文近似逐字 token） | ⚠️ `story_lines_fts` 的 tokenizer 需明确选择并配套 LIKE 回退（计划 §4.1 已提示） |

### 2.3 P0 阶段评估（确定性覆盖层）

- **schema additive**：4 张新表 + 1 个 FTS 均为新增，不修改现有表，旧 App 不受影响 ✅。
  落地需同步改 3 处：`gamedata_installer.dart` 必需表清单（194–205 行）与
  `schema_version` 校验（234 行）、`finalize_gamedata_assets.dart` 的 manifest 计数/hash、
  `check_gamedata_retrieval.dart` 固定 QA 增加新表断言。
- **构建第 5 阶段**：trie 单遍扫描（约 50 MB 剧情文本）、章节画像、bigram doc_freq、
  `story_lines_fts` 重建，全部确定性、可复现 ✅。两个工程注意点：
  1. bigram doc_freq 统计在 5,691 个 story 文件上会产生百万级 distinct bigram，
     内存峰值需控制（建议 per-file 去重后累积，或落临时表）；
  2. `story_lines_fts` 外部内容索引重建 40.6 万行，桌面约 1–3 分钟，移动端构建时
     需并入后台任务（见 §3）。
- **3 个新工具**：纯 SQL、无模型调用 ✅。建议每个工具定义稳定、机器可解析的观察标记
  （如 `Coverage Count:`、`Next Page Token:`），为 P1 的 transform 校验留契约（§2.4 补充点 1）。
- **已读范围报告**：`finalAnswerTransform` 拿到的是 observations 列表（`react_loop.dart` 348 行），
  但**观察文本不含工具名**——校验"声明读取了 X 章节"必须依赖工具输出中的显式标记
  （如 `Read Lines: story_id=... count=...`），计划需把标记格式写入工具契约，否则只能做弱校验。
- **QA 方案**：5 章合成 fixture + 单元测试 + 回归门禁设计完整 ✅。

**工作量（P0）**：约 4–6 人日（schema + 构建阶段 + 3 工具 + 工作流/报告 + 测试与 QA），
不含真实 DB 谜题用例的人工选定。

### 2.4 P1 阶段评估（跨章节推理）

- `find_detail_echoes` / `collect_suspect_evidence`：SQL 层直接可做 ✅；
  特征词提取需过滤实体名/别名，否则角色名会淹没细节词（建议补充该规则，计划未显式列出）。
- `StoryInvestigationAgent`：照抄 `FactCheckAgent` 的装配模式（独立 registry + loop 配置 +
  transform）即可承载 S0–S8 协议 ✅；阶段门槛由 transform + 观察标记代码级校验可行，
  但本质是 stringly-typed 契约——建议为新工具定义严格观察格式并配套解析函数
  （可参考 `evidence_observation.dart` 的块解析，27–77 行）。
- **补充设计点 2：上下文预算策略缺失。** 12–15 轮 × 每页 4,800 字符原文，
  一次调查的上下文会快速增长（`agent_provider.dart` 144–174 行 buildHistory 会把全部
  ReAct 文本回灌下一轮）。需要在计划中明确：单章节精读页数上限、已读章节是否压缩后
  进入后续轮次、以及模型上下文窗口的硬约束（否则长章节读完即超窗）。
- **补充设计点 3：实体覆盖边界。** 出场覆盖 = `entities` 表覆盖（17,680 个实体：干员/敌人/
  物品/收藏品等），**不含剧情中的普通 NPC 与艺术化指称**。建议 P0 的 trie 增加
  "story speaker 名"扩展通道（`_parseStoryLines` 已提取 speaker，成本极低），否则
  "某角色全部出场"对无实体行的 NPC 会系统性漏报，且计划应把该边界写入文档。
- verdict 校验（S6 门槛、行级 provenance、覆盖报告比对）有 `validateFactCheckVerdict`
  现成同构实现 ✅。

**工作量（P1）**：约 5–8 人日 + 2–3 个真实剧情谜题用例的人工选定与 QA。

### 2.5 风险与诚实边界

- **艺术化伏笔的推理无法完全可靠**：计划已明确这是开放研究问题（NovelHopQA/SagaQA 同款
  失败模式），以置信度 + 替代解读 + 已读范围报告兜底——定位诚实，工程目标（可达性 +
  证据链 + 覆盖透明）可达成，不承诺谜底可靠 ✅。
- **误导内容占比高**：多候选对比只能部分缓解"多数内容指向错误结论"；计划未承诺
  反方证据的自动权重，依赖 Agent 遵循协议，需用 QA 验证。
- **成本**：一次调查 12–15 次 LLM 调用 + 大量原文 token，单次成本可预估但有上限；
  建议 P1 上线前做成本测算并给出单次调查预算提示。

### 2.6 AI 计划小结

P0 是**可立即立项的确定性工程**，代码基础完备，主要风险是构建阶段的内存/时长与
schema v3 安装链同步。P1 可行，但需要先补上：observation 标记契约、上下文预算策略、
实体覆盖边界（含 speaker 扩展）。建议按 P0 → P1 顺序推进，P2 严格走门禁。

---

## 3. App 内构建剧情数据库可行性

### 3.1 事实基础（实测数据）

| 项 | 数值 | 来源 |
| --- | --- | --- |
| 源仓库 | Kengxxiao/ArknightsGameData（master） | GitHub API |
| 仓库 git 体积 | ~785 MB（size 字段 803,657 KB） | GitHub API |
| `zh_CN` 工作树 | 11,890 个文件，~945 MB（blob 求和） | tree API |
| **importer 实际需要** | **~168 MB**：20 个 excel JSON（105 MB，最大 stage_table 18.6 MB）+ 5,691 个剧情 TXT（62.7 MB，单文件均值 ~11 KB） | tree API + 构建器路径核对 |
| 不需要的文件 | levels/（3,743）、bakemuzzledata/（702）、`[uc]lua/`、art/、resource_manifest_idx.json（44 MB）等 | 构建器 grep 核对 |
| 产出 DB | 395 MB（gz 115 MB） | build/gamedata_mobile |
| 更新节奏 | 约 1–2 周一次（CN update：07-10、07-17、08-01、08-08、08-18） | commits API |
| 当前 DB 锁定的源 commit | 634e7e7d（2026-07-10）；master 头 6844859c（2026-08-18） | manifest + API |
| compare API 实测 | `compare/<old>...<master>` 可返回 changed files 列表（**分页上限 300 文件/页，超限需翻页**，勿把 300 当总量） | 实测 |

### 3.2 能力 1：拉取仓库

- **首次全量**：`https://codeload.github.com/Kengxxiao/ArknightsGameData/zip/<sha>` 单请求
  下载（估算 400–600 MB，JSON/TXT 压缩比 2–3×，未实测精确值）。App 侧用 `archive` 包
  （纯 Dart）解压，需 ~1 GB 临时空间。可用固定 SHA 锁定可复现快照，**优于拉 master 分支**。
- **不推荐首次逐文件拉取**：5,691 个 raw 请求即使 16 并发也要 10–20 分钟且脆弱。
- 可选优化（不阻塞）：在自己的仓库用 GitHub Action 监听上游 commit，产出
  "importer 子集 zip"（~168 MB 源 → zip ~50–80 MB）作为 release asset——这能显著降低
  首次拉取成本，但引入自己的资产管线（与 §3.6 的双通道设计兼容）。
- **`Process.run('git', ...)` 不可用**（iOS 不支持 Process，Android 无 git 二进制）：
  commit SHA 改为构建前调 GitHub API（`GET /repos/.../commits/<ref>`）获取并注入 importer，
  语义与现在 `_gitCommit`（`build_gamedata_database.dart` 380–387 行）一致。

### 3.3 能力 2：增量更新

- **机制**：已装 DB 的 manifest 记录 `source_arknights_commit`（installer 已有
  `GameDataInstallStatus.sourceCommit` 读取）→ 调 `compare/<old>...<master>`（或
  `<old>...<new_sha>`）拿 changed files 列表 → **按 importer 路径白名单过滤**
  （`zh_CN/gamedata/excel/*.json` 的 20 个 + `zh_CN/gamedata/story/**/*.txt`）→
  逐个从 `raw.githubusercontent.com` 下载新文件。每文件一请求、16 并发、断点重试。
- **典型更新量**：一次游戏版本更新约 50–200 个 importer 相关文件（新活动 ~30–70 个剧情
  TXT + 数个 excel 表），合计 **10–60 MB**，远小于全量 zip——增量收益显著。
- **API 限流**：compare/commits 调用一次会话仅 2–3 次，未认证 60 次/小时足够；
  raw 下载走 CDN 不占 API 配额。若未来高频使用再考虑 token。
- **可靠性**：下载单个文件失败 → 该文件标记失败并整体回滚（保留旧 DB），不产生半新库；
  下载全部完成后统一进入构建阶段。

### 3.4 能力 3：按结构规约更新数据库

- **importer 抽取**：`_ArknightsImporter`（389–1415 行）是纯 Dart（除 `_gitCommit`），
  可直接移入 `lib/core/gamedata/build/`，把 `sqflite_common_ffi` 后端参数化。
- **移动端 DB 后端二选一**：
  - (a) 直接用现有 `sqflite` 平台通道写库——零新依赖，但 FTS5/trigram 依赖设备系统
    SQLite 版本（老设备建 trigram 表直接报错）；
  - (b) 新增 `sqlite3` + `sqlite3_flutter_libs`（捆绑新版 SQLite 3.4x，含 FTS5+trigram），
    仅构建器用 FFI、读取侧保持 sqflite（文件格式互通）。
    **推荐 (b)**：保证构建端 FTS 能力与版本一致，构建还能跑在后台 isolate（FFI 不依赖
    平台通道）。
- **增量 DB 更新（变化粒度 = 源文件）**：
  1. 对每个 changed 源文件，`DELETE FROM 派生表 WHERE source_path = ?`；
  2. 重跑该文件的导入（importer 的 story/excel 导入是 per-file 独立事务，天然支持）；
  3. 末尾对 `lore_chunks_fts` / `entity_documents_fts`（及 P0 的 `story_lines_fts`）
     执行全量 `rebuild`（现成命令，`build_gamedata_database.dart` 118–121 行）——约 30–90 秒，
     比逐行 FTS 增量维护简单可靠；若实测太慢再优化为行级 delete/insert。
  4. 主键是内容 SHA-1（`_stableId`），重复导入幂等（`ConflictAlgorithm.replace`）——
     现有设计已为增量打好基础 ✅。
- **校验与替换**：复用 installer 模式——写 `.tmp` → 必需表/schema_version/计数校验
  （建议把 P0 新表与 `story_line_count` 补进校验清单）→ 删旧 → rename ✅。
- **差异报告**：更新前后对比 manifest 计数 + 固定 QA 结果，写入 `gamedata_build_report`，
  满足 `GAMEDATA_BUILD_PIPELINE.md` 的 v1.0 前数据产品缺口（§v1.0 更新模式）✅。
- **确定性**：`updated_at`/`built_at` 时间戳导致字节级不可复现——差异报告/增量判断
  不应依赖字节 diff；行级内容用 PK 与 content 指纹（建议把 `_nowSeconds()` 改为内容哈希
  派生或至少不在增量比较路径上使用）。

### 3.5 移动端约束与风险

| 风险/约束 | 影响 | 对策 |
| --- | --- | --- |
| `Process.run('git')` 不可用 | 拿不到 commit | GitHub API 注入 SHA（§3.2） |
| `sqflite_common_ffi` 移动端不可用 | 构建器无法直接跑 | 后端换 sqflite 或捆绑 sqlite3_flutter_libs（§3.4） |
| trigram FTS 依赖设备 SQLite 版本 | 老设备建表失败 | 捆绑 SQLite（推荐）或建前版本检查 + 降级 |
| 内存峰值（jsonDecode 大 excel） | 单文件 10–25 MB → 解码后数十 MB | 逐文件顺序处理、及时释放；现代手机可承受 |
| 构建时长 | 估算桌面 3–10 分钟；移动端 10–40 分钟 | 后台任务 + 进度 + 取消/续传（构建本身可断点：per-file 幂等） |
| 存储 | 峰值 ~2 GB（zip 400–600 MB + 解压 945 MB + DB 395 MB + gz 115 MB） | 构建完成即删解压源与 zip；构建前检查空闲空间并明示 |
| **store 缓存句柄不关闭（既有缺陷）** | 替换后 App 继续读旧库 | 安装/替换前调用 `GameDataKnowledgeStore.close()`（297–300 行，当前 lib 内无调用点）——本次应一并修复 |
| GitHub 网络不稳/限流 | 下载失败 | 重试 + 失败整体回滚保留旧库（与现有 installer 语义一致） |
| 仓库结构漂移（路径/字段变化） | importer 报错 | 版本化 manifest + 校验失败回滚 + 明确报错文案 |
| 法律/许可 | 与现有 DB 资产同源（社区解包数据） | 无新增风险；App 内构建反而减少"App 再分发"环节 |

### 3.6 产品形态建议

**双通道知识库**：

1. **官方快照（默认快速路径）**：维持现有 release asset 下载（115 MB gz，一次安装即用）；
2. **从仓库构建（高级/新鲜度路径）**：知识库页新增"从源仓库构建"入口，首次 zip 全量
   或复用已装 DB 做增量；展示来源 commit、构建进度、预计耗时、存储要求；构建完成自动替换。

增量更新的收益在 3.3 已量化（10–60 MB/次 vs 115 MB 全量）；"跟着游戏版本走"的诉求
（新干员、新活动剧情）由该通道满足，且不再依赖开发者发版节奏。

### 3.7 App 内构建工作量估算

| 工作项 | 人日 |
| --- | --- |
| importer 抽到 lib/ + DB 后端参数化 + sqlite3_flutter_libs | 1–2 |
| 拉取层（API SHA、zip 下载/解压、compare 增量、raw 并发下载、重试） | 2–3 |
| 增量 DB 更新（per-file delete+reimport、FTS rebuild、校验、原子替换、差异报告） | 2–3 |
| 构建 UI（入口、进度、存储检查、取消/续传、错误/空态、ARB 双语） | 1–2 |
| 测试（单元 + widget + 真机 smoke 构建 + 失败恢复） | 1–2 |
| 合计 | **7–12 人日**（不含 P0 表的新增构建阶段，见 §4） |

---

## 4. 两条路线的协同与建议落地顺序

共同前置：**importer 进 lib/（一次抽取，两条路径共用）**；schema v3（P0 新表）的构建
阶段一次实现，桌面 release 管线与 App 内构建同时受益（否则两套构建代码会漂移）。

建议阶段路线（R0 已于 2026-08-24 落地，见 `docs/R0_BUILD_LAYER_SUMMARY.md`）：

- **R0（前置，1–2 人日）✅ 已完成**：importer 抽到 `lib/core/gamedata/build/`；修复 store 缓存句柄
  在替换前不关闭的既有缺陷；补 `story_line_count` 校验。
- **R1（AI 计划 P0，4–6 人日）✅ 已完成（2026-08-24，见 `docs/R1_STORY_COVERAGE_LAYER_SUMMARY.md`）**：
  schema v3 + 构建第 5 阶段 + 3 个新工具 + 已读范围报告。
- **R2（App 内构建，7–12 人日）✅ 已完成（2026-08-24，见 `docs/R2_IN_APP_BUILD_SUMMARY.md`）**：
  拉取层（zip 白名单解压 + compare 增量 raw）+ per-file 增量入库 + 后台 isolate 构建 + 构建 UI。
- **R3（AI 计划 P1，5–8 人日 + 谜题用例）**：跨章节细节定位 + 多候选对比 + 调查协议。
  门禁：合成 fixture 与 2–3 个真实剧情谜题固定用例通过；成本测算后设定单次调查预算。
- **R4（可选）**：P2 增强（全部走 `RETRIEVAL_QA.md` Hybrid 门禁）；服务器打包器
  （降低首次拉取成本）。

---

## 5. 结论

1. **AI 检索优化计划可行**，且 P0 是当前性价比最高的确定性工程——代码基础已验证完备，
   落地即把"40 万行原文的覆盖枚举 + 行级可读"从无到有建立起来，直接回应
   `KNOWN_LIMITATIONS_AND_DEBT.md` §4.4/§5.1 的核心检索债。P1 的 3 个补充设计点
   （观察标记契约、上下文预算策略、实体覆盖边界含 speaker 扩展）应在立项时写入计划。
2. **App 内构建数据库可行**，是 `GAMEDATA_BUILD_PIPELINE.md` 数据产品化缺口的直接落地，
   增量更新收益量化明确（10–60 MB/次）。3 个关键决策：SQLite 后端（推荐捆绑
   sqlite3_flutter_libs 给构建器）、首次拉取方式（zip 全量 vs 服务器子集包）、构建 UX
   （后台 + 进度 + 续传 + 失败保留旧库）。
3. 两项工作共享 importer 抽取与 schema v3 构建阶段，按 R0→R1→R2→R3 顺序推进可避免
   重复建设；两者组合后，用户将能"在 App 上从最新解包数据构建/增量更新知识库，
   并让 AI 对超长剧情做有覆盖保证的跨章节推理"。
