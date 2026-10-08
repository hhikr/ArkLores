# GameData 知识库：构建、更新、补算与发布

> 当前：明日方舟中文知识库，schema 5（条目层 + 可选剧情向量 + 可选故事目录），v0.11.0 Release 资产。
> 经验与踩过的坑见 **`KNOWLEDGE_BASE_LESSONS.md`**（改建库代码前必读）；Agent 怎样用这些表见 `AI_ARCHITECTURE.md`。
> 建库代码全部在 `lib/core/gamedata/build/`：桌面命令行、App 内构建、增量更新、补算工具共用同一份实现。

## 1. 数据源

- 上游：`Kengxxiao/ArknightsGameData`，`master`，`zh_CN/gamedata`。约 1 GB；文字只在 `story/`（约 63 MB）与 `excel/`（约 144 MB），
  `levels/`（约 500 MB）只提供关卡 ↔ 敌人/装置/召唤物/剧情 的关联。其余目录不读。
- 读哪些表由 `EntryTables`（条目表、上下文表、依赖关系）与 importer 白名单决定；App 内完整构建下载仓库 zip 后只解压这些。
- 本机开发用的源目录：`notes/src`（指向 `notes/upstream/{excel,story,levels}`，gitignored）。

## 2. 内容范围

- **收**：剧情脚本全部带文字的行（对白、旁白、字幕、文档、选项、标题；教程/引导作为 `kind=system`，不进检索块与向量）、
  干员档案与语音、设定描述、活动档案/新闻/来信/事件叙述、物品/皮肤/奖章/藏品描述、世界观、肉鸽与生息演算的叙事结构。
- **不收玩法文字**：技能、天赋、基建、商店、规则/任务说明、效果与数值、获得方式、敌人技能描述。表格长尾文字由 `text_harvest.dart`
  的通用规则收集（路径关键词 + 文字特征），不写活动/人物名表、不为单个活动补特例。

## 3. 表（schema 5）

DDL 以 `gamedata_schema.dart` 为准，可选表见 `story_vectors.dart`、`story_catalog.dart`。

| 表 | 内容 |
| --- | --- |
| `collections(id, kind, name, parent_id, sort_key, start_time)` | 归属单位（书架）。`kind`：`main`、`sidestory`、`ministory`、`branchline`、`activity`、`memory`（干员密录，`parent_id`=干员条目）、`roguelike`、`sandbox`、`system` |
| `entries(id, type, name, code, collection_id, group_name, sort_key, entity_id, raw_id, record_id, source_path)` | 每个官方条目一行，`id = <type>:<原始 id>`；`record_id` 指向承载文字的记录 |
| `entry_links(src, relation, dst, source_path)` | 绑定：`appears_in`、`plays_in`、`attached_to`、`belongs_to`、`belongs_to_stage`、`part_of`、`summoned_by`、`same_person`、`features`、`reads_story`…；视图 `collection_enemies` |
| `story_lines(story_id, line_index, speaker, content, kind, …)` | 剧情逐行（约 44 万行）；索引 `(story_id, line_index)`；行内换行是真换行 |
| `normalized_records` | 非剧情文字（档案、语音、描述…），`entry_id`/`collection_id`；可作为出处 `record:<id>` |
| `entities` / `entity_aliases` / `entity_documents` | 实体与别名（覆盖层、近似名用） |
| `entity_story_mentions`、`story_chapter_profiles`、`rare_terms`、`story_lines_fts`、`lore_chunks(_fts)` | 确定性覆盖层与全文索引（定位线索） |
| `story_catalog`（可选） | 故事集名、关卡号、章名、行动前/后、顺序、官方梗概、上线时间（`story_review_table.json` + `[uc]info`） |
| `story_chunk_vectors`（可选） | 剧情向量，12 行一块、步长 8，int8；模型/维度/切块记在 manifest |
| `gamedata_manifest` | schema 版本、上游提交、计数、向量与目录元数据 |

关系、名字、复刻合并、去重等规则见 `KNOWLEDGE_BASE_LESSONS.md` §2。

## 4. 四条构建路径（同一套代码）

### 4.1 全量构建（桌面）

```bash
dart run tools/build_gamedata_database.dart --arknights-source=<源目录> --output=build/gamedata_v5 --force
# 可选：--source-commit=<sha>（源目录不是 git 检出时）；--story-limit=30（约 30 秒，调规则用，不能验收）
```

Windows 本机约 7 分钟。有 `levels/` 才生成关卡绑定。全量构建自带故事目录。

### 4.2 增量更新（App 知识库页 “检查更新 / 构建”，或命令行）

```bash
dart run tools/update_gamedata.dart --db=<库> --source=<源目录>          # 只打印向量计划
dart run tools/update_gamedata.dart --db=<库> --source=<源目录> --embed  # 同时补向量（花钱）
dart run tools/update_gamedata.dart --db=<库> --vectors-only [--embed]
# --output=<新库>（默认 <库>.updated）  --replace（替换，旧库留作 .previous）
```

流程：比较两个提交的文件树（excel/story/levels 按 blob 哈希）→ 只下载变化的文件与缺的上下文表（6 个并发）→ 复制旧库，按
“数据表 → 关卡文件 → 剧情文件”逐个先清后导；上下文表变化时按完整构建的顺序重读全部条目表 → 重算派生层、目录、FTS → 校验后原子替换 →
更新报告。没有装库、旧 schema、旧提交已不在上游时自动完整重建。GitHub 匿名额度 60 次/小时，token 来自 `tools/github_pat` 或 `GITHUB_TOKEN`。

### 4.3 补算（规则改了，不重建剧情和向量）

```bash
dart run tools/rederive_gamedata.dart --db=<库> --source=<源目录> [--output=<新库>]   # 默认 <库>.rederived
```

重导全部条目表、重解析与库里不同的故事（这些故事的向量会被删）、重建派生层与 FTS。末尾打印 `unnamed kind:`（要去 wiki 查名字的新类型）。
补算后若有故事被重解析，接 §5 的向量迁移。补算结果必须与全量新建一致（`KNOWLEDGE_BASE_LESSONS.md` §4 一致性实验）。

### 4.4 App 内完整构建

没有安装库或变化过多时，App 下载仓库 zip，按白名单解压（含 `levels/`，建完删除），在后台 isolate 构建（`sqflite_common_ffi`），
用与安装器相同的 `validateGameDataDatabase` 校验后原子替换。**已安装的库在替换前永不修改。** App 内不生成向量（由“故事向量”卡片另补）。

## 5. 剧情向量

```bash
dart run tools/build_story_embeddings.dart --db=<库>                                # 全量/续跑（按内容哈希缓存）
dart run tools/build_story_embeddings.dart --db=<新库> --migrate-from=<旧库> --dry-run   # 按行对齐迁移的计划
dart run tools/build_story_embeddings.dart --db=<新库> --migrate-from=<旧库>
```

- 默认百炼 `qwen3.7-text-embedding`，512 维；key 来自 gitignored 的 `tools/embedding-apiKey.csv`。真实调用要开发者同意。
- 迁移按行对齐（忽略省略号点数、空白、字面 `\n`），首尾都对得上的旧向量搬到新行号，其余才嵌入。
- App 的“故事向量”卡片（`story_vector_updater.dart`）补缺的故事，显示块数、token 与估算费用（0.706 token/字，¥0.0005/千 token，估算）；
  模型/维度与库里不一致时拒绝混用。
- 向量只是定位线索；证据是 `read_story` 读到的原文。

## 6. 故事目录

全量/增量构建自动生成。给旧库补表：`dart run tools/build_story_catalog.dart --db=<库> --source=<含 story_review_table 与 [uc]info 的源>`。
目录与梗概只是定位线索。没有目录的故事由条目层给名字（`queryCatalogEntries` 回退到 `entries`）。

## 7. 发布

1. 压缩：`finalize_gamedata_assets.dart --output=<目录>`（没有 `.gz` 时自己压缩，Windows 不需要 gzip），写 manifest 的大小与 SHA。
2. 验收：`flutter test`；`ARKLORES_RUN_DB_CHECK=true flutter test test/live/gamedata_v5_acceptance_test.dart`（真实库）；
   `dart run tools/check_gamedata_retrieval.dart --db=<库>`；改了建库结构时做一致性实验。
3. `tools/release_gamedata.env` 写 **将要创建的 Release** 的资产 URL 与 gz 的 SHA，提交。
4. `tools/release_app.ps1 -Version <v> -NotesFile <md> [-Stable]`：推 `release/v<v>` → CI 构建签名 APK（把 env 里的 URL/SHA 烘进去）→ 建 Release 并上传 APK。
5. 把 `arklores_gamedata_zh.db.gz`（和 `gamedata_manifest.json`）上传到同一个 Release。
   v0.11.0 时建 Release 的请求遇到过 GitHub 500：Release 没建出来，CI 产物已下载到 `%TEMP%\arklores_release_<v>`，直接用 REST 补建即可，不要重推分支。

未发布时在手机上试：`tools/install_local.ps1 -Build -Kb`（用 release key 签名、烘入 env 的 SHA，并把本地 gz 放进应用目录，
在知识库页点“下载”即离线校验安装）。

## 8. App 端的安装与兼容

- 安装器只接受 schema 5；校验必需表、版本、计数与 SHA；失败保留旧库。断点续传、阶段显示、取消、手动放置 `arklores_gamedata_zh.db.download.gz`。
- 知识库页在已安装的官方资产与 APK 指向的不同（`.asset_sha256` 标记）时提示更新。
- 首次打开旧库时补建缺的索引（`story_lines(story_id, line_index)`）。

## 9. 终末地知识库（0.12）

终末地没有可以增量跟随的社区数据仓库，数据从本机安装的游戏客户端解包，在电脑上整库重建，作为单独的 Release 资产发布
（`arklores_endfield_zh.db.gz`，`release_gamedata.env` 的 `ENDFIELD_DB_URL/SHA256`）。表结构与明日方舟库相同（schema 5），所有 id 带 `ef/`。

### 9.1 解包（不启动游戏）

工具：[Variante/endfield_research_kit](https://github.com/Variante/endfield_research_kit) 里的 AnimeStudio 终末地分支（自定义 VFS 解密、表与 JSON 数据导出）。
只第一次需要跑 kit 的 `setup.bat` 构建 AnimeStudio CLI；之后直接用 CLI 导出，不走 kit 的完整导出流程（它要一两个小时，且在本机卡死过）。

```powershell
.\tools\unpack_endfield.ps1 -Version <客户端版本>   # 导出两层 → 合并 → 建库（约 4 分钟）
.\tools\unpack_endfield.ps1 -SkipUnpack              # 用上次导出的数据重建
.\tools\unpack_endfield.ps1 -SkipUnpack -Embed       # 重建并补剧情向量（发布用）
```

脚本会把新 gz 的 SHA 写进 `release_gamedata.env`。只在本地重建、不发布时，提交前 `git checkout -- tools/release_gamedata.env`：
URL 仍指向已发布的资产，带着新 SHA 构建的 APK 会拒收它。

- 导出两个块：`table`（游戏表，文字是 `{id, text}`，字符串在 `I18nTextTable_CN.json`）和 `json-data`（其中 `MissionRuntimeAsset/<任务>.json` 是任务定义：
  名字与简介的文字键、任务类型、所属干员、关卡）。客户端有两层：StreamingAssets 是安装包，Persistent 是热更新层；**先放 StreamingAssets，再用 Persistent 覆盖**。
- 对话树是 Unity 资源包里的 TextAsset，不在上面两个块里：`AnimeStudio.CLI <层> <输出> --game ArknightsEndfield --types TextAsset --names ^dlg_ --export_type Convert`
  （`--logger_flags` 用逗号分隔，写成 `A|B` 时 CLI 只打印帮助）。过场时间线的台词片段同理：`--types MonoBehaviour --names ^Dialog(Trunk|Option)PlayableAsset --export_type JSON`。
  每次都要读遍资源包，是解包里最慢的一步（StreamingAssets 首次约 20 分钟）；两层各导一次，建库时 Persistent 覆盖前者。偶尔中途以退出码 4 结束，看文件数，不全就重跑。
- **不要加 `--packed-game-store`**：kit 的完整流程会把 Json/LipSync 写进一个 SQLite，这一步在本机卡死（上千个线程、无 CPU 无 IO），而它只存口型数据。
- 本机环境：AnimeStudio 运行时 `DOTNET_ROOT` 指向 kit 下载的 .NET 9（`tools\AnimeStudio\.dotnet`）；kit 的 Python 脚本用 embeddable Python
  （`C:\Users\hhikr\endfield\python312`，`._pth` 里加 kit 目录）。工作目录要在 NTFS 上（exFAT 上 git 拒绝、不能建硬链接）。
  Claude Code 的 shell 设了 `NoDefaultCurrentDirectoryInExePath`，批处理要用完整路径调用。
- 任务面板的分类名在 Lua UI 脚本里（`-b lua` 导出的是明文 Lua）：`MissionCtrl.lua` 用 `GEnums.MissionViewType` 的 Main/Discovery/Side/Activity/Other，
  文字键 `ui_mis_panel_tab_*` → 主线任务/探索任务/支线任务/活动任务/委派任务；任务类型到分类见 `MissionTypeInfoTable.missionViewType`。

### 9.2 建库

```bash
dart run tools/build_endfield_database.dart --tables=<表目录> --missions=<MissionRuntimeAsset 目录> --version=<客户端版本> --output=build/endfield --force
```

- 表 → 干员（阵营/种族/专长/爱好标签、档案、语音）、档案库（PRTS：分类 → 文档 → 页面 → `RichContentTable` 正文；调查与线索）、
  敌人/武器/物品的描述（敌人带分布地点；物品只收 `decoDesc`，去掉多件物品共用的模板句和机制句）、副本（`DungeonTable`：名字、简介、地区，敌人 `appears_in`）、
  角色来信（`MailTemplateTable`，系统邮件不收）、势力名；档案库不列的留言与告示（`RichContentTable`）归到所在任务或地点。
- 剧情：`DialogTextTable`、`RadioTable`、`RemoteCommonTable`、`EnvTalkTable`（只收属于已知任务或地点的）、`SNSDialogTable`。
  **一个任务是一篇剧情**（`ef/<任务>.txt`；地点、敌人、短信话题、礼物对话同样各一篇），每段对话前一行 `kind = 'section'`，内容是这段的种类
  （对话/通讯/远程通话/闲话/短信）。一篇里按种类分块（对话 → 通讯 → 远程通话 → 闲话 → 短信），块内按游戏编号（`0d5` = 0.5）：
  各表的编号互相独立，跨种类的先后游戏数据只给了一部分（见 `KNOWLEDGE_BASE_LESSONS.md` §10），所以不交错。
  一段对话内部的顺序按它的**对话树**（`dlg_…` TextAsset，`readDialogTree`）：台词节点的 `_trunkId` 是文本行，选项节点的出边依次是各选项的回应，分支在汇合处接上；
  分叉的选项写成“选项 → 它的回应”，不分叉的写成一行“甲／乙”；`Ex…` 节点是设置，不走。过场节点处放这段对话的时间线台词（按片段的 `startTime`，
  绑定的选项接在那句后面）。两者都没覆盖的行与选项组按行号补在后面，选项组填在行号的空位上（2026-10 客户端：约 11% 的台词行）。
  任务 = 对话 id 去掉前缀与末尾编号（`dlg_a1m2_1` → `a1m2`）；任务名、简介（`mission_intro` 条目，`group_name` 是任务所在地区）、分类（书架）、所属干员来自任务定义。
- `section` 行不进检索记录；向量切块在 `section` 处断开（`chunkStory`），所以合并前后每段切出的块文字相同，按内容哈希缓存的向量全部沿用（0.12 合并时 9969 块零新增）。
  干员的任务、短信话题（`SNSDialogTopicTable`）与礼物对话挂在干员下（kind `ef/memory`）；地图上的交互按地点（`LevelDescTable`）、敌人遭遇的通讯按敌人归组
  （kind `ef/world`，书架显示为“其他”）；没有定义的任务按分类编号（“支线任务 3”）；对话之间的插话、工业教学、测试对话不收。
  `DialogSummaryMapTable`/`DialogSummaryTable` 给每段对话的官方摘要（进 `story_catalog.synopsis`）。
- 文字规范化（`endfieldText`）：去标记与资源路径；主角台词的 `{F}…{M}…` 只留女性版本（kit 的默认）；`{player}` 写作“管理员”；
  说话人名后面花括号里的内部注释（`{c13-…}`，可能是剧情里尚未揭示的身份）去掉。
- 一个 40 秒左右的整库构建；重建后的库没有向量，加 `-Embed`（脚本在压缩前跑 `build_story_embeddings.dart`）。
  向量按内容哈希缓存在 `build/embedding_cache/`，没变的块不再收费；新块要花钱，先问开发者。
  v0.12.0：8379 段对话、9969 块、约 115 万字，嵌入 77 秒、约 ¥0.4；两个库用同一个模型（`qwen3.7-text-embedding`@512），`find` 跨库合并分数。
