# GameData 知识库：构建、更新、补算与发布

> 当前：两个中文知识库，都是 schema 5（条目层 + 可选剧情向量 + 可选故事目录）。**官方知识库只放在固定的 `gamedata-channel` Release 上**（2026-10-25 起；之前随各版 App 的 Release 发布）：
> 明日方舟库的游戏数据是上游 `17759cc`（2026-10-08），终末地库是 2026-10-18 客户端（任务按步骤排列），两个库与 v0.16.0 / v0.17.0 发布的是同一份。
> 本地文件是 `build/gamedata_rebuild/`、`build/endfield/`。差别与检查见 `KNOWN_ISSUES.md` §1.1。终末地只能在本机从游戏客户端构建（§9）。
> 经验与踩过的坑见 **`KNOWLEDGE_BASE_LESSONS.md`**（改建库代码前必读）；Agent 怎样用这些表见 `ASK_AGENT.md`。
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
| `collections(id, kind, name, parent_id, sort_key, start_time)` | 归属单位（书架）。`kind`：`main`、`sidestory`、`ministory`、`branchline`、`activity`、`memory`（干员密录，`parent_id`=干员条目；终末地的 kind 带 `ef/`，见 §9）、`roguelike`、`sandbox`、`system` |
| `entries(id, type, name, code, collection_id, group_name, sort_key, entity_id, raw_id, record_id, source_path)` | 每个官方条目一行，`id = <type>:<原始 id>`；`record_id` 指向承载文字的记录 |
| `entry_links(src, relation, dst, source_path)` | 绑定：`appears_in`、`plays_in`、`attached_to`、`belongs_to`、`belongs_to_stage`、`part_of`、`summoned_by`、`same_person`、`features`、`reads_story`…；视图 `collection_enemies` |
| `story_lines(story_id, line_index, speaker, content, kind, …)` | 剧情逐行（约 44 万行）；索引 `(story_id, line_index)`；行内换行是真换行 |
| `normalized_records` | 非剧情文字（档案、语音、描述…），`entry_id`/`collection_id`；可作为出处 `record:<id>`。只带 `entity_id` 的记录（干员语音）的 `entity_name` 在派生步骤里按 id 从 `entities` 填上 |
| `entities` / `entity_aliases` / `entity_documents` | 实体与别名（资料的所属对象、近似名用）；`entity_documents` 是每位干员的整份档案（也可作为出处） |
| `story_catalog`（可选） | 故事集名、关卡号、章名、行动前/后、顺序、官方梗概、上线时间 `start_time`、剧情回顾的开放时间 `show_time`（`story_review_table.json` 的 `startShowTime`；主线只有这个时间；2026-10-18 加，问答取材按它排上线顺序）（`story_review_table.json` + `[uc]info`） |
| `story_chunk_vectors`（可选） | 剧情向量，12 行一块、步长 8，int8；模型/维度/切块记在 manifest |
| `record_chunk_vectors`（可选，0.14） | 资料向量：`normalized_records` 里不是剧情副本的每条记录与 `entity_documents` 的每份档案；一条一块，超过 800 字的在 `## ` 小节处切、再按行切；每块存文字哈希与它覆盖的字符范围；与剧情向量同一模型 |
| 立绘五张表（可选，0.20，只有明日方舟库） | `story_line_portraits`（每句显示的立绘）与派生的 `portrait_sprites`、`portrait_groups`、`speaker_portraits`、`speaker_names`；格式、规则与四条路径的写法见 `PORTRAITS.md` §2。旧 App 不读，加表不改 `min_app_build` |
| 剧情美术事件表（可选，仅明日方舟） | `story_art_events` 记录背景、CG 和特写的位置；四条路径与补算工具同立绘，见 `PORTRAITS.md` §2。 |
| `gamedata_manifest` | schema 版本、上游提交、计数、向量与目录元数据（0.20 起有 `portrait_index_version`、立绘行数与立绘数） |

关系、名字、复刻合并、去重等规则见 `KNOWLEDGE_BASE_LESSONS.md` §2。

**0.14 删掉的（没有任何代码读，真机与 live 的 40 份会话里模型也没查过）**：`lore_chunks` 与它的全文索引（全部文字切块后的又一份副本）、
`story_lines_fts`（unicode61 不切中文词，匹配不到句子里的词；关键词检索一直走 LIKE）、`entity_documents_fts`、
`entity_relations`（只有“干员 ↔ 自己的语音”一种关系）、覆盖层三张表 `entity_story_mentions` / `rare_terms` / `story_chapter_profiles`、
`normalized_records` 里剧情的切块副本（`parent_type = 'story_file'`，正文在 `story_lines`）、由说话人名字造的实体（`source_type = 'story_speaker'`）。
清单在 `gamedata_schema.dart` 的 `obsoleteGamedataTables` / `dropObsoleteGamedataData`。schema 版本没变（仍是 5）：有没有这些表对 App 是一样的，
旧资产照常能装；App 内更新一个带着它们的库时先删掉再 `VACUUM`（进度“清理不再使用的数据”），命令行用 `tools/compact_gamedata.dart --db=<库>`。
明日方舟库未压缩 679 → 299 MB（679,129,088 → 299,241,472 字节），下载 210 → 119 MB（209,900,351 → 119,420,657 字节，两版的 manifest），终末地 62 → 31 MB；剧情行、资料、条目与之前逐行相同，向量按行迁移。v0.13.0 及更早的 App 的校验要求这些表，装不了新库：新库只随新版本发布。

## 4. 四条构建路径（同一套代码）

四条路径都写立绘表（0.20）：导入剧情时记下每句的立绘，最后 `rebuildPortraitIndex` 重算派生表。给已有的库补立绘、不重建剧情和向量：

```bash
dart run tools/build_portrait_index.dart --db=<库> --source=<同一个提交的源目录>
```

逐篇重新解析，只有每行 `kind|speaker|content` 与库里相同的故事才写立绘行，不同的跳过并列出（同一个提交时应为 0）。

### 4.1 全量构建（桌面）

```bash
dart run tools/build_gamedata_database.dart --arknights-source=<源目录> --output=build/gamedata_v5 --force
# 可选：--source-commit=<sha>（源目录不是 git 检出时）；--story-limit=30（约 30 秒，调规则用，不能验收）
```

Windows 本机约 7 分钟。有 `levels/` 才生成关卡绑定。全量构建自带故事目录。

**只因建库代码改了而重建、游戏数据不变**（2026-10-19 的做法）：源目录（`notes/src`，`.source_commit` 记着它对应的提交）要先同步到已发布库的那个提交，
而不是上游最新——`update_gamedata.dart` 只会同步到最新。用 `SourceSync.sync(installedSha: <源目录的提交>, latestSha: <库的提交>)` 只下载两者之间变化的文件
（那次写了个不提交的小脚本调用它；`a550f5e` → `17759cc` 是 84 个文件），再全量构建（`--source-commit=<库的提交>`），然后 §5 的 `--migrate-from=<旧库>` 迁移向量，
最后与旧库逐表对比，只允许预期的差别和 `updated_at`。

### 4.2 增量更新（App 知识库页 “检查更新 / 构建”，或命令行）

```bash
dart run tools/update_gamedata.dart --db=<库> --source=<源目录>          # 只打印向量计划
dart run tools/update_gamedata.dart --db=<库> --source=<源目录> --embed  # 同时补向量（花钱）
dart run tools/update_gamedata.dart --db=<库> --vectors-only [--embed]
# --output=<新库>（默认 <库>.updated）  --replace（替换，旧库留作 .previous）
```

流程：比较两个提交的文件树（excel/story/levels 按 blob 哈希）→ 只下载变化的文件与缺的上下文表（6 个并发）→ 复制旧库，按
“数据表 → 关卡文件 → 剧情文件”逐个先清后导；上下文表变化时按完整构建的顺序重读全部条目表 → 重算派生层、目录 → 校验后原子替换 →
更新报告。没有装库、旧 schema、旧提交已不在上游时自动完整重建。GitHub 匿名额度 60 次/小时，token 来自 `tools/github_pat` 或 `GITHUB_TOKEN`。

### 4.3 补算（规则改了，不重建剧情和向量）

```bash
dart run tools/rederive_gamedata.dart --db=<库> --source=<源目录> [--output=<新库>]   # 默认 <库>.rederived
```

重导全部条目表、重解析与库里不同的故事（这些故事的向量会被删）、重建派生层，并删掉旧构建留下的没人读的表。末尾打印 `unnamed kind:`（要去 wiki 查名字的新类型）。
补算后若有故事被重解析，接 §5 的向量迁移。补算结果必须与全量新建一致（`KNOWLEDGE_BASE_LESSONS.md` §4 一致性实验）。

### 4.4 App 内完整构建

没有安装库或变化过多时，App 下载仓库 zip，按白名单解压（含 `levels/`，建完删除），在后台 isolate 构建（`sqflite_common_ffi`），
用与安装器相同的 `validateGameDataDatabase` 校验后原子替换。**已安装的库在替换前永不修改。** App 内不生成向量（由“语义检索”卡片另补）。

0.14（知识库页“用游戏数据更新”，只有明日方舟页有）：

- App 里更新或构建出来的库旁边写一个 `<库>.local_build` 标记（`replaceInstalledDatabase`），安装状态的 `builtLocally` 读它。
  这样的库不再被当成“有新版官方知识库”（官方资产比它旧，以前会一直提示“更新”，点了就把新库盖掉）；
  页面显示“本机更新”，按钮是“换回官方版本”（先确认）。装回官方资产时标记删掉。
- 取消会真正停下（`_run` 计数）：下载在两个文件之间停，上一次运行没有结束前不开始下一次（`_active`）。以前取消后下载还在后台继续，
  紧接着再点“更新”会有两次运行同时改源目录，导入时报“Missing required GameData file”（2026-10-10 真机上遇到）。
  每次运行开始时删掉临时目录里失败的构建留下的 `build_*.db`（每个都是整库的一份副本）。
- 更新成功后状态里的已装提交就是最新提交（`GameDataBuildUiState.upToDate`）：“拉取并更新”不可按、更新前那次检查的计数不再显示；
  “检查更新”查到新提交，或换了一个库（安装状态变化时 `installedChanged`），按钮恢复。每次更新都重新向上游问最新提交，
  不沿用上一次检查看到的。
- 真机实测（2026-10-10，PJH110，瘦身后的库）：`a550f5e` → `17759cc`，84 个变化的文件，连下载 187 秒，结果与电脑上同一次更新的报告逐项相同
  （+52 篇剧情、16 张表、15 个关卡文件）；更新后 284 MB，状态“本机更新”。
- 完整重建建的是一个新库，**不带向量**。已装的库有向量（清单里有 `embedding_model`）而这次只能完整重建时
  （库的 schema 旧，或改动超出 compare 接口能列出的范围），不直接开始：页面写明代价，点“仍然完整重建”才继续
  （`GameDataBuildUiState.confirmFull` / `buildFromSource(allowFull: true)`）。增量更新不受影响。

**官方资产与本机更新的先后（2026-10-11，开发者定）**：游戏数据较新的在前；同一份游戏数据，官方资产在本机更新的之前（它的向量是全的）。

- 库自己知道的：清单里的上游提交（`source_arknights_commit`）、那个提交的日期（`source_commit_date`，2026-10-17 起本机更新时写，取 GitHub 的 committer 日期）
  和构建时间（`built_at`）；旁边的标记说明来源——`.asset_sha256`（从哪个官方资产装的）、`.local_build`（在本机更新过）。
- 构建 App 时除了资产的 URL 和 SHA，还写进它所基于的提交和那个提交的日期：`tools/release_gamedata.env` 的 `GAMEDATA_DB_COMMIT` / `GAMEDATA_DB_COMMIT_DATE`
  （GitHub 上那个提交的 committer 日期；`install_local.ps1` 和发布工作流都会传）。**发新资产时四个值一起改。** 终末地库不是从仓库来的，没有这两项。
- 官方卡什么时候提示“更新”（`GameDataInstallStatus.updateReason`）：
  - 手机上是官方资产装的：App 指向的是另一份资产（与原来一样）。
  - 手机上是本机更新过的：官方资产与它是同一个提交，或官方资产的提交比已装的提交**晚**。比的是两边提交的日期（`source_commit_date`），与手机时钟无关；
    清单里没有这个日期的旧库退回比“那次更新是什么时候做的”（`built_at`：本机更新拿的是当时上游的最新提交，之后才有的提交一定比它新）。
    其余情况不提示，只留“换回官方版本”（会丢较新的内容，要确认）。
  - 构建时没写提交的 App（旧的构建方式）不会提示替换本机更新过的库。
- “用游戏数据更新”卡：检查到的上游最新提交就是官方资产的提交、而官方卡正提示更新时，“拉取并更新”变灰并提示用上面的“更新”。
- **渠道文件**（2026-10-17）：只上传新库、不发新 App 时，App 从渠道文件知道有新库。文件是 `gamedata_channel.json`，放在固定 tag `gamedata-channel` 的 Release 上
  （地址是 env 的 `GAMEDATA_CHANNEL_URL`，构建时烘进包里），每个游戏一项：`url`、`sha256`、`commit`、`commit_date`（明日方舟）、`schema_version`、`min_app_build`。
  App 启动后和每次打开知识库页时读一次（`gameDataChannelProvider`），读不到就照旧用包里的资产。渠道里的资产只在 schema 与本版相同、本版 build 号不小于 `min_app_build`、
  而且不比包里的资产旧（两边都有提交日期时比日期）时才替换包里的（`withChannel`）；之后“更新”的判断照上面不变。
  从第一个带渠道的版本起生效：v0.14.0 及更早的 App 不读它。

## 5. 向量（剧情与资料）

```bash
dart run tools/build_story_embeddings.dart --db=<库>                                # 全量/续跑（按内容哈希缓存）
dart run tools/build_story_embeddings.dart --db=<新库> --migrate-from=<旧库> --dry-run   # 按行对齐迁移的计划
dart run tools/build_story_embeddings.dart --db=<新库> --migrate-from=<旧库>
# --stories-only：不做资料向量
```

- **先看 `--dry-run`**：它分两行打印剧情和资料各自的 “to embed”。明日方舟库的剧情向量是按行迁移来的，内容缓存里只有一小部分，
  不带 `--migrate-from` 直接跑会把五万多块剧情重嵌入一遍（约 ¥5）；带上 `--migrate-from=<有向量的旧库>` 后剧情应为 0。
  迁移只把落在搬过来的向量范围内的行算作已覆盖（2026-10-10 前是“旧库有这一行就算”，旧库里没有向量的剧情因此一直补不上）；
  `--migrate-from` 不能指向 `--db` 同一个文件，先复制一份。
- 资料向量（0.14，`record_vectors.dart`）：嵌入的文字是“所属对象 · 标题：正文”（所属对象是 `entity_name`，没有时取 `entity_id` 的名字），
  所以一条语音带着它的干员名。四条路径都覆盖：全量脚本与剧情向量共用内容缓存；增量（`update_gamedata.dart --embed`、App 的“语义检索”卡片）
  按每块文字的哈希比对，只嵌入新增或改动的块，记录已删除的块的向量一并删掉；补算之后接一次增量或全量脚本即可（文字没变的块不重算）。
  2026-10 实测：明日方舟 37,010 块（约 366 万字）、终末地 3,663 块（约 76 万字），合计约 ¥1.6。

- 默认百炼 `qwen3.7-text-embedding`，512 维；key 来自 gitignored 的 `tools/embedding-apiKey.csv`。真实调用要开发者同意。
- 迁移按行对齐（忽略省略号点数、空白、字面 `\n`），首尾都对得上的旧向量搬到新行号，其余才嵌入。
- App 的“语义检索”卡片（`story_vector_updater.dart`）补缺的故事和资料，显示块数、token 与估算费用（0.7 token/字，`embeddingTokensPerChar`；¥0.0005/千 token，`bailianYuanPer1kTokens`；估算）；
  模型/维度与库里不一致时拒绝混用。0.14：每个游戏的知识库页各有一张（`storyVectorProvider(game)`，以前只看明日方舟库）；
  没有缺口时只有两行（剧情/资料向量各多少条、“完整”），有缺口、模型不一致或运行中才展开成操作区。
- 向量只是定位线索；证据是 `read_story` / `read_record` 读到的原文。

## 6. 故事目录

全量/增量构建自动生成。给旧库补表：`dart run tools/build_story_catalog.dart --db=<库> --source=<含 story_review_table 与 [uc]info 的源>`。
目录与梗概只是定位线索。没有目录的故事由条目层给名字（`queryCatalogEntries` 回退到 `entries`）。

## 7. 发布

1. 压缩：`finalize_gamedata_assets.dart --output=<目录>`（没有 `.gz` 时自己压缩，Windows 不需要 gzip），写 manifest 的大小与 SHA。
2. 验收：`flutter test`；`ARKLORES_RUN_DB_CHECK=true flutter test test/live/gamedata_v5_acceptance_test.dart`（真实库）；
   改了建库结构时做一致性实验。
3. `tools/release_gamedata.env` 写新 gz 的 SHA，以及这份库所基于的上游提交和那个提交的日期
   （`GAMEDATA_DB_COMMIT` = 库清单里的 `source_arknights_commit`；`GAMEDATA_DB_COMMIT_DATE` = GitHub 上该提交的 committer 日期，
   `https://api.github.com/repos/Kengxxiao/ArknightsGameData/commits/<sha>` 的 `commit.committer.date`）。提交和日期写错，本机更新过的库会被错误地提示或不提示（§4.4）。
   两个 URL 固定是 `gamedata-channel/<文件名>`，不改。`GAMEDATA_MIN_APP_BUILD` 是能装这两个库的最早 build 号，库的结构或校验要求变了就改成那个 build 号。
4. **发布知识库**：`.\tools\publish_gamedata.ps1 -Files <gz>,<manifest>[,…]`。知识库只放在固定的 `gamedata-channel` Release 上（App 从 v0.14.5 起每次打开知识库页都读那里的渠道文件），
   每次原地替换：每个文件先以 `<名字>.new` 上传、核对 SHA，再删掉旧的、改名，旧文件只缺那一瞬间；最后从 env 写出渠道文件（`write_gamedata_channel.dart`）并同样替换。
   之后用公开地址下载两个 gz 核对 SHA，改 `gamedata-channel` Release 的说明（当前版本、SHA、和上一份的差别），提交 env 的改动。
   渠道里的资产与包里的同一提交、同一日期时也算“不比包里的旧”；SHA 不同就会提示用着旧官方库的手机更新。
   **立绘包**（0.20）：`build/portraits/arklores_portraits_zh.db` 不压缩，和知识库同一个 Release、同一个脚本：env 写 `PORTRAITS_URL`（`gamedata-channel/arklores_portraits_zh.db`）、
   `PORTRAITS_SHA256`、`PORTRAITS_SIZE`（字节）、`PORTRAITS_KB_COMMIT`（生成它的知识库的上游提交），`-Files` 加上这个文件；渠道文件里就有 `arknights_portraits` 一项（`pack_version = 1`、`min_app_build = 43`）。
   打包与增量见 `PORTRAITS.md` §3。知识库的立绘表变了（新的剧情、新的立绘）就重打一次包；包不变时不用重传。
5. **发布 App**：`tools/release_app.ps1 -Version <v> -NotesFile <md> [-Stable]`：推 `release/v<v>` → CI 构建签名 APK（把 env 里的 URL/SHA 烘进去）→ 建 Release 并上传 APK。
   App 的 Release 只放 APK 和 `ArkLores-<v>.apk.sha256`，说明末尾一行指向知识库 Release。发版之后删掉 `release/v<v>` 分支（tag 指向同一提交）。
   知识库和 App 一起变时，先做第 4 步再发 App。
   v0.11.0 时建 Release 的请求遇到过 GitHub 500：Release 没建出来，CI 产物已下载到 `%TEMP%\arklores_release_<v>`，直接用 REST 补建即可，不要重推分支。

历史：v0.10–v0.17.0 的 App Release 都带着当时的知识库，`gamedata-20261020` 是只发知识库的一次。2026-10-25 起统一到 `gamedata-channel`：
v0.10.0–v0.16.0 上的知识库文件和 `gamedata-20261020` 的 Release 已删除（tag 保留；这些旧版 App 装不了现在的库，build 37 之前的 App 也不读渠道里 build 37 起的库）；
v0.17.0 上的两个库保留，是 v0.17.0–v0.19.0 的 APK 里烘进的备用地址（渠道读不到、或渠道里的库要求更新的 App 时用它）。
未发布时在手机上试：`tools/install_local.ps1 -Build -Kb`（用 release key 签名、烘入 env 的 SHA，并把本地 gz 放进应用目录，
在知识库页点“下载”即离线校验安装）。

## 8. App 端的安装与兼容

- 安装器只接受 schema 5；校验必需表、版本、计数与 SHA；失败保留旧库。断点续传、阶段显示、取消、手动放置 `arklores_gamedata_zh.db.download.gz`。
- 知识库页在已安装的官方资产与 APK（或渠道文件，§4.4）指向的不同（`.asset_sha256` 标记）时提示更新。
- 首次打开旧库时补建缺的索引（`story_lines(story_id, line_index)`）。

## 9. 终末地知识库（0.12）

终末地没有可以增量跟随的社区数据仓库，数据从本机安装的游戏客户端解包，在电脑上整库重建，作为单独的 Release 资产发布
（`arklores_endfield_zh.db.gz`，`release_gamedata.env` 的 `ENDFIELD_DB_URL/SHA256`）。表结构与明日方舟库相同（schema 5），所有 id 带 `ef/`。

### 9.1 解包（不启动游戏）

工具：[Variante/endfield_research_kit](https://github.com/Variante/endfield_research_kit) 里的 AnimeStudio 终末地分支（自定义 VFS 解密、表与 JSON 数据导出）。
只第一次需要跑 kit 的 `setup.bat` 构建 AnimeStudio CLI；之后直接用 CLI 导出，不走 kit 的完整导出流程（它要一两个小时，且在本机卡死过）。
客户端改了资源格式时 CLI 会失败（2026-10-18 的客户端：`invalid block data: unsupported code version 5`）：到 `kit\tools\AnimeStudio` 里 `git fetch`，
切到上游支持新格式的提交（这次是分支 `codex/endfield-vfs-v5` 的 `aafe0d3`），在 kit 目录用 embeddable Python 重编：
`python312\python.exe -m scripts.game_data.extraction.animestudio.rebuild --target CLI --configuration Release`（几秒钟）。
客户端没有明文版本号（`config.ini` 是加密的），`-Version` 写 Persistent 层的更新日期。

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
  任务面板的章节同理：`--types MonoBehaviour --names ^(main_e\d+|chr_\d+_[a-z]+_e\d+)$ --export_type JSON`（`ChapterInfo` 对象，由 `ChapterTable` 列出；
  2026-10 客户端在 StreamingAssets 有 21 个，Persistent 没有覆盖）。不知道类名时先按名字导出 `MonoScript` 找类（`ChapterTable`、`ChapterInfo`），再导实例。
- **不要加 `--packed-game-store`**：kit 的完整流程会把 Json/LipSync 写进一个 SQLite，这一步在本机卡死（上千个线程、无 CPU 无 IO），而它只存口型数据。
- 本机环境：AnimeStudio 运行时 `DOTNET_ROOT` 指向 kit 下载的 .NET 9（本机在 `C:\Users\hhikr\endfield\kit\tools\AnimeStudio\.dotnet`）；kit 的 Python 脚本用 embeddable Python
  （`C:\Users\hhikr\endfield\python312`，`._pth` 里加 kit 目录）。工作目录要在 NTFS 上（exFAT 上 git 拒绝、不能建硬链接）。
  Claude Code 的 shell 设了 `NoDefaultCurrentDirectoryInExePath`，批处理要用完整路径调用。
- 任务面板的分类名在 Lua UI 脚本里（`-b lua` 导出的是明文 Lua）：`MissionCtrl.lua` 用 `GEnums.MissionViewType` 的 Main/Discovery/Side/Activity/Other，
  文字键 `ui_mis_panel_tab_*` → 主线任务/探索任务/支线任务/活动任务/委派任务；任务类型到分类见 `MissionTypeInfoTable.missionViewType`。

### 9.2 建库

```bash
dart run tools/build_endfield_database.dart --tables=<表目录> --missions=<MissionRuntimeAsset 目录> \
  --trees=<对话树目录>;<…> --clips=<时间线片段目录>;<…> --chapters=<章节目录>;<…> \
  --data=<Persistent 导出的 Data/Json> --step-order=all --version=<客户端版本> --output=build/endfield --force
```

`unpack_endfield.ps1` 会按上面的导出目录（StreamingAssets 在前、Persistent 在后）填好这些参数。

**按任务步骤排列剧情**（v0.16.0 起）：`--data`（热更新层带全套关卡数据）加 `--step-order=all`，每个有步骤的任务的剧情按步骤排，
`step` / `stage` / `unplaced` 三种标题行不嵌入、不检索、切块在此断开；每段对话去了哪一步、依据是什么写在输出目录的 `story_order_report.md`。
`--step-order=<任务,…>` 只排这些任务，`--only-missions=<任务,…>` 只写这些任务的剧情（审核用，库不能发布）；不加 `--data` 时按种类分块（0.15 的排法）。
数据、规则、审核与验证见 `ENDFIELD_STORY_ORDER.md`。

- 先读任务定义（`--missions`），再导表：文字的地区可能要从它 id 里的任务的关卡推出。
- 表 → 干员（干员情报：阵营/种族/专长/爱好，及每项专长、爱好在这位干员身上的描述 `CharacterTagDesTable`；干员档案；语音记录——段名取游戏的界面文字 `ui_char_profile_*`）、
  情报档案库（PRTS：分页 `PrtsPage` → 分类 → 文档 → 页面 → `RichContentTable` 正文，音像存档的页面是 `RadioTable` 的录音；
  分类按它页面的类型归到中枢档案/见闻辑录/音像存档；调查解锁的报告放在那项调查的集合里（游戏里在调查内部读），只装报告的分类（“调查报告”）不建集合；每个分类集合带一条无正文的 `archive_section` 条目，`group_name` 是分页名；
  事件调查 `PrtsInvestigate` 带地区 `domainId`、它收集的页面和它解锁的报告 `unlockPrts`）、
  敌人/武器/物品的描述（敌人带分布地点；物品只收 `decoDesc`，去掉多件物品共用的模板句和机制句）、副本（`DungeonTable`：名字、简介、地区，敌人 `appears_in`）、
  角色来信（`MailTemplateTable`，系统邮件不收）、势力名；档案库不列的留言与告示（`RichContentTable`）归到所在任务或地点：先看 id（`text_<任务>_<n>`），再看关卡，再看 id 各段里已知的任务（`text_collection_<任务>_1`），最后看显示它的阅读弹窗的 id（`ReadingPopUpTable`：`rp_text_prts_<地图>_<任务>_…`）。
  文档的地区只看 id（`regionOfIds`）：调查收集或解锁的页面取调查的地区；否则看文档、页面、正文的 id 里的地图号（`map01…`），
  再看 id 里的任务（`paper_sm1l1m4_2` → 任务 `sm1l1m4` → 它的关卡 → 地区）。中枢档案是通用设定，没有地区。
- 剧情：`DialogTextTable`、`RadioTable`、`RemoteCommonTable`、`EnvTalkTable`（只收属于已知任务或地点的）、`SNSDialogTable`。
  **一个任务是一篇剧情**（`ef/<任务>.txt`；地点、敌人、短信话题、礼物对话同样各一篇），每段对话前一行 `kind = 'section'`，内容是这段的种类
  （对话/过场动画/通讯/远程通话/闲话/短信）。有步骤的任务按步骤排（上面，`ENDFIELD_STORY_ORDER.md`）；其余的（地点、敌人、话题，没有关卡数据时的全部任务）
  按种类分块（对话 → 过场动画 → 通讯 → 远程通话 → 闲话 → 短信），块内按游戏编号（`0d5` = 0.5）。
  一段对话内部的顺序按它的**对话树**（`dlg_…` TextAsset，`readDialogTree`）：台词节点的 `_trunkId` 是文本行，选项节点的出边依次是各选项的回应，分支在汇合处接上；
  分叉的选项写成“选项 → 它的回应”，不分叉的写成一行“甲／乙”；`Ex…` 节点是设置，不走。过场节点处放这段对话的时间线台词（按片段的 `startTime`，
  绑定的选项接在那句后面）。两者都没覆盖的行与选项组按行号补在后面，选项组填在行号的空位上（2026-10 客户端：约 11% 的台词行）。
  任务 = 对话 id 去掉前缀与末尾编号（`dlg_a1m2_1` → `a1m2`），再经 `canonicalMission`：子任务 `<任务>d<n>` 与基础任务同名、没有名字、
  或基础任务有定义而它自己没有时，并进基础任务；有自己名字的隐藏步骤（`e1m9d5`“准备工作”）是单独的任务，放在基础任务的书架上（以前落在委派任务里）。
  **没有 `MissionRuntimeAsset` 的任务不在游戏里**（客户端留下的旧版剧情、删掉的任务；warfarin/fz 都没有它们的页面），放在 `unused` 书架（“未实装任务”）——除非有一个有定义的任务播放它的对话（任务定义里写着对话 id，`loadPlayedConversations`；例：`db01m2` 的通讯由隐藏步骤 `db01m2d1…` 播放），那它就在游戏里，书架、关卡跟播放它的任务。同名基础任务的子任务有定义、但播放的是自己的对话（`f1m4d1` 播 `dlg_f1m4d1_*`）时，基础任务那批对话是改写前的旧版，仍是未实装。
  任务名依次取：任务定义 → `TextTable` 的 `<任务>_name` / `<任务>_desc_001` → 子任务共同的名字；都没有就叫“无名任务（<任务 id>）”（只出现在未实装书架上）。
  同一书架上重名的任务按游戏顺序加“·一阶段”“·二阶段”（与 fz.wiki 一致）。没有名字、不是别的任务的步骤的隐藏任务归到它关卡所在的地点（`ef/world`）。
  **章节**：任务面板的章节是资源包里的 `ChapterInfo` 对象（`main_e<n>`、`chr_<编号>_<名>_e<n>`，`unpack_endfield.ps1` 导出到 `chapters_*`，
  构建参数 `--chapters`），带章号/进程号/进程名的文字键和 `missionIdList`；章节里的任务 `group_name` 是“第一章 · 进程Ⅰ · 碎裂大地”或“篇章Ⅰ · 离群之狼”，
  `sort_key` 是章节内顺序（主线书架因此按章、进程分组，和游戏一致）；不在章节里的任务 `group_name` 是所在地区。
  干员任务挂在干员下（`parent_id`）；任务面板列在主线的（汤汤的任务）仍在主线书架上。
- `section` 行不进检索记录；向量切块在 `section` 处断开（`chunkStory`），所以合并前后每段切出的块文字相同，按内容哈希缓存的向量全部沿用（0.12 合并时 9969 块零新增）。
  挂在干员下的三种集合：干员任务（kind `ef/memory`）、Baker 话题（`SNSDialogTopicTable`，kind `ef/baker`；话题键里的干员按编号 `chr_0033` 找，
  名字部分和角色表不一定相同，如 `kamiu`/`camille`；地点的话题 `topic_map01_lv001_*` 归到该地点，各自一篇）、帝江号上的互动
  （`sim_talk/gift/rest/work_<干员>`：闲谈按信赖等级、送礼、休息、工作，一位干员一篇，kind `ef/ship`）；`ef/baker`、`ef/ship` 不是书架。
  地图上的交互按地点（`LevelDescTable`；`map01lv005_…` 也是关卡 `map01_lv005`）、敌人遭遇的通讯按敌人归组
  （kind `ef/world`，书架显示为“其他”）；对话之间的插话、工业教学、测试对话不收。
  `DialogSummaryMapTable`/`DialogSummaryTable` 给每段对话的官方摘要：一份进 `story_catalog.synopsis`（全任务连起来），
  一份作为这段的第二行（`kind = 'summary'`，紧跟 `section` 行；阅读器折叠显示，有它时不再在开头显示整篇梗概；不嵌入向量，`unembeddedLineKinds`）。
  **过场动画的台词**（预渲染视频和引擎内过场的字幕）在 `TextTable` 里：键 `cutscene_<任务>_<n>_<行>` / `cs_video_<任务>_<n>_<行>`，按 id 查 `I18nTextTable_CN`，
  没有说话人（`kind = 'subtitle'`）；`…_m` 是男性主角的写法，不收。一段过场一个块，种类“过场动画”（游戏界面文字里的词），归到 id 里的任务（第一段），
  块内按行号、块间按过场号（任务后面那个数）。它在任务里哪段对话前后播放只写在关卡脚本里：按步骤排的任务里由关卡脚本定位，其余单独成块。
  客户端留着同一段过场的几个版本（视频与引擎版、旧编号）：一段过场的每一行（去掉标点和空格）同一任务里另一段都有，就不收（2026-10-18 客户端：93 段收 81 段）。
- 文字规范化（`endfieldText`）：去标记与资源路径；主角台词的 `{F}…{M}…` 只留女性版本（kit 的默认）；`{player}` 写作“管理员”；
  说话人名后面花括号里的内部注释（`{c13-…}`，可能是剧情里尚未揭示的身份）去掉。
- 一个 40 秒左右的整库构建；重建后的库没有向量，加 `-Embed`（脚本在压缩前跑 `build_story_embeddings.dart`）。
  向量按内容哈希缓存在 `build/embedding_cache/`，没变的块不再收费；新块要花钱，先问开发者。
  v0.12.0：8379 段对话、9969 块、约 115 万字，嵌入 77 秒、约 ¥0.4；两个库用同一个模型（`qwen3.7-text-embedding`@512），`search` 跨库合并分数。
  只改归类或命名时先用 `build_story_embeddings.dart --migrate-from=<旧库>` 按行对齐搬旧向量，剩下的块多半在缓存里
  （0.12 归类修正：447 篇整篇对齐、其余 349 块全部命中缓存，零费用）；`--dry-run` 会报“to embed”的块数，非零才要问开发者。
