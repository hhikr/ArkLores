# ArkLores Developer Notes

明日方舟剧情阅读与问答 App（Flutter）。主线：中文 GameData 知识库（SQLite，schema 5 条目层 + 可选剧情向量/故事目录）+ 资料页（阅读）
+ 工具型问答 Agent（`LoreAgentLoop`，直接查库作答，代码核对出处）。向量、目录、梗概只作定位线索，不作证据。

- **已发布**：v0.13.0（正式版，2026-10-09，Android build 32）。两个知识库没变，原样附在 v0.13.0 Release 上（v0.11.0 / v0.12.0 上的仍在），
  `tools/release_gamedata.env` 指向 v0.13.0。v0.10.0 之前的 Release 已删（tag 都保留）；`release/v<版本>` 分支在发版后删掉（tag 指向同一提交）。
  下一轮开发从 `main` 新开分支。
- 未经开发者明确同意不发版、不跑花钱的真实 API 测试；Android build 号每次发版递增。
- **仓库里只放面向用户的内容和必要的开发约定**：调查笔记、方案讨论、普查数据放本地 `notes/`（gitignored），不提交、不写进 PR。
- 用中文和开发者交流。

## 当前进度（每轮结束时更新；细节进 CHANGELOG 与 docs，这里只留要点）

- **0.11（已发布）**：知识库重做为条目层（`entries`/`collections`/`entry_links`）、剧本全量解析、增量更新通道、用户库与阅读历史、
  资料页与阅读器、悬浮式界面与点击反馈、工作过程时间线、非 GLM 服务商兼容、删除角色扮演（开发者 2026-10-07 决定，不要恢复）。
  建库/更新/补算的经验与全部错误见 `docs/KNOWLEDGE_BASE_LESSONS.md`。
- **0.12（已发布，v0.12.0）**：终末地知识库与双游戏资料页/问答。设计见 `docs/KNOWLEDGE_BASE_LESSONS.md` §9–10，构建见 `docs/GAMEDATA_BUILD_PIPELINE.md` §9，
  已知限制见 `docs/KNOWN_LIMITATIONS_AND_DEBT.md` §5。
  - 架构：每个游戏一个库文件；终末地 id 一律 `ef/`（`game.dart`）；Agent 用 `MultiGameRetrieval`（`sql` 按 `game` 选库，`grep`/`find` 默认两个库），
    装了终末地时提示词加“两个游戏”一节（`loreGamesGuide` + `lore_endfield_prompts.dart`）；资料页每个游戏一页（明日方舟 / 终末地 / 我的资料）、页面按 id 路由；知识库页每个游戏一张下载卡。
  - 终末地建库：`tools/unpack_endfield.ps1`（AnimeStudio 导出客户端两层的表与 JSON 数据，Persistent 覆盖 StreamingAssets，不用 kit 的完整流程）→
    `tools/build_endfield_database.dart`：干员情报/档案/语音记录、情报档案库（PRTS）、敌人/武器/物品描述、对话/通讯/短信，
    任务名/简介/分类/所属干员/关卡来自 `MissionRuntimeAsset`（没有定义的任务不在游戏里，放 `unused`“未实装任务”，名字取 `TextTable`，都没有叫“无名任务（id）”；
    无名/同名的子任务并进基础任务，同书架重名加“·一阶段”），书架是游戏任务面板的分类（主线/探索/支线/活动/委派任务）；
    章节（主线的章·进程、干员的篇章）来自资源包的 `ChapterInfo`（`--chapters`），章节外的任务按地区分组。
    干员下挂三种集合：角色纪事（干员任务）、`baker` Baker 话题、`ship` 帝江号互动（后两种不是书架）；档案库按游戏分页（中枢档案/见闻辑录/音像存档/情报采集）。
    界面里的名词一律到 `TextTable` 的界面文字里查（每一层都查），查不到就不起名。
  - **一个任务一篇剧情**（参考 warfarin/fz 的编排）：段前一行 `section` 标种类，按种类分块、块内按编号；一段对话内部按对话树（`dlg_…` TextAsset）
    与过场时间线片段（`DialogTrunk/OptionPlayableAsset`）排，89% 台词行由它们定位，其余按行号。阅读器只在种类变化处写种类名。
  - 终末地资产带剧情向量（与明日方舟同一模型；切块在 `section` 处断开）。重建后先 `build_story_embeddings.dart --migrate-from=<旧库>` 按行对齐搬旧向量，
    剩下的块多半在 `build/embedding_cache/` 里（`--dry-run` 看 “to embed”，非零才花钱，要先问）；`unpack_endfield.ps1 -Embed` 是直接补全。
  - 待开发者决定：真实 API 跑一两道双游戏问题验证选库（花钱，未跑；live 测试用 `ARKLORES_ENDFIELD_DB` 装上终末地库）。
  - 本机工具（不提交）：`C:\Users\hhikr\endfield\`（kit、embeddable Python、导出数据；`python312\python.exe` 带 sqlite3，可直接查库）。
- **0.13（已发布，v0.13.0）**：问答 Agent 的 Wiki 检索与证据，设计见 `docs/WIKI_EVIDENCE.md`，已知限制见 `docs/KNOWN_LIMITATIONS_AND_DEBT.md` §6。
  - 工具 `wiki_search` / `wiki_read`（明日方舟 PRTS 的 MediaWiki API；终末地 Warfarin 的搜索 API + 服务端渲染页；fz.wiki 无公开接口且开发机连不上，没选）；
    页面按段编号，出处 `wiki:<站点>:<页面>@<版本>:<段>`，与剧情出处同一套核对（只能引用展示过的段、照搬退回）；读过的版本存快照（`wiki_snapshots/`）。
  - Wiki 是二手资料：剧情事实以库里原文为准，只有 Wiki 支持的说法要写明（`loreWikiGuide`）。输入框“回答选项”里的“Wiki 资料”开关，默认开。
  - 界面：证据卡与出处树里的 Wiki 行、引用段落弹窗（快照、在 Wiki 标签打开）、工作过程里的 Wiki 步骤。
  - 真实模型已各游戏验收（2026-10-09，`docs/WIKI_EVIDENCE.md` §7）：先查库、Wiki 只补库里没有的并写明。真机只看到安装与“回答选项”里的 Wiki 开关；
    带 Wiki 出处的答案（出处卡、弹窗、“在 Wiki 中打开”）只用真实页面快照渲染截图检查过，下次真机检查时补看。
- **0.14（开发中，`feature/v0.14-ask`，2026-10-09 从 `main` 开）**：问答工作流重构。依据是 v0.13.0 真机 10 个会话（评估在本地 `notes/ask_0.14_review.md`），
  设计与改动见 `docs/R17_TOOL_AGENT.md` §5，已知限制见 `docs/KNOWN_LIMITATIONS_AND_DEBT.md` §7。
  - 开发者决定（2026-10-09）：Wiki 与本地库**检索同级**，答案仍区分来源；以向量（语义）检索为主，没有向量服务时自动退回关键词并提示“问答质量可能下降”；
    审稿与子助手默认关闭；不发 0.13.1，直接全量重构。
  - 已做：统一检索 `search`（取代 `find`）+ 问题预检索；工具调用守门（`tool_call_gate.dart`）；数据库连接独立（修 `database_closed`）；
    流式解析按 id 分开同 index 的调用；空回复只对一轮降级；等待与失败可见、取消立即生效；出处少量问题由代码删去；整理只发条目；工作过程显示故事名、失败原因、子助手步骤。
  - 真实 API 验收（2026-10-09，开发者同意）：两套 API（`tools/api_info` 较好的 GLM、`tools/garbage_api_info.txt` 较弱的 gemini 中转，键名 `API=`）× 两题全部 answered，
    结果与据此做的修正见 `docs/R17_TOOL_AGENT.md` §5。`search` 现在也查资料（档案、干员资料、语音等，含 `entity_documents` 的干员档案合集）。
    第二轮（同日）在电脑上验收追问、核查、无向量，修了追问预检索、`record:record:` 出处、无向量关键词（短语）。
    2026-10-10：无向量时不预检索、由模型写检索词（评测集上代码定的关键词只有 16/29 题命中金标），结果列出每个词的命中行数；
    答案用提问的语言写；一次回复里有几份答案时取最后一份完整的。GLM 实测良好；较弱的 gemini 检索正常但作答不稳。
  - 真机测试工具：`tools/phone_ask.dart` + `install_local.ps1 -Bridge`（`lib/features/ai/phone_bridge.dart`，只在本地构建里），见 `docs/ANDROID_SETUP_GUIDE.md`。
  - 真机两份会话之后（2026-10-10，开发者在手机上问的两个会话；设计经开发者确认，`docs/R17_TOOL_AGENT.md` §5 末）：
    第一批检索改由独立的小调用拟定（代码不再切词）；答案被退回时整轮回档；删去照搬台词的检查；“已读”统一成一本账、出处裁到读过的行；
    较远的游戏只列一行、资料按词的稀有度加权、检索分段计时；提示词按角色组合。
    同日真机复跑（带桥，GLM，同一会话两问）：都 answered、出处全部通过；拟定检索词 1.3–1.6 秒、能用但会带进不相干的名字；总耗时没有明显下降；
    分段计时显示检索的大头是关键词扫描（单次约 2.3 秒，三条并行时每条 5 秒多）。退回与出处裁剪两条路径在真机上没被触发，仍只有离线用例。
  - 同一问题的两份真机会话之后（2026-10-10 下午，`docs/R17_TOOL_AGENT.md` §5 末）：答案 JSON 提前闭合不再丢条目；新工具 `read_record`；
    `sql` 的已读登记与单行不截断；0 行提示不再说假话；汇总行数所有展示过正文的故事；语音的所属干员名在派生步骤按 id 填上；
    **资料向量**（`record_chunk_vectors`，两个库的每条资料，`docs/GAMEDATA_BUILD_PIPELINE.md` §5）。本机两个库已补算并嵌入，资产没有发布。
    评测集上拟定检索词 25/29（带向量）；GLM 在电脑上验三题全部 answered（同一问题 72 秒 / 5 次调用，改前真机 120 秒 / 20 次）；
    较弱的 gemini 中转返回 404，没跑成。
  - 真机验收（2026-10-10 傍晚，带桥的包 + 本机构建的两个库，17 题全部答完，`docs/R17_TOOL_AGENT.md` §5 末）：修了嵌入脚本迁移时漏掉从没有向量的剧情
    （289 篇，v0.13.0 资产同样，已补）和 `search` 里只按意思找到的资料被关键词命中挤掉；退回与出处裁剪在真机上都触发过。界面只经桥看了文字。
  - 输入框选项、答后操作、知识库页（2026-10-10 晚，方案经开发者确认；`docs/R17_TOOL_AGENT.md` §5 末、`docs/GAMEDATA_BUILD_PIPELINE.md` §4.4）：
    输入框只剩一个选项按钮，面板从输入框上沿向上展开、不取焦点（键盘不动），里面是 Wiki 资料 / 子助手 / 深度思考（服务商有思考开关时才有）；
    **提要与复核不再是提问的选项**，是答案下方的按钮（提要：5 条以上条目的答案；复核：只对最后一条，作为单独一轮，原答案不动；都只对本次运行期间的答案有）；
    知识库页每个游戏一页（官方知识库 → 语义检索 → 更新方式），向量卡片按游戏分；本机更新过的库有 `.local_build` 标记、不再被提示“更新”成较旧的官方资产；
    会丢向量的完整重建先确认。只有离线用例与布局截图，**没有真机、没有真实模型**。
  - 知识库瘦身（2026-10-10 夜，开发者要求；`docs/GAMEDATA_BUILD_PIPELINE.md` §3）：没有代码读、模型也从没查过的表全部从建库与更新里删掉——
    `lore_chunks(_fts)`、`story_lines_fts`、`entity_documents_fts`、`entity_relations`、覆盖层三张表（`entity_story_mentions` / `rare_terms` /
    `story_chapter_profiles`）、剧情的切块记录副本、说话人实体；`StoryCoverageBuilder` 已删，增量更新不再把几千篇剧情重扫一遍。
    schema 仍是 5，旧库照常能装，更新时由 `dropObsoleteGamedataData` 清掉再 `VACUUM`（命令行 `tools/compact_gamedata.dart`）。
    明日方舟库 701 → 292 MB（内容与向量逐行一致，向量按行迁移没花钱），终末地 62 → 31 MB。新库只随新版本发布（v0.13.0 的校验要求旧表）。
    更新卡片的旧报错在下一次检查/更新开始时清掉。**不要把这些表或“覆盖层”加回来**；加表前先写清谁读它。
  - “用游戏数据更新”的三处修正（同夜，真机上遇到；`docs/GAMEDATA_BUILD_PIPELINE.md` §4.4）：取消会真正停下下载、上一次运行没结束前不开第二次
    （否则两次运行互相删源目录里的表，导入报“Missing required GameData file”）；每次开始时删掉失败的构建留下的整库副本；
    更新完成后已装提交就是最新提交，“拉取并更新”变灰，直到再次检查到新提交或换了库。
    桥能按知识库页的按钮：`phone_ask.dart --kb=status|install|check|update`（`update` 会改手机上的库，先问开发者）。
    手机上现在是瘦身后的、停在上游 `a550f5e`（9 月 29 日）的库，**留给开发者自己验证更新**；经桥跑通过一次（187 秒），按钮变灰只有离线用例。
  - 对话记录改成“对话列表”（2026-10-10 深夜，开发者要求）：问答页右上角不再有“最近阅读”（它在资料页）；对话记录不限条数、按页读取
    （`ChatSessionStore.count/page`，分页条 `shared/widgets/page_bar.dart` 与最近阅读共用）；点一条就把它换成当前对话，当前对话带标记；
    每行只有删除（最近阅读同样加了逐条删除按钮）；对话从第一个问题发出时就写进记录。只读的“查看”页已删。只有离线用例，**没有真机**。
  - 按故事集来问的问题（2026-10-11，依据“某个故事集之前发生了什么”的两份真机会话，方案经开发者确认；`docs/R17_TOOL_AGENT.md` §5 末）：
    `outline` 末尾列出相关的故事集（共有说话人——SQL 数行数、两边各 10 行以上——与剧情向量的故事集平均方向按名次融合，前 6 个，现算不加表，只是线索）；
    `search` 的词是故事集名时如实说；拟定的第一批查找可以是 `search` / `outline` / `wiki_search`；工作方式加“先确定范围”“目录搭骨架、出处要是讲这件事的行”；
    Wiki 说明改成实际情况。GLM 在电脑上验两题（用从手机拉下来的库 `build/gamedata_phone_1010/`）：8 次 / 15.4 万、6 次 / 10.6 万输入
    （改前真机 12 次 / 34.1 万、21 次 / 56.8 万），相关的前作都讲到。**没有真机。**
  - 工具说出“这个词在哪几部故事里”（2026-10-11，三项都做，开发者确认；`docs/R17_TOOL_AGENT.md` §5 末）：`search` / `grep` 写出每个词的命中按故事集的分布
    （统一格式：列到八成或 6 部、补“占比高的”短篇、写出其余的占比；`computeTermSpread`，现算不加表、不算已读）；
    `search` 的 `near`（一段读过的剧情的位置，用库里的向量找别的故事集里相近 0.70 以上的段落，不调嵌入服务；`query` / `near` 至少给一个，`AgentTool.requireOneOf`）；
    `read_record` 第一页写所属对象的名字分布（多扫一遍台词表，手机上的代价没量，是否保留待开发者定）。
    GLM 在电脑上验两题都 answered；按人物那题新旧代码各跑 4 次：五部都讲到的改前 1 次、改后 2 次（改后是带 `collection` 到分布里的故事集去查），
    **模型照不照分布去找仍不稳定**（另 2 次没去；按组织那题拿故事集名当检索词，没看目录）。单次结果不能下结论，要比较就两边各跑几次。**没有真机。**
    同日再改（开发者定）：**`search` 给分布里列出、最相关 5 篇没覆盖的故事集各一段原文**（`_elsewhere`，每个游戏最多 6 段，较少见的词先取）；
    分布下写明故事集名用在 `collection` / `outline`、不是检索词；工作方式加“分布里列出的故事集都要有读到的原文再作答”。
    同一题 4 次全部讲全（改前 1/4、只有分布 2/4），代价是输入约 2–3 倍（5.2–15.3 万）、耗时 61–90 秒。只有这一题、一个模型。
    表结构收进手册（同日，开发者提出）：表与列、绑定、资料页结构、终末地库的结构不再进系统提示词（9922 → 约 6000 字），
    由 `guide` 工具给出，没看过时随一次问答的第一条 `sql` 结果附上（`LibraryManual`）；阅读原则（时间、同一人物、终末地的读法）留在提示词里。
    按人物那题 2 次仍讲全、输入 2.7 / 5.9 万；一道要查表的题跑成 29 次 `sql`、47 万输入（库里查不到要的条目，模型停不下来；没有改前的对照）。
    那道查表题查出一个建库的错（已改，`docs/KNOWLEDGE_BASE_LESSONS.md` §“复刻不是独立内容”）：复刻过的活动的关卡挂在复刻的区域下、被当成复刻删掉，
    41 个 SideStory 一直没有关卡和敌人绑定。全量重建核对过（关卡 1843 → 3241），**本机和手机的库还没有重建**。
    没有结果的查找有了上限、不留在上下文里（同日，开发者要求）：同一道查表题在旧库上 31 次 / 47 万 → 13 次 / 34 万；
    模型不记得试过什么、同一条查询发了 3 次，所以次数旁边留下试过的调用的简短清单。
    本机的库已用修正后的建库代码重建并替换 `build/gamedata_v5`（源 `a550f5e`，关卡 3241，向量齐全；旧的留作 `.pre11`；gz 的 SHA `ef6e177e…dae3ef`），**没有装到手机、没有发布**。
    同一题在它上面一次 6 次 / 10.8 万 / 55 秒查出 25 种敌人，另一次模型没查表、读 Wiki 作答（8 次 / 19.5 万）；按人物、按组织的题照常答全。
    实测否定的做法不要再试：读资料时按向量指向相关剧情、读剧情时自动附相近段落。
  - 历史问题集（2026-10-11 下午，开发者要求；`docs/R17_TOOL_AGENT.md` §5 末）：手机上实际问过的 52 份会话整理成 37 问
    （`test/fixtures/history_questions_eval.json`，追问链用 `session` 分组），电脑上整套跑完：全部答完，47 分 39 秒、516.6 万输入，输出在本机 `build/live_sessions/history_1011/`。
    据此改了：答案 JSON 里没转义的引号把每条截断（一份答案只剩两成）、`grep` 同时给 `story_ids` 与 `collection` 时范围被放大、不是 JSON 的答案里括号里的出处、
    `wiki_search` 多词没有结果时工具自己逐词搜、`grep` 截断时列出没列出的命中在哪、同一个词的 Wiki 搜索合并成一次请求（`search` 等 Wiki 最多 8 秒）。
    没改的：英文提问用中文作答、拟定的检索带进无关的词、集成战略结局与主线混讲。改后只重跑三题，**没有真机**。
  - 工作过程改成会话记录那样的明细（同日，开发者看了测试结果的网页后要求）：每步写工具名和参数原文、结果字数、标记，点开看完整结果；
    退回和出处裁剪的原因作为记录行显示。只有离线用例（320dp 宽无溢出），**没有真机**。
  - 知识库的更新顺序（同日，开发者定；`docs/GAMEDATA_BUILD_PIPELINE.md` §4.4）：**游戏数据较新的在前；同一份游戏数据，官方资产在本机更新的之前。**
    构建时写进官方资产所基于的提交和那个提交的日期（`tools/release_gamedata.env` 的 `GAMEDATA_DB_COMMIT` / `GAMEDATA_DB_COMMIT_DATE`，发新资产时一起改）；
    本机更新过的库只在官方资产是同一个提交、或是更新之后才有的提交时才被提示“更新”（`GameDataInstallStatus.updateReason`）；官方卡写明来源（官方发布 / 本机更新）；
    官方资产就是上游最新提交时，“拉取并更新”让位给上面的“更新”。App 不会自己去 GitHub 找新资产：新的官方库要随新的 App 构建才看得到。
    手机上现在是带桥的这一版 + 电脑重建的库（上游 `a550f5e`，有关卡修正，来源显示为官方发布；之前那份本机更新到 `17759cc` 的库被它替换了）。
  - **交接说明与遗留问题清单：`docs/ASK_0.14_HANDOFF.md`**（接手这个分支先读它）。
  - 待开发者决定（清单在交接说明 §2）：是否 push 本机的提交；是否发布带资料向量的知识库资产、是否发版；写短的故事路径出处要不要补回；
    是否再收紧拟定检索的提示词；是否优化关键词扫描；`read_record` 的名字分布和 `search` 的 `near` 是否保留（真实模型下一次没用上 / 没被调用）；“各给一段”带来的输入增加要不要收（段数、每段行数）。

## 文档索引

- `docs/KNOWLEDGE_BASE_LESSONS.md`：建库、更新、修改知识库的经验、注意点、错误与终末地清单——**改建库代码前必读**。
- `docs/GAMEDATA_BUILD_PIPELINE.md`：表、四条构建路径（全量/增量/补算/App 内）、向量、目录、发布命令。
- `docs/AI_ARCHITECTURE.md`：问答链路与设计原则；`docs/R17_TOOL_AGENT.md`：Agent 的工具、提示词约定、出处核对、验收数据。
- `docs/LLM_PROVIDERS.md`：各模型服务的思考参数与兼容怪癖。
- `docs/WIKI_EVIDENCE.md`：问答的 Wiki 检索与证据（站点、段落、快照、出处）。
- `docs/LIBRARY_AGENT_GUIDE.md`：资料页结构说明（问答 Agent 查库前参考；正文在 `loreLibraryGuide`）。
- `docs/RETRIEVAL_QA.md`：按改动范围的验收清单。`test/README.md`：测试目录、夹具与约定。
- `docs/KNOWN_LIMITATIONS_AND_DEBT.md`：仍开放的问题。
- `docs/ANDROID_SETUP_GUIDE.md`：本机构建、试装、发布；`docs/CLOUD_DEV.md`：云端会话；`docs/WIKI_SITE_ADAPTATION.md`：Wiki 站点适配。

## Do

- 运行相关 tests / analyze 后再汇报。保护 `logs/`。
- 保留 source path、raw id、content type、entity id。
- 剧情问答 Agent 查本地 GameData 库（`lore_tools.dart`），0.13 起可选查 PRTS / Warfarin Wiki（`wiki_tools.dart`，二手资料，出处同样核对）；
  用户文本和 Wiki 页里选中的文字只作上下文，不是证据。
- 新的推入页面用 `FloatingScaffold`（`shared/widgets/floating_bar.dart`，全 App 不用 `AppBar`，有守卫测试）；主页面里的列表用 `floatingPadding`；
  新的可点块用 `PressFeedback` + `withHaptic`。
- 长时操作（问答、知识库下载/构建、向量）包在 `BackgroundWork.instance.run(...)` 里（Android 前台服务保活）。
- 形状与动效照两款游戏：方角（卡片用切角 `ThemeAwareCard`），图标用 `Icons.*_sharp`，选中的标签用 `SelectionBar` 擦入的横条，
  悬浮板用 `FloatingBar`（角标）；动效短、直线、无回弹（`easeOutCubic`/`easeOutExpo`）。圆角、圆形、`_rounded` 图标、回弹曲线有守卫测试（`test/guards/square_shapes_test.dart`）。
- 资料页每个游戏一页（顶部标签切换，`SwitchedPages`），不能左右滑动换页。知识库页同样每个游戏一页，两页的组成和顺序相同；
  给一个游戏加的东西（状态、向量、提示）先想另一个游戏是否也要有。
- 输入框旁的面板、菜单用浮层且不取焦点（`canRequestFocus: false`），不要用会推路由的 `PopupMenuButton` / 底部弹窗（会把键盘收起来）。
- 资料页不做只有一行的中间页：集合从列表打开走 `openCollectionOf`（一篇剧情直接进阅读器、一类条目直接进列表）；短列表在集合页里就地列出；
  分组的长列表用组标题 + 选择条，不先列一页分组。
- 长文用阅读字体（`reading_text.dart`：`ReadingText`/`readingStyle`），档案类文档用 `ProfileText`（每段可折叠、默认展开），语音用 `VoiceLines`；
  剧情开头的官方梗概默认折叠（`FoldSection`）。
- 颜色：信号黄（`accentPrimary`）只做填充和粗线；文字、图标、细边框用 `accentText`，黄底上的前景用 `onAccent`。
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
- 凭据（`tools/api_info`、`tools/*apiKey*`、`tools/github_pat`、`tools/api.txt`、keystore 与签名配置）不得提交、打印、写入 git 配置或 remote URL。
  PAT 只在单条命令内用 `git -c "http.extraHeader=Authorization: Basic <base64(x-access-token:PAT)>" ...` 或 REST 请求头。

## 发布与签名

- APK 由 GitHub Actions 构建签名：推 `release/<版本>` 触发 `android-release.yml`（证书 SHA-256 `b1b09ebf…e364`）。
  一条命令：`tools/release_app.ps1 -Version <v> -NotesFile <md> [-Stable]`（Linux/云端 `tools/release_app.sh`）。云端不能建 Release（403）。
- 知识库资产的 URL/SHA 在 `tools/release_gamedata.env`，**先指向将要创建的 Release** 再构建 APK；资产 gz 与 manifest 另行上传。详见 `docs/ANDROID_SETUP_GUIDE.md`。
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

## 问答 Agent 的约定（详见 `docs/R17_TOOL_AGENT.md`）

- 一个模型 + 通用工具（`search`（也可以用 `near` 找与一段读过的剧情相近的段落）、`read_story`、`read_record`、`grep`、只读 `sql`、`guide`（知识库手册：表、绑定、资料页结构）、`outline`（章节目录，末尾是相关的故事集）、`similar_names`，开着“Wiki 资料”时 `search` 含 Wiki 并加 `wiki_search`、`wiki_read`，
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
  没拟定出来时：有向量就用问题原文按意思检索一次，没有向量就由主模型自己检索。**代码不从问题里切词、找名字**（切出来的是句子碎片；`search` 的关键词只是 query 里空格分开的词）。
- 工具调用先过守门（`tool_call_gate.dart`）：进入对话的调用参数必须是合法 JSON，非法调用不执行、报错写明正确写法；不要把模型的原始参数原样存进历史。
  不要加手写的进度规则（预算提示、重读拒绝、阅读计划）；改进方向是工具表达力、工具输出的信息量和通用工作方式。
  唯一的例外是开发者 2026-10-11 要的：**没有结果的查找**每个工具每次问答最多 6 次（`maxFailedLookups`），到了就不再执行那个工具；
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
  加标记（拟定 / 重复 / 没有结果 / 出错 / 未执行 / Wiki 超时 / 助手 n）；点开是完整的参数和结果（限高、可滚动、可选中）。不要改回“在某处搜索某词”那样的概括句。
- 答案的状态：not_covered 由代码按核实过的出处数定；answered / partial 取决于模型自己报的 `coverage`（有没有声明遗漏），代码不核对。
  partial 不等于答得差：比较两版代码时看答案里有出处的故事集，不看 answered 的比例（`docs/R17_TOOL_AGENT.md` §“状态信封”）。
- 思考档位每个角色显式指定，默认全部 off，“深度思考”= low；不给剧情问答开 high。各家参数见 `docs/LLM_PROVIDERS.md`。
- 提示词留在 Dart 里（与解析器同版本、有守卫测试），不进 ARB。
- 系统提示词只放每次都要用的（工作方式、阅读原则、出处、答案格式）；只有某个工具用得上的参考内容放进手册（`loreLibraryManual`），
  由 `guide` 给出并随第一条 `sql` 附上。往提示词里加大段参考内容之前先想它是不是手册的一部分。

## 真实 API 测试的成本约束（开发者要求）

- 先离线（mock LLM）复现，确认后才动用真实 API；开发者同意后才跑。
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
# 真实同链路问答（花钱，先问开发者）
$env:ARKLORES_RUN_LIVE_ASK='true'; $env:ARKLORES_LIVE_QUERIES='问题一||问题二'
$env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_v5\arklores_gamedata_zh.db"
$env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"   # 可选：装上终末地库（双游戏问题）
flutter test test/live/ask_pipeline_live_test.dart
# 真机问答：带桥安装后在电脑上提问、实时看 App 的输出（docs/ANDROID_SETUP_GUIDE.md）
.\tools\install_local.ps1 -Build -Bridge; dart run tools/phone_ask.dart "问题"
# Wiki 接口联网检查（免费）
$env:ARKLORES_RUN_WIKI_CHECK='true'; flutter test test/live/wiki_live_test.dart
```

- live 测试驱动 App 的 `askChatProvider`（只替换启动注入的 provider 与平台路径），输出 `build/live_sessions/` 下的会话 JSON 与 `*.summary.json`
  （`usage`、`timeline`）。追问用 `ARKLORES_LIVE_CONVERSATION=true`；`ARKLORES_LIVE_EVAL`/`ARKLORES_LIVE_IDS` 选评测题；`ARKLORES_LIVE_NO_EMBEDDING=true` 模拟无向量。
- 配置来自 gitignored 的 `tools/api_info`（API_KEY=/MODEL=/URL=）与 `tools/embedding-apiKey.csv`。
- 建库、更新、补算、向量、发布的命令见 `docs/GAMEDATA_BUILD_PIPELINE.md`。
