# ArkLores · AI Agent Prompt 合集

> 本文件供委托 AI agent 开发 ArkLores 时使用。
> 每个 Prompt 是一个独立的任务委托模板，按需选用。

---

## 目录

1. [Prompt 0 — 项目上下文速读](#prompt-0)
2. [Prompt 1 — 开始某个迭代版本](#prompt-1)
3. [Prompt 2 — 验证某个迭代版本](#prompt-2)
4. [Prompt 3 — 专项 Bug 修复](#prompt-3)
5. [Prompt 4 — 保持 Git 合规提交](#prompt-4)
6. [Prompt 5 — v0.4 架构转向接手](#prompt-5)
7. [附录：如何撰写针对本项目的 Prompt](#appendix)

---

<a name="prompt-0"></a>
## Prompt 0 — 项目上下文速读

**用途**：在开始任何任务前，让 agent 了解项目全貌。可附在其他 Prompt 之前。

---

```
你是 ArkLores 项目的 Flutter 开发 agent。在开始任何工作之前，请先阅读以下文档并完整理解项目：

1. 架构设计文档：/home/hhikr/ArkLores/docs/implementation_plan.md
   - 重点阅读：项目概览表格、2026-07 架构转向决策、整体架构图、功能模块详细设计（各节）、知识库 RAG 引擎、AI 资料可信度策略、双主题系统设计、项目目录结构、迭代计划

2. GameData 知识库计划：/home/hhikr/ArkLores/docs/GAMEDATA_KNOWLEDGE_PLAN.md
   - 重点阅读：中文-only 决策、release asset 分发、GameData > Wiki > Book 可信度优先级、schema 草案、Agent 工具映射
    
3. Git 管理手册：/home/hhikr/ArkLores/docs/GIT_GUIDE.md
   - 重点阅读：分支策略、分支命名规范、Commit Message 规范

阅读完毕后，请：
- 用 3 句话总结你对项目的理解
- 列出你认为在本次任务中最需要注意的架构约束（不超过 5 条）
- 确认你理解 Git 分支和 commit 规范后再继续
- 确认你理解：后续主知识源是中文 GameData release asset，Wiki 仅为受限补充搜索，不得把 `search_wiki` 当作 Agent 主知识源

不要开始写代码，等待我确认你的理解后再行动。
```

---

<a name="prompt-1"></a>
## Prompt 1 — 开始某个迭代版本

**用途**：委托 agent 实现 implementation_plan.md 中某个具体迭代版本（如 v0.1、v0.2 等）的全部交付内容。

**使用方法**：将 `[VERSION]` 替换为目标版本号（如 `v0.1`）。

---

```
你是 ArkLores 项目的 Flutter 开发 agent。

【第一步：读取文档】
请先完整阅读以下文档：
- /home/hhikr/ArkLores/docs/implementation_plan.md
- /home/hhikr/ArkLores/docs/GAMEDATA_KNOWLEDGE_PLAN.md（如任务涉及 RAG / Agent / 知识库）
- /home/hhikr/ArkLores/docs/GIT_GUIDE.md

【第二步：理解当前代码库状态】
检查 /home/hhikr/ArkLores/ 目录结构，了解已有代码。
如果 lib/ 目录不存在，说明从零开始。

【第三步：制定任务分解计划】
根据 implementation_plan.md 中 [VERSION] 章节的「交付内容」表格，将每一行分解为一个独立的开发子任务。
以列表形式给我看你的任务分解（放在 /home/hhikr/ArkLores/docs/ 目录下），等待我确认后再开始编码。

【第四步：执行（经我确认后）】
按以下原则开发：

代码规范：
- 语言：Dart / Flutter
- 状态管理：Riverpod（flutter_riverpod）
- 所有 UI 颜色/字体/间距必须从 themeProvider 读取 Token，禁止硬编码
- 每个功能文件放在 implementation_plan.md「项目目录结构」章节对应的路径下

Git 规范（每完成一个独立子任务就提交一次，不要攒到最后一次性提交）：
- 从 dev 分支创建工作分支，命名格式见 GIT_GUIDE.md 第二节
- 每个 commit 遵循 GIT_GUIDE.md 第三节的 Conventional Commits 格式
- commit 粒度：一个 commit = 一件清晰的事情

完成后：
- 告诉我所有创建的文件列表
- 列出你认为需要人工验证的地方
- 如果发现文档中存在模糊或矛盾之处，列出来告诉我，不要自行猜测
- 一切结束后，在 /home/hhikr/ArkLores/docs/ 文件夹下添加这一次工作的总结文档。

当前目标版本：[VERSION]
```

---

<a name="prompt-2"></a>
## Prompt 2 — 验证某个迭代版本

**用途**：在 agent 完成某个迭代的代码实现后，委托另一个（或同一个）agent 进行验证。

**使用方法**：将 `[VERSION]` 替换为目标版本号。

---

```
你是 ArkLores 项目的 QA agent。

【你的任务】
对 [VERSION] 迭代的实现进行代码层面的验证（注意：你无法运行真实设备，但可以执行静态分析和逻辑审查）。

【第一步：阅读文档】
- /home/hhikr/ArkLores/docs/implementation_plan.md
  重点：找到 [VERSION] 章节，记录所有「交付内容」和「验收标准」

【第二步：验证交付完整性】
根据 implementation_plan.md 中 [VERSION] 的「交付内容」表格，逐项检查：
- 对应文件是否存在于正确路径（参考文档的「项目目录结构」章节）
- 文件内容是否实现了该交付项的功能

【第三步：代码质量审查】
运行以下命令并报告所有问题：

  cd /home/hhikr/ArkLores
  flutter analyze

对每一个 warning/error：
- 说明问题所在（文件 + 行号）
- 判断是否会影响功能
- 建议修复方式

【第四步：架构合规审查】
检查以下关键约束是否满足（来自 implementation_plan.md）：

1. 主题合规：
   - 所有颜色是否通过 ref.watch(themeProvider) 读取，无硬编码
   - UI 组件是否同时适配 ArkTheme 和 EndfieldTheme

2. AI 资料可信度策略（如本迭代涉及 Agent/RAG）：
   - 是否遵循 GameData > Wiki > Book 的证据优先级
   - Wiki 是否仅作为补充来源，而不是主知识源
   - 书籍来源（source_type='book'）的 chunks 是否被正确标注
   - System Prompt 中是否包含规定的可信度策略插入

3. 数据库 Schema（如本迭代涉及 sqlite）：
   - chunks / lore_chunks 表是否包含 source_type 字段
   - GameData 相关表是否符合 GAMEDATA_KNOWLEDGE_PLAN.md（如本迭代涉及 v0.4.5+）
   - books 表是否存在

4. 目录结构：
   - 新增文件是否在 implementation_plan.md 规定的路径下

【第五步：Git 合规审查】
运行：
  git log --oneline dev..HEAD

检查每一个 commit：
- subject 是否符合 Conventional Commits 格式（参考 GIT_GUIDE.md 第三节）
- 分支名是否符合规范（参考 GIT_GUIDE.md 第二节）

【输出格式】
请用以下结构输出验证报告（放在 /home/hhikr/ArkLores/docs/ 目录下）：

## [VERSION] 验证报告

### ✅ 通过项
（列出）

### ❌ 未通过项
（列出，每项说明：问题描述 / 影响级别 P0-P2 / 建议修复）

### ⚠️ 待人工确认项
（需要真机/模拟器验证的内容）

### Git 合规性
（通过 / 有问题，具体说明）
```

---

<a name="prompt-3"></a>
## Prompt 3 — 专项 Bug 修复

**用途**：描述一个具体 Bug，委托 agent 定位并修复。

**使用方法**：填写 `[BUG_DESCRIPTION]` 和 `[RELATED_MODULE]`。

---

```
你是 ArkLores 项目的 Flutter 开发 agent。

【项目文档】
在开始之前，请阅读：
- /home/hhikr/ArkLores/docs/implementation_plan.md（了解模块设计意图）
- /home/hhikr/ArkLores/docs/GAMEDATA_KNOWLEDGE_PLAN.md（如涉及 Agent/RAG/知识库）
- /home/hhikr/ArkLores/docs/GIT_GUIDE.md（Git 规范）

【Bug 描述】
[BUG_DESCRIPTION]

相关模块：[RELATED_MODULE]

【你的工作流程】

1. 定位阶段（先不改代码）：
   - 阅读相关模块的代码
   - 描述你认为的根本原因（root cause）
   - 告诉我你打算改哪些文件的哪些部分
   - 等待我确认

2. 修复阶段（经我确认后）：
   - 最小化修改：只改导致 Bug 的代码，不要顺手重构无关内容
   - 如果修复需要改动超过 3 个文件，先和我确认

3. Git 提交：
   - 在当前分支（或从 dev 新建 fix/ 分支）提交
   - commit 格式：fix(<scope>): <简短描述>
   - 不要在 fix commit 中混入 feature 改动

4. 完成后告诉我：
   - 修改了哪些文件（精确到函数/方法）
   - 为什么这样修复能解决问题
   - 是否有潜在副作用需要注意
```

---

<a name="prompt-4"></a>
## Prompt 4 — 保持 Git 合规提交（内嵌工作流）

**用途**：这不是一个独立 Prompt，而是在任何开发任务中附加的「Git 规范提醒」。可以粘贴到 Prompt 1/3 之后。

---

```
【Git 合规要求（附加在所有开发任务中）】

请在整个工作过程中严格遵守以下规范（来自 /home/hhikr/ArkLores/docs/GIT_GUIDE.md）：

─── 分支 ───
- 永远不要直接在 main 或 dev 分支上提交
- 从 dev 分支创建你的工作分支：
    git checkout -b <type>/<scope>-<description> origin/dev
- 分支名全小写，用连字符，格式：<type>/<scope>-<short-description>
  示例：feature/rag-book-import-pipeline

─── Commit 节奏 ───
- 每完成一个独立的功能点/修复点就立即提交，不要攒着
- 一个 commit 只做一件事
- 如果你发现自己写了 "and" 来描述一个 commit，说明它应该拆成两个

─── Commit Message 格式 ───
必须遵守 Conventional Commits 格式：

  <type>(<scope>): <subject>

  [可选 body：解释为什么，不是做了什么]

type 列表：feat | fix | chore | docs | refactor | perf | test | style
scope 列表（参考文档）：wiki | ai | materials | rag | agent | theme | settings | llm | db | ci

✅ 正确示例：
  feat(rag): add PDF text extraction via syncfusion_flutter_pdf
  fix(wiki): prevent CSS injection from breaking PRTS table layout
  chore(ci): add GitHub Actions APK build workflow

❌ 错误示例：
  update code
  fix bug
  feat: add some features and fix some bugs

─── 检查点 ───
每次提交前，自问：
1. 这个 commit 只做了一件事吗？
2. subject 是否清楚描述了"改动了什么"？
3. 分支名是否符合规范？

─── 禁止事项 ───
- 禁止提交任何包含 API Key、密码、.env 文件内容的代码
- 禁止提交 build/ 目录、*.db、*.sqlite 文件
- 禁止 force push（--force）到任何共享分支
```

---

<a name="prompt-5"></a>
## Prompt 5 — v0.4 架构转向接手

**用途**：把 ArkLores 从旧 v0.3 Wiki RAG 原型接到新的 v0.4 / v0.4.5 路线。适合在已有未提交改动、已有调试日志、方向刚完成调整时交给另一个 agent 继续。

---

```
你是 ArkLores 项目的 Flutter / Dart 开发 agent。当前任务不是从零实现一个普通迭代，而是在已有工作区状态上接手 v0.4 架构转向：从旧 Wiki RAG 原型，转向中文 GameData release asset 作为主知识源，并完成 Agent 基础设施与 Summary MVP 的稳定化。

【第一步：按顺序阅读文档】
请先按以下顺序阅读，不要跳读：

1. /home/hhikr/ArkLores/docs/implementation_plan.md
   - 重点确认：2026-07 架构转向决策、v0.4 / v0.4.5 迭代目标、知识源可信度策略。

2. /home/hhikr/ArkLores/docs/GAMEDATA_KNOWLEDGE_PLAN.md
   - 重点确认：中文-only GameData、GitHub release asset 分发、GameData > Wiki > Book 可信度优先级、schema 草案、Agent 工具映射。

3. /home/hhikr/ArkLores/docs/v0.4_TASK_BREAKDOWN.md
   - 这是当前执行主清单。后续开发优先按这里推进。

4. /home/hhikr/ArkLores/docs/RAG_RETRIEVAL_HEALTH.md
   - 重点确认：检索健康标准、structured lookup / FTS 优先、vector 只作为补充、embedding 诊断规则。

5. /home/hhikr/ArkLores/docs/v0.4_SUMMARY.md
   - 只把它当作旧 Wiki RAG Summary Agent 原型状态记录，不要当成新路线最终状态。

6. /home/hhikr/ArkLores/docs/v0.3_SUMMARY.md
   - 了解旧 v0.3 Wiki RAG seed / embedding 原型的边界和已知问题。

7. /home/hhikr/ArkLores/docs/GIT_GUIDE.md
   - 确认分支、commit message、不得直接推 main/dev 等规则。

【第二步：检查当前工作区】
执行前先检查：
- 当前分支和 git status。
- 是否已有未提交改动；不要 revert、reset 或覆盖用户/其他 agent 的改动。
- /home/hhikr/ArkLores/log/ 下是否有最新 AI 对话日志；这些日志有价值，不要删除。
- Flutter 工具优先使用 /home/hhikr/flutter/bin/flutter。

【当前上下文】
- 主知识源决策已改变：后续主知识源是中文 GameData release asset。
- Wiki 不再是主知识源，只能作为受限在线补充搜索。
- Book 是用户导入材料，可信度低于 GameData 和指定 Wiki。
- 可信度优先级必须是：GameData / 游戏原始文本 > 指定 Wiki > 用户导入 Book。
- 不要继续把 search_wiki 当作长期主检索工具；它只是旧原型和临时 fallback。
- 不要继续深挖 built-in embedding / Wiki seed 数据作为长期方案。

【优先处理的问题】
按这个顺序推进：

1. ReAct Loop 稳定性
   - 修复非严格 Action Input 解析，例如 {query: 缪因, top_k: 5} 不应被当作完整 query。
   - 处理 final answer 为空的问题。
   - 读取并处理 LLM finish_reason，避免 max_tokens 截断时静默返回残缺答案。

2. Tool source abstraction
   - 从 search_wiki 过渡到可替换知识源接口。
   - 预留 search_local_lore / GameData structured lookup / FTS / vector fallback 的边界。
   - 保持 Wiki 作为 fallback，而不是主路径。

3. Summary MVP
   - 基于新知识源抽象调整 Summary Agent。
   - 回答需要带来源区分和可信度提示。
   - 空知识库、无结果、低置信结果必须有可理解的用户提示。

4. Citation / source metadata
   - 引用卡和 agent observation 需要区分 GameData、Wiki、Book。
   - 当 Book 与 GameData / Wiki 冲突时，不得把 Book 内容说成官方设定。

5. Tests and verification
   - 优先跑 /home/hhikr/flutter/bin/flutter test test/agent_test.dart。
   - 如果碰到 Linux TFLite runtime 缺失，不要把它当成业务失败；记录限制并继续可验证测试。
   - 代码改动后至少跑相关 unit tests；大改动后跑 flutter analyze。

【禁止事项】
- 不要删除 log/。
- 不要 revert 未提交改动，除非用户明确要求。
- 不要引入新的主知识源路线。
- 不要把 Wiki seed RAG 当作最终方案继续扩展。
- 不要提交 API key、token、.env 内容。
- 不要用 print 留 debug residue；必要诊断走现有 logger 或测试输出。

【完成后汇报】
请用简洁列表汇报：
- 你读过的文档。
- 你确认的当前架构方向。
- 你实际修改的文件。
- 你运行的测试 / analyze 命令和结果。
- 未完成事项和下一步建议。
```

---

<a name="appendix"></a>
## 附录：如何为本项目撰写好的 Prompt

给 @hhikr 参考，在委托新任务时快速写出高质量 Prompt。

### 原则

**1. 先读文档，再行动**
每个 Prompt 的开头都应该要求 agent 阅读 `implementation_plan.md`。这是唯一的权威设计来源，避免 agent 凭空假设。

**2. 两阶段工作：计划 → 执行**
先让 agent 输出任务分解或修改计划，人工确认后再执行。
避免 agent 直接大量改动代码后才发现方向错误。

**3. 明确边界**
说清楚"不要做什么"和"什么需要问我再决定"，比说"做什么"更重要。

**4. 不要在 Prompt 里重复文档内容**
不要把 implementation_plan.md 的内容粘贴到 Prompt 里。
直接指向文档，让 agent 自己读。这样文档更新时 Prompt 不需要同步更新。

### Prompt 结构模板

```
你是 ArkLores 项目的 [角色] agent。

【必读文档】
- /home/hhikr/ArkLores/docs/implementation_plan.md（[需要重点阅读的章节]）
- /home/hhikr/ArkLores/docs/GIT_GUIDE.md

【任务】
[一句话描述目标]

【前置条件】
[需要 agent 先确认/检查的内容]

【工作流程】
1. [第一步]（完成后告诉我，等待确认）
2. [第二步]
...

【约束】
- [不能做的事]
- [需要问我才能决定的事]

【完成后输出】
- [需要 agent 汇报的内容]
```

### 常见错误

| 错误 | 更好的做法 |
|------|-----------|
| "帮我实现 RAG 功能" | "根据 implementation_plan.md v0.3 章节实现知识库基础设施" |
| 在 Prompt 里粘贴大量设计细节 | "详细设计见 implementation_plan.md 第 4 节" |
| 让 agent 一次完成整个迭代 | 按文档「交付内容」表格逐子任务推进，每步确认 |
| 没有要求 Git 规范 | 附加 Prompt 4 的内容 |
| 没有指定「完成后输出什么」 | 明确要求：文件列表 / 遗留问题 / 需人工验证的项 |
