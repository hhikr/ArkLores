# Contributing to ArkLores

感谢你考虑为 ArkLores 贡献代码。

## 开发流程

1. Fork 本仓库并 clone 到本地。
2. 从最新 `dev` 分支创建功能或修复分支。
3. 小步提交，每个 commit 只做一件事。
4. 提交 PR 到 `dev` 分支，等待 review。

详见 [GIT_GUIDE.md](docs/GIT_GUIDE.md)。

## 分支命名

```text
<type>/<scope>-<short-description>
```

常用 scope：`wiki` / `ai` / `materials` / `rag` / `agent` / `theme` / `settings` / `llm` / `db` / `gamedata`。

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

- 当前未发布开发版本为 v0.8.0，最新 release 为 v0.7.0；主知识源是中文 GameData
  release asset，当前兼容 schema version 为 2。
- 知识库 DB 由 `tools/build_gamedata_database.dart` 构建。
- App 端检索使用结构化 lookup、别名、LIKE 和 FTS。
- Wiki 与用户资料不得被表述为官方游戏原文。
- Book/用户资料链路当前暂停，恢复前需要重新设计来源标注和可信度策略。
- scoped story evidence 必须使用稳定 scope/entity ID；普通复合关键词无结果不能作为反证。
- 默认 Agent 检索只注册 `search_local_lore`；不得恢复 Wiki seed、Book indexing、embedding、
  vector 或 TFLite 主线，除非另行立项。
- 真实 Chat 测试必须显式 opt-in，凭据只放在 Git ignored 的 `tools/api_info`，不得写入
  test fixture、日志、文档或提交历史。

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
