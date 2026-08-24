# R1 开发总结：AI 检索优化阶段 P0 —— 确定性覆盖层

> 完成日期：2026-08-24
> 范围：`docs/AI_RETRIEVAL_OPTIMIZATION.md` 阶段 P0（确定性覆盖层），即建议路线的 R1。
> 状态：P0 已落地并通过全部验证；下一步为 R2（App 内构建数据库）或 R3（P1 跨章节推理）。

---

## 1. 背景与目标

`AI_RETRIEVAL_OPTIMIZATION.md` 指出当前检索的两大结构性缺陷：检索依赖字面匹配
（FTS/LIKE），"某角色在哪些章节出场"这类基础问题无法被确定性回答；Agent 拿不到
40 万行剧情原文（`story_lines` 未暴露）。P0 的目标是建立**与查询措辞无关的确定性
覆盖层**：

1. 实体出场倒排——无论用户怎么问，都能确定性枚举"某实体出现在哪些 scope/章节/
   哪些行区间"；
2. 章节画像——为"精读哪些章节"提供浏览依据；
3. 行级原文读取——Agent 可以直接按行区间/分页阅读剧情原文；
4. 已读范围报告——回答末尾如实声明读了哪些 scope，不允许虚构。

## 2. 工程变更

### 2.1 schema v3（`lib/core/gamedata/build/gamedata_schema.dart`）

四张新表 + 一个 FTS，全部 additive（不修改现有表）：

| 表 | 内容 | 规模预估（真实数据） |
| --- | --- | --- |
| `entity_story_mentions` | 实体出场倒排：entity_id / story_id / scope_id / 行区间 run / mention_count / matched_alias | 20–50 万行级 |
| `story_chapter_profiles` | 每 story 画像：行范围、speaker 集合、实体密度 top N、抽取式摘要、死亡/凶案词典命中（triage 提示） | 5,691 行 |
| `rare_terms` | 跨文件 doc_freq ≤ 20 的中文双字词（IDF 依据，供 P1 细节匹配） | 数十万行级 |
| `story_lines_fts` | `story_lines` 的行级外部内容 FTS（tokenizer 与 `lore_chunks_fts` 一致的默认 unicode61，配套 LIKE 回退） | 40.6 万行索引 |

`gamedataSchemaVersion` 升至 3；安装器必需表清单同步 + 校验 `schema_version == '3'`。

### 2.2 构建第 5 阶段（`lib/core/gamedata/build/story_coverage_builder.dart`）

`StoryCoverageBuilder` 在四阶段 importer 之后运行，三遍扫描 `story_lines`：

- **Pass A**：实体 trie（canonical name + 全部 alias，最长匹配）逐行扫描
  **speaker + content**（关键设计：台词人物的出场名在 speaker 字段，只扫 content
  会漏掉绝大部分出场；bigram 与词典命中仍只取 content），连续命中行合并为 run
  写入 `entity_story_mentions`；同时累积 bigram 跨文件 doc_freq（freq > 20 即停止
  跟踪以控内存）与每 story 的画像草稿。
- **Pass B**：`doc_freq <= 20` 的 bigram 写入 `rare_terms`（分批事务 + batch）。
- **Pass C**：每 story 重读行，按"实体命中 ×2 + 稀有词命中"取分数最高的行作为
  确定性抽取式摘要，`entity_density` 由 mentions 表聚合得到，写 `story_chapter_profiles`。

`BuildStats` 增加 `storyCoverageMentions` / `storyProfiles` / `rareTerms` 计数，
CLI 写入 manifest（`story_coverage_mention_count` / `story_profile_count` /
`rare_term_count`）与构建报告。

### 2.3 三个新工具（`lib/core/agent/tools/`）

| 工具 | 参数 | 行为 |
| --- | --- | --- |
| `search_story_coverage` | `query` 或 `entity_id`，可选 `scope_filter` | 实体消歧后按 scope 分组枚举全部出场；观察输出机器可读标记 `Coverage Scopes:` / `Coverage Stories:` / `Scope:` |
| `read_story_lines` | `story_id` + `start_line`/`end_line`/`max_lines`/`page_token` | 行级原文读取，独立 4800 字符预算，`Next Page Token` 续读，`Story not found` 与无行区分；单行超预算强制截断首行保证 token 推进 |
| `get_story_map` | `story_ids` 列表或 `scope_id` | 章节画像（行范围、speaker、Top Entities、Keyword Hits、Summary），输出 `Mapped Stories:` 标记 |

三个工具均为纯 SQL + 格式化，无模型调用；`GameDataKnowledgeStore` 新增对应查询方法
（`searchStoryCoverage` / `readStoryLines` / `getStoryMap`），复用句柄失效修复与
`_hasTable` 守卫（旧 schema 库返回空而非报错）。

### 2.4 Summary 叙事工作流与已读范围校验

- `SummaryAgent` 注册全部四个工具（search_local_lore + 三个新工具），迭代预算
  4 → 8（覆盖枚举 + 画像 + 分页阅读 + 回答）。
- `summaryInstructions` 增加叙事类问题流程：coverage 枚举出场 → map 选精读范围 →
  read 通读原文 → 末尾输出 `Coverage: read=<精读 scope 数> | mapped=<画像 scope 数> |
  skipped=<未读+原因>`。
- 新 `validateCoverageReport`（`lib/core/agent/story_coverage_transform.dart`）作为
  Summary 的 `finalAnswerTransform`：从 observations 的机器可读标记重算 read/mapped/
  covered 的真实 scope 数，**改写虚构的 Coverage 行**、补缺失行、非叙事回答不动。
  Fact-check / Role-play 保持原注册不变（避免回归风险）。

### 2.5 其他

- `test/agent_test.dart` 测试助手升级到 schema v3（含四张新表），`story_line_count`
  校验保持。
- 端到端 CLI 验证：合成源树完整跑通 schema v3 构建（mentions / profiles / rare_terms
  落库、manifest 计数正确）。

## 3. 验证结果

| 验证项 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` 全量 | **86 passed / 3 skipped（live Chat opt-in）/ 0 failed** |
| 新增 `test/story_coverage_test.dart` | 16 项全过 |
| 固定检索 QA（既有 v2 DB） | 11 个固定 query、`特蕾西娅` 3 候选、`act21mini+米格鲁+死亡` scoped evidence 全绿 |
| 端到端 CLI 构建（合成源） | schema v3 产物：mentions 2 / profiles 2 / rare_terms 26，manifest 计数正确 |

新增测试覆盖：run 合并、bigram 过滤、mentions 断言（含 speaker 出场）、画像
（keyword hits / entity density / summary）、rare_terms doc_freq 阈值、`story_lines_fts`
重建非空、三个工具（含分页与缺章）、coverage transform（补行/改写虚构/非叙事不动）、
Summary 叙事工作流集成（coverage→map→read 工具序 + Coverage 行被规范化为真实值）。

## 4. 用户端影响

1. **叙事类提问的检索能力质变**：此前"某角色在哪些剧情出场"依赖 FTS/LIKE 措辞
   巧合，现在可确定性枚举全部出场章节、行区间与提及次数；Agent 能直接阅读原文
   行而非只依赖相似度截断片段。
2. **回答可审计性**：叙事回答末尾的 `Coverage:` 行与真实工具调用绑定，模型
   "声称读了没读的章节"会被自动改写——从机制上禁止虚构已读范围。
3. **对既有功能零破坏**：schema 变更 additive；Fact-check / Role-play / Wiki /
   梗概非叙事路径行为不变；旧 schema v2 库在检索侧仍可用（新工具返回空 + 明确
   提示），只是安装器要求新库用 schema v3。
4. **用户侧无新 UI 负担**：本阶段不新增界面，行为变化全部发生在 Agent 内部；
   后续 R3（P1）会在证据卡上展示覆盖范围。

## 5. 实际效益

- **确定性覆盖替代概率性猜测**：出场枚举与"怎么写查询词"解耦，直接回应
  `KNOWN_LIMITATIONS_AND_DEBT.md` §4.4/§5.1 的核心检索债；`entity_story_mentions`
  也是 P1 `collect_suspect_evidence` 的现成数据源。
- **行级原文可达**：`story_lines_fts` + `read_story_lines` 打通了"40 万行原文可被
  Agent 逐行阅读"的能力，这是跨章节推理（P1）与"误导章节只算一份证据"的前提。
- **为 R2（App 内构建）铺路**：覆盖层构建全部在共享 `lib/core/gamedata/build/`，
  schema v3 一次实现，桌面 release 管线与未来的 App 内构建共用；新增表计数进入
  manifest，R2 的增量差异报告可直接对比。
- **可测试性**：trie/run 合并/bigram 提取均为纯函数；构建管线用真实 schema +
  importer + builder 端到端测试；transform 校验有确定性单测——后续 P1 门槛测试
  可同构扩展。
- **成本**：P0 全部为确定性实现（全量扫描 + 新表 + 纯 SQL 工具），无模型调用成本；
  合成 fixture 验证 5 章场景，真实 40 万行数据构建的耗时/内存尚未量化（R2 后台
  构建体验一并处理）。

## 6. 遗留与下一步

- **未做**：P0 的 `story_lines_fts` 用默认 unicode61 tokenizer，2 字符中文词的
  精确短语匹配有限（与 `lore_chunks_fts` 一致），P1 `find_detail_echoes` 需配套
  LIKE 回退；真实数据规模下 rare_terms 内存峰值与构建时长未量化（桌面可承受，
  R2 需优化）；`check_gamedata_retrieval.dart` 尚未增加 v3 覆盖层断言（旧 v2 DB
  仍为回归基准，v3 发布时补充）。
- **下一步 R2（App 内构建数据库）**：GitHub 拉取/增量 + per-file 增量入库 + 构建
  UI；schema v3 构建阶段已在 lib 中，直接复用。
- **再下一步 R3（P1 跨章节推理）**：`find_detail_echoes` / `collect_suspect_evidence`
  + StoryInvestigationAgent + 结论校验，依赖本阶段覆盖层。
