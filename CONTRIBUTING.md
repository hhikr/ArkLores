# Contributing to ArkLores

感谢你考虑为 ArkLores 贡献代码！

---

## 开发流程

1. Fork 本仓库并 clone 到本地
2. 从最新的 `dev` 分支创建功能/修复分支
3. 小步提交，每个 commit 只做一件事
4. 提交 PR 到 `dev` 分支，等待 review

详见 [GIT_GUIDE.md](docs/GIT_GUIDE.md)。

---

## 分支命名

```
<type>/<scope>-<short-description>
```

| type | 用途 |
|------|------|
| `feature` | 新功能 |
| `fix` | Bug 修复 |
| `chore` | 依赖/CI/构建配置 |
| `docs` | 文档 |
| `refactor` | 重构 |
| `perf` | 性能优化 |
| `test` | 测试 |

scope 可选：`wiki` / `ai` / `materials` / `rag` / `agent` / `theme` / `settings` / `llm` / `db` / `ci`

**示例**：`feature/wiki-bookmark-system`、`fix/agent-fact-check-topic-detection`

---

## Commit Message 规范

ArkLores 采用 **Conventional Commits 1.0.0**：

```
<type>(<scope>): <subject>

[body: 解释为什么，而非做了什么]

[footer: Closes #N]
```

- subject ≤ 72 字符，祈使语气，无句末句号
- 中文或英文均可，全文统一

**示例**：

```
feat(rag): add PDF text extraction via syncfusion_flutter_pdf
fix(wiki): prevent CSS injection from breaking PRTS table layout
chore(ci): add GitHub Actions workflow for APK build
```

---

## Code Style

- **状态管理**：使用 Riverpod，所有状态通过 `ref.watch()` 读取
- **主题**：所有颜色/字体/间距通过 `ref.watch(themeProvider)` 读取，不得硬编码
- **分析**：提交前确保 `flutter analyze` 零警告零错误
- **测试**：`flutter test` 全部通过
- **无调试残留**：提交前移除所有 `print()` 语句和调试代码

### RAG / Seed 数据

- 普通本地数据库、用户导入资料和调试输出不得提交。
- `assets/seeds/arklores_knowledge.db` 和 `assets/seeds/arklores_knowledge.db.gz` 不得提交。预构建 DB 作为 GitHub Release asset 发布。
- `assets/seeds/wiki_cache.zip` 和 `assets/seeds/seed_manifest.json` 是发布用 seed metadata/cache，只有在执行 v0.3+ seed 构建或发布收尾时才应更新。
- 修改 seed pipeline 后请至少校验：`chunks == chunk_embeddings`，且 `embedding_status` 全部为 `ok`。
- Wiki / Book 来源必须保留 `source_type`，Agent 和引用卡片不得把 Book 内容当作官方 Wiki 内容展示。

---

## PR 规范

1. PR 标题与 commit message 格式一致
2. 描述中说明变更内容、动机、测试方式
3. 所有 PR 需由 @hhikr review 后方可合并
4. 合并使用 **Squash and Merge**

---

## 代码审核检查清单

- [ ] 功能实现是否符合需求描述
- [ ] 边界情况是否处理（API 超时、空数据、网络断开）
- [ ] `flutter analyze` 无警告
- [ ] 无 `print()` 或调试代码残留
- [ ] UI 变更同时兼容 ArkTheme 和 EndfieldTheme
- [ ] 涉及 Agent/RAG 时，书籍来源内容是否正确标注

---

## 获取帮助

- 提交 [Issue](https://github.com/hhikr/ArkLores/issues)
- 阅读 [implementation_plan.md](docs/implementation_plan.md) 了解架构设计
