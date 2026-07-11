# ArkLores · Git 管理手册

> 本手册适用于 ArkLores 项目的所有开发者（包括维护者 @hhikr 及外部贡献者）。
> 目标：保持提交历史清晰可读，让任何人都能快速理解每一次变更的意图。

---

## 一、分支策略

ArkLores 使用简化的 **GitFlow** 模型，仅保留必要的层级。

```
main          ──●────────────────────────────●──────────── (仅稳定发布版本)
                 ↑ merge                      ↑ merge
dev           ──●──●──●──●──●──●──●──●──●──●──●────────── (日常开发集成)
                    ↑          ↑
feature/xxx   ──────●──●──●────┘
fix/xxx       ──────────────●──┘
```

### 分支说明

| 分支名 | 说明 | 创建自 | 合并到 | 谁能推送 |
|--------|------|--------|--------|---------|
| `main` | 稳定的发布版本，每个 tag 对应一次发布 | — | — | 仅 @hhikr |
| `dev` | 日常开发集成分支，始终保持可运行 | — | `main` | 仅 @hhikr（PR 合并） |
| `feature/<name>` | 新功能开发 | `dev` | `dev` | 贡献者 via PR |
| `fix/<name>` | Bug 修复 | `dev` | `dev` | 贡献者 via PR |
| `chore/<name>` | 维护性工作（依赖更新、CI、文档） | `dev` | `dev` | 贡献者 via PR |
| `release/v<X.Y>` | 发布准备（版本号更新、changelog） | `dev` | `main` + `dev` | 仅 @hhikr |

### 规则

- **任何人都不得直接 push 到 `main` 或 `dev`**（包括 @hhikr，通过 PR 合并到 `dev`，发布时 @hhikr 直接操作 `release/` 分支）
- `main` 上的每一个 commit 必须对应一个 version tag
- `dev` 分支在每个迭代版本（v0.1、v0.2…）完成后合入 `main`

---

## 二、分支命名规范

格式：`<type>/<scope>-<short-description>`

- `type`：见下表
- `scope`（可选）：功能模块缩写，见下表
- `short-description`：2~4 个英文单词，用连字符连接，全小写

### type 列表

| type | 用途 |
|------|------|
| `feature` | 新功能 |
| `fix` | Bug 修复 |
| `chore` | 依赖升级、CI/CD、构建配置 |
| `docs` | 文档更新 |
| `refactor` | 重构（不涉及功能变更） |
| `perf` | 性能优化 |
| `test` | 测试相关 |

### scope 缩写（可选）

| scope | 对应模块 |
|-------|---------|
| `wiki` | Wiki 浏览模块 |
| `ai` | AI 对话模块 |
| `materials` | 资料 Tab |
| `rag` | 知识库 / RAG 引擎 |
| `agent` | Agent 逻辑 |
| `theme` | 主题系统 |
| `settings` | 设置页 |
| `llm` | LLM 客户端层 |
| `db` | 数据库 / sqlite-vec |
| `ci` | CI/CD 相关 |

### 命名示例

```
feature/wiki-bookmark-system
feature/rag-book-import-pipeline
fix/agent-fact-check-topic-detection
fix/wiki-dark-mode-layout-break
chore/upgrade-flutter-inappwebview
refactor/llm-client-interface
docs/update-contributing-guide
```

---

## 三、Commit Message 规范

ArkLores 采用 **Conventional Commits 1.0.0** 规范。

### 格式

```
<type>(<scope>): <subject>

[body]

[footer]
```

### 各部分说明

#### `<type>` — 必填，小写

| type | 含义 | 是否触发版本号变更 |
|------|------|-----------------|
| `feat` | 新功能 | minor |
| `fix` | Bug 修复 | patch |
| `chore` | 构建/依赖/CI，不影响用户功能 | 无 |
| `docs` | 仅文档变更 | 无 |
| `refactor` | 重构，无功能变化 | 无 |
| `perf` | 性能优化 | patch |
| `test` | 测试用例 | 无 |
| `style` | 代码格式（空格、缩进等，不影响逻辑） | 无 |
| `revert` | 回滚某个 commit | 视情况 |

#### `(<scope>)` — 可选，小写，括号内

对应上方 scope 缩写表，或自由填写更精确的模块名。

#### `<subject>` — 必填

- **中文或英文均可**，保持全文统一
- 不超过 72 个字符
- 首字母不大写（英文时），句末不加句号
- 使用祈使语气：`add` / `fix` / `remove`，而非 `added` / `fixed`

#### `[body]` — 可选

- 与 subject 之间空一行
- 解释**为什么**做这个改动，而不是**做了什么**（代码本身说明做了什么）
- 每行不超过 72 字符

#### `[footer]` — 可选

- 关联 issue：`Closes #12` / `Refs #8`
- Breaking change：`BREAKING CHANGE: <description>`

### 示例

```
feat(rag): add PDF text extraction via syncfusion_flutter_pdf

支持用户从资料 Tab 导入 PDF 文件并自动提取纯文本进行 embedding。
仅存储提取后的文本块，不保留原始 PDF 内容。

Closes #23
```

```
fix(wiki): prevent CSS injection from breaking PRTS table layout

之前注入的深色模式 CSS 会覆盖 PRTS Wiki 的表格 border 样式，
导致部分技能表格列宽错乱。通过提升 CSS specificity 修复。

Refs #19
```

```
chore(ci): add GitHub Actions workflow for APK build

在每次 push 到 dev 分支时自动构建 debug APK 并上传到 Artifacts。
```

```
feat(agent)!: change search_wiki tool return format

BREAKING CHANGE: search_wiki 现在返回带 source_type 字段的对象数组，
而非纯字符串数组。所有调用 search_wiki 的 Agent 均需更新解析逻辑。
```

### 不好的示例（避免）

```
# ❌ 含糊不清
fix: bug fix

# ❌ 过于具体但没有上下文
feat: add button

# ❌ 全是"做了什么"，没有"为什么"
refactor: move files around and rename some functions

# ❌ 过长 subject
feat(rag): implement complete PDF text extraction pipeline using syncfusion_flutter_pdf with chunking and embedding support
```

---

## 四、版本号与 Tag 规范

ArkLores 使用 **语义化版本（SemVer）**：`vMAJOR.MINOR.PATCH`

| 变更类型 | 版本位 | 示例 |
|---------|--------|------|
| 重大功能里程碑（迭代计划中的每个版本） | MINOR | `v0.1.0` → `v0.2.0` |
| Bug 修复或小改进 | PATCH | `v0.2.0` → `v0.2.1` |
| 架构性重大变更（破坏性改动） | MAJOR | `v0.x` → `v1.0.0` |

### Tag 操作

```bash
# 创建带注释的 tag（包含 changelog 摘要）
git tag -a v0.2.0 -m "v0.2.0 - Wiki 浏览器

新增：
- 双站 WebView（PRTS Wiki + 终末地 Wiki）
- 书签系统
- Wiki 夜间模式注入

修复：
- PRTS Wiki 表格样式注入冲突"

# 推送 tag
git push origin v0.2.0
```

---

## 五、外部贡献者工作流

### 5.1 提交 PR 前的准备

```bash
# 1. Fork 仓库到自己账号
# 2. Clone 自己的 fork
git clone https://github.com/<your-username>/ArkLores.git
cd ArkLores

# 3. 添加上游仓库
git remote add upstream https://github.com/hhikr/ArkLores.git

# 4. 从最新的 dev 分支创建功能分支
git fetch upstream
git checkout -b feature/your-feature-name upstream/dev
```

### 5.2 开发过程中保持同步

```bash
# 定期同步上游 dev 分支，避免大量冲突
git fetch upstream
git rebase upstream/dev
```

> **使用 rebase 而非 merge**：保持线性历史，便于 review。

### 5.3 提交代码

```bash
# 小步提交，每个 commit 只做一件事
git add <files>
git commit -m "feat(wiki): add bookmark swipe-to-delete gesture"

# push 到自己的 fork
git push origin feature/your-feature-name
```

### 5.4 发起 Pull Request

PR 标题格式与 commit message 一致：
```
feat(wiki): add bookmark swipe-to-delete gesture
```

**PR 描述模板**（`.github/pull_request_template.md` 中维护）：

```markdown
## 变更内容
<!-- 简短描述这个 PR 做了什么 -->

## 动机
<!-- 为什么要做这个改动？解决了什么问题？ -->

## 测试方式
<!-- 如何验证这个改动是正确的？ -->
- [ ] 在 Android 模拟器上测试通过
- [ ] 在 iOS 模拟器上测试通过（如有条件）
- [ ] 相关单元测试已添加/更新

## 关联 Issue
Closes #<issue-number>

## 截图（如有 UI 变更）
```

### 5.5 PR 审核规则

- 所有 PR 必须由 @hhikr review 后方可合并
- PR 合并使用 **Squash and Merge**（将所有 commit 压缩为一个，保持 dev 历史整洁）
- 压缩后的 commit message 由 @hhikr 按规范整理
- PR 合并后，贡献者的原分支应删除（GitHub 自动删除选项开启）

---

## 六、代码审核检查清单

@hhikr 在 review PR 时参考以下清单：

### 功能正确性
- [ ] 功能实现是否符合 issue/需求描述
- [ ] 边界情况是否处理（API 超时、空数据、网络断开）
- [ ] 是否有明显的逻辑错误

### 代码质量
- [ ] 是否遵循 Dart/Flutter 代码风格（`flutter analyze` 无警告）
- [ ] 是否有无用的 `print` 语句或调试代码残留
- [ ] 新增的公共方法/类是否有注释

### 主题兼容性
- [ ] UI 变更是否同时兼容 ArkTheme 和 EndfieldTheme
- [ ] 是否使用了 `ref.watch(themeProvider)` 而非硬编码颜色

### AI 相关（如涉及 Agent/RAG）
- [ ] 来自书籍资料（`source_type = 'book'`）的内容是否正确标注
- [ ] System Prompt 是否包含可信度策略插入

### 性能
- [ ] 是否有明显的不必要重建（Flutter Widget rebuild）
- [ ] 大量数据操作是否在 isolate 中执行，避免阻塞主线程

---

## 七、常用 Git 操作速查

```bash
# 查看当前分支状态
git status

# 暂存所有修改（包括新文件）
git add .

# 修改最后一次 commit（还未 push）
git commit --amend

# 交互式 rebase，整理最近 3 个 commit
git rebase -i HEAD~3

# 放弃本地所有未提交修改
git restore .

# 从远端 dev 创建本地分支
git checkout -b feature/xxx origin/dev

# 查看两个分支的差异文件列表
git diff --name-only dev feature/xxx

# 查看简洁的提交历史
git log --oneline --graph --all
```

---

## 八、.gitignore 重要条目

以下内容**不得**提交到仓库：

```
# Flutter 构建产物
build/
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies

# 用户本地数据（知识库向量数据库等）
*.db
*.sqlite
*.sqlite-vec

# 敏感信息
.env
*.key
api_keys.dart         # 任何包含 API Key 的文件

# IDE
.idea/
.vscode/settings.json  # 个人设置（launch.json 可以提交）
```

> [!CAUTION]
> **严禁将任何 API Key、Bearer Token、Secret 提交到仓库。**
> 即使已删除，历史记录仍可被检索。如果不慎提交，立即使用 `git filter-branch` 或 BFG Repo Cleaner 清理，并立即吊销相关 Key。

---

*本手册随项目演进持续更新。如有建议，请提 issue 或 PR。*
