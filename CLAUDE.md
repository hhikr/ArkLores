# ArkLores Developer Notes

当前主线：中文 GameData release asset + SQLite structured retrieval + FTS/LIKE
+ 可选剧情向量召回（R12）+ 可选故事目录与官方梗概（R14，`story_catalog`）；
剧情问答由工具型 Agent（R17，`LoreAgentLoop`）直接查库作答。向量、目录、梗概都只作定位线索，不作证据。
当前发布版本：v0.10.0（正式版，2026-10-04；取代并删除了之前的 v0.10.0–v0.10.7 八个预发布）；知识库资产在 v0.10.0 Release 上。
**0.10 线已收尾；0.11 开发中**，按下面的顺序分步做（开发者 2026-10-04 定）：
① 考察上游解包仓库（结构、更新频率、与现有知识库的覆盖差距）；② 知识库扩充与重构（补内容、按故事集/肉鸽/活动重新排布）；
③ 随时可用的增量更新通道；④ 用户库与阅读历史；⑤ 可阅读资料页（阅读器 + 用户资料），放最后。
0.11 不重构角色扮演（保持现状，只修崩溃）。
未经开发者明确同意不要发版；发版时 Android build 号继续递增（当前 22），知识库资产的 URL 随 `tools/release_gamedata.env` 更新。
**仓库里只放面向用户的内容和必要的开发约定**：调查笔记、方案讨论、竞品分析等放本地 `notes/`（已 gitignore），不要提交、不要写进 PR。
GameData schema：5（0.11 起；含条目层 `collections` / `entries` / `entry_links`、`story_lines.kind`、确定性覆盖层，
可选剧情向量表、可选故事目录表）；已发布的 v0.10.0 资产仍是 schema 4。
知识库页会在已安装的官方资产与本 APK 指向的资产不同（`.asset_sha256` 标记）时提示更新。

## 当前进度（每轮结束时更新）

- **0.11 资料页检索、问答的可选步骤（2026-10-07，未发布，不需重算知识库）**：① 资料页每个子页面右上角都有搜索（`LibrarySearchButton`），
  默认只搜该页的范围（`LibraryScope`：书架、集合、某类条目列表、干员页=密录集+属于他的条目；条目页搜它所在的集合），范围显示为可删掉的标签，删掉即搜全部；
  列表的筛选框没有结果时给“搜索「…」”按钮。检索分层（`library_search.dart`，`library_queries` 的 part）：名字/代号包含全部词（空格分词，某个词可以是集合名，
  但至少一个词要在条目自己的名字里）→ 都没有时自动给“相近的名字”（同序字符 `%a%b%`、`nameDistance` 读音感知编辑距离；两个字的名字只认同音字，否则
  “切城”会配上“坚城”）和“正文提到”（故事行、记录、干员档案里同一行/块含全部词，按命中数排，故事点进去在命中行高亮打开）；名字有命中时正文只在点“在正文里搜索”后才查。
  实测（真实库）：全库名字检索 <10 ms，回退层约 250 ms（冷缓存第一次约 1–2 s，后台线程，界面不卡）；页面范围内都是个位数毫秒。
  向量检索（“按意思找剧情”，`librarySemanticProvider`）要把问题发给向量服务、首次还要载入约 28 MB 索引，是用户能感觉到的等待，所以做成按钮，不自动跑；
  没配向量服务、库没有向量、模型不一致时分别提示。阅读页加了“在本篇中查找”（`story_find_sheet.dart`，点结果以引用方式高亮打开该行）。
  ② 问答的“复核”（R18 读者审稿）和“提要”（长答案整理成几段、详细版折叠）改为可选：输入框工具栏一个小按钮（`answer-options`，tune 图标）弹出两个勾选项，
  默认都开、保存在 secure storage（`AnswerOptions`，`ask_answer_options`），每问读取（`AskChatNotifier.optionsReader` → `StoryQaAgent.run(options:)` →
  `LoreAgentLoop(review:, digest:)`）；关掉不改检索、不改出处核对。

- **0.11 收尾检查（2026-10-07，未发布，不需重算知识库）**：① 修了测试整理时发现的两个问题：Wiki 页站点标签可收缩（长站名显示省略号）；
  `WikiBrowserPage` 在 `initState` 里取 `SettingsService`、`dispose` 时先复制状态再保存（以前 dispose 里用 `ref`，状态从来没存上）。
  ② 性能（用真实库 `build/gamedata_v5` 计时）：资料页查询都很快（最慢的图鉴书架 96 ms），不用改；剧情向量索引（约 28 MB）改为后台 isolate 用 FFI SQLite 读
  （`StoryVectorIndex.loadFile`，`Isolate.run` 零拷贝交回）——以前经 sqflite 平台通道一次性传进 UI isolate 解码，手机上会卡住界面；
  向量检索本身桌面 AOT 27 ms，改写循环只快 20%，没改。启动时的 9 项设置、Wiki 页恢复状态、API/向量配置的逐项读取改为并行（都是 secure storage 平台调用）。
  ③ 后台：问答、角色扮演、知识库下载/构建、故事向量都包在 `BackgroundWork` 里（“检查更新”只是十来个短请求，没包）；修了两处：从最近任务里划掉 App
  时前台服务现在随之停止（`onTaskRemoved`，以前通知和唤醒锁会留到 3 小时超时），服务已在运行时只更新通知文字、不再重新 `startForegroundService`
  （Android 12+ 在后台会拒绝）。④ 长文件：`entry_importer.dart` 3242 行 → 主文件 803 行 + 按数据来源分的 8 个 `part`（items/stages/activities/
  handbook/roguelike/sandbox/levels/derived，私有 extension，公开入口仍在类上）；`library_pages.dart` 拆成每页一个文件（它保留导航函数并 re-export）；
  知识库页拆出 `SourceBuildCard`、`StoryVectorCard`；设置页拆出资料设置页、Wiki 来源页；角色扮演的状态与通知器移到 `roleplay_provider.dart`
  （`agent_provider.dart` re-export）；知识库 store 的角色扮演用实体检索移到 `gamedata_entity_search.dart`（part）。删掉没人调用的代码：
  store 的 `searchStoryCoverage`/`getStoryMap`/`namesInText`/`namedStoryTargets`/`filterRareTerms` 等 8 个方法、`queryNamedStoryTargets`、
  `namesMentionedIn`、`collectCompletion`、旧的引用格式化（`humanizeCitations` 等）；LIKE 转义合并为 `story_catalog.escapeLike` 一处。
  没拆的：`wiki_browser_page.dart`（WebView，只能真机验证）、`lore_agent_loop.dart`（一个循环）、`arknights_importer.dart`、`chat_bubble.dart`、
  `story_reader_page.dart`（各是一个整体）、`wiki_reader_scripts/css.dart`（注入页面的 JS/CSS 文本）。⑤ 提示词留在 Dart 里（与解析器的格式同版本、
  有守卫测试、桌面工具与 live 测试同步可用；不是界面文字，不进 ARB）。界面文字绝大多数走 ARB（中英各 411+5 个键）；这轮把阅读页的行类型标记、
  Wiki 书签按钮提示、资料页无名分组改成跟随界面语言。仍只有中文的：资料页的条目类型/分组/绑定名（`library_labels.dart`，游戏内容用语，与库内容同语言）、
  LLM 错误信息（中英混杂）。未改、建议 0.11 之后处理：角色扮演提示词（`agent_prompts.dart`）还有旧功能的残留（“Endfield”、“用户导入 Book”、
  要求列出 source path 而第 7 条又要求只输出对白）——0.11 冻结角色扮演，没动；问答提示词没有规定回答语言（英文界面的用户也会得到中文回答）。

- **测试重整（2026-10-07，为之后的代码优化做准备）**：测试目录改为与 `lib/` 一一对应（`test/README.md`），拆掉按开发轮次堆起来的
  大文件（`agent_test`、`investigation_test`、`locality_test`、`streaming_test`、`fact_check_widget_test`）；GameData 夹具一律用生产
  schema（`test/support/gamedata_fixture.dart`）——原来 9 个文件手写建表，已与真实表分叉（`story_lines` 列不同、`lore_chunks_fts`
  分词器不同）。删掉：已删除的核查模式的 live 测试、只测 Riverpod 本身的测试、两个重复的 ReAct 测试、一个不可能失败的测试，以及
  `main.dart` 走不到的旧 Wiki 爬虫代码（`core/wiki/*`、`citation_card.dart`）。补上原来几乎没测的：App 内构建/更新的通知器
  （`gamedata_build_provider`，用内存里的 GitHub 端到端跑：首次 zip、增量、上游提交消失、无相关变化、检查更新）、角色扮演通知器、
  `SettingsService`、API 设置页、嵌入客户端与故事向量卡、App 外壳（四个标签页、记住的标签、命名路由）、会话日志的隐私截断与清理。
  行覆盖率 71% → 79%（不计 WebView 里的 Wiki 浏览器和生成的 l10n：85%）；仍偏低的是设置页、知识库页的界面分支和
  `rag/chunker.dart`，没有自动测试的部分见 `test/README.md` 末尾。473 项通过、5 项跳过（opt-in live 与 POSIX 专用）。
  测试中发现、未改：Wiki 页站点标签的 `Text` 不能收缩（自定义长站名会溢出）；`WikiBrowserPage` 在 dispose 里用 `ref` 保存浏览状态，
  Riverpod 不允许，状态没存上（日志 “Error saving browsing state”）。

- **0.11 一致性复测与同一人物（2026-10-07，未发布，需重算知识库；`tools/release_gamedata.env` 已指向新的本地库）**：① 第二轮一致性实验：早库也带关卡文件
  （App 完整重建现在读 `levels/`），更新到 `a550f5e`，与全量新建库逐项对比，**条目、故事行、记录、绑定、集合全部一致**（`build/consist/cmp.dart` 对比）。
  这一轮抓到的问题：导入一张表时没有先清掉它上次写的行（只有肉鸽表清），规则变过之后旧行留着——更新库和 `rederive_gamedata.dart` 都和新建库不一样
  （之前发给你装的本地库就有 1340 条多余的复刻关卡条目、213 个故事名不同）。现在 `_importTableWith` 先 `_purgeSource`（条目、记录、本表写的绑定、实体与别名），
  上下文表（活动/关卡/分区/复刻/回顾/沙盘）有变化时增量构建按完整构建的顺序重读全部条目表（`importAllTables`；先到先得的重复 id 取决于顺序），
  `rederive_gamedata.dart` 也改成 `importAllTables`；重算后的库与全量新建库完全一致。② 同一人物：`char_meta_table.spCharGroups`（37 组，组内第一个是原型）→
  `same_person` 链接（异格 → 原型），干员页“同一人物”小节（`samePersonOf`）；`char_meta_table.json` 加进下载的表。表里没有“是否假设线”，没有干员上线时间
  （`gacha_table` 只覆盖 82/458 个干员），也没有故事内时间表，所以不造这些表；提示词（`loreLibraryGuide`）讲清：上线时间不是故事时间、后出的可以推翻先出的、
  同一干员的多个版本要读档案与剧情判断。提示词标题里的括号说明已去掉。
- **0.11 新建库/更新库一致性、名字兜底、资料页结构说明（2026-10-07，未发布）**：① 一致性实验（`build/consist/`，不用向量）：从上游较早提交
  `fa63359`（2026-06-26）建“早库”，用 App 同一套增量代码（`tools/update_gamedata.dart`）更新到 `a550f5e`，与 `a550f5e` 的新建库逐项对比：
  条目、故事行、记录、绑定（除依赖关卡文件的 `appears_in`/`plays_in`/`attached_to`，因为早库没读关卡文件）完全一致；`system` 集合的排序号以前取决于行的
  物理顺序，现在按 story_id 排序（`rebuildDerived`）。实验抓到并修了四个更新通道的真问题：GitHub compare 接口一次最多给 300 个文件，一个提交里有几百个
  `bakemuzzledata` 文件就把所有表、剧情文件挤掉（App 会说“没有相关变化”）→ `compareCommits` 改为读两个提交的文件树（excel/story/levels 三个文件夹按 blob
  哈希比，约十个请求，与提交大小无关；旧提交已不在上游或文件夹过大 → 完整重建）；`[uc]info` 目录下的文件下载被二次编码成 404；活动表/关卡表/分区表变了而物品表、
  奖章表没变时，它们的归属不重算（`EntryTables.contextTables`/`ownerDependents`，增量构建里重读）；App 完整重建的 zip 提取不含 `levels/`，建出的库没有敌人/装置/召唤物
  绑定（现在提取，建完删除该目录）。变化文件改为 6 个并发下载。知识库页的“构建”就是同一条路径（没有装、版本旧、上游变化太多时自动完整重建），没有过时的重复入口。
  ② 名字兜底（`library_labels.dart`、`shelfSummaries`）：表或 prts 的名字 → 家族默认名（`roguelike_`/`sandbox_`/`archive_`/`activity_`）→ 类型 id；未知书架
  排在已知书架之后显示“其他”，未知绑定关系显示“相关”，没有名字的分组不显示标题。③ 问答提示词新增 `loreLibraryGuide`（`lore_agent_prompts.dart`，主/子 agent 都读到）：
  资料页书架、条目类型、绑定与对剧情的作用，来源依据见 `docs/LIBRARY_AGENT_GUIDE.md`；不含具体人物/章节/活动名。

- **0.11 图鉴小条目的关联（2026-10-07，未发布，需重算知识库）**：规则都在建库代码里（全量/增量/`rederive_gamedata.dart` 同一套），不改库本身。
  ① 奖章归属（`_medalOwner`）：`medal_activity_<活动>_n`（活动 id 可缺 `act`）→ 活动；否则看通关条件里点名的东西（集合 id、关卡 id → 它的区域 → 集合、区域 id）；
  记录奖章的条件 `[干员, story_<干员>_set_n]` 就是密录集合 id；条件里的 `char_…` → `features` 链接到干员，`char_…@…#n` → 皮肤。②物品归属：id 前缀、`main16_…`→`main_16`、
  `iconId`；活动类（`ACTIVITY*`、`ET_STAGE`）再看 `stageDropList` 的关卡所在集合（唯一时）、最后看唯一一个在活动表（各分区按活动 id）里点名它的活动
  （`_activityMentions`）。③ 复刻：`ctx.alias`（复刻 id → 原活动：`retro_table.linkedActId`，其余按“名字·复刻”找同名活动），复刻的活动文本、奖章、掉落并入原活动（`ctx.home`、`collectionForId`
  认复刻 id）；复刻的关卡仍不单独出条目。④ 同名且同文字、同集合的物品只留一条（`rebuildDerived` 的 `item_twin` 现在也管 `item`：寻访数据契约 26 条→1、ID 信息更新卡 23→1…）。
  ⑤ 装置/召唤物：关卡文件 `predefines`/`hardPredefines` 的 `characterInsts`/`tokenInsts` 里的 `trap_…`/`token_…` → `appears_in` 关卡；集合页的敌人菜单里也列装置、召唤物
  （`stageBoundTypes`，视图 `collection_enemies` 不变，按条目类型筛）；召唤物 → 干员用新关系 `summoned_by`（角色表 `displayTokenDict`/技能 `overrideTokenKey`，
  `arknights_importer._linkCharacterRefs`），干员页列出召唤物；干员信物（`p_char_…`）及活动给的文件夹用角色表的 `potentialItemId` 等 → `belongs_to` 干员（从图鉴物品列表移到干员页）。
  ⑥ 皮肤 → 皮肤系列：系列（`brandList`）的 `groupList[].skinGroupId` 对皮肤的 `skinGroupId`，`belongs_to`；条目页最多 400 条绑定（系列有上百个皮肤）。
  ⑦ 描述里的 `<热泵通道>`（尖括号括起的名字）以前被当成标签删了，句子变成“场地内有……的和”：`stripMarkup` 只删真正的标签（`<@x>`、`<$x>`、`</…>`、`<color=…>`、纯 ASCII 标签），
  名字只去尖括号；剧本里的 `<清香花束>` 同理（`cleanStoryText` 用同一函数，rederive 会重解析变化的故事）。⑧ 自拟名字按 prts.wiki 改：护符→标志物（多索雷斯假日“标志物一览”）、
  表情→表情套组、勋章→奖章、背景→首页场景；没有依据的物品分组名（理智与补给、凭证与券、补给包、经验、剧情道具、收藏品）去掉。条目页头的集合名可点，进集合页。

- **0.11 关卡内对话、剧本解析、生息演算（2026-10-07，未发布，需重算知识库）**：① 剧本解析（`story_script.dart`）：命令可以跨行
  （行尾 `\` 续行，`[Tutorial(…,\` 的属性在下面几行，文字在 `)] \` 之后的行），以前逐行读，属性行成了“旁白”（全库 1471 行、319 个故事，教程/训练/引导全中），
  现在 `storyLogicalLines` 先合并续行，连续的命令（`[A(…)] [B(…)]文字`）文字归最后一个；给已有的库补算：`rederive_gamedata.dart` 现在先
  `reimportChangedStories`（解析与库里行不同的故事，`deleteStoryRows` 清旧行——库里的 `source_path` 在 Windows 上是反斜杠写法，两种都要认——再补算覆盖层；
  被重写的故事的向量会删掉，321 个故事 701 条，要用 `build_story_embeddings.dart` 或 App 里的“故事向量”补）。② 关卡内对话（教程、训练、战斗内对话）不单独成条目：
  关卡文件里的 `STORY` 动作就是“这场战斗播放这篇剧情”（`_levelBindings` 写 `plays_in` 链接，故事→关卡；大小写按关卡文件的写法，`_attachLevelStories`
  再对到故事条目；没有关卡文件的构建（App 内增量）沿用库里已有的链接），再由 `rebuildDerived` 写 `attached_to`：宿主是该关卡的第一篇真正的剧情（顺序最前，
  通常是行动前），没有就是关卡条目本身；目录里有名字的章节永远是剧情而不是关卡内对话；名字能推出关卡的 `training_*`/`tutorial_*` 也算。
  界面：列表、计数、搜索不列它们（`_isAttached`），关卡条目页把它们的内容放在“关卡内对话”小节里（`_AttachedDialogue`），阅读页在宿主剧情的末尾接上
  （`storyReadingProvider`：宿主行 + 每段一个 `divider` 行 + 该段的行，行号显示它自己的；引用/续读用对话自己的 id 打开时换算到宿主，
  历史记在宿主名下）。关卡没有条目的一百来个（obt/training、引导关卡、军团教程、周常…）仍是它们集合里的普通条目。只有标题行的文件（`ref_*`、镜头测试）不再有条目。
  ③ 生息演算：表里本来就有剧情结构，旧导入把事件/档案文字揉成无标题的文本块（`sandbox_text`，已取消）。现在：`sandbox_act` 篇章（`archiveQuestData`：幕/支线的名字
  和概述，条目 `part_of` 它）、`sandbox_topic` 简介、`sandbox_event` 事件（`_enter` 场景起头，每个场景自己列选项，选项后的场景按编号 `choice_x_1`→`scene_x_1`，
  `<color>` 与 【】 里的效果文字不收；`sandboxEventOutline`）、`sandbox_stage` 关卡（名字、描述的文字，描述里 `<@lv.…>` 标出的第一句不含数字的是所在区域，作分组；
  关卡文件绑定敌人）。剧情名字：幕里的故事用 `avgName`，NPC 对话按 id 干（`dialog_sandbox_1_main1_2_op` → 任务 `mainline1_2` 的标题）归入对应的幕，没有任务认领的
  用 NPC 名，仍无名的 battleavg 用第一个说话人，重名的编号（“名 · n”，按阅读顺序，对所有未收录目录的故事生效）；引导弹窗用触发它的任务线标题；
  `dialog_<主题>_level_<n>` 是关卡里的路牌，并入对应关卡。物品分组用表里的 `itemTypeData` 名（V2 独有的类型没有名字就没有标题，旧的 `groupLabel` 里自拟的分类删了）。
  第一个生息演算（沙中之火）是活动，但 `sandbox_table.sandboxActTables` 列了它，于是放进生息演算书架，它的物品也归它。“战斗对话”改称“对话”（文件夹名 battleavg
  不是玩家的词）。- **0.11 活动分类、阅读器与设置（2026-10-05，未发布，需重算知识库）**：① 活动书架按游戏表分类（`_activityKind`）：活动表的 `displayType`
  （SIDESTORY → `sidestory` “SideStory”、MINISTORY → `ministory` “故事集”、BRANCHLINE → `branchline` “插曲”），没有时看剧情回顾表的 `entryType`
  （ACTIVITY/MINI_ACTIVITY），其余（签到、登录、玩法类）仍是 `activity` “其他活动”；`shelfKinds` 里依次排开。② 复刻不再出现：`isReplicate` 或名字含“复刻”的活动、
  没有链到原活动的 `retroActList` 条目进 `ctx.dropped`，`rebuildDerived` 删掉它们名下的条目/记录/链接/实体（它们没有剧情，只是原活动的重复）。
  ③ 皮肤文本：`description/dialog/content/usage` 互相重复段落，按行去重（`_distinctParagraphs`）；`_emit` 重写条目时先清掉该条目旧的记录（重算已有库不再叠加）。
  ④ 进度百分比 = 页面首行（`ReadingEntry.progress` 用 `lineIndex`，与“继续阅读第 x 行”一致；“读完”标记仍看 `furthest`）。⑤ 阅读器：段间距（同说话人 14、换人 20）
  大于行距，字体是打包的霞鹜文楷屏幕阅读版（LXGW WenKai Screen v1.522，OFL，`assets/fonts/LXGWWenKaiScreen.ttf` 25.7 MB，`readingFontFamily`），旁白只在“有对白的
  故事”里斜体，纯叙述的故事（月度小队等）正体；`{@nickname}` 阅读时换成“设置 → 资料设置 → 称呼”（`withPlaceholders`，不改库；留空显示“博士”），`{@nbs}` 换成不换行空格。
  阅读页是惰性列表（`CustomScrollView` + `center`：锚点之前的 sliver 往上建、之后的往下建，滚动偏移从锚点算起，不估高度；打开时锚在引用块/续读行上，
  `anchor` 0.25/0.08；“回到引用处”= 滚动归零并换锚点）——任意长的故事打开、跳转、滚动的开销一样（之前一次性建出全部几千行，进页面卡；换小字体没用，
  那不是字体的问题）。进度用已建出的行的 GlobalKey 取屏幕首/末行。列表高度靠滚动逐步校准，所以没有滚动条/不能一键拖到末尾，要连续滑。
  ⑥ 阅读历史没有条数上限，按页读取（`readingPageProvider`：LIMIT/OFFSET，每页 15 条；`readingCountProvider` 给总数），页面上下各有一个分页条：首页/上一页/页码方框（当前页附近 + 首尾，中间省略号）/下一页/末页，点“第 x / y 页”输入页码跳转；资料首页只取最新 5 条。⑥b 读过与次数（用户库 v4：`completed_count`/`pass_start`/`pass_done`，逻辑在 `ReadingEntry.afterProgress`，内存与 SQL 两种 store 共用）：不再有“永久读完”标记，改为“趟”——打开时开一趟；一趟在 `pass_start` ≤ 全文 15% 处起头、且末 3 行在屏幕上停留 `readingEndDwell`（3 秒，阅读页的计时器）才算读到末尾，计数 +1（从引用处跳进中段再滚到底只是查阅，不计）；已读完的故事再从列表打开时从头开始，回到前 15% 就开新一趟（旧计数保留，`finished` = 当前这趟已到末尾，`hasCompleted` = 至少读过一次）。列表标记：当前趟的百分比 + ✓，第 2 次起 “×N”，N>999 显示 “999+”（`ReadTimesBadge`，提示里和历史页文字里是完整次数）；旧库里读到末尾的算读过 1 次。⑦ 没有结局书的主题（rogue_1）：`ending_<n>` 的结局对应文件 `level_*ending_<n>` 作为它自己的剧情（组 `结局`，`part_of`），
  `level_*_entry` 一律是开局剧情；条目页的“自己的故事”按组 `结局` 认，不再靠和结局同名。
- **0.11 资料页学名核对（2026-10-05，未发布，需重算知识库）**：界面里凡由代码推出来的名词，一律以游戏表或 prts.wiki 为准，查不到的不起名
  （无标题好过臆造）。表里有名字的构建时直接取：奖章分组取 `medal_table.medalTypeData`（履历/章节/剿灭/保全/成长/记录/基建/活动/远行/加密奖章，
  类型名“勋章”→“奖章”）；`roguelike_buff` 的分组名构建时写进 `group_name`（`_buffKind`：表里 `innerName` 全带“X：”前缀就取 X，否则查
  `_buffKinds`——幻觉/排异反应/乌托邦，来自各模式的 wiki 页面）。界面标签 `groupLabel`：剧目（capsule）、密文板（totem）、调查装备、思绪（fragment）、
  通宝（copper）、零件（scrap）、黄色襁褓生灵（legacy）/蓝色襁褓生灵（`<主题>_start_<n>`）；没有可靠名字的（copper_buff、totem_effect、wrath、
  rogue_2 的分队加成）不显示标题。活动档案的 logs 是“行动日志”（不是“探索记录”）。规则的计数器/票券（占卜工具、票券、投钱数量、存券数量）和通宝的加成孪生（copper_buff）不再导入。新主题出现时：`rederive_gamedata.dart` 末尾会打印“unnamed kind: <主题> <类型> <分组>”，逐个去 prts.wiki 查名字再补进 `groupLabel` / `_buffKinds`，查不到的保持无标题，不要按代码字面起名。
- **0.11 肉鸽页第六轮（2026-10-05，未发布，需重算知识库）**：⓪ 收藏品去重（`rebuildDerived`）：同主题、同名且（同类 `group_name`，或导入后文字完全相同——钱币与它的加成、物品与它的票券、按槽位重复的变异加成）的 `roguelike_item`/`roguelike_buff` 只留一条；同名但文字不同且不同类的（钱币 vs 加成的修订措辞）保留两条
  （优先新表 `roguelike_topic_table`，再取最短 id），链接改指向保留的一条。原因：rogue_1 的新旧两张表各列一遍；rogue_5 的钱币每枚有 4 个朝向、
  新旧各一套、每套 a–k 共 11 个附加词条变体（差别只在不导入的玩法行），3502 条 → 539；rogue_6 传承物按阶段重复。
  ① 事件的选项按层折叠：`event_outline.dart` 的 `eventOutline`——表里只有
  “选项→下一场景”，没有“场景提供哪些选项”，层是按选项在表里的排列读出来的：没有 `nextSceneId` 的选项开一层，其后的选项（到下一个这样的选项为止）
  属于这一层；与选项同号的场景（`scene_<词干>_<n>`，没有任何选项指向它）是选这个选项时先出现的文字，再接 `nextSceneId` 的场景；文字相同的变体合并，
  整层与前面某层完全相同则不再列。事件开场文字只取没有选项指向、也不是某个选项的结果的场景。存成 `## 选项` 下用 `-`/`--`/`---` 表示深度的列表
  （不用缩进：长文被 `splitText` 切成多条记录，记录开头的空白会被去掉），界面 `EventText` 画成嵌套折叠行；`entryTexts` 把 markdown 类条目的多条记录
  按 raw_id 拼成一整篇。② 集合页“注释”不再是一个大类，是一个折叠行，展开后列出各条注释，点进条目页。`## 选择后` 小节取消（旧库仍能显示）。
- **0.11 肉鸽页第五轮（2026-10-05，未发布，需重算知识库）**：① 肉鸽关卡的敌人绑定丢了：`_purgeSource` 曾按 `src/dst IN (被清掉的条目)` 删链接，
  把关卡文件写的 `appears_in` 一起删了——现在只删“本表自己写的链接”（`source_path = 表`），其余留着按 id 重新对上；
  `EntryImporter.importLevels()`（rederive 工具里调用）可重新绑定敌人↔关卡。② 事件条目（markdown，`markdownEntryTypes`）= `## 事件`（没有任何选项指向的场景，
  即开场文字）+ `## 选项`（选项标题去重，有散文说明的带上）+ `## 选择后`（选项指向的场景文字；文字相同的变体合并，标题并列）。
  场景↔选项靠 id 词干，选项→场景靠 `nextSceneId`；表里没有“某场景提供哪些选项”，所以是按词干归在同一事件下。③ 表里没有区域↔事件/加成的关系
  （区域的 `buffDescription` 是玩法文字），区域页只关联关卡。④ `roguelike_tip`=“注释”，和结局、月度小队一样是集合页的 inline 条目（`inlineEntryTypes`），
  排在开局剧情前；区域…勋章等资料类型放在“相关资料”标题下。
- **0.11 肉鸽页第四轮（2026-10-05，未发布，需重算知识库）**：① 类型显示名去掉“集成战略”前缀（`entryTypeName`；目录标签 `ROGUELIKE` 不再加前缀；
  `_typeLabels` 里写进记录 `section` 的仍带前缀，利于检索）。② 区域：游戏按“层位”重复列同一区域（rogue_3 有 337 条，文字相同、只差 id），
  构建时按“名字+去掉规则行后的文字”去重（`_prose`：逐行去掉玩法行），仍同名的编号；关卡按 `levelId` 的 `_<区>-<序>` 归到 `zone_<区>`，
  写 `belongs_to`（区域页的“包含 · 关卡”）。表里没有事件/加成与区域的关系（`rollNodeData` 只有传送门区域的节点类型，`relics` 里的 zone 是机制参数），所以不做。
  ③ 事件：场景与选项在表里没有互相列出，只靠 id 词干相连（`scene_<主题>_<词干>_enter/_2`、`choice_<主题>_<词干>_1`，`choice.nextSceneId` 指向下一场景）；
  构建按词干把同一事件的场景与选项合成一个 `roguelike_scene` 条目（场景依次，末尾“选项”列出标题与通向的场景，效果文字略去），
  不再有 `roguelike_choice` 条目（rogue_6：338 场景 + 396 选项 → 59 个事件）。
- **0.11 肉鸽页第三轮（2026-10-05，未发布，需重算知识库；本地 release APK 供开发者试装）**：肉鸽主题页改为一页读完。
  构建（`entry_importer.dart`/`story_naming.dart`，全部来自表里的 id 关系）：`StoryHint.parent` + 新链接关系 `part_of`——结局书的页面
  （`clientEndbookItemDatas`）与结局同名的故事（`avgId`，排在最后）属于结局（`endbook.endingId`），月度小队的三段故事（`monthSquad.chatId`
  → `archiveComp.chat`）属于小队，`rebuildDerived` 写链接；顺序用故事的 `sort_key`。小队条目：分组=年月、文字=一句话（英文/自造语言的副标题不导入）、
  `features` 链接到主角干员；`roguelike_topic` 的文字作为集合简介。关卡：`isElite` 的名字加“· 突袭”，有突袭孪生的普通关加“· 普通”，同名同关卡去重，仍同名的编号；
  提示只留“词——解释”型（其余是玩法提示）；`feature` 类收藏品（机制物品）不导入。`_purgeSource` 让 `roguelike_topic`/旧肉鸽表的重导入先清掉旧条目
  （否则规则变了旧行还在）。类型显示名：`roguelike_squad`=月度小队（游戏表里的叫法），`roguelike_tip`=背景词条。
  界面：集合页 = 简介 + 结局/月度小队行（`inlineEntries`）+ 没有归属的剧情（“其他剧情”）+ 资料类型菜单，不再有“剧情”“相关资料”标题；条目页的“包含的故事”
  （`entryParts`）；小队的“涉及”显示为“主角”。已上线的 pre.4 库没有这些结构，需要重新下载知识库。

- **0.11 资料页第二轮修正（2026-10-05，未发布，需重算知识库）**：真机再反馈四点。① 编码残留不止一层：阅读页标题/续读卡/历史/证据链
  用的是 `story_catalog`（只含 71% 的故事）+ 路径兜底，所以训练、肉鸽等仍显示文件名——`queryCatalogEntries` 现在对目录没有的故事
  从条目层（`entries`+`collections`）取名字（`集成战略·主题 分组《名》`），历史/续读卡显示“当前名字”（`storyLabelProvider`，库不认识时才用存的旧标题）；
  列表里的分组码（关卡的 zone id、`TRADE`/`copper_buff`/物品类型、邮件发件人 id、活动文本的键名）：构建时 `rebuildDerived` 把关卡分组换成章节名、
  邮件发件人换成干员名、其余 id 型分组置空，界面用 `groupLabel()` 给游戏枚举取中文名，没有名字的不显示原码；`operator_stage` 的 `code`
  （`mem_x_1`）、活动的 `type`（`VEC_BREAK_V2`）不再当代号；模组的代号改为型号（`X`/`Y`）；没有表给名字的故事目录
  （`bossrush`、`arkhub`）按 id 后缀并入对应活动，否则归“其他”系统集合，不再以文件夹名显示。② 集成战略：集合页的故事按分组（结局/分队…）折叠，
  相关资料按 `typeRank` 排序，长列表（收藏品、事件选项…）先出分类菜单（`entryGroups` → `EntryListPage(groups:)`）；`feature` 类收藏品
  是规则替身（“机制物品”），不再导入。③ 干员页：档案放在最前并按 markdown 渲染（`MarkdownText`）。④ `character_table` 里 `profession`
  为 TOKEN/TRAP 的是召唤物/装置，之前被当成干员：条目类型拆成 `token`/`trap`（id 仍是 `operator:<charId>`，在图鉴里显示为“召唤物”“装置”）；
  `RCX7` 是游戏自带的干员编号（`displayNumber`），界面写成“编号 RCX7”，不再当前缀。给已有的库补算：`rederive_gamedata.dart`（现在也重导角色表）。
  产物 `build/gamedata_v5/rederived.db`，发布前需压缩并作为新资产上传。

- **0.11 资料页修正（2026-10-05，未发布，需重建/重算知识库）**：真机反馈三点。① 训练/指引/教程/肉鸽/生息演算的剧情用的是解包文件名：
  新增 `build/story_naming.dart`（`rebuildDerived` 里调用）——名字优先级：表里给文件本身的名字（肉鸽 `archiveComp.endbook/chat`、
  生息演算 NPC 对话 `picName`、档案条目 `reads_story`）→ 所属关卡（`level_<关卡>_beg/end`、`training_<集合>_<nn>_x` → 关卡 `<集合>_tr<nn>`、
  `levelId` 文件名、关卡 id；训练文件只认 `tr` 关卡，不会落到同号的章节关卡）并写 `belongs_to_stage` → 只能判断类型时
  按类型编号（`训练 3`，自然序）。全部来自 id 结构与表，没有任何故事/活动/人名。实测（上游 a550f5e）：非中文名字的故事 1676 → 39（剩下的是
  “6:44P.M.” 这类真实标题和 NPC 名）。② 复刻不再是书架：`retro_table.linkedActId` 指向原活动，复刻的区域/关卡并入原活动（无链接的才保留为活动）。
  ③ 干员页：`operatorShelf`（=`memory`）书架列干员，`OperatorPage` 汇集密录集（`collections.parent_id`）、模组/皮肤/悖论模拟关卡
  （`belongs_to` 干员的条目）与档案；图鉴不再单列这些类型和干员；`operator_stage` 显示名改为“悖论模拟”。
  给已有的库补算：`dart run tools/rederive_gamedata.dart --db=<库> --source=notes/src --output=<新库>`（重导条目表 + `rebuildDerived` + FTS，
  不动故事与向量）。上线前需把新库作为知识库资产重新发布。

- **预发布 v0.11.0-pre.2（2026-10-05）**：pre.1 在真机上知识库下载一直停在“下载中”、进度条不动（部分文件夹里只有 `.download.gz.key`，没有
  `.download.gz`：等不到服务器应答）。桌面上用 `test/live/release_asset_install_live_test.dart`（`ARKLORES_RUN_ASSET_INSTALL=true` +
  `ARKLORES_ASSET_URL/SHA`）完整装了这个资产（下载 39 s、安装 44 s），所以资产与安装代码没问题，真机根因未能复现（疑为手机到
  `release-assets.githubusercontent.com` 的连接卡住）。修复的是“看不见、出不来”：`installFromReleaseAsset` 报告阶段
  （连接第 n 次/下载/校验/解压安装），连接超时 45 s、最多 6 次、每次新连接；页面显示阶段与“取消”，连接第 2 次起提示手动下载
  （把 Release 里的 `.gz` 改名为 `arklores_gamedata_zh.db.download.gz` 放进应用目录，点“下载”即按断点续传逻辑校验并安装，无需 key 文件）；
  失败且没有部分文件时不再留下 `.key`。知识库附件随 pre.2 一起上传，`release_gamedata.env` 指向 pre.2。
- **预发布 v0.11.0-pre.1（2026-10-05）**：0.11 第 1–5 步的首个预发布（`pubspec` 0.11.0-pre.1+23）；知识库资产（schema 5，含向量，
  195 MB gz）作为该 Release 的附件，`tools/release_gamedata.env` 已指向它。旧的 PR #8 已关闭并删除远端分支；
  之后的 0.11 工作从 `release/v0.11.0-pre.1` 之后继续（本地分支 `feature/v0.11-library`）。

- **0.11 第 5 步：可阅读资料页（2026-10-05，同一分支，未发布）**：
  - **“资料”标签页**（`features/materials/materials_page.dart`，原“暂停”占位被替换）：顶栏与 Ask 页一致的 TabBar [阅读 | 我的资料]。
    阅读：继续阅读卡（最近一篇，含进度）→ 书架（`collections.kind`：主线/活动/干员密录/集成战略/生息演算/复刻 + 图鉴=无归属条目类型）→ 最近阅读。
    书架页 → 集合页（章节列表带官方梗概与已读进度、相关资料入口：关卡/敌人/藏品/事件…）→ 条目列表页（可筛选）→ 条目页
    （文字去标记 + `entry_links` 绑定，可点进相关条目）；右上角搜索（集合名、条目名、关卡代号）。全部页面代码在 `features/library/`。
  - **读取**：`core/library/library_queries.dart`（纯函数，只读，全部由 schema 派生：书架=collections.kind、列表=entries.type、顺序=sort_key，
    不出现任何具体名字）+ `library_provider.dart`；`GameDataKnowledgeStore.withDatabase` 借用已打开的只读连接。旧库（schema 4）
    给出“知识库需要更新”提示而不是崩。显示名（条目类型、绑定动词）在 `library_labels.dart`。
  - **阅读页**（`story_reader_page.dart`）三种打开方式：引用（高亮）、续读（定位到上次的行，左侧竖线标记）、资料页（从头）；
    每行一个 GlobalKey，滚动结束时二分查视口首行/末行，防抖写入用户库（锚点=首行，`furthest`=末行只增不减，`total_lines`）；章末“上一章/下一章”
    （同集合 `sort_key` 邻居）；非对白行显示 `字幕/文档/选项` 小标记。第 4 步的三个局限（只有证据链进历史、记的是引用行、历史只认故事）
    由此解决；非故事条目很短，不记历史。
  - **用户库升到 v3**：v2 = `reading_history.total_lines/furthest`，v3 = `materials`（我的资料：新建、从剪贴板导入、编辑、删除、阅读；
    只存在本机，不进知识库）。迁移只追加。资料页的“用它提问”把资料文字（≤1500 字）放进提问框草稿并切到 Ask 页，由用户补完问题再发送；
    **不改 agent**，资料只是用户提供的上下文，不是证据（`handoff_provider.dart`）。
  - **验证**：纯 Dart 查询在合成条目层上有单测，并在真实 schema 5 库（上游 a550f5e）上核过：3660 个故事全部有条目、有名字、有归属，
    且 `story_lines` 里没有无条目的故事（都能从书架走到）；查询均 <30 ms。界面在 Ahem 字体下做了布局截图检查
    （`ARKLORES_SHOT_DIR=<目录> flutter test test/features/library/library_ui_test.dart` 导出 PNG，仅看布局不看字形）。
  - **已知局限**：数据层——主线章 `main_14` 的关卡被归到它的复刻活动（上一步已记的“活动与其复刻共用关卡，归属复刻”），所以该章页面没有关卡/敌人；
    要修需在 `entry_importer` 里让主线关卡按 id 前缀归主线章并重建库。App 端——条目类型与绑定的显示名只有中文
    （长故事的惰性渲染见上面“活动分类、阅读器与设置”一条）。真机待确认：书架网格观感、阅读页滚动保存的进度、续读定位。
- **0.11 第 4 步：用户库与阅读历史（2026-10-05，同一分支，未发布）**：
  - **用户库** `lib/core/userdata/`：独立文件 `<documents>/userdata/arklores_user.db`（与知识库不同目录，不 ATTACH、不建外键，
    知识库更新/替换/删除都碰不到它）。结构版本用 `PRAGMA user_version`，由 `UserDataStore` 自己管理（`userDataMigrations`，
    只追加不改已发布的步骤；不用 sqflite 的 version，因为较新 App 写的文件会被它降级盖章）；较新文件照常打开、不降级。
  - **条目引用** `LibraryRef`（`story:<story_id>`、`record:<id>`、`document:<实体>/<类型>`、`user:<id>`）：用户库只存引用字符串，
    目标消失时引用仍能解析，界面提示而不是崩。
  - **阅读历史**只存“条目 + 一行锚点 + 该行原文开头 60 字”（`reading_history`，每条目一行，不设上限）；知识库变动后用
    `reanchorLine` 按原文片段找回位置（原位置还在 → 最近的同文行 → 夹到范围内并提示“已定位到大致位置”）。
    （第 5 步在阅读页里补了真正的阅读位置与进度：见上，用户库 v2。）
  - **界面**：阅读页 `story_reader_page.dart` 打开时写历史（`ReadingHistoryPage`：Ask 页顶栏书本图标，点条目回到锚点行，
    左滑删除、清空）。第 5 步的资料页复用这套用户库，不要另建文件。

- **0.11 第 3 步：增量更新通道（2026-10-05，同一分支，未发布）**：
  - **用户**：知识库页“检查更新”显示上游变化（剧情/数据表/关卡文件数），“构建”做增量更新（只下变化的文件 + 缺的上下文数据表，
    不拉 850 MB 仓库；`SourceSync`、`.source_commit` 标记），完成后显示**更新报告**（`UpdateReport`），下面的“故事向量”卡片
    （`story_vector_provider.dart` + `story_vector_updater.dart`）显示缺多少向量、约多少 token、按百炼价格约多少钱，
    没配向量服务时提示在哪里配置（设置 → API 设置 → 向量），模型/维度与已有向量不一致时拒绝混用；首次完整生成会先确认。
  - **开发者**：`tools/update_gamedata.dart`（`--source=<源目录>`，`--embed` 才嵌入，不加只打印计划；`--replace`、`--vectors-only`）。
    与 App 同一套代码，另外会应用变化的关卡文件。
  - 费用常数来自实测：0.706 token/字；¥0.0005/千 token 是按百炼公开价格的**估算**，以账单为准（常量在 `story_vector_updater.dart`）。
  - 变化超过 3000 个文件（compare API 上限）或库是旧 schema 时退回完整重建；GitHub 匿名额度 60 次/小时，增量只用几次。
  - 下一步：第 4 步（见上）完成后是第 5 步：可阅读资料页（阅读器 + 用户资料）。

- **0.11 第 2 步：知识库扩充与重构（2026-10-05，分支 `feature/v0.11-library`，未发布）**：
  - **按条目建模（schema 5）**：每个官方条目（故事、干员、敌人、关卡、物品、藏品、肉鸽事件…）一行 `entries`，归属某个 `collections`
    （主线章、活动、干员密录、肉鸽主题、沙盘、复刻），文字在 `normalized_records`（`entry_id`），条目间绑定在 `entry_links`
    （敌人 `appears_in` 关卡来自 `levels/` 的出场表；关卡 `belongs_to` 地区；剧情 `belongs_to_stage` 关卡…）；视图
    `collection_enemies` 直接给出“同一故事集/活动/肉鸽主题里的敌人”。实现：`entry_importer.dart`、`text_harvest.dart`；
    详见 `docs/GAMEDATA_BUILD_PIPELINE.md` “条目层”一节。
  - **剧情脚本全量解析**（`story_script.dart`）：旧解析器只认 `[name="X"]文本`，丢了约 4% 的行和 885 个文件（场景字幕、书信/日记、
    玩家选项、其他对白写法、教程）；现在每行带 `kind`，读章/搜索时非对白行显示 `[字幕]` `[文档]` `[选项]` 等标记。
  - **不收玩法文字**（开发者决定）：技能/天赋/规则/效果/获得方式一律不进库；**敌人技能描述不进库**（实测 75% 是机制用语，
    对“召唤/复活/重生/隐匿”这类词的命中数是剧情台词的 3–7 倍，会淹没检索且没有设定内容），只保留敌人的设定描述和出场绑定。
    教程/引导文字保留在 `story_lines`（`kind=system`）但不进检索块和向量。
  - **向量迁移**：两次构建之间上游把全文的“......”统一成“……”，哈希缓存全部失效；改为按行对齐迁移
    （`build_story_embeddings.dart --migrate-from=<旧库>`，旧库 51,264 条向量全部迁移，只嵌入新增的 4,309 块）。
  - 实测（上游 a550f5e，2026-09-29）：29,987 个条目、788 个集合（活动 327、密录 387、复刻 44、主线 18、肉鸽 6…）、35,283 条绑定
    （敌人↔关卡 26,048，剧情→关卡 1,440）、436,823 行剧情、55,573 条向量，库 643 MB；`flutter test` 316 通过；重建后用
    `test/live/gamedata_v5_acceptance_test.dart`（`ARKLORES_RUN_DB_CHECK=true`）和 `tools/check_gamedata_retrieval.dart` 验收。
    记录的 `section` 是条目类型的中文名（“集成战略收藏品”“关卡”“敌人”…），`title` 是“集合名 · 条目名”，方便按玩家的叫法检索。
  - **发版前必须先发 schema 5 的知识库资产**：App 现在只接受 schema 5，`tools/release_gamedata.env` 仍指向 v0.10.0 的 schema 4 资产，
    直接发 App 会装不上知识库（已装的旧库仍可读，但没有条目层）。
  - **待办（第 3 步起）**：App 内增量更新目前不下载 `levels/`（敌人绑定保持不变）；故事目录 `story_catalog` 仍只覆盖 71%，
    其余按路径归属（`collections` 已有）；阅读目录/资料页在最后一步用 `collections` + `entries` 做。

- **v0.10.0 正式版（2026-10-04）**：下面 v0.10.1–v0.10.7 的各条都是并入它的开发迭代（对应的预发布、`release/*` 与 `feature/*` 分支、旧 PR 已删除，只留 `main`）。
  输入框收起时是两行（文字一行 + 工具栏一行）。

- v0.10.7（2026-10-04，同一分支，已发布预发布）：① 删除 自动/概括/核查/回答 模式、`QuestionRouter`、
  三个转发 agent 和 `AnswerStyle`（一份提示词，核查 verdict 保留，旧会话仍能打开）；② 输入框 `ask_composer.dart`：更宽、
  随文字长到 4 行、可展开到半屏/全屏；③ 来源卡片紧凑 + 同故事集分组缩进；④ 回答下面一行灰色小字显示用量（输入/缓存率/
  输出/调用数/用时，也存进会话文件 `usage` 与逐次 `timeline`）；⑤ **速度**：`story_lines(story_id, line_index)` 一直没有索引，
  每次读章/grep 上下文/出处核对都全表扫描（约 0.45 s 一次，一次回答几十次，出处核对一次 19 s）——现在首次打开旧库时自动建索引
  （`GameDataKnowledgeStore._ensureStoryLinesIndex`，约 1 s、+20 MB），新构建自带；实测数据库耗时从 ~45 s 降到 <6 s。
  测量结论见 `docs/R17_TOOL_AGENT.md` 速度一节（并发 ≥5 不被限流；带工具的调用有 4.5–6 s 的服务商底噪，与是否流式无关；
  答案文本写 3 遍占 ~55%）。**待开发者真机确认**：输入框展开手感与动画、来源卡片紧凑度、首次问答建索引的耗时、
  用量行显示。
- v0.10.6（2026-10-04，分支 `feature/r18-answer-quality`，已发布预发布）：修手机真机发现的四件事——
  ① 证据链消失（GLM 平铺 `cite`，提示词补骨架 + 解析容错 + 零出处退回，见 R17 一节）；② 知识库页“更新”按钮在已是最新时仍可点
  （现在显示“已是最新”+ 带确认的“重新下载”）；③ 长时操作退后台被截断（`BackgroundWork` 前台 service，见 R16 一节“后台”）；
  ④ 审稿并非不同流程，是随机（日志证实审稿在手机上也运行了）。已在本机装好 Android SDK/JDK，Kotlin/清单已用 debug 包编译验证，
  **待开发者真机确认**：长问题退后台超过 1 分钟后能否完成（会出现一条常驻通知，Android 13+ 首次会询问通知权限）、证据链是否出现。
- v0.10.5（2026-10-04，同一分支）：默认改用智谱 `glm-5.3-flash`（`reasoning_effort` 控制思考）；原文阅读页重排；
  每条答案下的出处改成可折叠胶囊。**待开发者真机确认**阅读页与出处的观感，以及 GLM 每题约 4 分钟的耗时是否可接受
  （带工具的轮次智谱不逐字流式，见下文 R16 一节；live 数据见 `docs/R17_TOOL_AGENT.md` R18 表后）。
- v0.10.4（2026-10-03，R18，分支 `feature/r18-answer-quality`）：Release 已由本机补建。内容：§5.9 答案质量——审稿子 agent（读者视角，
  只提本故事后段揭示/其他故事层面的待核实问题，主 agent 回原文核实后重写）+ 按阶段整理（详细版折叠在 `[DETAILS]` 下，
  每段出处由代码合并，段数只软性提示）+ 重写后只有过程话时的兜底。复测数据见 `docs/R17_TOOL_AGENT.md` §2「R18」。
  **待开发者真机确认**：答案开头是否交代故事性质、整理段落的可读性、“详细经过”折叠与流式手感
  （v0.10.3 的 R17d 界面项也一并确认）。
- 开发可在本机（Windows）或云端（环境 ArkLores-Cloud，见 `docs/CLOUD_DEV.md`）进行。

## 文档索引

- `docs/CLOUD_DEV.md`：云端会话的环境、每次开始要跑的脚本、能做/不能做的事、发版。
- `docs/AI_ARCHITECTURE.md`：Agent 与检索架构（当前状态 + 演进简史）——改 agent/检索层前先读。
- `docs/LIBRARY_AGENT_GUIDE.md`：资料页结构说明（问答 Agent 查库前参考；正文在 `loreLibraryGuide`）。
- `test/README.md`：测试目录（与 `lib/` 一一对应）、共用夹具、约定（测试库一律用生产 schema，不手写表）、没有自动测试的部分。
- `docs/R17_TOOL_AGENT.md`：剧情问答 Agent 的结构、工具、子 agent、出处核对与验收数据。
- `docs/KNOWN_LIMITATIONS_AND_DEBT.md`：已知限制与根因。
- `docs/RETRIEVAL_QA.md`：验收清单（离线 + 真机同链路）。
- `docs/GAMEDATA_BUILD_PIPELINE.md`：数据构建、向量、发布。
- `docs/R12_BOTTLENECK_ANALYSIS.md`：R12 决策记录。
- `docs/ARKLORES_V0.9_TECHNICAL_REPORT.md`：v0.9 审计快照（不再更新）。

## Do

- Linux 使用 `/home/hhikr/flutter/bin/flutter`；Windows 使用 `C:\src\flutter\bin\flutter`
  （已在 PATH）；云端会话里是 `/opt/flutter`（已链接到 `/usr/local/bin/flutter`）。
- **云端会话**（环境变量 `CLAUDE_CODE_REMOTE=true`）开始时先运行 `bash tools/cloud/session_start.sh`
  （git 作者、key 文件、pub get）；需要知识库时 `bash tools/cloud/fetch_gamedata.sh`。详见 `docs/CLOUD_DEV.md`。
- 保护 `logs/`。
- 保持 GameData 为 Agent 主知识源。
- 保留 source path、raw id、content type、entity id。
- 剧情问答 Agent 只查本地 GameData 库（`lore_tools.dart`），角色扮演只用 `search_local_lore`；Wiki 和用户文本只能作为浏览/上下文。
- 运行相关 tests / analyze 后再汇报。

## Do Not

- 不往知识库里导入玩法文字（技能、天赋、基建、商店、规则/任务说明、效果与数值、获得方式、敌人技能描述）；新增数据源先判断
  “对剧情有没有参考价值”。叙事文字的收集规则是通用的（`text_harvest.dart`：路径关键词 + 文字特征），不写活动名/剧情名/人物名表，
  也不为某个活动补特例。
- 条目的归属与绑定只来自表里的 id（zone→activity、id 前缀=集合 id、`levelId`、`charId`、关卡文件的出场表），不用名字猜。

- 不恢复旧 Wiki seed 运行链路。
- 不恢复旧用户资料索引链路。
- 不提交 API key、token、`.env`。
- 不直接 push `main` 或 `dev`。

## 发布与签名（v0.10.0 起）

- APK 由 GitHub Actions 构建：把要发布的提交推到 `release/<版本>` 分支即触发
  `android-release.yml`，产物在该次运行的 artifact 中。GameData 资产的 URL/SHA 在
  `tools/release_gamedata.env`，每次数据发版都要更新。
- App 发布一条命令（默认建预发布；加 `-Stable`（ps1）/ 环境变量 `STABLE=1`（sh）建正式版）：先改版本号/文档并提交推送，再运行 `tools/release_app.ps1 -Version <v> -NotesFile <md>`（Windows，
  PAT）或 `tools/release_app.sh <v> <md>`（Linux/云端，`gh`）：推 `release/v<v>` → 等 CI → 下载 APK → 建预发布。
  发版前必须得到开发者明确同意。云端会话不能创建 Release（403），最后一步由开发者完成，见 `docs/CLOUD_DEV.md`。
- 签名用项目 release keystore（仓库 secrets：`ANDROID_KEYSTORE_BASE64` 等）；workflow
  会校验证书 SHA-256 为 `b1b09ebf…e364`。本地备份 `tools/arklores-release.jks` +
  `tools/android_signing.properties`（gitignored），绝不提交、绝不打印。
- 本地 `flutter build apk --release` 没有 `android/key.properties` 时会退回 debug key，
  这样的包不能发布。
- CI（`ci.yml`）在 PR 上跑 analyze 与 test。
- Android 工具链：Flutter 3.47.5、Gradle 8.14.3、AGP 8.11.1、Kotlin 2.2.20、Java 17
  （Flutter 3.47 的最低要求）；Linux 本地构建也需要升级到同一 Flutter 版本。
- `release/<版本>` 分支只放构建 APK 的那个提交：再推送会重新构建，产出的 APK 哈希也会变。

## 提交规范（贡献者只有 hhikr）

- 提交的 author / committer 只能是 hhikr。
- 提交信息中**禁止**出现 `Co-Authored-By` 或任何把 AI 写为作者/协作者的
  尾注或署名（如 "Generated with ..."）；未经开发者明确许可不得添加。
- 2026-10 已改写全部历史移除旧的 Claude 协作者尾注；不要再引入。
- `.claude/settings.json` 的 `attribution` 已关闭 Claude Code 自动加的协作者尾注、PR 署名和 `Claude-Session` 尾注；不要改回。
- 凭据（`tools/api_info`、`tools/*apiKey*`、`tools/github_pat`）不得提交、
  打印、写入 git 配置或 remote URL。

## 检索与数据设计原则（防桥段专项优化）

背景教训：`story_chapter_profiles.keyword_hits` 曾内置 20 个死亡/凶案词做
`content.contains` 命中统计，围绕"凶手问题"用例设计；该桥段在真实问题分布中
占比极小，专项优化覆盖面趋近于零，还会把模型锚定向单一方向（2026-08 已移除）。
任何 agent 改动检索/数据层前必须过以下检查：

1. **只做桥段无关的通用机制**：可达性（原文/行级可读）、确定性覆盖（出场枚举）、
   通用信号（IDF 稀有词、实体密度）、可对比的证据集。新特征对"任意剧情问题"
   仍应有意义；只对某一类桥段有意义的特征一律拒绝。
2. **先量化再立项**：新增检索特征前，评估该用例在真实问题分布中的占比；占比
   极小的用例只能作为验收样例（QA fixture），不得驱动 schema / 特征设计。
3. **禁止硬编码"场景词典"作为检索特征**：如"死亡/凶案词表"这类为具体剧情桥段
   定制的词表。模型推理需要场景知识时，交给 Agent 在通用检索结果上自行完成，
   不要在数据层预置方向。
4. **可复现且来源清晰**：每个检索特征必须解释得清它从哪些源字段、用什么确定性
   规则算出来；构建两次结果一致，便于增量对比。
5. **不制造隐性证据**：检索/画像字段只能是"浏览提示或定位线索"，绝不参与事实
   判定或推理打分；判定只能由 Agent 基于检索到的原文形成。

## 禁止特判（R13，开发者硬性要求）

**特判**：任何只对某一类问题或某种剧情桥段生效的代码分支、阈值、提示词步骤或输出
字段。反例（均已在 R13 删除）："至少比较 2 个嫌疑人才能下结论"的门槛、`culprit=`
结论信封、"仅当问题问谁导致时"的提示词步骤、为凶手/死亡类问题定制的工具命名。

1. 所有剧情问题走同一条流程（`StoryQaAgent` → `LoreAgentLoop`）：同一份系统提示、同一套工具、
   引用校验与 `[STORY_ANSWER: status=…]` 状态。
2. 没有任何模式或分支（v0.10.7 起删除了 自动/概括/核查/回答 四种模式、`QuestionRouter` 和 `AnswerStyle`）：
   一份系统提示，其中的“条目安排”（`loreEntryLayout`）只讲输出格式——先直接回答/概述，再分小节；用户要求核查某个说法时
   JSON 以 `verdict` 开头（结论由代码按“有读过并引用的原文”降级）。这是模型按问题自己选的**输出格式**，
   不得因此改变检索或判定规则。
3. 新增任何特判一律拒绝；以后也不许再写。修改后自查：

   ```bash
   grep -rnE "culprit|suspect|嫌疑|凶手|罪魁" lib/
   ```

   结果必须为空（`test/guards/no_special_case_test.dart` 在 `flutter test` 中守卫这一点）。
   换成任意其他类型的问题（"怎样""什么关系""在哪"），逻辑路径应完全相同。

## 禁止针对验收样例编程（anti-fixture-hardcoding）

背景教训（R11，2026-08）：调查死循环修复曾以"导致特蕾西娅死亡的罪魁祸首是谁"
为真机验收样例。该样例必须只作为**测试 fixture 与人工验收场景**，绝不进入
产品逻辑。任何 agent 改动 agent/检索/数据层前必须自查：

1. **产品代码（`lib/`）不得出现具体实体名/实体 id/剧情桥段字面量作为判定分支
   或特征**：如"特蕾西娅→选魔王候选""凶手问题→xx"这类针对特定问题的特判。
   实体名只能出现在注释/示例文案/测试 fixture 中；判定必须消费运行时输入
   （当前 query、候选列表、状态），而非固定值。
2. **通用机制验证方法**：新逻辑若只对某个样例有效而对"任意剧情问题"无意义，
   一律拒绝（与上方第 1 条同理）。修改后可自测：把样例换成一个不相关实体
   （如"阿米娅的某件事是谁做的"）或虚构实体，逻辑路径应同样成立。
3. **测试 fixture 允许具体实体**（它们是模拟输入，不是产品逻辑），但不得把
   fixture 里的具体 id/名字复制进 `lib/` 的判定条件；测试断言只验证通用行为
   （如"选了候选而非无脑选第一个""重复搜索被终结"），不验证某个具体实体
   被特殊对待。
4. **自查命令**：改动后运行
   `grep -rn "特蕾西娅\|enemy_1554\|enemy_3006\|trap_762" lib/`，
   结果应只有注释/文案；任何出现在 `if`/`switch`/数据结构键/检索参数中的
   具体实体，都必须证明其通用性（如来自运行时候选列表）。

## Useful Commands

```bash
/home/hhikr/flutter/bin/flutter test test/core/agent
/home/hhikr/flutter/bin/flutter test
/home/hhikr/flutter/bin/flutter analyze
/home/hhikr/flutter/bin/dart run tools/build_gamedata_database.dart --help
HOME=/tmp /home/hhikr/flutter/bin/dart run tools/check_gamedata_retrieval.dart \
  --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

### Windows（开发机 2026-10 起）

- flutter / dart：`C:\src\flutter\bin`；git：codex 自带
  `C:\Users\hhikr\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe`
  （同目录 `..\usr\bin` 下有 sh、sed；没有 gzip，压缩用 .NET `GZipStream`）。两者已加入用户 PATH；若当前 shell 没刷新，先执行
  `$env:Path = "C:\src\flutter\bin;<git cmd 目录>;$env:Path"`。
- 没有 `gh`：GitHub 操作用 REST API；发布用的 APK 由 GitHub Actions 构建（签名）。
- Android SDK/JDK 装在 `C:\Users\hhikr\dev`（`android-sdk`、`jdk-17`，已用 `flutter config --android-sdk/--jdk-dir` 指定，
  没有写环境变量）：改了 `android/` 下的 Kotlin/清单后用 `flutter build apk --debug` 本机编译检查（debug 包不能发布）。
  Flutter 迁移器会自动往 `android/gradle.properties` 加 `android.builtInKotlin/newDsl=false`，提交前确认是否需要。
- 磁盘：C 盘曾满到 0 字节，`flutter test` 编译失败后卡住半小时。全量测试正常约 25 秒，明显变慢先查剩余空间。
- PowerShell 设置环境变量用 `$env:NAME='value'`，不支持 `NAME=value cmd` 前缀。
- sqflite FFI 会把相对 DB 路径解析到 `.dart_tool` 下，`ARKLORES_GAMEDATA_DB` 等路径要写绝对路径。
- 依赖 POSIX 文件替换语义的测试在 Windows 上跳过；临时目录用 `test/support/temp_dir.dart`
  的 `deleteTempDir`（文件锁时重试）。

```powershell
flutter test
flutter analyze
$env:ARKLORES_RUN_LIVE_ASK='true'; $env:ARKLORES_LIVE_EVAL='test/fixtures/investigation_eval.json'
$env:ARKLORES_LIVE_IDS='frostnova_end'
$env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_mobile\arklores_gamedata_zh_vec.db"
flutter test test/live/ask_pipeline_live_test.dart
```

GitHub PAT 在 gitignored 的 `tools/github_pat`：只在单条命令内用
`git -c "http.extraHeader=Authorization: Basic <base64(x-access-token:PAT)>" ...` 或 REST
请求头使用；不得打印、写入 git 配置或 remote URL。

### 电脑端调查复现（不需真机，与 App 同一条链路）

改完 agent/检索层后，先在电脑上用真实 GameData DB + 真实 LLM 跑一轮，
再真机验证。复现工具是 opt-in 的 live 测试（R12 起取代旧的
`tools/run_investigation.dart`，后者重写了数据层、与 App 不一致，已删除）：

```bash
ARKLORES_RUN_LIVE_ASK=true \
ARKLORES_LIVE_QUERIES="导致特蕾西娅死亡的罪魁祸首是谁||另一个问题" \
flutter test test/live/ask_pipeline_live_test.dart
```

- 驱动的是 App 的 `askChatProvider`（`AskChatNotifier.sendMessage` →
  `StoryQaAgent` → `GameDataKnowledgeStore` → `ChatSessionStore`）；只覆盖 `main.dart` 启动时注入的 provider（API 配置、
  向量配置、会话日志开关）和两个平台路径（DB、会话目录）。SQL 引擎换成
  sqflite FFI，其余每个 Dart 类都是 App 代码。
- 输出：`build/live_sessions/<...>/conversation_*.json`（与 App
  `chat_sessions/`、`logs/` 同格式）+ 每题 `*.summary.json` 指标。
- 追问类用例用 `ARKLORES_LIVE_CONVERSATION=true`：`||` 分隔的问题作为同一会话的连续轮次。
- 输出的 `*.summary.json` 含 `timeline`：每次 LLM 调用的起止、首字节/首 token 延迟、429 等待、token，
  以及每次工具运行和本地检查（`span`）的起止——用来看时间花在哪。
  `ARKLORES_RUN_LIVE_PROBE=true flutter test test/live/concurrency_probe_live_test.dart` 测并发限制（几美分）。
- 可选：`ARKLORES_LIVE_EVAL=test/fixtures/investigation_eval.json`（批量评测）、
  `ARKLORES_LIVE_IDS=a,b`、`ARKLORES_LIVE_NO_EMBEDDING=true`（模拟无向量 key）、
  `ARKLORES_GAMEDATA_DB`、`ARKLORES_LIVE_OUT`。
- 配置从 gitignored 的 `tools/api_info`（API_KEY=/MODEL=/URL=）和
  `tools/embedding-apiKey.csv`（`openAiCompatible`、`apiKey`）读取。
  **绝不提交有效 key**；`tools/*apiKey*` 已加入 .gitignore。

**真实 API 测试的成本约束**（开发者要求，2026-10）：
- 先跑离线测试（mock LLM 复现问题），离线确认之后才动用真实 API。
- 每个方面最多挑 2 个最有代表性的用例（用 `ARKLORES_LIVE_IDS` 过滤），逐题串行跑；
  每题跑完先看结果，有问题立即停止。复杂和边际情况等基础用例通过后再测。
- 不要整批跑 30 题评测，也不要并行开多组评测，除非开发者明确要求。
- 每题的 `*.summary.json` 会记录 `usage`（调用次数和 token 数），用它评估成本。
- 遇到 provider 错误（如 402 余额不足）时，harness 会自动跳过剩余题目。
- 成本取舍（开发者要求，2026-10）：除非这一轮就是专门的降本改动，新机制带来的调用次数/token 增加只要不是
  数量级上的差异，就先不处理，优先答案质量；验收表里照常记录 usage 以便对比。

### 故事目录（可选表，R14）

`story_catalog`（故事集名、关卡号、章名、行动前/后、顺序、官方梗概）来自
`story_review_table.json` + `story/[uc]info/**`，全量/增量构建自动生成；给现有库补表：

```bash
dart run tools/build_story_catalog.dart --db=<db> --source=<ArknightsGameData 稀疏检出>
```

Agent 用 `outline` 看整个故事集的章节梗概，用 `sql` 关联它排序；App 用它把引用显示为故事名。
R15 起目录带 `start_time`（活动上线时间；主线、密录为空），`grep` 全库统计与 `outline` 按它排序 / 显示"上线 yyyy-MM"。

### 名字与身份（R15）

知识库**不判定"谁是谁"**（代号/真名、"？？？"、冒名、夺舍都是剧情解读，写死的身份标注会把错误
当事实喂给模型）。数据层只保证每一跳检索能走通：库中没有的写法给出读音感知的近似名
（`name_similarity.dart`，只陈述"字符串相近"，`sql`/`grep` 零命中时自动附上）；身份由 Agent 在问答时读原文确认。
不要新增别名/身份表来"修"某个具体角色。没有目录表的库照常可用（引用显示由路径推出的名字）。

### 工具型剧情 Agent（R17，唯一流程）

- `LoreAgentLoop`（`lore_agent_loop.dart`）：一个模型 + `lore_tools.dart` 的通用工具（只读 `sql`、`grep`、
  `read_story`、`find`、`outline`、`similar_names`，主 agent 另有 `delegate` 派出并行子 agent），messages 只追加
  （前缀缓存命中约 85–90%）。R8–R16 的 `PlannerLoop` 及其状态/提取器/writer/COVER 等工具已删除（git 历史可查）。
- 不要往这条链路里加手写的进度规则（预算提示、重读拒绝、代码规则复核、阅读计划）：R13–R16 证明这类规则只对样例有效。
  改进方向是工具的表达力、工具输出的信息量和提示词里的通用工作方式。
- 审稿子 agent（R18，开发者同意）不是上面说的复核：它是另一次模型调用，只看问题和去掉出处的答案，以读者身份
  提最多三个“整个故事或其他故事是否改变了答案的理解”的问题；它的了解只是线索，结论由主 agent 读原文决定，
  每题一轮，失败就放行。不要让它逐条核实细节（实测会白白多出十几次调用），也不要给它加针对某类剧情的检查项。
- 按阶段整理（R18）：答案 JSON 有 5 条以上正文时，主 agent 再写一轮 `{"stages":[{"text","from":[条目号]}]}`，
  出处由代码按 `from` 合并（`lore_answer_stages.dart`），模型不写出处；整理版在 `[DETAILS]` 上方，详细版折叠在下方。
  整理那一轮不留在对话里，追问时对话停在详细版 JSON。段数、字数只在提示词里软性提示（一般不超过十段左右），
  不加硬性数字限制或代码截断（开发者要求：硬限制会伤害质量）。
- 出处：`story_id:起始行-结束行` 或 `record:<normalized_records.id>`，代码核对必须是工具实际给模型看过的
  （`SeenLines`）。写错的名字靠“模型用自身知识构造查询 + 零命中如实报告 + 自动附近名”解决，不加别名表。
- 提示词与工具说明里**不放任何具体人物、章节、活动或剧情示例**（开发者要求，2026-10）：示例会把模型带向那类问题，
  等于特化优化。需要示意格式时只用占位符（`X`、`<story_id>`、`main_<章>`）；`test/core/agent/lore_agent_loop_test.dart` 守卫。
  R18 起也不写具体剧情手法的名字（梦境、幻觉、叙诡等），只写“故事后来揭示了另一种性质”这类对任意故事成立的说法；
  守卫覆盖审稿和整理的提示词。
- 答案写给玩家（R17b）：正文不提库/表/文件名/id，用自己的话叙述；出处在每条末尾，界面把它们放到该条下面的证据链，
  点行号打开原文阅读页（`story_reader_page.dart`）。
- **提示词里凡是代码要严格解析的格式，都必须给出完整骨架（用占位符），不能只用文字描述**（v0.10.6 教训：只写“出处写成元组”，
  GLM 把 `cite` 写成平铺的 `["<id>.txt", 97, 127]`，解析器静默丢掉，答案没有出处和证据链）。解析器对常见变体要容错
  （平铺、`L12`、`"12-30"`、缺 `.txt`、反向范围；`loreCitationRefs`），丢弃的出处要计数并触发一次退回，不能静默吞掉。
  换模型后先看会话日志里 `cite`/`coverage`/`from` 等的真实写法。
- 主 agent 的最终答案是 JSON（R17c，`lore_answer_json.dart`）：条目 = 正文 + 出处元组，代码边流式边转成 markdown。
  提示词只说“不要用引号引用台词”，不要写“哪些可以加引号”（开发者判断：写了模型就会刻意用）；照搬台词由代码检查、退回一次。
- 只读 SQL（`readonly_sql.dart`）：单条 SELECT/WITH、拒绝写/ATTACH/PRAGMA、只读连接、每次查询一个 isolate、
  超时用 `sqlite3_interrupt` 在 SQLite 内部中止（工作 isolate 等主 isolate 说 close 才关连接，避免中止已释放的连接）。

### 思考强度与流式（R16）

- 思考档位用 `llmClientProvider(ReasoningLevel.off|low|high)`（`llm_provider.dart`）。deepseek 不传参数
  时默认开启 high 档，所以每个角色都必须显式指定档位。现在全部默认 `off`；只有“深度思考”开关
  （`deepThinkingProvider`）让本问的 Agent 用 `low`。不要给剧情问答开 `high`：开发者实测剧情过度思考
  会延伸推测原文没写的内容。
- 各家的思考开关在 `OpenAICompatibleClient.reasoningFieldsFor`：deepseek（`thinking` + `reasoning_effort`）、
  百炼（`enable_thinking`）、智谱 GLM（`reasoning_effort`：off→`low`、low→`high`、high→`max`，按 host `z.ai`/`bigmodel.cn`
  或模型名 `glm*` 识别；**不发 `thinking: disabled`**，glm-5.3-flash 会以 1210 拒绝）；
  其他 provider 不发字段。智谱只接受 `tool_choice: auto`，所以对它不发 `none`（最后一轮和 R18 整理段落时
  模型仍可能调用工具：前者按答案处理，后者回退为只显示详细答案）。429 按 `Retry-After` 或 2/5/10 秒重试三次。
- 服务商因思考字段报 400/422（错误里提到 thinking/reasoning）时，该 client 去掉思考字段重发、之后不再发；
  拒绝 `stream_options` 时先去掉它再流式重发，仍被拒才改为非流式。
- **默认模型是智谱 `glm-5.3-flash`**（`https://api.z.ai/api/paas/v4`，2026-10 开发者决定：写作更好）。
  实测（2026-10-04，api.z.ai）：它**不能关闭思考**，但 `reasoning_effort: low` 几乎不思考（80 字回答：不设 ~1100 段思考 / 20 s，
  low 无可见思考 / 4 s），所以默认 off 对应 `low`，“深度思考”对应 `high`。请求里**带工具时**智谱会把整轮回复攒齐再发
  （工具调用轮次没有逐字流式；纯文字答案仍是流式的）。`api.z.ai` 与 `open.bigmodel.cn` 用同一个 key 都能通。
  已保存过设置的用户不受影响（URL、key、模型三项总是一起保存）。
- R17/R18 文档里的验收数据是 deepseek 测的，换模型后调用次数、token、缓存命中率都要重新测。
- 流式：`LLMClient.streamTurn`（带 tools；默认实现调用一次 `chatCompletion`，测试假 client 可直接覆盖它）。
  Agent 依次发 `status` / `toolCall` / `toolObservation` / `finalAnswerToken`… →（继续查资料或出处退回时
  `finalAnswerReset`）→ `finalAnswerReplace`（信封 + 核对后正文）。测试取答案用 `finalAnswerOf(events)`。
- 状态：没有核对通过的出处 → `not_covered`；模型写 `[COVERAGE: gaps]` 或到轮数上限 → `partial`；否则 `answered`。
- 后台（v0.10.6）：长时操作（Ask 问答、角色扮演、知识库下载/构建）包在 `BackgroundWork.instance.run(...)`
  （`lib/core/background/background_work.dart`）里，Android 上由前台 service（`BackgroundWorkService.kt`，dataSync、
  唤醒锁、常驻通知）保活，否则退后台后 socket 被冻结、问答被截断。新增长时操作也要包进去。
  一轮被连接中断（无 HTTP 状态的超时/重置）打断时 `LoreAgentLoop` 重发该轮最多 2 次。
- 界面（R17d，开发者要求）：问答列表**不随流式内容自动滚动**（只在发新问题时滚到底一次）；思考窗口固定高度、
  内部也不跟随；阅读位置上方的内容在流式中不得变高变矮。不要再加“贴底跟随”。
- 颜色：Endfield 的信号黄（`accentPrimary`）只做填充和粗线；文字、图标、细边框用 `accentText`，黄底上的前景用 `onAccent`。

### 剧情向量（可选表，R12）

`story_chunk_vectors` 是 schema 4 上的**可选附加表**（`schema_version` 不变，
没有该表的库照常可用，`find` 退化为关键词检索）。构建（可续跑、按内容哈希缓存）：

```bash
dart run tools/build_story_embeddings.dart --db=build/gamedata_mobile/arklores_gamedata_zh.db
```

manifest 记录 `embedding_model / embedding_dims / embedding_chunking`；App 只在
所配置的向量模型和维度与 manifest 一致时才启用语义检索。向量命中只是定位线索，
必须 `read_story` 读到原文后才能作为证据（检索原则 5）。
