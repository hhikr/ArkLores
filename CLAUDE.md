# ArkLores Developer Notes

明日方舟剧情阅读与问答 App（Flutter）。主线：中文 GameData 知识库（SQLite，schema 5 条目层 + 可选剧情向量/故事目录）+ 资料页（阅读）
+ 工具型问答 Agent（`LoreAgentLoop`，直接查库作答，代码核对出处）。向量、目录、梗概只作定位线索，不作证据。

- **已发布**：v0.21.0 预发布（2026-10-28，Android build 44，问答省 token、资料页剧情美术、美术默认折叠；只有 APK，从分支 `v0.21` 发出，知识库与美术包沿用 0.20 的；还没合回 `main`）；v0.20.0（2026-10-27，Android build 43，剧情美术：立绘、场景、CG、特写进入阅读、问答与资料页，只有 APK，从分支 `v0.20` 发出、经 PR 合回 `main`；
  同日明日方舟知识库（加立绘表与美术事件表，SHA `94c07dbb…`）与剧情美术包（`arklores_story_art_zh.db`，396 MB，`48b702bd…`，渠道 `arknights_story_art`，`min_app_build` 43）传到 `gamedata-channel`）；
  v0.19.1（2026-10-25，Android build 42，阅读器拖动进度、Wiki 与问答滚动时收起栏、毛玻璃换页只在资料页，只有 APK，从分支 `releases-tidy` 发出、经 PR #25 合回）；v0.19.0（2026-10-25，Android build 41，Quality of Life 更新：流畅度、多对话、设置分类与检索修正，只有 APK）；v0.18.0（2026-10-23，Android build 40，补充资料与《大地巡旅》）；
  v0.17.1（2026-10-23，Android build 39）；三版都只有 APK。**官方知识库 2026-10-25 起只放在 `gamedata-channel` Release 上**（v0.10.0–v0.16.0 上的旧知识库与 `gamedata-20261020` 已删，tag 都在；v0.17.0 上的同一份留作备用地址）。v0.17.0（正式版，2026-10-22，Android build 38，全 App 新界面）：APK + 两个知识库 + 源码。两个库与 v0.16.0 同一份：明日方舟库与 v0.15.x 同一份（上游 `17759cc`）；
  终末地库（2026-10-18 客户端）按任务步骤排列、加了过场台词与段首梗概（渠道 `min_app_build` 仍是 37）；`tools/release_gamedata.env` 与渠道文件指向 `gamedata-channel` 上的文件。
  v0.10.0 之前的 Release 已删（tag 都保留）；`release/v<版本>` 分支在发版后删掉（tag 指向同一提交）。
  0.19.0 从分支 `fix/qa-retrieval-evidence` 发出，经 PR #23 合回 `main`；下一轮从合并后的 `main` 开新分支（推之前先确认 PR 没有合并）。
- 未经开发者明确同意不发版。真实 API 测试（模型与向量）：测试模型用 glm-5.3-flash；预计一轮总消耗 ≤150 万 token 直接跑，超过先问（开发者 2026-10-19）。Android build 号每次发版递增。
- **仓库里只放面向用户的内容和必要的开发约定**：调查笔记、方案讨论、普查数据放本地 `notes/`（gitignored），不提交、不写进 PR。
- 用中文和开发者交流。

## 当前进度（每轮结束时更新；细节进 CHANGELOG 与 docs，这里只留要点）

- **0.21.0（2026-10-28 预发布，分支 `v0.21`，从合并 PR #26 后的 `main` 开出，Android build 44）**：开发者手改中文 ARB 里“AI 化”的表达；优化提示词；减少问答的 token 消耗（不降低质量）。
  离线 token 回放：`test/live/token_replay_test.dart` 固定历史模型回复、执行真实工具，统计累计输入字数、重复与合并读取估算；默认跳过，命令与限制见 `docs/QA_CHECKLIST.md` §3。
  已做：设置 → AI 的“回答价格”（输入/输出每百万 token 的价格、缓存命中占输入价格的 %，答案下的用量行末尾 `cost`，按现在的价格算，不含向量）；“深度思考”默认开
  （开发者 2026-10-27：一个真实问题里思考约占输出的四分之一、费用的百分之几）。T6 已完成：剧情美术的显示设置（图片 / 只标出 / 不显示），只影响阅读器内联美术，切换时保留阅读位置。
  T2 已完成：`search`、`gather`、`grep` 根据 `ContextLedger` 省略仍在上文的证据；planned `gather` 等前面的结果入账后再运行，其他调用仍并发。默认回放累计字数下降 4.20%，离线召回逐条金标命中不变。
  T3：补充资料来源说明同一问只印一次（之后写“同第 N 步”）、`search` 每次都印的四句说明移进工具说明（-0.95%）。
  T4：`read_story` 的 `ranges` 一次读同一章的最多四段，说明与系统提示改成一章一次读完；真实模型（2026-10-28，glm-5.3-flash、深度思考、两次）：同一问累计输入 315 万 → 81 万 / 67 万 token，省下的主要来自一轮发多个调用；
  一章仍常分几次读。答案主干与评价齐全但比 0.20 短（正文 55–70%），开发者看后接受。T5a 提示词审计完成；T5b 按审计改提示词（过时、矛盾、重复的说法，前缀 −374 字），真实模型各跑一次：一章基本一次读完（`ranges`），累计输入与 T4 持平。
  T7 已完成：明日方舟资料页新增“剧情美术”总览，立绘按说话人搜索，背景与 CG 按首次出现的故事集分组，可全屏翻看同类全部图片并回到剧情。真库浅深截图在 `build/shots/v021_t7/`，未在真机查看。
  T8 已实现：美术默认折叠防剧透（美术页分组、故事集美术一节与全部美术分组、阅读器场景与 CG），阅读器场景按原图比例整宽显示；故事集与美术页只查看点开的单图，查看器在双指按下时暂停翻页与竖长图滚动。真机双指缩放待开发者确认。
- **0.20.0（2026-10-27 发布，分支 `v0.20`，Android build 43）**：重大更新——剧情美术（开发者 2026-10-26 定名“剧情立绘”，10-27 扩成剧情美术）。细节见 CHANGELOG 与 `docs/PORTRAITS.md`。
  - 剧情美术：知识库记下每句的立绘（立绘索引版本 7）与每篇的场景、CG、特写事件（美术索引版本 2，特写带位置、缩放、透明度、层次）；一个剧情美术包（立绘差分 + 背景 + CG + 特写，396 MB，`tools/portraits/` 增量打包，原图缓存 `build/portraits_src/`、`build/story_art_src/`）。
    阅读器排出场景与 CG 段、特写按 1280×720 × 1.5 合成到舞台上，进度面板有当前画面，全屏查看器（剧情画面与立绘）；故事集页的剧情美术与全部美术页。没有包时阅读器与资料页不变。
  - 立绘与人名：阅读器与答案点名字先看旁边的小卡片，再点“更多”打开大卡片；答案人名用正文色加 2 px 强调色下划线，凡是配着立绘说过话的标签都标，只排除单字、无文字、合说（开发者 2026-10-27，5,028 个）；
    下划线不持久化、每次显示时算（开发者 2026-10-27 问过，答：现算）；顶栏开关、长按屏蔽、设置里的屏蔽词；答案逐段放出。
  - 补充资料：引用计入“出处 N”；《大地巡旅》在资料页不能点开全文，只通过答案引用看被引的段落（规避版权，开发者 2026-10-27）。
  - App 内更新：帮助与引导 → 更新，公开 GitHub Releases 检查、断点下载、SHA-256 校验与 Android 安装通道；自动检查默认关闭，每 24 小时最多在启动时检查一次，不自动下载。原生编译和真机覆盖安装待验证，见 `docs/ANDROID_SETUP_GUIDE.md`。
  - 问答（`docs/ASK_AGENT.md` §6.5–6.7）：主 agent 不限轮数；上下文用量显示与提醒（设置：提醒值默认 1M、压缩位置默认 80%，开发者 2026-10-26：长上下文模型压缩效果常常不好）；
    不重复读取还在上文的原文（`ContextLedger`）；取消旧的工具结果折叠，改为模型写纪要、代码按已读取回原文的压缩（真实模型 64k 下测过三问：压后 10–15k、答案连贯）；完整对话随会话文件保存。
  - 界面：Android 系统栏透明（edge-to-edge，图标跟 App 主题）；问答输入框平时一行、点开两行、回车换行。按压反馈等待 100 ms 排除滚动；分段选项的选中块滑到新位置（开发者 2026-10-26：设置保留分段选项，不用滑块）；阅读进度用粗轨道加大方块滑块，点阅读器标题开关面板，松手保留，跳到的行在面板下方。
    界面复核（2026-10-26，开发者：UI 由我来做，优先级“我的判断 > 开发者的要求 > skill”，两者冲突要汇报）：左侧 trace 线只伸缩长度、展开期间常驻（`TraceRail`/`FoldBlock`/`FoldTile`，见 DESIGN.md §3）；按钮画小；竖长立绘小卡片；补充资料页重排；Wiki 与问答点空白处唤回或让开栏。
  - 只有离线测试与截图（真库真包，浅深两套）；开发者手机上装过本地包（build 43），发布的 APK 与美术包没在真机上看过，清单在 `docs/KNOWN_ISSUES.md` §3。
    本地：发布的库 `build/gamedata_portraits/`、美术包 `build/story_art/`，设计稿、任务书与报告在 `notes/v0.20/`，一次性的真库截图探针在 `notes/probes/v020/`。
- **0.19.1（2026-10-25，分支 `releases-tidy`，Android build 42）**：长按阅读器标题展开拖动进度条（按行定位）；Wiki 与问答往下拖时顶栏、底栏让出屏幕（只平移，`BarsAway`，见 `docs/DESIGN.md`）；毛玻璃换页只在资料页（`smoothPageRoute(frosted: true)`）；知识库只放 `gamedata-channel`。只有 widget 测试，没上真机。
- **0.19.0（2026-10-25，分支 `fix/qa-retrieval-evidence`，Android build 41，从 v0.17.1 开出、合并了 0.18.0 的 `main`）**：Quality of Life 版本（开发者 2026-10-25 定名），不加新资料或玩法。整个 App 的流畅度与人机交互修正，加上问答检索的工程修正。
  - 界面：问答可以同时开几个对话、各自在后台答（左上角对话栏：作答中 / 最近 / 查看全部）；设置分五个大类、各一页；开屏动画（`launch_curtain.dart`），深色主题下开屏不闪白（App 把自己的深浅告诉 Android 12+）；
    启动图标只留一个（纸色底的自适应图标，删掉了浅色/深色图标设置）；后台问答在 ColorOS 上保活，新用户导览里有这一步。
  - 字体：中文换成打包的思源黑体（`NotoSansSC`），装饰小字用终末地文字（`EndfieldCipher`，CC BY-NC，只作装饰）；两个中文字体按 App 用到的字裁剪（`tools/subset_fonts.py`，重建知识库后要重跑）。
  - 问答检索：collection 检索范围与实际展示行的引用登记；结构标题和梗概不再能作剧情证据。离线回归通过，真实概念题和时间顺序题仍有语义错误，**不能当作问答质量验收通过**（`docs/ASK_EXPERIMENTS.md`）。
  - 清理：死代码、没用的依赖、翻译键与旧脚本。知识库沿用 v0.17.0 的发布资产。真机看过本地包（build 51）；发布的包没有在真机上看过。
- **0.18.0（2026-10-23，Android build 40）**：补充资料与《大地巡旅》接入现有 Ask 工具链，资料页管理参考选择、来源说明和增量向量，按版本与段落引用。预置包只含正式正文及取证必需信息。说明见 `docs/MATERIALS.md`；不再使用“就此提问”或截取草稿。

- **0.11（已发布）**：知识库重做为条目层（`entries`/`collections`/`entry_links`）、剧本全量解析、增量更新通道、用户库与阅读历史、
  资料页与阅读器、悬浮式界面与点击反馈、工作过程时间线、非 GLM 服务商兼容、删除角色扮演（开发者 2026-10-07 决定，不要恢复）。
  建库/更新/补算的经验与全部错误见 `docs/KNOWLEDGE_BASE_LESSONS.md`。
- **0.12（已发布，v0.12.0）**：终末地知识库与双游戏资料页/问答。设计见 `docs/KNOWLEDGE_BASE_LESSONS.md` §9–10，构建见 `docs/GAMEDATA_BUILD_PIPELINE.md` §9，
  已知限制见 `docs/KNOWN_ISSUES.md` §5。
  - 架构：每个游戏一个库文件；终末地 id 一律 `ef/`（`game.dart`）；Agent 用 `MultiGameRetrieval`（`sql` 按 `game` 选库，`grep`/`search` 默认两个库），
    装了终末地时提示词加“两个游戏”一节（`loreGamesGuide` + `lore_endfield_prompts.dart`）；资料页每个游戏一页（明日方舟 / 终末地 / 我的资料）、页面按 id 路由；知识库页每个游戏一张下载卡。
  - 终末地建库：`tools/unpack_endfield.ps1`（AnimeStudio 导出客户端两层的表与 JSON 数据，Persistent 覆盖 StreamingAssets，不用 kit 的完整流程）→
    `tools/build_endfield_database.dart`：干员情报/档案/语音记录、情报档案库（PRTS）、敌人/武器/物品描述、对话/通讯/短信，
    任务名/简介/分类/所属干员/关卡来自 `MissionRuntimeAsset`（没有定义、也没有被有定义的任务播放对话的任务不在游戏里，放 `unused`“未实装任务”，名字取 `TextTable`，都没有叫“无名任务（id）”；
    无名/同名的子任务并进基础任务，同书架重名加“·一阶段”），书架是游戏任务面板的分类（主线/探索/支线/活动/委派任务）；
    章节（主线的章·进程、干员的篇章）来自资源包的 `ChapterInfo`（`--chapters`），章节外的任务按地区分组。
    干员下挂三种集合：角色纪事（干员任务）、`baker` Baker 话题、`ship` 帝江号互动（后两种不是书架）；档案库按游戏分页（中枢档案/见闻辑录/音像存档/情报采集）。
    界面里的名词一律到 `TextTable` 的界面文字里查（每一层都查），查不到就不起名。
  - **一个任务一篇剧情**（参考 warfarin/fz 的编排）：段前一行 `section` 标种类，按种类分块、块内按编号；一段对话内部按对话树（`dlg_…` TextAsset）
    与过场时间线片段（`DialogTrunk/OptionPlayableAsset`）排，89% 台词行由它们定位，其余按行号。阅读器只在种类变化处写种类名。
  - 终末地资产带剧情向量（与明日方舟同一模型；切块在 `section` 处断开）。重建后先 `build_story_embeddings.dart --migrate-from=<旧库>` 按行对齐搬旧向量，
    剩下的块多半在 `build/embedding_cache/` 里（`--dry-run` 看 “to embed”，非零才花钱，要先问）；`unpack_endfield.ps1 -Embed` 是直接补全。
  - 本机工具（不提交）：`C:\Users\hhikr\endfield\`（kit、embeddable Python、导出数据；`python312\python.exe` 带 sqlite3，可直接查库）。
- **0.13（已发布，v0.13.0）**：问答 Agent 的 Wiki 检索与证据，设计见 `docs/WIKI.md`，已知限制见 `docs/KNOWN_ISSUES.md` §6。
  - 工具 `wiki_search` / `wiki_read`（明日方舟 PRTS 的 MediaWiki API；终末地 Warfarin 的搜索 API + 服务端渲染页；fz.wiki 无公开接口且开发机连不上，没选）；
    页面按段编号，出处 `wiki:<站点>:<页面>@<版本>:<段>`，与剧情出处同一套核对（只能引用展示过的段）；读过的版本存快照（`wiki_snapshots/`）。
  - Wiki 是二手资料：剧情事实以库里原文为准，只有 Wiki 支持的说法要写明（`loreWikiGuide`）。输入框“回答选项”里的“Wiki 资料”开关，默认开。
  - 界面：证据卡与出处树里的 Wiki 行、引用段落弹窗（快照、在 Wiki 标签打开）、工作过程里的 Wiki 步骤。
  - 真实模型已各游戏验收（2026-10-09，`docs/WIKI.md` §9）：先查库、Wiki 只补库里没有的并写明。真机只看到安装与“回答选项”里的 Wiki 开关；
    带 Wiki 出处的答案（出处卡、弹窗、“在 Wiki 中打开”）只用真实页面快照渲染截图检查过，下次真机检查时补看。
- **0.14（已发布，v0.14.0，2026-10-11）**：问答工作流重构与知识库瘦身。依据是 v0.13.0 真机 10 个会话、之后几轮真机会话和 37 问的历史问题集；
  设计见 `docs/ASK_AGENT.md`，验收数据见 `docs/ASK_EXPERIMENTS.md` §4，已知限制见 `docs/KNOWN_ISSUES.md`。
  - 开发者定下的方向（不要改回）：Wiki 与本地库**检索同级**，答案仍区分来源；以向量（语义）检索为主，没有向量服务时退回关键词并提示“问答质量会显著下降”；
    审稿与子助手默认关闭；**提要与复核是答案下方的按钮**，不是提问的选项；两个库的所有资料都要有向量；知识库里没人读的东西要删。
  - 问答：统一检索 `search`（剧情、资料、Wiki 一起查，按来源分组）；第一批查找由独立的小调用拟定；工具调用守门；`read_record`；
    词在各故事集的分布与“各给一段”、`near`；表结构收进手册（`guide`）；没有结果的查找每个工具每问最多 6 次；
    答案被退回时整轮回档；“已读”是一本账（`SeenLines`），出处裁到读过的行；数据库连接独立、空回复只对一轮降级、取消立即生效。
  - 界面：输入框只有一个选项按钮（面板不取焦点）；工作过程写成明细（工具名、参数原文、字数、标记，点开看完整结果）；对话记录是对话列表；
    知识库页每个游戏一页。
  - 知识库：没人读的表全部删掉（明日方舟库未压缩 679 → 299 MB），**不要把这些表或“覆盖层”加回来**，加表前先写清谁读它；
    资料向量（`record_chunk_vectors`）；复刻活动的关卡不再被当成复刻删掉（`docs/KNOWLEDGE_BASE_LESSONS.md` §2.2 的“复刻不是独立内容”）；
    “用游戏数据更新”能真正取消、不留失败的副本、更新后按钮变灰；官方资产与本机更新按游戏数据新旧定先后（`docs/GAMEDATA_BUILD_PIPELINE.md` §4.4）。
    v0.14.0 的明日方舟库基于上游 `17759cc`（2026-10-08）。旧版 App 装不了 0.14 的库（v0.13.0 的校验要求已删掉的表），所以新库只随新版本发布。
  - 真机测试工具：`tools/phone_ask.dart` + `install_local.ps1 -Bridge`（`lib/features/ai/phone_bridge.dart`，只在本地构建里），见 `docs/ANDROID_SETUP_GUIDE.md`。
    **手机上的验证由开发者自己做**：把包和库装好、说明要看哪里即可，不要替他解锁、点按或跑更新。
  - 没有在真机屏幕上看过的界面改动、没有被真实模型再触发的修正，列在 `docs/KNOWN_ISSUES.md` §3。
- **0.14.5（2026-10-17）**：真机反馈的修正——干员语音（两个游戏）、档案默认展开/收起的设置、梗概向下展开、阅读进度、引用的资料打开资料页、
  PRTS 用站点自带的黑夜模式、删掉 Wiki 阅读模式与“转交给 AI”；知识库渠道文件（`gamedata_channel.json`，`gamedata-channel` Release）与按提交日期比新旧；
  终末地档案 id 带 `ef/`（要重建终末地库才生效）。悬浮栏自动隐藏留到 UI 重构（0.17 起顶栏、底栏改成实心，不再悬浮；阅读时自动隐藏仍未做）。
- **0.15.0（2026-10-20，问答统一重构，分支 `ask-recall-eval`）**：方向是“找原文由代码一次找全、给齐；模型只读和写；卡片、梗概只做定位”。
  每一种做法、数据与结论见 `docs/ASK_EXPERIMENTS.md` §5，现在的流程见 `docs/ASK_AGENT.md`。
  - 留下的：离线召回测试（`test/live/recall_eval_test.dart`，日志题第一步金标行 37% → 74%）、按名字取材（`gather`）、追问重读上一答引用的行、查证“没有查到”（`missing`）、
    出处的短路径补全、拟定超时即中断请求（`abortTrigger`）。
  - 试过、没采用的（不要再试）：按段挑行（64% 对 74%，代码在、默认关）、加大取材的前后行数、场景卡（整张或按句，代码只在 `test/support/`）、检索块加前缀（排名变差）。
  - **问答质量没有解决**：概念题找不到原文、取材后“够了就答”、答案先后顺序（`docs/KNOWN_ISSUES.md` §2.1）。开发者 2026-10-19 说先停下想方向。
  - 知识库（2026-10-19）：按现在的建库代码在本机重建了两个库（同一份游戏数据，向量全部迁移、新算 0 块，逐表对比与验收通过）：明日方舟 `build/gamedata_rebuild/`
    （`story_catalog` 多 `show_time`，主线因此有时间）、终末地 `build/endfield/`（档案 id 带 `ef/`；旧库备份 `build/endfield_v0140/`）。
    2026-10-20 先发布到 `gamedata-20261020`，同日随 v0.15.0 再发一份（同样的文件），渠道文件指向 v0.15.0，见 `docs/KNOWN_ISSUES.md` §1.1。
    同日晚终末地库按 2026-10-18 的客户端重建（AnimeStudio 要换成支持 VFS v5 的提交，`docs/GAMEDATA_BUILD_PIPELINE.md` §9.1），
    开发者同意后直接覆盖了 v0.15.0 上的终末地资产并改了渠道文件（旧库备份 `build/endfield_v0150/`）。
    2026-10-21 修了真机发现的终末地资料页问题（武器英文名、调查报告进调查、阅读文字归属、被播放的任务不算未实装、调查页的文档打开条目页），发布 v0.15.1。
    本机测试用 `build/gamedata_rebuild`，不要用更旧的 `build/gamedata_v5`（没有 act52side，召回测试的金标检查会失败）。
  - 当时待办的终末地风格界面已在 0.17 完成；《大地巡旅》与资料来源说明在 0.18 接入。
- **0.15.1（2026-10-21，已发布）**：终末地库换成 2026-10-18 客户端（第二章进程VIII、干员“祀”等；AnimeStudio 要用支持 VFS v5 的提交），
  以及真机发现的终末地资料页问题：武器英文名是文字对象被原样输出、调查报告单列一栏、阅读文字认不出任务而散在图鉴、
  被隐藏步骤播放的任务被当成未实装（规则改为“没有任何定义播放它的对话”才算未实装）、调查页把文档当剧情开阅读器。
  经验写进 `docs/KNOWLEDGE_BASE_LESSONS.md` §10，真实库验收加了对应检查。留给开发者定的：`db01m2` 落在“支线”（`docs/KNOWN_ISSUES.md` §5）。
  开发者真机看过后，这一轮结束；下一轮从合并 PR #18 后的 `main` 开始。
- **0.16.0（2026-10-22，分支 `endfield-cutscenes`，Android build 37）**：终末地剧情按任务步骤排列，加上过场动画台词与段首梗概。
  - 过场动画台词（`TextTable` 的 `cutscene_`/`cs_video_` 键）、段首梗概（`kind = 'summary'`，不嵌入向量）。
  - 按任务步骤排列（数据、规则、审核与验证见 `docs/ENDFIELD_STORY_ORDER.md`）：建库自己解码关卡数据（`endfield_level_data.dart`）、排列（`endfield_story_order.dart`），
    `unpack_endfield.ps1` 带 `--data --step-order=all`，294 个任务按步骤排；规则来自伊冯的角色纪事（开发者 2026-10-22 审核过），其余任务没人读过。
    标题行 `step`/`stage`/`unplaced` 不嵌入、不检索（开发者 2026-10-21；检索一律用 `searchableLinesFilter`），Agent 的工具标成 [步骤]/[任务]/[未定位]。
    数据给不出位置的段放在“未定位的对话”下，阅读器默认收起（开发者 2026-10-22，不写“可能已删减”）。有自己剧情的任务不嵌套；没有对话的步骤不写标题。
  - 终末地库在本机 `build/endfield/`（v0.15.1 的备份 `build/endfield_v0151/`），向量迁移、新算 3 块；渠道文件 `min_app_build` = 37（旧 App 不认识标题行）。
    明日方舟库与 v0.15.x 同一份。
- **0.17.0（2026-10-22 发布，分支 `ui-0.17`，Android build 38，从合并 PR #19 后的 `main` 开出；同日删除了全部已合并的分支）**：全 App 界面重构与人机交互修正，
  用开发者的 skill `endfield-ui`（`~/.claude/skills/endfield-ui`，来自 github.com/hhikr/endfield-ui-skill）。设计、代码位置与规则见 `docs/DESIGN.md`。
  - 开发者的要求：保留浅色/深色两个主题的强调色（黄 / 蓝），其余自由发挥。
  - 新增：主题“跟随系统”（新装默认）、设置“阅读字体”（默认黑体，可换回霞鹜文楷）、Saira 界面字体（`assets/fonts/`，OFL）。
  - 只在测试里截图看过（真实字体、浅深两套），**没有上真机**；真机检查由开发者做（见 `docs/KNOWN_ISSUES.md` §3）。
- **0.17.1（2026-10-23，分支 `hhikr/vibrant-ride-tzcih3`，Android build 39）**：开发者真机看 0.17.0 后的修正——换页改成整页从右推入、下面的页左移变暗
  （`smoothPageRoute` 是 `MaterialPageRoute`，下面的页才会动）；顶部标签不再撑满 180（Wiki 站点标签 `compact`）；没保存过 Wiki 来源时站点地址用默认值，不用浏览到的页面；
  关卡列表按编号自然排序、突袭（`#f#`）排在普通关卡之后并标“突袭”（`sortStages`，库里关卡没有 `sort_key`）；无向量提示改成“会显著下降”。只跑了测试，没上真机。

## 文档索引

- `docs/ARCHITECTURE.md`：项目结构与各模块的实现方式（从这里开始）。
- `docs/DESIGN.md`：界面设计（颜色、字体、部件、动效）与人机交互约定——**改界面前必读**。
- `docs/KNOWLEDGE_BASE_LESSONS.md`：建库、更新、修改知识库的经验、注意点、错误与终末地清单——**改建库代码前必读**。
- `docs/GAMEDATA_BUILD_PIPELINE.md`：表、四条构建路径（全量/增量/补算/App 内）、向量、目录、发布命令。
- `docs/ENDFIELD_STORY_ORDER.md`：终末地剧情怎么按任务步骤排列（关卡数据的格式、规则、库里的样子、审核与验证）——**改排列规则前必读**。
- `docs/ASK_AGENT.md`：问答 Agent 现在怎么工作（流程、工具、出处、答案格式、追问与查证、去重与压缩）。
- `docs/PORTRAITS.md`：剧情立绘与美术（剧本里的立绘、场景、CG、特写与判定规则，知识库的表，剧情美术包的来源与打包，App 的入口、阅读器与答案里的人名）——**改立绘或美术相关代码前必读**。
- `docs/ASK_EXPERIMENTS.md`：问答试过的所有办法、实测表现与评估、不要再试的、没试过的方向——**改问答之前必读**。
- `docs/LLM_PROVIDERS.md`：各模型服务的思考参数与兼容怪癖。
- `docs/WIKI.md`：Wiki 浏览（站点主题适配）与问答取证（站点接口、段落、快照、出处）。
- `docs/QA_CHECKLIST.md`：按改动范围的验收清单（含离线召回测试与真实模型测试的命令）。`test/README.md`：测试目录、夹具与约定。
- `docs/KNOWN_ISSUES.md`：仍开放的问题。
- `docs/ANDROID_SETUP_GUIDE.md`：本机构建、试装、发布；`docs/CLOUD_DEV.md`：云端会话。

## Do

- 运行相关 tests / analyze 后再汇报。保护 `logs/`。
- 保留 source path、raw id、content type、entity id。
- 剧情问答 Agent 查本地 GameData 库（`lore_tools.dart`），0.13 起可选查 PRTS / Warfarin Wiki（`wiki_tools.dart`，二手资料，出处同样核对）；
  用户文本和 Wiki 页里选中的文字只作上下文，不是证据。
- 界面照 `docs/DESIGN.md`（0.17 的设计与人机交互约定，**改界面前必读**）：推入页面用 `PageScaffold`、主标签页用 `MainTopBar`（`shared/widgets/page_frame.dart`，
  全 App 不用 `AppBar`）；列表用 `pagePadding`；部件从 `shared/widgets/ef_widgets.dart` 取（`AppButton`、`SquareIconButton`、`PressRow`、`NoticeBox`、`EmptyState`、
  `LoadingView`、`confirmAction`、`showAppSheet`/`showAppDialog`、`showToast`……），没有的按 DESIGN.md §3 从规则推，不另起样式。
- 长时操作（问答、知识库下载/构建、向量）包在 `BackgroundWork.instance.run(...)` 里（Android 前台服务保活）。
- 形状与动效：方角，**能点的才切一个角**（`CutBorder`）；图标用 `Icons.*_sharp`；动效走 `Motion`（`snap`/`mech` 曲线，`Motion.of` 在减少动效时为 0），不回弹、不缩放弹出、不做循环装饰。
  守卫测试：圆角/圆形/`_rounded`/回弹（`square_shapes_test`）、转圈/投影/红绿色/原生开关与底部弹出/小于 12 的字（`design_rules_test`）。
- 触控区至少 48×48，纯图标按钮必须有 `tooltip`；删除先问（`confirmAction(danger: true)`）；出错写在出错的地方（输入框 `errorText`、`NoticeBox`），不用红字。
- 资料页每个游戏一页（顶部标签切换，`SwitchedPages`），不能左右滑动换页。知识库页同样每个游戏一页，两页的组成和顺序相同；
  给一个游戏加的东西（状态、向量、提示）先想另一个游戏是否也要有。
- 输入框旁的面板、菜单用浮层且不取焦点（`canRequestFocus: false`），不要用会推路由的 `PopupMenuButton` / 底部弹窗（会把键盘收起来）。
- 资料页不做只有一行的中间页：集合从列表打开走 `openCollectionOf`（一篇剧情直接进阅读器、一类条目直接进列表）；短列表在集合页里就地列出；
  分组的长列表用组标题 + 选择条，不先列一页分组。
- 长文用阅读字体（`reading_text.dart`：`ReadingText`/`readingStyle`，字体由设置“阅读字体”定，默认黑体、可选霞鹜文楷），档案类文档用 `ProfileText`（每段可折叠，默认展开还是收起按设置“资料页的档案默认展开”），语音用 `VoiceLines`；
  剧情开头的官方梗概默认折叠（`FoldSection`）。
- 颜色：每个主题一种强调色（浅色信号黄、深色方舟蓝，开发者 2026-10-22 定下保留），`accentPrimary` 只做填充，表示当前位置、可以操作、需要注意；
  标出当前位置的线和字用 `trace`/`accentText`（浅色为墨，深色为蓝），强调色上的前景用 `onAccent`；**红色（`danger`）只给删除**，警告、出错用强调色小旗。
- 问答列表不随流式内容自动滚动（只在发新问题时滚到底一次）；思考窗口固定高度；阅读位置上方的内容在流式中不变高。不要加“贴底跟随”。
- 提交前 `git checkout -- android/gradle.properties`（Flutter 迁移器会往里加两行）。

## Do Not

- 不往知识库里导入玩法文字（技能、天赋、基建、商店、规则/任务说明、效果与数值、获得方式、敌人技能描述）；新数据源先判断“对剧情有没有参考价值”。
  叙事文字的收集规则是通用的（路径关键词 + 文字特征），不写活动名/剧情名/人物名表，也不为某个活动补特例。
- 条目的归属与绑定只来自表里的 id，不用名字猜；界面里由代码推出的名词以游戏表或 wiki 为准，查不到就不起名。
- 不新增别名/身份表来“修”某个角色（身份由 Agent 读原文确认）。
- 不恢复旧 Wiki seed / 旧用户资料索引链路 / 角色扮演。
- 不提交 API key、token、`.env`、keystore；不直接 push `main`。

## 提交规范（贡献者只有 hhikr）

- author / committer 只能是 hhikr；提交信息**禁止** `Co-Authored-By` 或任何 AI 署名尾注（2026-10 已改写历史移除，`.claude/settings.json` 的 `attribution` 已关闭，不要改回）。
- PR 标题不出现 Claude；Claude 不作为作者或协作者出现在任何提交信息里（开发者 2026-10-17 再次明确）。
- 凭据（`tools/api_info`、`tools/*apiKey*`、`tools/github_pat`、`tools/api.txt`、keystore 与签名配置）不得提交、打印、写入 git 配置或 remote URL。
  PAT 只在单条命令内用 `git -c "http.extraHeader=Authorization: Basic <base64(x-access-token:PAT)>" ...` 或 REST 请求头。

## 发布与签名

- APK 由 GitHub Actions 构建签名：推 `release/<版本>` 触发 `android-release.yml`（证书 SHA-256 `b1b09ebf…e364`）。
  一条命令：`tools/release_app.ps1 -Version <v> -NotesFile <md> [-Stable]`（Linux/云端 `tools/release_app.sh`）。云端不能建 Release（403）。
- **知识库只放在固定的 `gamedata-channel` Release 上**（开发者 2026-10-25 定）：App 每次打开知识库页都读那里的渠道文件，从那里检查和下载。
  更新时 `tools/publish_gamedata.ps1` 原地替换文件并重写渠道文件；`tools/release_gamedata.env` 的 URL 固定指向那里，只改 SHA、提交与日期、`GAMEDATA_MIN_APP_BUILD`。
  App 的 Release 只放 APK 与 `.sha256`，说明末尾一行指向知识库 Release。不要再把知识库传到 App 的 Release 或另建 `gamedata-<日期>` Release。详见 `docs/GAMEDATA_BUILD_PIPELINE.md` §7。
- 发版前先 `git fetch`，确认 `origin/main` 没有本分支之外的提交（别的会话可能已经发过版，0.19.0 时就是这样）。
- `release/<版本>` 分支只放构建 APK 的那一个提交：再推会重新构建，APK 哈希会变。
- 本地 `flutter build apk --release` 没有签名文件时退回 debug key，不能发布。本机试装用 `tools/install_local.ps1 -Build -Kb`。

## 检索与数据设计原则（防桥段专项优化）

背景：`story_chapter_profiles.keyword_hits` 曾内置 20 个死亡/凶案词，围绕“凶手问题”设计，覆盖面趋近于零还把模型锚定向单一方向（2026-08 已移除）。

1. 只做桥段无关的通用机制：可达性、确定性覆盖、通用信号、可对比的证据集；只对某类桥段有意义的特征一律拒绝。
2. 先量化再立项：用例占比极小的只能作为验收样例，不得驱动 schema / 特征设计。
3. 禁止硬编码“场景词典”作为检索特征；场景知识交给 Agent 在通用检索结果上完成。
4. 可复现且来源清晰：每个特征说得清来自哪些源字段、什么确定性规则；构建两次结果一致。
5. 不制造隐性证据：检索/画像字段只是浏览提示或定位线索，不参与事实判定。

## 禁止特判（R13，开发者硬性要求）

特判 = 只对某一类问题或某种剧情桥段生效的代码分支、阈值、提示词步骤或输出字段（反例：“至少比较 2 个嫌疑人”门槛、`culprit=` 信封）。

1. 所有剧情问题走同一条流程（`StoryQaAgent` → `LoreAgentLoop`）、同一份系统提示、同一套工具与出处核对。
2. 没有模式或分支；“条目安排”只讲输出格式；核查某个说法时 JSON 以 `verdict` 开头（结论由代码按已读并引用的原文降级），不得因此改变检索或判定规则。
3. 新增任何特判一律拒绝。自查 `grep -rnE "culprit|suspect|嫌疑|凶手|罪魁" lib/` 必须为空（`test/guards/no_special_case_test.dart` 守卫）。

## 禁止针对验收样例编程（anti-fixture-hardcoding）

1. `lib/` 不得出现具体实体名/实体 id/剧情桥段字面量作为判定分支或特征；实体名只能出现在注释、文案、测试 fixture。
2. 新逻辑换成不相关或虚构的实体，路径应同样成立；只对某样例有效的一律拒绝。
3. 测试 fixture 可以有具体实体，但不得复制进 `lib/` 的判定；断言只验证通用行为。
4. 自查：`grep -rn "特蕾西娅\|enemy_1554\|enemy_3006\|trap_762" lib/` 结果只应是注释/文案。

## 问答 Agent 的约定（详见 `docs/ASK_AGENT.md`，试过的做法与数据见 `docs/ASK_EXPERIMENTS.md`）

- 一个模型 + 通用工具（`search`（也可以用 `near` 找与一段读过的剧情相近的段落）、`read_story`、`read_record`、`grep`、只读 `sql`、`guide`（知识库手册：表、绑定、资料页结构）、`outline`（章节目录，末尾是相关的故事集）、`similar_names`、`gather`（按名字取材），开着“Wiki 资料”时 `search` 含 Wiki 并加 `wiki_search`、`wiki_read`，
  开着“子助手”时主 agent 另有 `delegate`），messages 只追加。
- 读有专门的工具：剧情用 `read_story`，剧情以外的资料（档案、语音、描述）用 `read_record`（按 id，两张表都找，分页，开头写所属对象）；
  `sql` 用来统计和按条件找，不用来翻页读长文。工具结果里凡是“属于谁”的信息都按表里的 id 给出，不让模型按内容猜。
- 0 行时的近似名提示只对“名字”说话：库里有这个名字（完全相同）时不提示；只取与名字列或正文比较的字面量，类别、id 片段不算名字。
- 答案 JSON 的解析要能读完模型写出的全部条目：中途多了括号提前闭合的，接着读同一个 entries 数组；读不下去而后面还有条目的，退回，不静默丢弃。
  字符串里没转义的引号按后文判断（只有接着 `}` 或 `, "<键>":` 才是结束），不在第一个引号处截断。
- 工具结果里“只列出一部分”的地方要写明剩下的在哪、怎么去看（`grep` 截断时列出没列出的命中所在的故事）；
  指路的话模型不照做而工具自己能做的，由工具做（`wiki_search` 多个词没有结果时逐词搜）。
- 第一批查找由一次独立的小调用拟定（`search_planner.dart` + `loreSearchPlanPrompt`，2026-10-10；10-11 起可以选种类）：它只看问题（追问时加上一问和上一答的要点）
  和各工具自己的说明，输出最多三条检索词、最多两个要看目录的故事集、最多两个 Wiki 搜索词（合计不超过四步）和一个附在第一条检索上的 Wiki 词，
  代码照着执行，以普通的 `search` / `outline` / `wiki_search` 调用和结果进入对话（可折叠），用户消息只有问题本身。
  **按名字取材**（重构第 1 期，开发者 2026-10-18 定下）：同一次小调用另写最多六个锚点（问题涉及的名字，`anchors`，不算在四步里），
  检索跑完后代码以一次 `gather` 调用取材（`coverage.dart`：锚点在剧情里出现和说话的行，按锚点稀有度与同场打分，每个故事集先给三篇，
  每处前后两行，约 3 万字，按上线顺序 `storyReleaseKey` 排列），登记为已读。依据是离线召回测试（`test/live/recall_eval_test.dart`）：
  检索加取材把日志题的金标行命中从 37% 提到 74%。这是固定的取材步骤，不是给模型的阅读计划；改它之前先重跑召回测试。
  追问时（S0）代码先用 `read_story` 把上一答引用过、读过的行段重读一遍（前后各两行，相距 20 行以内的合成一段，共最多 400 行，`followUpReads`）；0.20 起工具结果不再折叠，这一步经过去重，只读已被压缩掉的行。
  没拟定出来时：有向量就用问题原文按意思检索一次，没有向量就由主模型自己检索。**代码不从问题里切词、找名字**（切出来的是句子碎片；`search` 的关键词只是 query 里空格分开的词）。
- 工具调用先过守门（`tool_call_gate.dart`）：进入对话的调用参数必须是合法 JSON，非法调用不执行、报错写明正确写法；不要把模型的原始参数原样存进历史。
  不要加手写的进度规则（预算提示、读过就拒绝重读、阅读计划）；改进方向是工具表达力、工具输出的信息量和通用工作方式。
  0.20 的上下文去重（开发者 2026-10-25）只拦仍在上文的原文与相同调用，连续三轮全部拦下后要求直接作答；原文离开上下文后可重读。
  进度规则的例外有三条，都是开发者定的：第一轮由代码取材一次（上一条，2026-10-18）；答案 JSON 的 `missing`（说没查到的事和相关的名字）由代码用这些名字在没读过的剧情里再找一次，找到原文就连同答案交回重写一次（重构第 2 期 3.2，`_lookForMissing`，2026-10-19）；以及 2026-10-11 要的：**没有结果的查找**每个工具每次问答最多 6 次（`maxFailedLookups`），到了就不再执行那个工具；
  全是空结果的一轮在模型回复过一次之后不留在上下文里（`emptyTurns`），只留次数。对所有工具、所有问题一样，不要按问题种类调这个数。
- 指路的信息光写出来不够（八次路径：模型读完最相关的一篇就倾向于作答）：能确定地取到的原文由工具直接给（`search` 的“各给一段”），不靠模型去要；
  这不是进度规则，不要改成作答时按覆盖面退回。
- 词的分布（`termSpread`）和相近的段落（`search` 的 `near`）同样只是定位线索：分布不登记为已读；所有词同一个格式，不按词的种类分支、不判断“值不值得列”；
  `spread*`、`nearMinSimilarity` 这几个数来自真实库的实测，改之前先重看（`gamedata_v5_acceptance_test.dart`）。不要把相近段落自动附在 `read_story` 后面。
- 相关的故事集（`relatedCollections`）只是定位线索：库里没有数据能说明故事之间谁承接谁、谁先谁后，不要把它写成“前作/续作”表，
  也不要为某个系列补名单；门槛（`relatedMinLines`）和权重改动前先在真实库上看对照（`gamedata_v5_acceptance_test.dart`）。
- 审稿子 agent 只以读者身份提最多三个故事层面的问题，结论由主 agent 读原文决定；不让它逐条核实细节，不加针对某类剧情的检查项。
- 按阶段整理：出处由代码按 `from` 合并；段数只软性提示，不加硬性限制或截断。
- 审稿（“复核”）和整理（“提要”）不在一次提问里运行（0.14）：由答案下方的按钮触发，`AskChatNotifier.reviewAnswer` / `digestAnswer`。
  不要把它们加回 `AnswerOptions` 或循环里；复核有疑问时走的是同一条流程的追问（同一份提示、工具、出处核对），不是另一种模式。
- 出处：`story_id:起始行-结束行`、`record:<id>` 或 `wiki:<站点>:<页面>@<版本>:<段>`，必须是工具实际给模型看过的（`SeenLines`）。
  `SeenLines` 是唯一的“已读”账本：行只有连同正文展示才算读过，资料分全文与片段（片段可引用，检索结果里注明）；
  出处的范围只有一部分读过时由代码裁成读过的那几段，不整条删；折叠的工具结果留下它展示过的行段清单。新工具一律经它登记。
- 提示词与工具说明里**不放任何具体人物、章节、活动或剧情手法**；示意格式只用占位符（守卫测试）。
- 提示词里凡是代码要严格解析的格式，都给完整骨架；解析器对常见变体容错，丢弃的出处计数并退回一次。
- 答案写给玩家：正文不提库/表/文件名/id；照搬台词不由代码检查（2026-10-10 删去：退回只让模型去掉引号），提示词只要求不要大段照搬。
- 答案被退回（没有可识别的出处、多数出处没读过、出处缺行号）时整轮回档：出错的回答不进对话、不显示，
  原因（`recordNote` 事件）写进会话记录，并作为“记录：…”一行出现在工作过程里（默认折叠；2026-10-11 开发者要工作过程和会话记录一样详细）；
  重问时附的一条说明在答案被接受后从对话里拿掉。代码裁掉、删掉的出处同样是记录行。
- 工作过程（`work_steps.dart` + `chat_bubble.dart`）照会话记录的样子写：每一步是序号、工具名、模型写的参数原文、结果的字数和计数，
  加标记（拟定 / 已在上文 / 没有结果 / 出错 / 未执行 / Wiki 超时 / 助手 n）；点开是完整的参数和结果（限高、可滚动、可选中）。不要改回“在某处搜索某词”那样的概括句。
- 答案的状态：not_covered 由代码按核实过的出处数定；answered / partial 取决于模型自己报的 `coverage`（有没有声明遗漏），代码不核对。
  partial 不等于答得差：比较两版代码时看答案里有出处的故事集，不看 answered 的比例（`docs/ASK_AGENT.md` §5.3）。
- 思考档位每个角色显式指定，默认全部 off，“深度思考”= low（只给主 agent，0.21 起默认开）；不给剧情问答开 high。各家参数见 `docs/LLM_PROVIDERS.md`。
- 提示词留在 Dart 里（与解析器同版本、有守卫测试），不进 ARB。
- 系统提示词只放每次都要用的（工作方式、阅读原则、出处、答案格式）；只有某个工具用得上的参考内容放进手册（`loreLibraryManual`），
  由 `guide` 给出并随第一条 `sql` 附上。往提示词里加大段参考内容之前先想它是不是手册的一部分。

## 真实 API 测试的成本约束（开发者要求）

- 先离线（mock LLM）复现，确认后才动用真实 API。测试模型用 glm-5.3-flash（`tools/api_info` 的 `MODEL=`；免费的 glm-4.7-flash 并发 1、常过载，测不了）。
  **预计这一轮测试总消耗（模型 + 向量）≤150 万 token 直接跑；超过先说明估算、等开发者同意**（开发者 2026-10-19）。跑之前先用小样本量出每单位的实际用量再估。
- 每个方面最多 2 个最有代表性的用例（`ARKLORES_LIVE_IDS` 过滤），逐题串行，每题看完结果再跑下一题；不整批跑评测、不并行。
- 新机制带来的调用/token 增加只要不是数量级差异就先不处理，优先答案质量；验收表照常记录 usage。
- 向量嵌入同样花钱：优先按行对齐迁移（`build_story_embeddings.dart --migrate-from`）。

## 命令（Windows 开发机）

- flutter / dart：`C:\src\flutter\bin`；git：codex 自带
  `C:\Users\hhikr\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe`（同目录 `..\usr\bin` 有 sh、sed；没有 gzip，用 .NET `GZipStream`）。
  若当前 shell 没刷新 PATH：`$env:Path = "C:\src\flutter\bin;<git cmd 目录>;$env:Path"`。没有 `gh`：GitHub 用 REST API。
- Linux：`/home/hhikr/flutter/bin/flutter`；云端：`/opt/flutter`（会话开始先 `bash tools/cloud/session_start.sh`，见 `docs/CLOUD_DEV.md`）。
- PowerShell 5.1：设环境变量用 `$env:NAME='value'`；没有 `&&`；字符串替换前注意 CRLF 文件；`[regex]::Replace(x,y,z,1)` 的 1 是 IgnoreCase 不是次数。
- sqflite FFI 会把相对 DB 路径解析到 `.dart_tool` 下，`ARKLORES_GAMEDATA_DB` 等路径写绝对路径。
- 依赖 POSIX 文件替换语义的测试在 Windows 上跳过；临时目录用 `test/support/temp_dir.dart` 的 `deleteTempDir`。
- C 盘曾满到 0 字节，`flutter test` 编译失败后卡住半小时；全量测试正常约 1 分钟，明显变慢先查剩余空间。

```powershell
flutter test
flutter analyze
# 真实同链路问答（花钱；预计超过 150 万 token 先问开发者）
$env:ARKLORES_RUN_LIVE_ASK='true'; $env:ARKLORES_LIVE_QUERIES='问题一||问题二'
$env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_rebuild\arklores_gamedata_zh.db"
$env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"   # 可选：装上终末地库（双游戏问题）
flutter test test/live/ask_pipeline_live_test.dart
# 真机问答：带桥安装后在电脑上提问、实时看 App 的输出（docs/ANDROID_SETUP_GUIDE.md）
.\tools\install_local.ps1 -Build -Bridge; dart run tools/phone_ask.dart "问题"
# Wiki 接口联网检查（免费）
$env:ARKLORES_RUN_WIKI_CHECK='true'; flutter test test/live/wiki_live_test.dart
# 离线召回测试（免费，改问答的检索与取材时必做；完整写法见 docs/QA_CHECKLIST.md §3）
$env:ARKLORES_RUN_RECALL_EVAL='true'; $env:ARKLORES_RECALL_VECTORS="$PWD\build\recall_eval\query_vectors.json"
flutter test test/live/recall_eval_test.dart
```

- live 测试驱动 App 的 `askChatProvider`（只替换启动注入的 provider 与平台路径），输出 `build/live_sessions/` 下的会话 JSON 与 `*.summary.json`
  （`usage`、`timeline`）。追问用 `ARKLORES_LIVE_CONVERSATION=true`；`ARKLORES_LIVE_EVAL`/`ARKLORES_LIVE_IDS` 选评测题；`ARKLORES_LIVE_NO_EMBEDDING=true` 模拟无向量。
- 配置来自 gitignored 的 `tools/api_info`（API_KEY=/MODEL=/URL=）与 `tools/embedding-apiKey.csv`。
- 建库、更新、补算、向量、发布的命令见 `docs/GAMEDATA_BUILD_PIPELINE.md`。
