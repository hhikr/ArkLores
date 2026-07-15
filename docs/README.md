# ArkLores Documentation

本文档目录只保留当前规范、操作指南和精简发布记录。历史版本的详细任务清单与 QA
快照保存在 Git 历史中，不作为当前架构依据。

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

## 文档维护规则

- 当前架构只在 `implementation_plan.md` 定义，不为每个版本复制一份架构说明。
- 每个开发中迭代最多增加一份 task breakdown；封盘后把必要结论合并到
  `RELEASE_HISTORY.md`，再删除任务快照。
- Retrieval 固定用例持续维护在 `RETRIEVAL_QA.md`，不要按 patch 版本复制 QA 文件。
- GameData schema、importer 和发布资产规则分别归属 build pipeline、taxonomy 和
  retrieval QA，避免同一契约出现在多个文件并逐渐不一致。
- 文档不得恢复已废止的 Wiki seed、Book indexing、embedding、vector 或 TFLite 主线。
- 不删除 `logs/`；session 日志不属于 `docs/`，也不应被合并进发布记录。
