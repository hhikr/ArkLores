# ArkLores Documentation

本文档目录以当前规范、操作指南和精简发布记录为主。仍含未关闭 deferred 项的历史
task breakdown 会暂时保留，但不作为当前架构依据；已完全关闭或已迁移结论的快照只保存在
Git 历史中。

## 文档职责

| 文档 | 唯一职责 |
| --- | --- |
| 根目录 `README.md` | 当前开发版、最新 release、产品入口和快速开始 |
| 根目录 `CONTRIBUTING.md` / `CLAUDE.md` | 贡献流程与开发约束摘要 |
| 根目录 `CHANGELOG.md` | 用户可见版本变更；未发布版本必须标记 `Unreleased` |
| `implementation_plan.md` | 当前架构决策、跨版本红线和路线图 |
| `GAMEDATA_BUILD_PIPELINE.md` / taxonomy | schema、构建、finalization 与 importer 契约 |
| `RETRIEVAL_QA.md` | 固定 retrieval/Agent QA、验证记录和已知限制 |
| `RELEASE_HISTORY.md` | 已封盘版本、tag、asset 和当时验证事实 |
| `vX.Y_task_breakdown.md` | 当前迭代或仍有 deferred 项的逐项状态 |

## 接手顺序

1. [implementation_plan.md](implementation_plan.md)：当前架构、版本路线与验收目标。
2. [AGENT_PROMPTS.md](AGENT_PROMPTS.md)：无上下文 Codex 的开发、验收和收尾 Prompt。
3. [GAMEDATA_BUILD_PIPELINE.md](GAMEDATA_BUILD_PIPELINE.md)：GameData DB 构建与发布契约。
4. [ARKNIGHTS_GAMEDATA_CONTENT_TAXONOMY.md](ARKNIGHTS_GAMEDATA_CONTENT_TAXONOMY.md)：
   importer 内容分类与 normalized record 规范。
5. [RETRIEVAL_QA.md](RETRIEVAL_QA.md)：固定检索用例、失败规则与已知限制。
6. [GIT_GUIDE.md](GIT_GUIDE.md)：分支、提交与安全规则。

## 按需阅读

- [ANDROID_SETUP_GUIDE.md](ANDROID_SETUP_GUIDE.md)：Android 环境、构建与安装。
- [RELEASE_HISTORY.md](RELEASE_HISTORY.md)：已封盘版本、关键迁移与发布资产记录。
- [v0.6_task_breakdown.md](v0.6_task_breakdown.md)：v0.6 Role-play 实现与仍未完成的真机、
  多角色检索验收。
- [v0.7_task_breakdown.md](v0.7_task_breakdown.md)：v0.7 Wiki 阅读上下文转交的实现与
  deferred 验收项。
- [v0.8_task_breakdown.md](v0.8_task_breakdown.md)：v0.8 证据检查与 Agent 交互体验的实现、
  自动验证和 deferred 真机项。
- [v0.9_task_breakdown.md](v0.9_task_breakdown.md)：当前视觉重设计、设计依据、实现状态与
  截图验收矩阵。
- [v0.9_visual_design.md](v0.9_visual_design.md)：双主题视觉规则、页面结构、组件契约和
  资产边界。

## 文档维护规则

- 当前架构只在 `implementation_plan.md` 定义，不为每个版本复制一份架构说明。
- 每个开发中迭代最多增加一份 task breakdown；封盘后把稳定结论合并到
  `RELEASE_HISTORY.md`。只有 deferred 项已关闭或迁移到仍维护的 QA/issue 后，才删除任务快照。
- Retrieval 固定用例持续维护在 `RETRIEVAL_QA.md`，不要按 patch 版本复制 QA 文件。
- GameData schema、importer 和发布资产规则分别归属 build pipeline、taxonomy 和
  retrieval QA，避免同一契约出现在多个文件并逐渐不一致。
- 文档不得恢复已废止的 Wiki seed、Book indexing、embedding、vector 或 TFLite 主线。
- 不删除 `logs/`；session 日志不属于 `docs/`，也不应被合并进发布记录。
- 根目录的未跟踪采集输出或临时文本不是项目规范；只有 Git tracked 文档属于本索引维护范围。
