# ArkLores Developer Notes

当前主线：中文 GameData release asset + SQLite structured retrieval + FTS/LIKE
+ 可选剧情向量召回（R12，只作定位线索，不作证据）。
当前版本与最新 release：v0.9.0；GameData schema：4（含确定性覆盖层）。

## Do

- 使用 `/home/hhikr/flutter/bin/flutter`。
- 保护 `logs/`。
- 保持 GameData 为 Agent 主知识源。
- 保留 source path、raw id、content type、entity id。
- 默认 Agent 只使用 `search_local_lore`；Wiki 和用户文本只能作为浏览/上下文。
- 运行相关 tests / analyze 后再汇报。

## Do Not

- 不恢复旧 Wiki seed 运行链路。
- 不恢复旧用户资料索引链路。
- 不提交 API key、token、`.env`。
- 不直接 push `main` 或 `dev`。

## 提交规范（贡献者只有 hhikr）

- 提交的 author / committer 只能是 hhikr。
- 提交信息中**禁止**出现 `Co-Authored-By` 或任何把 AI 写为作者/协作者的
  尾注或署名（如 "Generated with ..."）；未经开发者明确许可不得添加。
- 2026-10 已改写全部历史移除旧的 Claude 协作者尾注；不要再引入。
- 凭据（`tools/api_info`、`tools/*apiKey*`、`tools/github_pat`）不得提交、
  打印、写入 git 配置或 remote URL。

## 检索与数据设计原则（防桥段专项优化）

背景教训：`story_chapter_profiles.keyword_hits` 曾内置 20 个死亡/凶案词做
`content.contains` 命中统计，围绕"凶手问题"用例设计；该桥段在真实问题分布中
占比极小，专项优化覆盖面趋近于零，还会把模型锚定向单一方向（2026-08 已移除）。
任何 agent 改动检索/数据层前必须过以下检查：

1. **只做桥段无关的通用机制**：可达性（原文/行级可读）、确定性覆盖（出场枚举）、
   通用信号（IDF 稀有词、实体密度）、可对比的证据集。新特征对"任意剧情问题"
   仍应有意义；只对某一类桥段有意义的特征一律拒绝。
2. **先量化再立项**：新增检索特征前，评估该用例在真实问题分布中的占比；占比
   极小的用例只能作为验收样例（QA fixture），不得驱动 schema / 特征设计。
3. **禁止硬编码"场景词典"作为检索特征**：如"死亡/凶案词表"这类为具体剧情桥段
   定制的词表。模型推理需要场景知识时，交给 Agent 在通用检索结果上自行完成，
   不要在数据层预置方向。
4. **可复现且来源清晰**：每个检索特征必须解释得清它从哪些源字段、用什么确定性
   规则算出来；构建两次结果一致，便于增量对比。
5. **不制造隐性证据**：检索/画像字段只能是"浏览提示或定位线索"，绝不参与事实
   判定或推理打分；判定只能由 Agent 基于检索到的原文形成。

## 禁止针对验收样例编程（anti-fixture-hardcoding）

背景教训（R11，2026-08）：调查死循环修复曾以"导致特蕾西娅死亡的罪魁祸首是谁"
为真机验收样例。该样例必须只作为**测试 fixture 与人工验收场景**，绝不进入
产品逻辑。任何 agent 改动 agent/检索/数据层前必须自查：

1. **产品代码（`lib/`）不得出现具体实体名/实体 id/剧情桥段字面量作为判定分支
   或特征**：如"特蕾西娅→选魔王候选""凶手问题→xx"这类针对特定问题的特判。
   实体名只能出现在注释/示例文案/测试 fixture 中；判定必须消费运行时输入
   （当前 query、候选列表、状态），而非固定值。
2. **通用机制验证方法**：新逻辑若只对某个样例有效而对"任意剧情问题"无意义，
   一律拒绝（与上方第 1 条同理）。修改后可自测：把样例换成一个不相关实体
   （如"阿米娅的某件事是谁做的"）或虚构实体，逻辑路径应同样成立。
3. **测试 fixture 允许具体实体**（它们是模拟输入，不是产品逻辑），但不得把
   fixture 里的具体 id/名字复制进 `lib/` 的判定条件；测试断言只验证通用行为
   （如"选了候选而非无脑选第一个""重复搜索被终结"），不验证某个具体实体
   被特殊对待。
4. **自查命令**：改动后运行
   `grep -rn "特蕾西娅\|enemy_1554\|enemy_3006\|trap_762" lib/`，
   结果应只有注释/文案；任何出现在 `if`/`switch`/数据结构键/检索参数中的
   具体实体，都必须证明其通用性（如来自运行时候选列表）。

## Useful Commands

```bash
/home/hhikr/flutter/bin/flutter test test/agent_test.dart
/home/hhikr/flutter/bin/flutter test
/home/hhikr/flutter/bin/flutter analyze
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
HOME=/tmp /home/hhikr/flutter/bin/dart run tools/check_gamedata_retrieval.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

### 电脑端调查复现（不需真机，与 App 同一条链路）

改完 agent/检索层后，先在电脑上用真实 GameData DB + 真实 LLM 跑一轮，
再真机验证。复现工具是 opt-in 的 live 测试（R12 起取代旧的
`tools/run_investigation.dart`，后者重写了数据层、与 App 不一致，已删除）：

```bash
ARKLORES_RUN_LIVE_ASK=true \
ARKLORES_LIVE_QUERIES="导致特蕾西娅死亡的罪魁祸首是谁||另一个问题" \
flutter test test/live/ask_pipeline_live_test.dart
```

- 驱动的是 App 的 `askChatProvider`（`AskChatNotifier.sendMessage`，默认
  auto 模式 → `QuestionRouter` → 各 Agent → `GameDataKnowledgeStore` →
  `ChatSessionStore`）；只覆盖 `main.dart` 启动时注入的 provider（API 配置、
  向量配置、会话日志开关）和两个平台路径（DB、会话目录）。SQL 引擎换成
  sqflite FFI，其余每个 Dart 类都是 App 代码。
- 输出：`build/live_sessions/<...>/conversation_*.json`（与 App
  `chat_sessions/`、`logs/` 同格式）+ 每题 `*.summary.json` 指标。
- 可选：`ARKLORES_LIVE_MODE=investigate|summarize|verify`、
  `ARKLORES_LIVE_EVAL=test/fixtures/investigation_eval.json`（批量评测）、
  `ARKLORES_LIVE_IDS=a,b`、`ARKLORES_LIVE_NO_EMBEDDING=true`（模拟无向量 key）、
  `ARKLORES_GAMEDATA_DB`、`ARKLORES_LIVE_OUT`。
- 配置从 gitignored 的 `tools/api_info`（API_KEY=/MODEL=/URL=）和
  `tools/embedding-apiKey.csv`（`openAiCompatible`、`apiKey`）读取。
  **绝不提交有效 key**；`tools/*apiKey*` 已加入 .gitignore。

**真实 API 测试的成本约束**（开发者要求，2026-10）：
- 先跑离线测试（mock LLM 复现问题），离线确认之后才动用真实 API。
- 每个方面最多挑 2 个最有代表性的用例（用 `ARKLORES_LIVE_IDS` 过滤），逐题串行跑；
  每题跑完先看结果，有问题立即停止。复杂和边际情况等基础用例通过后再测。
- 不要整批跑 30 题评测，也不要并行开多组评测，除非开发者明确要求。
- 每题的 `*.summary.json` 会记录 `usage`（调用次数和 token 数），用它评估成本。
- 遇到 provider 错误（如 402 余额不足）时，harness 会自动跳过剩余题目。

### 剧情向量（可选表，R12）

`story_chunk_vectors` 是 schema 4 上的**可选附加表**（`schema_version` 不变，
没有该表的库照常可用，FIND 退化为关键词检索）。构建（可续跑、按内容哈希缓存）：

```bash
dart run tools/build_story_embeddings.dart --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

manifest 记录 `embedding_model / embedding_dims / embedding_chunking`；App 只在
所配置的向量模型和维度与 manifest 一致时才启用语义检索。向量命中只是定位线索，
必须 READ 原文后才能作为证据（检索原则 5）。
