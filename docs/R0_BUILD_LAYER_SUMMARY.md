# R0 开发总结：构建层抽取与知识库替换健壮性

> 完成日期：2026-08-24
> 范围：`docs/FEASIBILITY_ANALYSIS.md` 建议路线的 R0（importer 抽到 lib/ + 修复 store
> 缓存句柄缺陷 + 补齐 installer 校验）。
> 状态：R0 已完成并通过全部验证；下一步为 R1（AI 计划 P0：schema v3 + 构建第 5 阶段 +
> 3 个新工具）。

---

## 1. 背景

可行性分析（`docs/FEASIBILITY_ANALYSIS.md`）给出两条长期路线的共同前置：**把
`_ArknightsImporter` 从 `tools/build_gamedata_database.dart` 抽到 `lib/`**，使桌面 release
管线与未来的 App 内构建（R2）共用同一套构建代码；同时修复检索侧两个已知薄弱点，为
后续"构建 → 校验 → 原子替换"铺路。R0 即落地这三件事，且严格保持现有行为不变。

## 2. 工程变更

### 2.1 新增共享构建层 `lib/core/gamedata/build/`

| 文件 | 内容 | 说明 |
| --- | --- | --- |
| `gamedata_schema.dart` | schema 2 全部建表 SQL、`writeGamedataManifest`、`rebuildGamedataFts`、常量（`gamedataSchemaVersion`/`gamedataLanguage`/`gamedataGame`/`arknightsSourceRepoUrl`） | 纯 SQL + 常量，无 importer 逻辑、无文件 I/O |
| `arknights_importer.dart` | `ArknightsImporter`（四阶段导入：角色档案 → 语音 → 结构化表 → 剧情）+ `BuildStats`/`StoryLine`/`TextSection`/`NormalizedRecord` + 纯函数（`stableContentId`、`storyScope`、`storyCategory/Subtype/ContentType`、`collectTextSections`、`rawIdFromMap`/`titleFromMap`/`parentIdFromMap`、`cleanStructuredText`/`cleanStoryText`、`containsChinese` 等） | 全部逻辑自原工具平移，SQL/正则/ID 生成逐字保留 |

两个关键设计决策：

1. **使用 `sqflite_common`（纯 Dart 接口）而不是 `sqflite`（Flutter 插件）**。`sqflite`
   的主库 import Flutter，纯 Dart CLI（`dart run`）无法加载；共享构建层改用
   `package:sqflite_common/sqlite_api.dart` 的 `Database`/`Transaction`/`ConflictAlgorithm`
   类型，桌面 FFI 后端与 App 平台通道后端返回的是同一接口，两层均可用。`pubspec.yaml`
   相应新增直接依赖 `sqflite_common: ^2.5.4`。
2. **`Process.run('git', ...)` 从 importer 中移除**（原 `_gitCommit`）。importer 不再
   假设存在 git 子进程；`source_arknights_commit` 由调用方注入（桌面 CLI 保留原 git
   读取逻辑；未来 App 内构建用 GitHub API 获取，见 R2）。

### 2.2 `tools/build_gamedata_database.dart` 变薄壳

- 原 1,582 行 → 约 160 行，保留：CLI 参数解析（`--arknights-source`/`--output`/
  `--force`/`--story-limit`）、`_gitCommit`、输出 `gamedata_manifest.json` 与
  `gamedata_build_report.json`、构建摘要打印。
- 构建主体改为调用 `createGamedataSchema` → `ArknightsImporter.importAll()` →
  `rebuildGamedataFts` → `BuildStats.refreshFrom` → `writeGamedataManifest`。
- 对外 CLI 契约与产物结构完全不变（`--help` 输出、manifest 字段、文件名均一致）。

### 2.3 修复 `GameDataKnowledgeStore` 缓存句柄失效缺陷

**问题**（`docs/RETRIEVAL_INSTALL_CHAIN_ANALYSIS.md` §3）：store 懒打开并缓存只读
`_db` 句柄，`close()` 在 lib 内无调用点，且每个 Agent/工具各自 `new
GameDataKnowledgeStore()` 多实例并存；安装器替换 DB 文件后，缓存句柄继续指向已删除的
旧 inode，**App 会一直读到旧库直到重启**。

**修复**：`_open()` 打开时记录文件 stamp（`size`/`modified`/`changed`），每次查询前
`statSync` 比对；文件被替换后 stamp 变化 → 关闭旧句柄并重开新文件。任意时刻替换 DB，
后续检索自动切到新库，无需知道有多少 store 实例。

### 2.4 补齐 installer 校验

- `_validateDatabase` 新增 `story_line_count` 必填正数校验（此前 manifest 写入该键但
  安装器不校验，与其它三个计数同权）。
- `GameDataInstallStatus` 新增 `storyLineCount` getter，便于 UI/后续版本展示。

### 2.5 其他

- `.gitignore`：`build/` 锚定为 `/build/`——原模式会匹配任意层级的同名目录，误忽略
  了新的 `lib/core/gamedata/build/` 源码目录。

## 3. 行为保持与验证

| 验证项 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test`（全量） | 70 passed / 3 skipped（live Chat QA 按设计 opt-in 跳过）/ 0 failed |
| `test/agent_test.dart` | 45 项全过（含新增 2 项） |
| 构建 CLI `--help` | 正常输出用法并退出 |
| 合成源端到端构建 | 用最小合成 ArknightsGameData 树（19 个 excel JSON + 2 个剧情 TXT + git 仓库）跑完整 CLI：产出 DB，manifest 计数正确（entities 2 / documents 1 / story lines 4 / chunks 6），story_lines/scope/记录/实体内容与源一致 |

新增测试（`test/agent_test.dart`）：

1. **store 缓存失效**：打开 store → 搜索命中 → 用替换文件模拟安装器换库（原文件被新
   库替换，新库含额外实体）→ 再搜索命中新实体；替换前同一查询返回 "No matching
   result"，证明重开确实读到了新文件而非旧缓存。
2. **installer story_line_count 校验**：把合法库的 `story_line_count` 改为 0 → 安装被
   拒绝且旧库保留。

## 4. 用户端影响

R0 是**行为保持型重构**，用户可见功能零变化（UI、检索、Agent、下载流程均不变），
但有三个隐性改进：

1. **更新知识库后 AI 立即用新库**：此前在 App 内下载新 DB 后，已打开的检索句柄仍读
   旧库，AI 回答可能基于过期数据直到重启；现在替换后下一次检索即切到新库。
2. **损坏/不完整库更不容易混入**：缺少 `story_line_count` 或计数异常的库会被安装器
   拒绝并保留旧库。
3. **为"App 内自建知识库"打底**：用户未来（R2）可以直接在 App 上从最新解包数据构建/
   增量更新数据库，R0 保证构建产物能无缝替换并被检索链路立即采用。

## 5. 实际效益

- **单一构建代码源，杜绝双份维护漂移**：schema SQL 与四阶段 importer 从 tools/ 进入
  lib/ 后，桌面 release 管线与 App 内构建（R2）共用同一份代码；R1 的 schema v3 新增
  表与构建第 5 阶段只需实现一次，两条路径同时受益。
- **构建逻辑进入可测试的 lib 层**：`stableContentId`（内容派生 SHA-1 主键）、story
  分类、文本抽取等纯函数现在可以被单元测试直接覆盖，为 R1 的实体出场倒排、rare_terms
  等新阶段铺平测试路径。
- **确定性主键保留 → 增量更新结构基础**：主键仍为内容派生，重复导入幂等
  （`ConflictAlgorithm.replace`），这是 R2 "按源文件删旧重导 + FTS 局部 rebuild" 增量
  方案的先决条件。
- **句柄失效修复是 R2 原子替换的必要前提**：App 内构建完成后替换 DB 的流程，只有在
  检索链路能感知文件变化时才成立，否则会出现"构建成功但 AI 还在读旧库"的假象。
- **代码规模**：tools 净减约 1,411 行，构建核心进入 lib 且被现有工具链（analyze/test）
  持续守护。

## 6. 遗留与下一步

- **未做**：完整 168 MB 源树的真实构建耗时未在真机量化（属 R2 的后台构建体验工作）；
  合成源验证覆盖了最小数据形态，未覆盖真实数据中的边界文本（R1/R2 的固定 QA 会补齐）。
- **下一步 R1（AI 计划 P0）**：在共享构建层新增 schema v3 四张表与 `story_lines_fts`，
  增加构建第 5 阶段（实体出场 trie 扫描、章节画像、rare_terms 提取），并注册
  `search_story_coverage` / `read_story_lines` / `get_story_map` 三个新工具。
- **再下一步 R2（App 内构建）**：GitHub API 拉取/增量 + per-file 增量入库 + 构建 UI。
