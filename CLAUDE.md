# ArkLores Developer Notes

明日方舟剧情阅读与问答 App（Flutter）。主线：中文 GameData 知识库（SQLite，schema 5 条目层 + 可选剧情向量/故事目录）+ 资料页（阅读）
+ 工具型问答 Agent（`LoreAgentLoop`，直接查库作答，代码核对出处）。向量、目录、梗概只作定位线索，不作证据。

- **已发布**：v0.11.0（正式版，2026-10-08，Android build 28；知识库资产在 v0.11.0 Release，`tools/release_gamedata.env` 指向它）。
- **预发布**：v0.12.1（2026-10-08，build 30）—— 终末地知识库，按任务编排（分支 `feature/v0.12-endfield`；资产在 v0.12.1 Release，v0.12.0 的旧结构资产已不用）。
- 未经开发者明确同意不发版、不跑花钱的真实 API 测试；Android build 号每次发版递增。
- **仓库里只放面向用户的内容和必要的开发约定**：调查笔记、方案讨论、普查数据放本地 `notes/`（gitignored），不提交、不写进 PR。
- 用中文和开发者交流。

## 当前进度（每轮结束时更新；细节进 CHANGELOG 与 docs，这里只留要点）

- **0.11（已发布）**：知识库重做为条目层（`entries`/`collections`/`entry_links`）、剧本全量解析、增量更新通道、用户库与阅读历史、
  资料页与阅读器、悬浮式界面与点击反馈、工作过程时间线、非 GLM 服务商兼容、删除角色扮演（开发者 2026-10-07 决定，不要恢复）。
  建库/更新/补算的经验与全部错误见 `docs/KNOWLEDGE_BASE_LESSONS.md`。
- **0.12（v0.12.0 预发布，`feature/v0.12-endfield`）**：终末地知识库与双游戏资料页/问答。设计见 `docs/KNOWLEDGE_BASE_LESSONS.md` §9–10，构建见 `docs/GAMEDATA_BUILD_PIPELINE.md` §9，
  已知限制见 `docs/KNOWN_LIMITATIONS_AND_DEBT.md` §5。
  - 架构：每个游戏一个库文件；终末地 id 一律 `ef/`（`game.dart`）；Agent 用 `MultiGameRetrieval`（`sql` 按 `game` 选库，`grep`/`find` 默认两个库），
    装了终末地时提示词加“两个游戏”一节（`loreGamesGuide` + `lore_endfield_prompts.dart`）；资料页每个游戏一页（明日方舟 / 终末地 / 我的资料）、页面按 id 路由；知识库页每个游戏一张下载卡。
  - 终末地建库：`tools/unpack_endfield.ps1`（AnimeStudio 导出客户端两层的表与 JSON 数据，Persistent 覆盖 StreamingAssets，不用 kit 的完整流程）→
    `tools/build_endfield_database.dart`：干员档案与语音、档案库（PRTS）、敌人/武器/物品描述、对话/通讯/短信（选项按组号插入），
    任务名/简介/分类/所属干员/关卡来自 `MissionRuntimeAsset`（没有定义的取 `TextTable` 的 `<任务>_name`、子任务共同名，都没有叫“无名任务（id）”；
    隐藏/同名的子任务并进基础任务），书架是游戏任务面板的分类（主线/探索/支线/活动/委派任务），书架内按地区分组、显示任务简介。
    干员下挂三种集合：`memory` 干员任务（按系列名分组）、`baker` Baker 话题、`ship` 帝江号互动（后两种不是书架）；档案库按游戏分页（中枢档案/见闻辑录/音像存档/情报采集）。
    界面里的名词一律到 `TextTable` 的界面文字里查（每一层都查），查不到就不起名。
  - **一个任务一篇剧情**（参考 warfarin/fz 的编排）：段前一行 `section` 标种类，按种类分块、块内按编号；一段对话内部按对话树（`dlg_…` TextAsset）
    与过场时间线片段（`DialogTrunk/OptionPlayableAsset`）排，89% 台词行由它们定位，其余按行号。阅读器只在种类变化处写种类名。
  - 终末地资产带剧情向量（与明日方舟同一模型；重建后 `unpack_endfield.ps1 -Embed` 补，缓存命中不收费；切块在 `section` 处断开）。
  - 待开发者决定：真实 API 跑一两道双游戏问题验证选库；转正式版。
  - 本机工具（不提交）：`C:\Users\hhikr\endfield\`（kit、embeddable Python、导出数据）。
## 文档索引

- `docs/KNOWLEDGE_BASE_LESSONS.md`：建库、更新、修改知识库的经验、注意点、错误与终末地清单——**改建库代码前必读**。
- `docs/GAMEDATA_BUILD_PIPELINE.md`：表、四条构建路径（全量/增量/补算/App 内）、向量、目录、发布命令。
- `docs/AI_ARCHITECTURE.md`：问答链路与设计原则；`docs/R17_TOOL_AGENT.md`：Agent 的工具、提示词约定、出处核对、验收数据。
- `docs/LLM_PROVIDERS.md`：各模型服务的思考参数与兼容怪癖。
- `docs/LIBRARY_AGENT_GUIDE.md`：资料页结构说明（问答 Agent 查库前参考；正文在 `loreLibraryGuide`）。
- `docs/RETRIEVAL_QA.md`：按改动范围的验收清单。`test/README.md`：测试目录、夹具与约定。
- `docs/KNOWN_LIMITATIONS_AND_DEBT.md`：仍开放的问题。
- `docs/ANDROID_SETUP_GUIDE.md`：本机构建、试装、发布；`docs/CLOUD_DEV.md`：云端会话；`docs/WIKI_SITE_ADAPTATION.md`：Wiki 站点适配。

## Do

- 运行相关 tests / analyze 后再汇报。保护 `logs/`。
- 保留 source path、raw id、content type、entity id。
- 剧情问答 Agent 只查本地 GameData 库（`lore_tools.dart`）；Wiki 和用户文本只能作为浏览/上下文。
- 新的推入页面用 `FloatingScaffold`（`shared/widgets/floating_bar.dart`，全 App 不用 `AppBar`，有守卫测试）；主页面里的列表用 `floatingPadding`；
  新的可点块用 `PressFeedback` + `withHaptic`。
- 长时操作（问答、知识库下载/构建、向量）包在 `BackgroundWork.instance.run(...)` 里（Android 前台服务保活）。
- 形状与动效照两款游戏：方角（卡片用切角 `ThemeAwareCard`），图标用 `Icons.*_sharp`，选中的标签用 `SelectionBar` 擦入的横条，
  悬浮板用 `FloatingBar`（角标）；动效短、直线、无回弹（`easeOutCubic`/`easeOutExpo`）。圆角、圆形、`_rounded` 图标、回弹曲线有守卫测试（`test/guards/square_shapes_test.dart`）。
- 资料页每个游戏一页（顶部标签切换，`SwitchedPages`），不能左右滑动换页。
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

- 一个模型 + 通用工具（只读 `sql`、`grep`、`read_story`、`find`、`outline`、`similar_names`，主 agent 另有 `delegate`），messages 只追加。
  不要加手写的进度规则（预算提示、重读拒绝、阅读计划）；改进方向是工具表达力、工具输出的信息量和通用工作方式。
- 审稿子 agent 只以读者身份提最多三个故事层面的问题，结论由主 agent 读原文决定；不让它逐条核实细节，不加针对某类剧情的检查项。
- 按阶段整理：出处由代码按 `from` 合并；段数只软性提示，不加硬性限制或截断。
- 出处：`story_id:起始行-结束行` 或 `record:<id>`，必须是工具实际给模型看过的（`SeenLines`）。
- 提示词与工具说明里**不放任何具体人物、章节、活动或剧情手法**；示意格式只用占位符（守卫测试）。
- 提示词里凡是代码要严格解析的格式，都给完整骨架；解析器对常见变体容错，丢弃的出处计数并退回一次。
- 答案写给玩家：正文不提库/表/文件名/id；不要写“哪些可以加引号”，照搬台词由代码检查退回。
- 思考档位每个角色显式指定，默认全部 off，“深度思考”= low；不给剧情问答开 high。各家参数见 `docs/LLM_PROVIDERS.md`。
- 提示词留在 Dart 里（与解析器同版本、有守卫测试），不进 ARB。

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
flutter test test/live/ask_pipeline_live_test.dart
```

- live 测试驱动 App 的 `askChatProvider`（只替换启动注入的 provider 与平台路径），输出 `build/live_sessions/` 下的会话 JSON 与 `*.summary.json`
  （`usage`、`timeline`）。追问用 `ARKLORES_LIVE_CONVERSATION=true`；`ARKLORES_LIVE_EVAL`/`ARKLORES_LIVE_IDS` 选评测题；`ARKLORES_LIVE_NO_EMBEDDING=true` 模拟无向量。
- 配置来自 gitignored 的 `tools/api_info`（API_KEY=/MODEL=/URL=）与 `tools/embedding-apiKey.csv`。
- 建库、更新、补算、向量、发布的命令见 `docs/GAMEDATA_BUILD_PIPELINE.md`。
