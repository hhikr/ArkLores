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

详细检索 QA 见 `RETRIEVAL_QA.md`。

封盘资产：

- `arklores_gamedata_zh.db.gz`：115090365 bytes，SHA256
  `c96599a7291751ada06f8d9b52b90fe0193615beb8eac39488bb49bd03694b10`
- `app-release.apk`：SHA256
  `58f4b42a5ac239af0a0e5d2f33a2dae786ea80ab87fb138395bd317d42e72b37`
- APK 为 release-mode、Android Debug certificate 签名的 GitHub 验收包，不是正式商店签名。

封盘验证：

- `flutter test`：47 passed，3 个 opt-in live tests 默认 skipped。
- `flutter analyze` 及 GameData builder/retrieval/finalizer analyze passed。
- schema v2 smoke build passed：17680 entities、833 entity documents、1 story line、
  82930 lore chunks。
- finalized 完整 DB retrieval QA passed，包括
  `activities/act21mini/level_act21mini_st07.txt:3` scoped evidence。
- 真实 Chat scoped 剧情目标和无 unsupported verdict 安全用例 passed；其余固定外部模型
  命题未全部执行。
- release URL/SHA dry-run、release-mode APK build 和 `apksigner` v1/v2 verification passed。
- PR #1 将 feature 合入 `dev`；PR #2 将 `dev` 合入 `main`。

GitHub Release：

- tag：`v0.5.0`
- target：`74a4a0c6061003f42a97813f9ba186d146aa88cb`
- URL：`https://github.com/hhikr/ArkLores/releases/tag/v0.5.0`
- 状态：非 draft、非 prerelease；APK、DB.gz、manifest、build report 的远端 size/digest
  已回读并与本地产物一致。

封盘时 deferred：

- 真实外部 Chat API 的全部固定命题矩阵。
- Android 双主题、双语、TalkBack、更多文字缩放与设备组合。
- 正式商店签名；当前 GitHub APK 仅为 Android Debug certificate 签名的验收包。

## v0.6.0

v0.6.0 于 2026-07-15 封盘。发布 tag 指向收尾提交；开发验收目标 commit 为
`94997f12e1224b720b5b577b9b2530df8522cf68`。

主要交付：

- 新增 GameData entity / alias 解析驱动的 Role-play Agent，开始会话前要求稳定
  `entity_id` 或返回消歧候选。
- Role-play 继续只注册 `search_local_lore`，每轮至少一次工具调用；角色绑定检索覆盖档案、
  语音、秘录、模组和 canonical 角色名剧情回查。
- 用户场景只作为 session context；UI 明确区分 GameData 事实依据和 AI 生成对白。
- 增加多轮本地 JSON 存档、继续、重新开始、取消和重试。
- 中英文 roleplay 文案已接入 localization。

发布来源继续固定为：

- repo：`Kengxxiao/ArknightsGameData`
- branch：`master`
- commit：`634e7e7d12c9d099c55896d51b4cf8ef633fa2a5`
- language path：`zh_CN`
- schema version：`2`

发布资产：

- `app-release.apk`：27116912 bytes，SHA256
  `a6d5dcc55b775fa08dc0609ca5e6dd91f672ca44bc906abaf3005c029d898e91`
- `arklores_gamedata_zh.db`：395022336 bytes，SHA256
  `3b6d61417da8bed1edda4535762d20f5ca2135389a37df3fa2c9fc4f785ab7c0`
- `arklores_gamedata_zh.db.gz`：115092521 bytes，SHA256
  `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5`
- `gamedata_manifest.json`：984 bytes，SHA256
  `805c3c1514e7849b5aad3f1a8e69a34561d0302e5306ca8f38e5948b65a78516`
- `gamedata_build_report.json`：690 bytes，SHA256
  `7116dc394db92173682e2560e0ea11ea115434816b227340f6869cdb908cb3db`

收尾验证：

- `/home/hhikr/flutter/bin/flutter test test/agent_test.dart`：41 passed。
- `/home/hhikr/flutter/bin/flutter test test/fact_check_widget_test.dart`：2 passed。
- `ARKLORES_RUN_LIVE_CHAT=true /home/hhikr/flutter/bin/flutter test
  test/live_fact_check_test.dart`：3 passed。
- `/home/hhikr/flutter/bin/flutter analyze`：No issues found。
- finalized 完整 DB retrieval QA passed，包括固定 query、`特蕾西娅` alias candidates 和
  `activities/act21mini/level_act21mini_st07.txt:3` scoped evidence。
- schema smoke build passed：17680 entities、833 entity documents、1 story line、
  82930 lore chunks。
- `tools/setup.sh` release GameData URL/SHA dry-run passed。

`app-release.apk` 为 v0.6.0 / versionCode 6、release-mode、Android Debug certificate
签名的 GitHub 验收包，不是正式商店签名。

封盘时 deferred：

- Android 真机上的本地存档恢复、双语、TalkBack、取消和长对话性能。
- Roleplay UI 的真实截图/真机渲染验收。
- 更广的多角色矩阵覆盖和低覆盖量化。
- tag、GitHub Release、远端 asset 上传和 push。

## v0.7.0

v0.7.0 于 2026-07-15 封盘。发布 tag 指向收尾提交；本次 release 不变更 GameData
schema、builder 或源数据，继续复用 v0.6.0 已 finalized 的 schema 2 中文 GameData DB。

主要交付：

- Wiki WebView 工具栏新增“转交给 AI”入口，读取当前选中文字，并携带页面标题、URL 和站点
  标签。
- 转交目标支持 Summary 和 Fact-check；AI 页面根据目标打开对应 tab，并把 Wiki context
  作为用户消息提交给既有 Agent。
- Wiki context 明确标记为用户阅读上下文，不是 GameData evidence；Summary / Fact-check
  prompt 要求独立调用 `search_local_lore` 核验事实声明。
- 未引入 Wiki embedding、vector indexing、隐藏索引、Book indexing 或 GameData DB 写入。
- 新增中英文本地化文案。

发布来源继续固定为：

- repo：`Kengxxiao/ArknightsGameData`
- branch：`master`
- commit：`634e7e7d12c9d099c55896d51b4cf8ef633fa2a5`
- language path：`zh_CN`
- schema version：`2`

发布资产：

- `ArkLores-0.7.0.apk`：27187140 bytes，SHA256
  `a656154d5cf0495fd70f12332b45da8ec29e2b7b9356e85bcb0e962c7ed96496`
- `arklores_gamedata_zh.db`：395022336 bytes，SHA256
  `3b6d61417da8bed1edda4535762d20f5ca2135389a37df3fa2c9fc4f785ab7c0`
- `arklores_gamedata_zh.db.gz`：115092521 bytes，SHA256
  `8870945a23e399b00736fff77883db8b1e4bd8eec866d9395aa0841ff01aabd5`
- `gamedata_manifest.json`：984 bytes，SHA256
  `805c3c1514e7849b5aad3f1a8e69a34561d0302e5306ca8f38e5948b65a78516`
- `gamedata_build_report.json`：690 bytes，SHA256
  `7116dc394db92173682e2560e0ea11ea115434816b227340f6869cdb908cb3db`

收尾验证：

- `/home/hhikr/flutter/bin/flutter test test/agent_test.dart`：43 passed。
- `/home/hhikr/flutter/bin/flutter test test/fact_check_widget_test.dart`：3 passed。
- `/home/hhikr/flutter/bin/flutter analyze`：No issues found。
- finalized 完整 DB retrieval QA passed，包括固定 query、`特蕾西娅` alias candidates 和
  `activities/act21mini/level_act21mini_st07.txt:3` scoped evidence。
- release-mode APK build passed，构建时注入 v0.7.0 GameData release asset URL 与 SHA256。
- `tools/setup.sh` v0.7.0 release GameData URL/SHA dry-run 参数解析通过。
- `apksigner verify --verbose --print-certs`：v1/v2 verified，签名证书仍为 Android Debug
  certificate。

`ArkLores-0.7.0.apk` 为 v0.7.0 / versionCode 7、release-mode、Android Debug certificate
签名的 GitHub 验收包，不是正式商店签名。

封盘时 deferred：

- Android 真机 WebView 选区读取、底部面板交互、返回浏览和无障碍验收。
- 真实外部 Chat QA 与 finalized 完整 DB 的 Wiki context 检索矩阵。
- 正式商店签名。
