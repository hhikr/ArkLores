# 项目结构与模块实现

> ArkLores：《明日方舟》与《明日方舟：终末地》的剧情阅读与问答 App（Flutter，Android）。截至 2026-10-22（v0.17.0）。
> 每个模块写“做什么、怎么做、代码在哪、细节看哪份文档”。

## 1. 总览

```
                ┌──────────── App（Flutter，Riverpod）────────────┐
  底部四个标签： │  Wiki 浏览   问答   资料   设置                    │
                └──────┬───────────┬─────────┬──────────┬───────────┘
                       │           │         │          │
               WebView + 站点适配  问答 Agent  资料页/阅读器  知识库页（下载/更新/向量）
                       │           │         │          │
                       │     ┌─────┴─────────┴──────────┴─────┐
                       │     │ 知识库（每个游戏一个 SQLite 文件，schema 5）│
                       │     │ arklores_gamedata_zh.db / arklores_endfield_zh.db │
                       │     └────────────────────────────────┘
                       │           │
                  PRTS / Warfarin  OpenAI 兼容的 Chat / Embedding 服务
                  （问答也查，作二手出处）
  用户库（阅读历史、我的资料）：userdata/arklores_user.db
```

- 知识库在电脑上建好、作为 GitHub Release 资产发布，App 下载安装；明日方舟库也可以在 App 里从上游仓库增量更新。终末地库只能在电脑上从游戏客户端解包重建。
- 问答只读本地库（可选查 Wiki），每条答案带由代码核对过的原文出处。

## 2. 目录

```
lib/
  main.dart            启动：并行读出保存的设置（安全存储），注入 ProviderScope，进入 App
  app.dart             MainShell：四个标签（IndexedStack），底部标签栏（`AppTabBar`），标签间的跳转请求
  core/
    agent/             问答：AskChatNotifier、LoreAgentLoop、工具（tools/）、提示词、答案解析、会话记录
    gamedata/          知识库：安装、渠道、检索（单库 / 两库合并）、向量、目录、只读 SQL
      build/           建库（明日方舟：导入、条目层、剧情脚本、命名；source/ 是上游同步；endfield/ 是终末地）
    library/           资料页的查询、搜索与界面名词
    userdata/          用户库（阅读历史、阅读进度、我的资料）
    llm/               OpenAI 兼容的 Chat / Embedding 客户端，用量统计
    wiki/              PRTS / Warfarin 的请求、HTML → 段落、缓存与快照
    background/        长时操作的 Android 前台服务保活
  features/
    ai/                问答页、对话列表、阅读器（story_reader_page）、工作过程、答案与出处的部件、真机调试桥
    library/           资料页：书架、集合、条目列表、条目页、干员页、搜索、我的资料、阅读字体
    materials/         “资料”标签的外壳（每个游戏一页 + 我的资料）
    settings/          设置、模型服务、知识库页（下载卡、更新卡、向量卡）、Wiki 来源、首次引导（每一项设置一步，读入本机已保存的值）
    wiki/              Wiki 浏览器、站点主题适配、书签
  shared/              主题（明日方舟 / 终末地两套 token）、界面语言（ARB 中英）、全局 provider、共用部件
tools/                 建库、更新、补算、向量、终末地解包、发布、本机试装、真机桥（phone_ask.dart）
test/                  与 lib/ 一一对应；live/ 是要真实服务的测试（默认跳过）；guards/ 是守卫测试
docs/                  文档（索引见 CLAUDE.md）
```

## 3. 启动与状态

- 状态用 Riverpod。`main.dart` 在第一帧之前并行读出保存的设置（引导状态、模型与向量服务、主题、语言、回答选项…），用 `overrideWithValue` 注入初始值，之后由各 provider 维护。
- 设置存在 `flutter_secure_storage`（Android 上是加密的 SharedPreferences，`settings_service.dart`），API key 也在这里。
- 只在本机测试构建里（`--dart-define=ARKLORES_PHONE_BRIDGE=true`）套一层 `PhoneBridgeHost`，供电脑上的 `tools/phone_ask.dart` 提问和看输出（`ANDROID_SETUP_GUIDE.md`）。
- 长时操作（问答、知识库下载/构建、向量）都包在 `BackgroundWork.instance.run(...)` 里：Android 上有操作在跑时开前台服务（通知 + 唤醒锁），防止切到后台后进程被冻结、连接被断。
  这还不够：ColorOS（2026-10-25 真机日志）不管前台服务，只要 App 不在电池优化白名单里，退到后台约 9 秒、没有网络流量时就会把进程冻结（`OplusHansManager freeze`）。
  所以 App 要申请“忽略电池优化”（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，系统自己的对话框）。申请之前先说明为什么要申请（`background_access.dart`），只说明一次：
  在导览的“后台运行”一步，或者第一次提问时（已有问答记录的老用户在第一次打开问答页时）。设置页“AI 服务”二级页也显示通知和电池优化的状态。
- 设置页（`settings_page.dart`）只列大类（外观、资料设置、AI 服务、知识库与资料、帮助与引导），每行是编号、装饰小标、粗体名字和一行当前状态或内容；
  点进去是二级页（`settings_sections.dart`），具体设置都在二级页里。
- 开屏：系统开屏只有纸色（Android 12+ 的开屏只能放图标），颜色按 App 自己的深浅（`syncSystemNightMode` 用 `UiModeManager.setApplicationNightMode` 告诉系统，
  选“跟随系统”时交回系统；否则深色 App 在浅色系统上会先白一下），App 第一帧起由 `LaunchCurtain`（`shared/widgets/launch_curtain.dart`）盖在主界面上：
  强调色块从左扫入再向右退出、露出 ARKLORES，三色条推出、一行说明，约 1.5 秒后淡出；减少动态效果时没有；只有 `main()` 启动时开（`launchCurtainProvider`）。

## 4. 知识库

细节：建库与发布 `GAMEDATA_BUILD_PIPELINE.md`；建库经验与规则 `KNOWLEDGE_BASE_LESSONS.md`（**改建库代码前必读**）。

### 4.1 数据模型（schema 5）

- **条目层**：`collections`（书架与集合）、`entries`（每个官方条目一行）、`entry_links`（绑定：出场、所属、同一人物…）。归属与绑定只来自表里的 id，不用名字猜。
- **原文**：`story_lines`（剧情逐行，带 `kind`）、`normalized_records`（档案、语音、描述等）、`entities` / `entity_aliases` / `entity_documents`（实体与干员的整份档案）。
- **可选**：`story_catalog`（故事集名、章名、顺序、官方梗概、上线时间、剧情回顾的开放时间）、`story_chunk_vectors`（剧情向量，12 行一块、步长 8，int8）、`record_chunk_vectors`（资料向量）、
  立绘五张表与美术事件表（0.20，明日方舟库：每句显示的立绘与按立绘、说话人的统计；每篇换场景、出 CG、出特写的位置，`PORTRAITS.md`）。图片不在库里，在单独的剧情美术包。
- 两个游戏各一个库文件、表结构相同；**终末地的所有 id 以 `ef/` 开头**，所以任何地方拿到一个 id 就知道该去哪个库（`game.dart` 的 `gameOfId`）。

### 4.2 建库

- 明日方舟：上游 `Kengxxiao/ArknightsGameData`。`build/arknights_importer.dart` 导入剧情脚本（`story_script.dart`，读所有带文字的命令）和表（`entry_importer*.dart`，按条目建模；`text_harvest.dart` 用通用规则收长尾文字），最后统一算派生层（命名、去重、挂靠）。
  四条路径同一套代码：桌面全量（`tools/build_gamedata_database.dart`）、增量更新（`SourceSync` 比两个提交的文件树、只下载变化的文件）、补算（`tools/rederive_gamedata.dart`）、App 内完整构建（后台 isolate）。
- 终末地：`tools/unpack_endfield.ps1` 用 AnimeStudio 从本机客户端导出表、任务定义、关卡数据、对话树、时间线片段、章节，`build/endfield/` 建库：一个任务一篇剧情、段前一行写种类，段内按对话树和时间线排；
  有步骤的任务由 `endfield_level_data.dart` 解码关卡脚本与子数据、`endfield_story_order.dart` 把各段排到它播放的那一步（`ENDFIELD_STORY_ORDER.md`），步骤目标是不嵌入、不检索的标题行。
- 校验（`gamedata_db_validator.dart`）：安装器与构建共用，检查 schema、必需表、计数。

### 4.3 安装与更新（App）

- `gamedata_installer.dart`：下载 Release 上的 `.db.gz`（断点续传、阶段显示、取消、45 秒连接超时、可手动放置 `.download.gz`）→ 校验 SHA → 解压到临时文件 → 校验 → 原子替换。**已安装的库在替换前永不修改。**
- 资产地址与 SHA 在构建 APK 时从 `tools/release_gamedata.env` 烘进去；`gamedata_channel.dart` 另外读 `gamedata-channel` Release 上的渠道文件（官方知识库也只放在那个 Release 上，更新时原地替换），所以新库不用等新 App。
- 官方资产与本机更新过的库按游戏数据的新旧排先后（`GameDataInstallStatus.updateReason`）。
- `gamedata_build_provider.dart` + `source_build_card.dart`：明日方舟页的“检查更新 / 拉取并更新”（增量更新）。
- `story_vector_updater.dart` + `story_vector_card.dart`：每个游戏的“语义检索”卡片，补缺的剧情与资料向量（用户自己的向量服务）。
- `story_art_pack_installer.dart` + `story_art_pack_card.dart`（0.20）：“剧情美术”卡片，下载 / 更新 / 删除剧情美术包（只在渠道文件里，复用断点续传，`resumable_download.dart`），见 `PORTRAITS.md` §3–4。

### 4.4 检索面

- `GameDataKnowledgeStore`（`gamedata_knowledge_store.dart`）：一个库的只读连接与查询（读章、关键词扫描、目录、近似名、向量）。连接是自己的、失效时重开；库被替换后按文件 stamp 自动重开。
- `MultiGameRetrieval`：把装着的库合成一个检索面——按 id 的调用去对应的库，统计与检索两个库都问并按游戏分组，`sql` 用 `game` 参数选库。
- 关键词用 LIKE（中文没有可用的全文索引）；向量是暴力 cosine（剧情约 5.6 万块 × 512 维 int8，约 28 MB，在后台 isolate 用 FFI 载入）。只在配置的嵌入模型/维度与库的 manifest 一致时启用。
- 只读 SQL（`readonly_sql.dart`）：只允许一条 `SELECT`/`WITH`，在后台 isolate 跑，8 秒超时用 `sqlite3_interrupt` 中止。

## 5. 资料页与阅读器

- 结构：资料标签每个游戏一页（明日方舟 / 终末地 / 我的资料，顶部标签切换，不能左右滑）。书架 → 集合（故事集、任务、干员…）→ 条目；条目之间按 `entry_links` 互相链接。
  查询在 `core/library/library_queries.dart`，界面名词在 `library_labels.dart`（每个名字的出处写在注释里；查不到就不起名，未知书架显示“其他”）。
- 书架（`collections.kind`）：

| 明日方舟 | 终末地 |
| --- | --- |
| `main` 主线（每章一个集合）、`sidestory` / `ministory` / `branchline`、`activity`、`memory`（干员：档案、密录、模组、皮肤、信物、召唤物）、`roguelike` 集成战略、`sandbox` 生息演算；图鉴（敌人、物品、奖章…） | `ef/main` 主线任务（按章、进程分组）、`ef/discovery` / `ef/side` / `ef/activity` / `ef/other`（任务面板的分类，按地区分组）、`ef/world` 其他（地点交互、敌人通讯）、`ef/unused` 未实装任务、`ef/archive` 情报档案库、`ef/memory` 干员（档案、语音、角色纪事、Baker 话题、帝江号互动）、`ef/codex` 百科 |

- 阅读器（`features/ai/story_reader_page.dart`）：惰性列表从锚点双向建（任意长的故事打开不卡），记住位置与读过的次数，标题板下有进度条；点标题展开共用 `AppSlider`，拖动或点轨道按行跳转，松手保存并保留面板，滚动正文同步当前行。再点标题、点正文或按返回键收起；从问答出处打开时高亮所引的行。
  明日方舟的说话人名字可以点开立绘卡片（这一句的确切差分，0.20，`PORTRAITS.md` §4）；装了剧情美术包时排出场景、CG 段与合成的特写，进度面板有当前画面，
  画面和立绘都能在 `story_art_viewer.dart` 全屏看；故事集页列出它的剧情美术（`collection_art_page.dart`，`PORTRAITS.md` §5）。
  终末地的篇里有种类分段线、折叠的段首梗概、步骤标题，“未定位的对话”默认收起（点标题展开）。
- 排版：长文用阅读字体（`reading_text.dart`，设置里选：默认黑体，即内置的思源黑体子集，可选霞鹜文楷）；档案按段可折叠（`ProfileText` / `ProfileSliver`，按需构建，默认展开还是收起按设置）；语音用 `VoiceLines`；剧情开头的官方梗概默认折叠（`FoldSection`）。
- 搜索（`library_search.dart`）：名字/代号 → 相近名字 → 正文提到；“按意思找剧情”是手动按钮。与问答无关。
- 用户库（`core/userdata/`）：阅读历史、阅读进度、我的资料存在独立的库，只存引用字符串（`story:<id>` 等）加原文片段，知识库更新后按片段重新定位。**所以知识库的 id 必须稳定。**

## 6. 问答

细节：`ASK_AGENT.md`（现在的流程）、`ASK_EXPERIMENTS.md`（试过的办法与数据）。

- 一个模型 + 通用工具（`search`、`read_story`、`read_record`、`grep`、只读 `sql`、`guide`、`outline`、`similar_names`、`gather`，可选 Wiki 工具与子助手），对话只追加，代码核对出处。
- 第一轮之前：一次小调用拟定检索词和锚点，代码执行检索、按名字取材；追问时先重读上一答引用、已不在上文的原文。
- 0.20：主 agent 不限轮数；还在上文的原文与相同的调用不再执行（`ContextLedger`）；接近上下文提醒值时由模型写纪要、代码按“已读”取回保留的原文重建对话（`lore_context_compaction.dart`）；
  完整对话随会话文件保存（`lore_conversation`），重启后接着问。答案逐段放出，有立绘的名字加下划线、可以点开立绘卡片；顶栏开关与屏蔽词（`PORTRAITS.md` §5.2）。
- 界面：问答页（`ai_chat_page.dart`）、输入框与选项面板（`ask_composer.dart`、`answer_options_menu.dart`）、答案与出处（`chat_bubble.dart`、`story_answer_body.dart`）、工作过程（`work_steps.dart`）、对话列表（`chat_history_page.dart`）。
- 会话记录：`ChatSessionStore`，每个对话一个 JSON（每次模型输出、工具调用与结果、答案、用量、分段计时）。
- 多个对话（`agent_provider.dart`）：每个打开的对话是 `askChatProvider(key)` 的一个 `AskChatNotifier`；`askSessionsProvider` 记着打开的对话和显示的那个（`shownAskProvider`）。
  换一个对话、开新对话都不停正在作答的那个，它在后台接着答（前台服务照常保活，几个同时作答时通知合在一起）；离开的空对话不留。
  用量各算各的：模型客户端共用一个计数器，每个对话在 `UsageMeter.runWith` 里跑，计数记到它自己的计数器上。
  正在作答的对话不能删除（作答结束时会把文件再写一次）。
- 对话栏（`widgets/conversations_panel.dart`）：问答页左上角的按钮从左侧滑出——新对话、作答中（强调色块、实时进度，按钮角上是别处作答中的个数）、
  最近（打开着的和保存的，当前的有竖线）、“查看全部”进完整的对话记录页。没做下拉刷新：设计不用转圈，打开对话栏时会重读列表。
  打开着、还没保存（“保存 AI 对话记录”关着）的对话也在“最近”里，只到这次退出 App 为止。

## 7. 模型服务

- 只说 OpenAI 兼容协议（`core/llm/openai_client.dart`）：流式（SSE 里拼接工具调用）、非流式、文本协议回退；429 按 `Retry-After` 重试；被拒的参数（思考字段、`max_tokens`、`temperature`、`stream_options`）去掉重发并记住；`abortTrigger` 中断请求。
- 思考档位按角色显式指定（默认全关，“深度思考” = low），各家的参数映射见 `LLM_PROVIDERS.md`。
- 向量：`embedding_client.dart`，默认百炼 `qwen3.7-text-embedding`、512 维。
- 用量：`usage_meter.dart` 统计每问的调用数、token、缓存命中、限流重试与分段计时。

## 8. Wiki

细节：`WIKI.md`。

- 浏览：`features/wiki/wiki_browser_page.dart`（`flutter_inappwebview`），PRTS 与终末地 Wiki（fz.wiki 或 Warfarin）两个标签、书签；深色模式只切站点自己的主题状态，不做反色；网页铺满屏幕，注入上下留白避开顶栏与底栏。
- 问答取证：`core/wiki/`（`wiki_sources.dart` 两个站点的接口、`wiki_html_text.dart` 页面 → 编号段落、`wiki_lookup.dart` 缓存与版本快照），工具 `wiki_search` / `wiki_read`。Wiki 是二手资料，答案里写明来源。

## 9. 界面体系

- 两套主题 token：明日方舟（`ark_theme_tokens.dart`）与终末地（`endfield_theme_tokens.dart`，黑白工业风 + 信号黄）。信号黄（`accentPrimary`）只做填充和粗线；文字、图标、细边框用 `accentText`，黄底上的前景用 `onAccent`。
- 界面设计（0.17）见 `docs/DESIGN.md`：两套主题 token（`shared/theme/`）、部件（`shared/widgets/ef_widgets.dart`）、页面框架（`page_frame.dart`）、动效（`motion.dart`）与人机交互约定；守卫测试禁止圆角、`_rounded` 图标、回弹曲线、转圈、投影、红绿色和小于 12 的字。
- 全 App 不用 `AppBar`：推入的页面用 `PageScaffold`，主标签页用 `MainTopBar`（`page_frame.dart`，有守卫测试）。
- 系统栏（0.20）：Android 状态栏、导航栏透明，App 铺到屏幕边上（`SystemUiMode.edgeToEdge`，`styles.xml` 四份）；图标深浅由 `MaterialApp.builder` 外层的 `AnnotatedRegion` 按 App 当前主题定（`system_bars_style.dart`）。
  顶栏背景画到状态栏下，收起时一起移出；主标签页保留系统底部留白，收栏后的输入框与 Wiki 工具停在手势条之上。
- 输入框旁的面板、菜单用浮层且不取焦点（不把键盘收起来）。
- 界面文字进中英 ARB（`shared/l10n/`，`flutter gen-l10n`）；提示词留在 Dart 里。

## 10. 测试与工具

- `flutter test`（约 1–3 分钟，全部离线）：测试目录与 `lib/` 一一对应，测试知识库一律用生产 schema（`test/support/gamedata_fixture.dart`），mock LLM。守卫测试在 `test/guards/` 与 `lore_agent_loop_test.dart`。
- `test/live/`：要真实服务或真实库的测试，用环境变量开启（真实模型问答、召回测试、真实库验收、Wiki 联网、资产安装、场景卡与前缀试验）。命令见 `QA_CHECKLIST.md`。
- `tools/`：建库与更新（`build_gamedata_database.dart`、`update_gamedata.dart`、`rederive_gamedata.dart`、`build_story_embeddings.dart`、`build_story_catalog.dart`、`compact_gamedata.dart`、`finalize_gamedata_assets.dart`）、
  终末地（`unpack_endfield.ps1`、`build_endfield_database.dart`）、立绘与剧情美术（`build_portrait_index.dart` 补算，`portraits/` 下的 Python 打包脚本）、发布（`release_app.ps1/.sh`、知识库 `publish_gamedata.ps1` + `write_gamedata_channel.dart`）、本机试装（`install_local.ps1`）、真机桥（`phone_ask.dart`）、云端会话（`tools/cloud/`）。
- 构建与发布：APK 由 GitHub Actions 构建签名（推 `release/<版本>` 触发），见 `ANDROID_SETUP_GUIDE.md`；云端会话见 `CLOUD_DEV.md`。
