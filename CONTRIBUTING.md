# Contributing to ArkLores

## 分支

- `main` 是已发布的稳定线，只通过 PR 合并（不直接 push）。
- 每个版本在一个功能分支上开发（如 `feature/v0.12-endfield`，合并后删除），完成后开 PR 合回 `main`。
- `release/v<版本>` 分支只放构建该版本 APK 的那一个提交（推送即触发 CI 构建签名），发版后删除（tag `v<版本>` 指向同一提交）。

## 提交

- 作者与提交者只能是仓库维护者本人；提交信息不得包含 `Co-Authored-By` 或任何 AI 署名尾注。
- 提交信息用一句英文写清楚“改变了什么”（行为层面），不写开发轮次编号。
- 不提交 API key、token、`.env`、keystore；凭据文件（`tools/api_info`、`tools/*apiKey*`、`tools/github_pat`、签名文件）已被 gitignore。

## 代码

- Riverpod 管状态；主题颜色、字体通过 theme 读取；用户可见字符串进中英文 ARB（`flutter gen-l10n`）。
- 新的推入页面用 `FloatingScaffold`；新的可点块用 `PressFeedback` + `withHaptic`。
- 测试目录与 `lib/` 一一对应（`test/README.md`）；测试知识库一律用生产 schema。
- 不写针对某类问题或剧情桥段的特判，不把验收样例的名字写进 `lib/`（见 CLAUDE.md）。
- 知识库只收与剧情有关的文字；归属与绑定只来自表里的 id（见 `docs/KNOWLEDGE_BASE_LESSONS.md`）。

## 提交前

```bash
flutter analyze
flutter test
git diff --check
```

改了建库、Agent 或界面时，按 `docs/RETRIEVAL_QA.md` 补做对应的验收。真实 API 测试会产生费用，默认跳过，按 CLAUDE.md 的成本约束运行。

## PR Checklist

- [ ] `flutter analyze` 无问题，`flutter test` 通过。
- [ ] 文档与实际实现、验证命令一致；不把自动测试写成真机验收。
- [ ] 改了知识库规则时说明已有的库怎么补算，并做了一致性检查。
- [ ] 没有 secrets、生成物（`build/`、`coverage/`）、`logs/` 进入提交。
