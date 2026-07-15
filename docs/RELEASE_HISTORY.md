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
