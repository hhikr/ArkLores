# Contributing to ArkLores

感谢你考虑为 ArkLores 贡献代码。

## 开发流程

1. Fork 本仓库并 clone 到本地。
2. 从最新 `dev` 分支创建功能或修复分支。
3. 小步提交，每个 commit 只做一件事。
4. 提交 PR 到 `dev` 分支，等待 review。

稳定发布分支为 `main`，集成分支为 `dev`；功能和修复从最新 `dev` 创建分支，
通过 PR 合回 `dev`，不要直接 push `main` 或 `dev`。

## 分支命名

```text
<type>/<scope>-<short-description>
```

常用 scope：`wiki` / `ai` / `materials` / `rag` / `agent` / `theme` / `settings` / `llm` / `db` / `gamedata`。

推荐前缀：`feature/`、`fix/`、`docs/`、`refactor/`。

## Commit Message

ArkLores 使用 Conventional Commits：

```text
<type>(<scope>): <subject>
```

示例：

```text
feat(gamedata): add structured lore database builder
fix(agent): handle empty final answer in react loop
```

## Code Style

- 状态管理使用 Riverpod。
- 主题颜色、字体、间距通过 theme provider 读取。
- 提交前运行相关测试和 analyze。
- 不提交 API key、token、`.env` 内容。
- 不在生产代码留下 `print()` 调试残留。

## Knowledge Base

- 当前版本与最新 release 为 v0.10.0。主知识源是中文 GameData
  release asset，当前兼容 schema version 为 4。
- 知识库 DB 由 `tools/build_gamedata_database.dart` 构建；可选剧情向量由
  `tools/build_story_embeddings.dart` 写入同一个库。
- App 端检索使用结构化 lookup、别名、LIKE、FTS、确定性覆盖层，以及可选的剧情向量召回
  （只作定位线索，命中后必须读原文）。架构见 `docs/AI_ARCHITECTURE.md`。
- Wiki 与用户资料不得被表述为官方游戏原文。
- Book/用户资料链路当前暂停，恢复前需要重新设计来源标注和可信度策略。
- scoped story evidence 必须使用稳定 scope/entity ID；普通复合关键词无结果不能作为反证。
- 不得恢复 Wiki seed、Book indexing 或 TFLite 主线；向量只用于 GameData 剧情原文的定位。
- 真实 API 测试必须显式 opt-in，凭据只放在 Git ignored 的 `tools/api_info`、
  `tools/embedding-apiKey.csv`，不得写入 test fixture、日志、文档或提交历史。
- 不写针对某类问题或剧情桥段的特判（见 CLAUDE.md）。

## 测试命令

```bash
flutter test
flutter analyze
```

Linux 上 flutter 在 `/home/hhikr/flutter/bin/`；Windows 上在 `C:\src\flutter\bin\`（已加入 PATH）。

真机同链路测试（会产生 API 费用）：

```bash
ARKLORES_RUN_LIVE_ASK=true ARKLORES_LIVE_EVAL=test/fixtures/investigation_eval.json ARKLORES_LIVE_IDS=frostnova_end flutter test test/live/ask_pipeline_live_test.dart
```

PowerShell 写法：先 `$env:ARKLORES_RUN_LIVE_ASK='true'` 等逐个设置环境变量，再运行
`flutter test test/live/ask_pipeline_live_test.dart`。

成本规则：先用 mock 离线复现；每个方面最多 2 个代表性用例，逐题串行，看完结果再跑下一题；
不整批跑评测。

## 提交署名

- 作者与提交者只能是仓库维护者本人；提交信息不得包含 `Co-Authored-By` 或 AI 署名尾注。

## PR Checklist

- [ ] 功能符合当前 GameData-first 架构。
- [ ] 边界情况可理解地提示用户。
- [ ] `flutter test` 或相关单测通过。
- [ ] `flutter analyze` 无新增问题。
- [ ] 涉及 Agent/RAG 时，来源可信度标注正确。
- [ ] 涉及剧情检索时，运行 finalized 完整 DB retrieval QA；不能用 smoke DB 代替。
- [ ] 用户可见字符串进入中英文 ARB，并运行 `flutter gen-l10n`。
- [ ] 文档同步实际实现、验证命令和 deferred 项，不把自动测试写成真机验收。
- [ ] 新增外部模型 QA 时保留 deterministic test，默认测试不得产生网络费用。
- [ ] 最后运行 `git diff --check`，检查 staged diff、secrets、生成物和 `logs/` 状态。
