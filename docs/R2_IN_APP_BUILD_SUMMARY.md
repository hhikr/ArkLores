# R2 开发总结：App 内构建剧情数据库

> 完成日期：2026-08-24
> 范围：建议路线的 R2（App 内直接构建知识库：拉取仓库 → 增量更新 → 按结构规约更新数据库），
> 对应 `docs/FEASIBILITY_ANALYSIS.md` §3 的可行性方案落地。
> 状态：R2 已完成并通过全部验证；下一步为 R3（P1 跨章节推理）。

---

## 1. 背景与目标

用户可以在 App 内"拉取仓库 → 获取增量更新 → 按照结构和规约更新数据库"，不再依赖
开发者发布 release asset 的节奏。可行性分析（§3）给出的事实基础：importer 实际只需要
源仓库 ~168 MB 子集（20 个 excel JSON 105 MB + 5,691 个剧情 TXT 63 MB），全仓库 ~945 MB；
仓库约 1–2 周更新一次，compare API 可列出增量变更。R2 把这条链路在 App 内落地。

## 2. 工程变更

### 2.1 依赖

| 依赖 | 用途 | 说明 |
| --- | --- | --- |
| `sqflite_common_ffi`（升为主依赖） | 构建后端 | 纯 FFI、无平台通道，可在后台 isolate 使用；importer 零改动复用 |
| `sqlite3_flutter_libs`（新增） | 移动端捆绑 SQLite | 保证 FTS5 与 SQLite 版本一致（老设备系统 SQLite 无 trigram） |
| `archive`（新增） | zip 解压 | 首次拉取按白名单选择性解压 |

### 2.2 importer 扩展（`arknights_importer.dart`）

- 新增可选 `onProgress(stage, done, total)` 回调（阶段：profiles/voices/structured/stories）。
- 新增 per-file 重导入入口，供增量更新按文件驱动：
  - `importStoryFile(relativePath)`——单个剧情 TXT；
  - `importCharacterTables()` / `importVoiceTable()`——character_table+handbook / charword；
  - `importStructuredTable(sourcePath)`——15 张结构化表任一张（表规格提取为
    `_structuredTableSpecs` 常量列表，与原有导入路径完全一致）。

### 2.3 源拉取层（`build/source/arknights_source_client.dart`）

- `ArknightsSourcePaths`：仓库坐标 + **importer 白名单**（18 个 excel + story/**/*.txt），
  供 compare 过滤与 zip 筛选复用。
- `fetchLatestCommit()`：GitHub commits API 取最新 SHA。
- `compareCommits(base, head)`：compare API 拉取变更文件（**处理 300 文件/页的分页**），
  只保留白名单内的变更，重命名给出旧路径。
- `downloadFile(sha, path, outputPath)`：raw.githubusercontent 逐文件下载。
- `downloadZip(sha, outputPath)`：codeload 单请求下载。
- `extractWhitelistedZip(zipPath, outputDir)`（静态、可在 `Isolate.run` 中执行）：
  archive 解码后**只提取白名单条目**并剥掉顶层目录——设备上只落 ~168 MB 源子集，
  不落 ~945 MB 全树；zip 解码需整包入内存，故放后台 isolate 隔离内存。

### 2.4 构建服务（`build/gamedata_build_service.dart`）

核心不变量：**已安装库永不原地修改**——全量构建写全新文件；增量更新先把旧库
`copy` 到临时路径再应用变更；校验通过后才 `replaceInstalledDatabase`（删旧 + rename）。

- `build(options)`：自动判定模式——有 v3 旧库且 `changedFiles` 非空 → 增量；否则全量。
- **全量**：`createGamedataSchema` → 四阶段 importer → `StoryCoverageBuilder` →
  `rebuildGamedataFts` → `stats.refreshFrom` → manifest（commit/计数）。
- **增量**：copy 旧库 → 逐变更文件 **`_deletePathRows`（按 source_path/story_id 删除
  story_scopes/story_lines/normalized_records/lore_chunks/entity_story_mentions/
  story_chapter_profiles/entity_documents）+ per-file 重导入** → 全量重建 coverage 与
  FTS（确定性、简单；逐行 FTS 增量维护留作后续优化）→ manifest 更新新 commit。
- `validateGameDataDatabaseFile`：构建产物校验（与 installer 共用同一验证器，见 2.5）。
- `replaceInstalledDatabase`：删旧 + rename 原子替换。

### 2.5 共享验证器抽取（`build/gamedata_db_validator.dart`）

把 installer 的必需表/schema_version/计数校验抽为 `validateGameDataDatabase(Database)`，
installer 与构建服务共用同一套拒绝规则（坏库、旧 schema 行为一致）。

### 2.6 后台 isolate（`build/gamedata_build_isolate.dart`）

- `GameDataBuildRunner`：`Isolate.spawn` 启动构建 isolate（isolate 内
  `sqfliteFfiInit()`），进度/完成/错误经 ReceivePort 事件流回主 isolate，UI 全程
  保持响应；取消 = `Isolate.kill` + 临时文件清理（构建从未触碰已安装库）。
- `GameDataBuildEvent`：progress / done（含 stats）/ error。

### 2.7 编排与 UI（`gamedata_build_provider.dart` + 知识库页）

- `GameDataBuildNotifier`（Riverpod）：`checkForUpdates`（最新 commit + 增量变更数）、
  `buildFromSource`（首次：下载 zip → isolate 内筛选解压；已有源：compare → 逐文件
  下载/删除 → 后台构建 → 校验 → 替换 → invalidate 安装状态）、`cancel`、`dismissDone`。
- 知识库页新增"从源仓库构建"卡片：检查更新、构建/取消按钮、阶段进度条、最新/已装
  commit、完成与错误提示；全部文案入 ARB（zh/en，28 个新键）。

### 2.8 其他

- `tools/build_gamedata_database.dart` 与构建服务共用 `countManifest`（manifest 计数
  键唯一来源，避免两处漂移）。
- 测试助手 `_createGameDataTestDb` 保持 schema v3（R1 完成）。

## 3. 验证结果

| 验证项 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` 全量 | **95 passed / 3 opt-in skipped / 0 failed**（R1 86 → R2 +9） |
| 新增 `test/gamedata_build_test.dart` | 9 项全过 |
| 回归 | `story_coverage_test.dart` 16 项、`agent_test.dart` 45 项、widget 测试全部保持通过 |

新增测试覆盖：

1. **源客户端**（MockClient）：commit 解析、HTTP 错误、compare 白名单过滤 + 分页、白名单谓词；
2. **zip 筛选解压**：内存构造含白名单/非白名单条目的 zip，断言只落白名单文件且剥顶层目录；
3. **全量构建**：合成源 → 有效 schema v3 库（46 行 story_lines、mentions>0、manifest commit）；
4. **增量更新**：v1 构建 → 新增章节/修改章节/修改 excel → 增量构建出 v2：新章节入库、
   修改章节行数更新、excel 新描述生效、coverage 含新章节、manifest commit 更新，
   **且 v1 库未被改动**；
5. **原子替换**：构建产物替换已安装库；
6. **后台 isolate 构建**：真实 `Isolate.spawn` + FFI 构建 + 进度事件（含 'stories' 阶段）+
   done 事件与统计。

## 4. 用户端影响

1. **知识库自主更新**：用户在知识库页点击即可从最新解包数据构建/增量更新知识库，
   新活动、新干员上线后可立即跟上，不再等 release 发版；首次构建约需 1.5–2 GB 空间
   （已明示），后续增量下载仅 10–60 MB。
2. **安全与可恢复**：构建全程不触碰已安装库；失败/取消保留旧库；产物经与 release
   资产相同的校验规则（必需表/schema v3/计数）后才替换；替换后检索链路（R0 的
   文件 stamp 失效机制）自动切到新库。
3. **双通道并存**：官方 release asset 下载（快、省流量）与"从源仓库构建"（新、自主）
   并列，互不影响。
4. **UI 零负担**：阶段进度、取消、错误/完成提示均本地化（中英）。

## 5. 实际效益

- **"拉取-增量-按规约更新"闭环落地**：importer/schema/coverage 构建代码在桌面 release
  管线与 App 内构建完全共用（单一实现、无漂移），`countManifest` 等辅助也共享；
  R1 的 schema v3 覆盖层构建阶段被 App 内构建直接复用。
- **增量收益量化**：DB 侧按源文件粒度删旧重导 + 全量 coverage/FTS 重建，避免 40 万行
  剧情全量重插；下载侧 compare 白名单过滤后每版本 10–60 MB。真实设备耗时（后台
  isolate 全量/增量构建分钟级）尚未在真机量化，R2 已在代码层预留进度与取消。
- **工程可靠性**：构建服务可脱离 Flutter 单独测试（FFI + 纯 Dart）；isoloate 事件协议
  有真实测试覆盖；安装器与构建器共用验证器，坏库/旧 schema 的拒绝语义一致。
- **为数据产品化铺路**：`GameDataInstaller` 仍是唯一安装入口语义（下载校验替换），
  App 内构建复用同一"校验 → 原子替换"契约；差异报告（增量前后计数对比）可在 R3+
  直接加到 manifest/UI。

## 6. 遗留与下一步

- **未做**：真机（Android/iOS）从 zip 与增量两条路径各完成一次完整构建/替换的性能
  与内存量化（`RETRIEVAL_QA.md` 真机性能项）；zip 解码内存峰值（~1 GB 级）依赖后台
  isolate 隔离，若低内存机型失败需改流式解码；FTS/coverage 全量重建的逐行增量优化；
  构建期间存储空间预检（无系统 API，靠文案提示）。
- **下一步 R3（P1 跨章节推理）**：`find_detail_echoes`（用 `rare_terms` 做 IDF）与
  `collect_suspect_evidence`（用 `entity_story_mentions`）+ StoryInvestigationAgent +
  结论/证据链校验——依赖 R1 覆盖层，与 R2 无耦合。
