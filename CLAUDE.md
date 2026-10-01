# ArkLores Developer Notes

当前主线：中文 GameData release asset + SQLite structured retrieval + FTS。
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

### 电脑端调查复现（不需真机）

改完 agent/检索层后，先在电脑上用真实 GameData DB + 真实 LLM 跑一轮完整调查，
确认无死循环/无失败，再真机验证。CLI 驱动器：

```bash
HOME=/tmp /home/hhikr/flutter/bin/dart run tools/run_investigation.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db \
  --query="导致特蕾西娅死亡的罪魁祸首是谁" \
  --out=build/investigation_run.json
```

API 配置从 gitignored `tools/api_info`（API_KEY=/MODEL=/URL=）读取，或用
`--api-key / --model / --url` 或环境变量 `ARKLORES_API_KEY/MODEL/URL` 覆盖。
**绝不提交有效 API key**——`tools/api_info` 只在本地存在，示例用占位 key，
真实 key 由开发者本机提供。输出写入 `build/investigation_run.json`，
可与 `logs/conversation_*.json` 对比行为。

注意：`run_investigation.dart` 只 import 纯 Dart 模块（`planner_loop`、
`react_event`、`entity_disambiguator`、`llm`），用 `sqflite_common_ffi` 直开
DB，不依赖 Flutter-bound 的 `GameDataKnowledgeStore`。若新增工具要进 CLI，
改用 FFI 实现或以纯 Dart 注入。
