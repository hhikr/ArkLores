# ArkLores Release History

本文档保留对后续开发仍有意义的历史结论。详细任务分解、逐项 QA 和旧架构原型可通过
Git 历史查看，不应作为当前实现依据。

## v0.1

- 建立 Flutter 工程、双主题 token、底部导航和基础页面结构。
- 早期主题与 Widget 验收记录已被后续实现和测试取代。

## v0.2

- 完成 PRTS / 终末地 Wiki WebView、书签、日夜模式和 Android setup 脚本。
- Wiki 保留为人工浏览入口，不是当前 Agent 默认检索或官方 GameData 证据。

## v0.3

- 曾验证 Wiki seed、Book indexing、embedding、向量检索和 TFLite 原型。
- 整条原型链路已被 v0.4.5 GameData-first 架构取代，当前代码主线不得恢复它。

## v0.4 / v0.4.5

v0.4.5 于 2026-07-15 封盘，将主知识源切换为中文 GameData release asset。

关键交付：

- `search_local_lore` 改为 GameData 结构化检索。
- builder 生成 entities、aliases、entity documents、normalized records、story lines、
  lore chunks 和 FTS。
- App 支持下载 GameData release asset，并在替换现有 DB 前校验 schema、manifest
  和基础计数。
- ReAct Loop 支持宽松 Action Input，拒绝空 final answer，并暴露 finish reason 截断。
- Summary Agent MVP 只使用 `search_local_lore`。
- 增加固定完整 DB retrieval QA、asset finalization 和 setup dry-run 工具。
- 删除旧 Wiki seed、Book indexing、embedding、vector 和 TFLite 主线。

GameData 来源：

- repo：`Kengxxiao/ArknightsGameData`
- branch：`master`
- commit：`634e7e7d12c9d099c55896d51b4cf8ef633fa2a5`
- language path：`zh_CN`

发布资产：

- APK：`app-release.apk`
- APK SHA-256：`a81d3c4ef849ca09319d8516226cbeaa1ea63d75b7654a299fa64acdc9c07977`
- DB：`arklores_gamedata_zh.db.gz`
- DB.gz SHA-256：`cfd3bfaeeefdf7477ae0c9342cab61ab4feb3367bb11b820ba8075c35dc70675`
- Manifest：`gamedata_manifest.json`
- Build report：`gamedata_build_report.json`
- Release：`https://github.com/hhikr/ArkLores/releases/tag/v0.4.5`

v0.4.5 封盘验证：

- `/home/hhikr/flutter/bin/flutter test test/agent_test.dart` passed。
- `/home/hhikr/flutter/bin/flutter analyze` passed。
- finalized 完整 DB 固定 retrieval QA passed。
- GameData schema smoke build passed。
- Android release APK 与 GameData URL/SHA 注入构建 passed。
- `tools/setup.sh` release GameData dry-run passed。

封盘时 deferred：

- 真机端到端下载、安装、检索和 AI 对话。
- story chunks 仍主要依赖 FTS / LIKE，缺少完整实体级剧情关系索引。
- 组织、阵营和概念实体汇总仍需增强。
- `肉鸽`、`秘录`、`模组` 等归一化仍是规则表。

## v0.5.0

v0.5.0 完成 GameData-only Fact-check 工作流，并将剧情取证升级到 schema v2 scoped
evidence。主要交付包括四态 verdict UI、来源约束、Fact-check debug log、取消/重试、
provider 格式兼容，以及可复现的真实 Chat opt-in QA。

GameData schema v2 增加 `story_scopes` 和剧情 chunk 的 `scope_type/scope_id`。剧情事实检索
按 canonical scope、entity 和关系/状态词取交集，并用实体与关系词的文本距离排序候选；
普通档案、活动名称或无结果不能放行 supported/refuted。

安装和开发工具同步到 Android API 36，默认更新安装保留 App 数据；setup 支持从 source
重建数据库、复用已有本地 `.db.gz` 或使用带 SHA256 的远程 asset。

发布来源继续固定为：

- repo：`Kengxxiao/ArknightsGameData`
- branch：`master`
- commit：`634e7e7d12c9d099c55896d51b4cf8ef633fa2a5`
- language path：`zh_CN`

详细验证、deferred 项和最终资产 hash 见 `v0.5_task_breakdown.md`、`RETRIEVAL_QA.md`
及 v0.5.0 GitHub Release。

封盘资产：

- `arklores_gamedata_zh.db.gz`：115090365 bytes，SHA256
  `c96599a7291751ada06f8d9b52b90fe0193615beb8eac39488bb49bd03694b10`
- `app-release.apk`：SHA256
  `58f4b42a5ac239af0a0e5d2f33a2dae786ea80ab87fb138395bd317d42e72b37`
- APK 为 release-mode、Android Debug certificate 签名的 GitHub 验收包，不是正式商店签名。
