# GameData Retrieval QA

当前主线使用中文 GameData release DB 作为唯一默认知识源。检索路线是结构化 RAG：

1. 实体 / 别名结构化查询。
2. `entity_documents` 汇总文档。
3. `entity_documents_fts` 全文检索。
4. `normalized_records` / `lore_chunks` 结构化与 LIKE fallback。
5. `lore_chunks_fts` 全文检索。

当前主线不使用向量、embedding、TFLite、旧 Wiki seed 或用户 Book 索引。

## Smoke Queries

每次重建或替换 GameData DB 后，至少人工检查以下 query。结果不要求完全一致，但必须能解释命中层级、source path、content type 和无结果原因。

| Query | 目的 | 预期 |
| --- | --- | --- |
| `阿米娅` | 实体基础召回 | 优先命中 `entity_document` 或结构化实体记录，包含 GameData source path。 |
| `阿米娅 语音` | 实体 + 内容类型归一化 | 归一化到 `operator_voice`，不应因为 `语音` 作为普通关键词导致无结果。 |
| `阿米娅 主线` | 剧情意图召回 | 可从 story chunks 取到相关剧情上下文；无精确剧情时必须说明未检索到。 |
| `莱茵生命` | 组织 / 阵营召回 | 命中实体、结构化文本或 FTS 结果。 |
| `萨卡兹王庭` | 世界观术语召回 | 命中结构化文本或 FTS 结果。 |
| `特蕾西娅` | 角色召回 | 命中角色相关 GameData 记录。 |
| `源石技艺` | 术语召回 | 命中物品、档案、剧情或 FTS 文本。 |
| `肉鸽` | 俗称归一化 | 扩展为 `集成战略`，可召回集成战略相关内容。 |
| `集成战略 收藏品` | 肉鸽内容召回 | 可命中收藏品 / 主题 / 描述类内容。 |
| `敌人介绍` | 类型描述召回 | 可命中 enemy profile / enemy handbook 相关内容。 |
| `干员秘录` | 内容类型归一化 | 扩展为 operator record / story review 相关检索词。 |

## Failure Rules

- 无库：提示用户安装中文 GameData 知识库。
- 无结果：明确说结构化 / FTS 未检索到，不允许用模型记忆补设定。
- 低覆盖：回答必须说明“当前知识库只检索到以下片段”。
- source claim：只有 observation 中出现对应来源时，Agent 才能声称使用了该来源。
- Book / Wiki：v0.4.5 默认不参与检索，不得把 Book 或 Wiki 说成当前 evidence。

## Current Unit Coverage

`test/agent_test.dart` 覆盖：

- GameData entity document 优先级。
- `content_type` 过滤。
- alias 结构化解析。
- entity document FTS。
- observation 长度边界。
- exact alias 歧义候选。
- Summary mode 检索计划与 story context。
- `阿米娅 主线` story intent 检索。
- `阿米娅 语音` query 归一化。
- ReAct loose Action Input 解析。
- ReAct truncated / empty final answer 错误处理。
- fallback source guard。
- GameData installer schema 校验与坏库不覆盖旧库。

## v0.4.5 Verification Record

Last verified on 2026-07-15:

- Passed: `/home/hhikr/flutter/bin/flutter test test/agent_test.dart`
- Passed: `/home/hhikr/flutter/bin/flutter analyze`
- Passed: fixed full-DB retrieval QA:

```bash
HOME=/tmp /home/hhikr/flutter/bin/dart run tools/check_gamedata_retrieval.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

- Passed: fixed retrieval queries:
  - `阿米娅` -> `operator_profile_bundle`
  - `阿米娅 语音` -> `operator_voice`
  - `阿米娅 主线`
  - `莱茵生命`
  - `萨卡兹王庭`
  - `特蕾西娅`
  - `源石技艺`
  - `肉鸽`
  - `集成战略 收藏品`
  - `敌人介绍` -> `enemy_profile`
  - `干员秘录` -> `operator_record_story`
- Passed: alias candidate count checks:
  - `特蕾西娅` -> 3 candidates
- Passed: GameData schema smoke build:

```bash
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart \
  --arknights-source=/tmp/ArkLores-ArknightsGameData \
  --output=/tmp/arklores_gamedata_schema_smoke \
  --story-limit=1 \
  --force
```

Smoke build counts:

- entities: 17680
- entity documents: 833
- story lines: 1
- lore chunks: 82930

Additional smoke check:

- `特蕾西娅` alias candidates exist in the rebuilt full DB for:
  - `enemy:enemy_1554_lrtsia`
  - `enemy:enemy_3006_tersia`
  - `trap_762_skztxy`

## Known Limits

跨 v0.6-v0.9 仍持续有效的 deferred 验收统一维护在此：

- Android 真机上的 Role-play 存档恢复、长对话、取消、双语与 TalkBack。
- Wiki WebView 原生选区、底部托盘、返回浏览、软键盘及系统选区行为。
- Summary/Fact-check Wiki context 的真实外部 Chat 与完整 DB 检索矩阵。
- 证据卡在横屏、极端文字缩放和 TalkBack 下的朗读/操作顺序。
- 多角色任务参与检索矩阵、低覆盖量化和 `source_path` 到原始文件的可信导航。
- 正式商店签名；既有 GitHub APK 使用 Android Debug certificate。
- v0.9 双主题/双语自动截图回读与代表性 Android 真机截图。

- Story chunks 当前仍以 FTS / LIKE 为主，没有实体级剧情索引。
- `肉鸽`、`秘录`、`模组` 等归一化是规则表，不是完整同义词知识库。
- `莱茵生命`、`萨卡兹王庭` 等宽泛组织 query 当前可命中相关干员档案，但 GameData DB 尚未构建组织级汇总实体。
- `特蕾西娅` 等变体名现在有基础 alias 候选，但用户提问时是否需要展示候选仍取决于 Agent 调用 `search_local_lore` 的 disambiguation 分支。
- 真机端到端仍需要用 release asset 或临时 HTTP asset 验证下载、安装、检索、Summary Agent 全链路。

## v0.6 Role-play QA

角色扮演继续只注册 `search_local_lore`。角色选择先通过 `entities/entity_aliases` 解析为
canonical name 和稳定 `entity_id`；角色绑定工具会覆盖模型传入的 entity id，并默认使用
`roleplay` 检索计划。该计划复用实体文档、档案记录和 canonical 角色名剧情回查，使未直接
写入 `entity_id` 的任务剧情仍可作为候选记忆；每轮至少完成一次检索，未覆盖经历不得用模型
记忆补齐。

2026-07-15 收尾验证：

- Passed: `test/agent_test.dart` 的 41 项测试，其中 Role-play 覆盖唯一角色解析、alias
  重名消歧、稳定 entity id 注入、首轮档案/语音/秘录/模组/任务记忆约束，以及会话文件的
  空状态、保存、读取、损坏和删除。
- Passed: Role-play 复用 ReAct 的空回答、截断、minimum tool-call 和 unsupported source
  claim 回归测试。
- Passed: `test/fact_check_widget_test.dart` 的 2 项测试，覆盖 320 logical px 窄屏、
  fact-check evidence 展开，以及 roleplay setup/conversation state 渲染，无 Flutter
  test exception。
- Passed: `ARKLORES_RUN_LIVE_CHAT=true test/live_fact_check_test.dart` 的 3 项真实 Chat
  QA；测试环境下 `AgentLogger` 回退到系统临时目录。
- Passed: finalized 完整 DB retrieval QA；固定 query、`特蕾西娅` alias candidates 和
  `activities/act21mini/level_act21mini_st07.txt:3` scoped evidence 均通过。
- Passed: schema smoke build：17680 entities、833 entity documents、1 story line、
  82930 lore chunks。
- Passed: `flutter analyze` 为 No issues found。
- Not verified: roleplay 真实截图/真机渲染、Android 本地存档恢复、双语、TalkBack、取消和
  长对话性能。
- Not covered: finalized 完整 DB 上的更广多角色任务参与检索矩阵和低覆盖量化。

## v0.7 Wiki Context Handoff QA

Wiki 阅读上下文转交不新增检索来源，不写入 GameData DB，也不恢复 Wiki seed RAG、
embedding、vector indexing 或 Book indexing。转交内容只作为用户上下文进入 Summary /
Fact-check；事实声明仍必须由既有 `search_local_lore` 和中文 GameData 结构化 DB 独立核验。

2026-07-15 自动验证：

- Passed: `test/agent_test.dart` 的 43 项测试，其中新增覆盖 Wiki context 有选区和空选区两种
  prompt 格式，确认文本被标记为 `not GameData evidence`，并要求使用 `search_local_lore`
  独立核验。
- Passed: `test/fact_check_widget_test.dart` 的 3 项测试，其中新增覆盖 AI 页面接收
  `WikiAiContext` 后进入 Summary tab，并把 Wiki 页面标题、URL 和选中文字作为用户上下文渲染。
- Passed: `/home/hhikr/flutter/bin/flutter analyze` 为 No issues found。
- Passed: finalized 完整 DB retrieval QA；固定 query、`特蕾西娅` alias candidates 和
  `activities/act21mini/level_act21mini_st07.txt:3` scoped evidence 均通过。
- Passed: v0.7.0 release-mode APK build、setup release GameData URL/SHA dry-run 和
  `apksigner` v1/v2 verification。

Not verified:

- Android 真机 WebView 的真实选区读取、系统选择菜单、底部面板操作和返回浏览页面。
- Fact-check Wiki context 的真实外部 Chat QA；尚未验证模型在真实 provider 下是否稳定从
  Wiki 选中文字解析主张并调用 `search_local_lore`。
- finalized 完整 DB 上的 Summary / Fact-check Wiki context 检索矩阵、实体歧义和无覆盖
  量化。
- Wiki 转交底部面板在双语、文字缩放、TalkBack 和常见手机尺寸下的截图或真机验收。

## v0.8 Evidence UX QA

v0.8 不改变 GameData schema、检索排序或 Agent 来源协议。UI 只解析
`search_local_lore` 已有 observation 字段；非 GameData、缺少必要 provenance 字段或格式不完整
的 result block 不会显示为 GameData 证据卡。

2026-07-15 自动验证：

- Passed: `test/evidence_observation_test.dart`，覆盖多 result block、含冒号原文、direct
  candidate、非 GameData 和不完整字段拒绝。
- Passed: `test/fact_check_widget_test.dart` 的 4 项测试；结构化证据卡在 320 logical px、
  2x 文字缩放下展示来源路径、ranking reason 和中性覆盖度，Summary 覆盖取消与重试状态。
- Passed: `test/agent_test.dart`，既有 GameData-only Agent、无库、无结果、歧义、截断和
  unsupported source claim 回归保持通过。
- Passed: `flutter analyze` 为 No issues found。
- Passed: 完整 `flutter test`：58 passed；3 个需 `ARKLORES_RUN_LIVE_CHAT=true` 的外部
  Chat QA 按默认离线策略 skipped。
- Passed: 文档全量审计后按修正的 pipeline 命令重跑 finalized 完整 DB QA；11 个固定 query、
  3 个 `特蕾西娅` alias candidates 和固定 scoped evidence 通过。
- Passed: v0.8.0 release-mode APK build、release GameData URL/SHA dry-run、versionName/versionCode
  检查及 `apksigner` v1/v2 verification。

Not verified:

- Android 真机的 Summary / Fact-check 长回答滚动、横屏、TalkBack 顺序和极端文字缩放。
- `source_path` 到原始 GameData 文件的应用内导航；当前字段用于 provenance 检查，release asset
  不包含可直接打开的源文件。
- 真实外部 Chat 的 v0.8 专项矩阵；本迭代未改变 prompt、ReAct 或 retrieval 行为。

## v0.5 Fact-Check QA

### Scoped Evidence 维护约束

真实 Chat QA 暴露的问题及当前通用处理如下：

| 问题表现 | 根因 | 当前处理 | 回归覆盖 |
| --- | --- | --- | --- |
| 模型解析出活动和角色，却没有进入 scoped evidence | prompt 约束不能保证 provider 严格编排 | 范围和实体必须分别解析；evidence mode 缺少 `scope_id/entity_id` 时工具返回可重试错误；最终回答前至少完成一次工具调用 | `agent_test.dart` 的 evidence 参数和 minimum tool-call tests |
| 用“范围名 + 实体名”检索无结果后错误断言角色未登场 | 普通复合 query 无结果被当成反证 | prompt 明确禁止该推断；evidence 无候选时要求保留稳定 ID，只用一个关系、状态或动作词重试 | invalid/empty scoped evidence test；live 目标命题 |
| 短关系词命中很多剧情片段，直接原文被弱相关片段挤出 | 候选原先按 `story_id/raw_id` 排序 | scope/entity/关系词取交集后，按实体名和关系词在 chunk 内的最短距离排序，再应用 `top_k` | synthetic distant-candidate test；finalized DB 固定 QA |
| provider 输出 `。Action:` 或附加 `Action Query/Tool` 时工具名解析失败 | ReAct key parser 只接受空白边界或吸收后续 metadata | key 支持常见中英文句末标点；Action 只取首行 | punctuated action 和 action metadata tests |
| 模型未检索就直接回答 | ReAct 默认接受首轮 Final Answer | ReAct 提供 `minimumToolCalls`；Fact-check 设置为 1，其他 Agent 默认 0 | early-final deterministic test；live QA |
| reasoning provider 在证据返回后截断 | 2048 tokens 同时承载隐藏 reasoning 和可见 ReAct 输出 | Fact-check 单步上限设为 4096，迭代上限设为 7；截断仍作为错误而非不完整答案返回 | truncated response unit test；live QA |
| provider 400 只显示状态码 | 标准错误正文未被解析 | Chat client 仅提取标准 `error.message`，不记录 key、请求正文或完整错误响应 | analyze/unit suite；不得把凭据写入 fixture |

Live test 默认跳过，避免普通 `flutter test` 产生外部费用或引入模型波动。只有设置
`ARKLORES_RUN_LIVE_CHAT=true` 才执行；`tools/api_info` 必须保持 Git ignored，格式为
`API_KEY/MODEL/URL` 三个键。该测试复用生产 Agent、检索和 verdict 链路，但显式指定
finalized DB，并临时解除 `flutter_test` 的网络拦截。它不是 Settings/UI/原生日志目录的
真机 integration test。

固定命题集：

| 结论 | 命题 / 操作 | 验收重点 |
| --- | --- | --- |
| 支持 | `阿米娅是罗德岛的公开领袖。` | 至少一条实际 GameData record，引用 source path、raw id 和 content type。 |
| 反驳 | `阿米娅从未加入罗德岛。` | 检索支持与反证方向；反驳必须引用实际 GameData record。 |
| 存疑 | `特蕾西娅就是当前检索结果中的同一个实体。` | exact alias 多候选时不得猜测实体，只能存疑并要求消歧。 |
| 无法确认 | `罗德岛在 2030 年公开举办过庆典。` | 无结果时不得使用模型记忆，结论为无法确认。 |
| 上下文追问 | 先核查阿米娅命题，再问 `那她是什么时候承担这个身份的？` | 保留原主张与证据上下文，对新时间主张再次检索。 |
| 剧情范围 + 实体 + 状态 | `丛林症结故事集中，米格鲁死掉了吗` | scoped evidence 命中 `level_act21mini_st07.txt:3`，并区分身体死亡与意识保留。 |

2026-07-15 自动验证：

- `test/agent_test.dart` 覆盖定向多次检索、唯一工具限制、支持/反驳证据门槛、无覆盖、
  实体歧义、unsupported verdict 降级、追问历史，以及降级后有效结论的 debug 日志。
- `test/fact_check_widget_test.dart` 覆盖 320 logical px 宽度、2 倍文字缩放、结论状态和
  GameData evidence 展开，无 RenderFlex overflow。
- `test/live_fact_check_test.dart` 使用 `tools/api_info` 中的真实 API 配置完成最小 chat
  completion、scoped story evidence 和未来命题的 live QA；`AgentLogger` 在测试环境下已降级到
  系统临时目录。
- 真实 Chat QA 可通过 `ARKLORES_RUN_LIVE_CHAT=true flutter test
  test/live_fact_check_test.dart` 显式运行。API 配置仅从已忽略的
  `tools/api_info` 读取，测试使用生产 `OpenAICompatibleClient -> FactCheckAgent ->
  ReActLoop -> search_local_lore -> GameDataKnowledgeStore` 链路和 finalized 完整 DB。
- Passed: schema v2 finalized 完整 DB scoped retrieval：`act21mini + 米格鲁 + 死亡` 命中
  `activities/act21mini/level_act21mini_st07.txt:3`。
- Passed: 2026-07-15 使用 `deepseek-v4-flash` 的真实 Chat QA；目标问题返回
  `supported`，引用 `level_act21mini_st07.txt:3`，并区分身体死亡与意识保留。
- Passed: 同一 live suite 的无覆盖未来命题没有返回 supported/refuted；当前模型结果为
  `uncertain`。其宽查询曾将数字 `2030` 误命中 enemy ID，后续定向查询均无结果。
- Not covered: `flutter_test` 没有原生 `path_provider` 真机插件实现，live QA 只能回退到系统临时目录；
  Settings/provider 状态和 Android 真机路径、TalkBack 仍需真机 integration 验收。
