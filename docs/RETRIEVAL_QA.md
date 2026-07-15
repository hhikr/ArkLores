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

- Story chunks 当前仍以 FTS / LIKE 为主，没有实体级剧情索引。
- `肉鸽`、`秘录`、`模组` 等归一化是规则表，不是完整同义词知识库。
- `莱茵生命`、`萨卡兹王庭` 等宽泛组织 query 当前可命中相关干员档案，但 GameData DB 尚未构建组织级汇总实体。
- `特蕾西娅` 等变体名现在有基础 alias 候选，但用户提问时是否需要展示候选仍取决于 Agent 调用 `search_local_lore` 的 disambiguation 分支。
- 真机端到端仍需要用 release asset 或临时 HTTP asset 验证下载、安装、检索、Summary Agent 全链路。

## v0.5 Fact-Check QA

固定命题集：

| 结论 | 命题 / 操作 | 验收重点 |
| --- | --- | --- |
| 支持 | `阿米娅是罗德岛的公开领袖。` | 至少一条实际 GameData record，引用 source path、raw id 和 content type。 |
| 反驳 | `阿米娅从未加入罗德岛。` | 检索支持与反证方向；反驳必须引用实际 GameData record。 |
| 存疑 | `特蕾西娅就是当前检索结果中的同一个实体。` | exact alias 多候选时不得猜测实体，只能存疑并要求消歧。 |
| 无法确认 | `罗德岛在 2030 年公开举办过庆典。` | 无结果时不得使用模型记忆，结论为无法确认。 |
| 上下文追问 | 先核查阿米娅命题，再问 `那她是什么时候承担这个身份的？` | 保留原主张与证据上下文，对新时间主张再次检索。 |

2026-07-15 自动验证：

- `test/agent_test.dart` 覆盖定向多次检索、唯一工具限制、支持/反驳证据门槛、无覆盖、
  实体歧义、unsupported verdict 降级和追问历史。
- `test/fact_check_widget_test.dart` 覆盖 320 logical px 宽度、2 倍文字缩放、结论状态和
  GameData evidence 展开，无 RenderFlex overflow。
- 上述固定命题尚未使用真实外部 Chat API 逐条执行；状态为 deferred，不记录为通过。
